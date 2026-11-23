import AppKit
import Combine
import ScreenCaptureKit
import CoreImage

/// Live view of another app's window (e.g. a Spotify video podcast),
/// captured with ScreenCaptureKit. Needs Screen Recording permission.
/// Capture only runs while the section is on screen.
@MainActor
final class WindowMirror: NSObject, ObservableObject {
    static let shared = WindowMirror()

    struct Candidate: Identifiable, Hashable {
        let id: CGWindowID
        let appName: String
        let bundleID: String
        let title: String
    }

    /// One-click choices in the Live section (only those installed).
    static var favourites: [(id: String, name: String)] {
        [("com.spotify.client", "Spotify"), ("tv.parsec.www", "Parsec")].filter {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.id) != nil
        }
    }

    @Published private(set) var frame: CGImage?
    @Published private(set) var status: String = "Not started"
    @Published private(set) var needsPermission = false
    @Published private(set) var candidates: [Candidate] = []
    /// Bundle id of the app to mirror; its largest window is used.
    @Published var targetBundleID: String {
        didSet {
            UserDefaults.standard.set(targetBundleID, forKey: "mirror.bundleID")
            if viewers > 0 { Task { await restart() } }
        }
    }

    private var stream: SCStream?
    private var viewers = 0
    private let output = FrameOutput()
    private let queue = DispatchQueue(label: "duonotch.mirror")

    override private init() {
        targetBundleID = UserDefaults.standard.string(forKey: "mirror.bundleID") ?? "com.spotify.client"
        super.init()
        output.onFrame = { image in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { WindowMirror.shared.frame = image }
            }
        }
    }

    var targetName: String {
        candidates.first { $0.bundleID == targetBundleID }?.appName
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: targetBundleID)?.deletingPathExtension().lastPathComponent
            ?? targetBundleID
    }

    func appear() {
        viewers += 1
        if viewers == 1 { Task { await restart() } }
    }

    func disappear() {
        viewers = max(viewers - 1, 0)
        if viewers == 0 { Task { await stop() } }
    }

    func bringTargetToFront() {
        NSRunningApplication.runningApplications(withBundleIdentifier: targetBundleID).first?
            .activate(options: [.activateAllWindows])
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func refreshCandidates() async {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) else { return }
        let me = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        candidates = content.windows
            .filter { ($0.owningApplication?.bundleIdentifier ?? me) != me && $0.frame.width > 200 && $0.frame.height > 150 && $0.windowLayer == 0 }
            .sorted { $0.frame.width * $0.frame.height > $1.frame.width * $1.frame.height }
            .compactMap { w -> Candidate? in
                guard let app = w.owningApplication, seen.insert(app.bundleIdentifier).inserted else { return nil }
                return Candidate(id: w.windowID, appName: app.applicationName, bundleID: app.bundleIdentifier, title: w.title ?? "")
            }
            .sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
    }

    // MARK: - Capture

    private func restart() async {
        await stop()
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            needsPermission = false
        } catch {
            needsPermission = true
            status = "Screen Recording permission needed"
            return
        }
        await refreshCandidates()
        let windows = content.windows.filter {
            $0.owningApplication?.bundleIdentifier == targetBundleID && $0.windowLayer == 0 && $0.frame.width > 200
        }
        guard let window = windows.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
            frame = nil
            status = "\(targetName) has no open window"
            return
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        // Sharp on Retina without being wasteful: cap the long side.
        let longSide: CGFloat = 1280
        let ratio = min(longSide / max(window.frame.width, window.frame.height), 2)
        config.width = Int(window.frame.width * ratio)
        config.height = Int(window.frame.height * ratio)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.capturesAudio = false

        do {
            let stream = SCStream(filter: filter, configuration: config, delegate: nil)
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: queue)
            try await stream.startCapture()
            self.stream = stream
            status = "Mirroring \(window.owningApplication?.applicationName ?? targetName)"
        } catch {
            status = "Couldn't start: \(error.localizedDescription)"
        }
    }

    private func stop() async {
        if let stream {
            try? await stream.stopCapture()
            self.stream = nil
        }
    }
}

/// Turns captured sample buffers into CGImages off the main thread.
private final class FrameOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    var onFrame: ((CGImage) -> Void)?
    private let context = CIContext(options: [.cacheIntermediates: false])

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let statusRaw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: statusRaw) == .complete,
              let pixelBuffer = sampleBuffer.imageBuffer else { return }
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cg = context.createCGImage(image, from: image.extent) else { return }
        onFrame?(cg)
    }
}
