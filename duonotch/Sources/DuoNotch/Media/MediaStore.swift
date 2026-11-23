import AppKit
import Combine

/// Now-playing state for Spotify and Apple Music. Track changes arrive as
/// system notifications both apps already broadcast (no permission needed);
/// play/pause/skip and the first reading go through AppleScript, which
/// macOS asks permission for once per app.
@MainActor
final class MediaStore: ObservableObject {
    static let shared = MediaStore()

    enum Source: String {
        case spotify = "com.spotify.client"
        case music = "com.apple.Music"

        var appName: String { self == .spotify ? "Spotify" : "Music" }
    }

    struct Track: Equatable {
        var source: Source
        var title: String
        var artist: String
        var album: String
        var isPlaying: Bool
        var artworkURL: URL?
        /// Seconds.
        var duration: Double?
        /// Seconds into the track at `positionDate`.
        var position: Double = 0
        var positionDate = Date()

        /// Where playback is now, counting on from the last reading.
        func elapsed(at now: Date = Date()) -> Double {
            let value = isPlaying ? position + now.timeIntervalSince(positionDate) : position
            if let duration { return min(max(value, 0), duration) }
            return max(value, 0)
        }
    }

    @Published private(set) var track: Track?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var lastError: String?
    /// 0…100, nil until read from the player.
    @Published private(set) var volume: Double?
    private var volumeInFlight = false
    private var pendingVolume: Double?

    private var artworkFor: URL?
    private var observers: [NSObjectProtocol] = []

