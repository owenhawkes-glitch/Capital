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
    }

    @Published private(set) var track: Track?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var lastError: String?

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
    func refresh() {
        guard track == nil, let source = activeSource else { return }
        let script: String
        switch source {
        case .spotify:
            script = """
            tell application "Spotify"
                if player state is stopped then return ""
                set t to current track
                return (name of t) & "\\n" & (artist of t) & "\\n" & (album of t) & "\\n" & (player state as string) & "\\n" & (artwork url of t)
            end tell
            """
        case .music:
            script = """
            tell application "Music"
                if player state is stopped then return ""
                set t to current track
                return (name of t) & "\\n" & (artist of t) & "\\n" & (album of t) & "\\n" & (player state as string) & "\\n"
            end tell
            """
        }
        run(script) { result in
            guard let result, !result.isEmpty else { return }
            let parts = result.components(separatedBy: "\n")
            guard parts.count >= 4 else { return }
            MediaStore.shared.update(Track(
                source: source, title: parts[0], artist: parts[1], album: parts[2],
                isPlaying: parts[3] == "playing",
                artworkURL: parts.count > 4 ? URL(string: parts[4]) : nil))
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
        run("tell application \"\(source.appName)\" to \(verb)") { _ in }
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
        update(Track(
            source: source,
            title: title,
            artist: info["Artist"] as? String ?? "",
            album: info["Album"] as? String ?? "",
            isPlaying: state == "Playing",
            artworkURL: artURL))
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