    private init() {
        let center = DistributedNotificationCenter.default()
        observers.append(center.addObserver(forName: Notification.Name("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main) { note in
            let info = note.userInfo ?? [:]
            MainActor.assumeIsolated { MediaStore.shared.received(info, source: .spotify) }
        })
        observers.append(center.addObserver(forName: Notification.Name("com.apple.Music.playerInfo"), object: nil, queue: .main) { note in
            let info = note.userInfo ?? [:]
            MainActor.assumeIsolated { MediaStore.shared.received(info, source: .music) }
        })
        let ws = NSWorkspace.shared.notificationCenter
        observers.append(ws.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { note in
            let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated {
                if let current = MediaStore.shared.track, current.source.rawValue == id {
                    MediaStore.shared.track = nil
                    MediaStore.shared.artwork = nil
                }
            }
        })
    }

    func isRunning(_ source: Source) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: source.rawValue).isEmpty
    }

    /// The app the controls act on: whatever last reported a track,
    /// otherwise Spotify if it's open, otherwise Music if it's open.
    var activeSource: Source? {
        if let track { return track.source }
        if isRunning(.spotify) { return .spotify }
        if isRunning(.music) { return .music }
        return nil
    }

    /// Ask the player directly, for when nothing has changed since launch.
    func refresh(force: Bool = false) {
        guard force || track == nil, let source = activeSource else { return }
        let script: String
        switch source {
        case .spotify:
            script = """
            tell application "Spotify"
                if player state is stopped then return ""
                set t to current track
                return (name of t) & "\\n" & (artist of t) & "\\n" & (album of t) & "\\n" & (player state as string) & "\\n" & (artwork url of t) & "\\n" & ((duration of t) / 1000) & "\\n" & (player position) & "\\n" & (sound volume)
            end tell
            """
        case .music:
            script = """
            tell application "Music"
                if player state is stopped then return ""
                set t to current track
                return (name of t) & "\\n" & (artist of t) & "\\n" & (album of t) & "\\n" & (player state as string) & "\\n" & "" & "\\n" & (duration of t) & "\\n" & (player position) & "\\n" & (sound volume)
            end tell
            """
        }
        run(script) { result in
            guard let result, !result.isEmpty else { return }
            let parts = result.components(separatedBy: "\n")
            guard parts.count >= 4 else { return }
            func number(_ i: Int) -> Double? {
                parts.count > i ? Double(parts[i].replacingOccurrences(of: ",", with: ".")) : nil
            }
            MediaStore.shared.update(Track(
                source: source, title: parts[0], artist: parts[1], album: parts[2],
                isPlaying: parts[3] == "playing",
                artworkURL: parts.count > 4 ? URL(string: parts[4]) : nil,
                duration: number(5),
                position: number(6) ?? 0,
                positionDate: Date()))
            if let v = number(7) { MediaStore.shared.volume = v }
        }
    }

    func playPause() { command("playpause") }
    func next() { command("next track") }
    func previous() { command("previous track") }

    func openPlayer() {
        let id = activeSource?.rawValue ?? Source.spotify.rawValue
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
        }
    }

    // MARK: - Private

    private func command(_ verb: String) {
        guard let source = activeSource else { openPlayer(); return }
        // Optimistic flip so the button responds instantly.
        if verb == "playpause", var t = track { t.isPlaying.toggle(); track = t }
        run("tell application \"\(source.appName)\" to \(verb)") { _ in
            // Re-read position and state once the player has acted.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                MainActor.assumeIsolated { MediaStore.shared.syncPosition() }
            }
        }
    }

    /// Jump to a point in the current track.
    func seek(to seconds: Double) {
        guard let source = activeSource, var t = track else { return }
        t.position = seconds
        t.positionDate = Date()
        track = t
        run("tell application \"\(source.appName)\" to set player position to \(Int(seconds))") { _ in }
    }

    /// Sets the player's volume (0…100). Coalesces fast slider drags so only
    /// one AppleScript call is in flight at a time.
    func setVolume(_ value: Double) {
        let v = min(max(value, 0), 100)
        volume = v
        pendingVolume = v
        sendVolumeIfIdle()
    }

    private func sendVolumeIfIdle() {
        guard !volumeInFlight, let v = pendingVolume, let source = activeSource else { return }
        pendingVolume = nil
        volumeInFlight = true
        run("tell application \"\(source.appName)\" to set sound volume to \(Int(v.rounded()))") { _ in
            MediaStore.shared.volumeInFlight = false
            MediaStore.shared.sendVolumeIfIdle()
        }
    }

    /// Reads position, play state and volume without touching the rest.
    func syncPosition() {
        guard let source = activeSource, track != nil else { return }
        let script = "tell application \"\(source.appName)\" to return (player position as string) & \"\\n\" & (player state as string) & \"\\n\" & (sound volume as string)"
        run(script) { result in
            guard let result, var t = MediaStore.shared.track else { return }
            let parts = result.components(separatedBy: "\n")
            if let p = Double(parts[0].replacingOccurrences(of: ",", with: ".")) {
                t.position = p
                t.positionDate = Date()
            }
            if parts.count > 1 { t.isPlaying = parts[1] == "playing" }
            if parts.count > 2, let v = Double(parts[2]) { MediaStore.shared.volume = v }
            MediaStore.shared.track = t
        }
    }

    private func received(_ info: [AnyHashable: Any], source: Source) {
        let state = info["Player State"] as? String ?? ""
        if state == "Stopped" {
            if track?.source == source { track = nil; artwork = nil }
            return
        }
        var artURL = track?.source == source ? track?.artworkURL : nil
        let title = info["Name"] as? String ?? ""
        if title != track?.title { artURL = nil }
        // Spotify: Duration in ms, Playback Position in s. Music: Total Time in ms.
        let durationMs = (info["Duration"] as? NSNumber) ?? (info["Total Time"] as? NSNumber)
        let position = (info["Playback Position"] as? NSNumber)?.doubleValue
        update(Track(
            source: source,
            title: title,
            artist: info["Artist"] as? String ?? "",
            album: info["Album"] as? String ?? "",
            isPlaying: state == "Playing",
            artworkURL: artURL,
            duration: durationMs.map { $0.doubleValue / 1000 },
            position: position ?? 0,
            positionDate: Date()))
        if position == nil { syncPosition() }
        // Spotify's notification has no artwork URL; ask for it.
        if source == .spotify, artURL == nil {
            run("tell application \"Spotify\" to return artwork url of current track") { result in
                guard let result, let url = URL(string: result), var t = MediaStore.shared.track, t.source == .spotify else { return }
                t.artworkURL = url
                MediaStore.shared.update(t)
            }
        }
    }

    private func update(_ new: Track) {
        track = new
        if new.artworkURL != artworkFor {
            artworkFor = new.artworkURL
            artwork = nil
            if let url = new.artworkURL { loadArtwork(url) }
        }
    }

    private func loadArtwork(_ url: URL) {
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = NSImage(data: data),
                  MediaStore.shared.artworkFor == url else { return }
            MediaStore.shared.artwork = image
        }
    }

    private func run(_ source: String, completion: @escaping @MainActor (String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            let output = NSAppleScript(source: source)?.executeAndReturnError(&error)
            let text = output?.stringValue
            let message = (error?[NSAppleScript.errorMessage] as? String)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if let message { MediaStore.shared.lastError = message }
                    completion(text)
                }
            }
        }
    }
}
