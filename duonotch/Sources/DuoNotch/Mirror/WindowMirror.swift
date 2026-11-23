import AppKit
import Combine
import ScreenCaptureKit
import CoreImage

/// Live view of another app's window (a Spotify video podcast, a Parsec
/// session). The window is chosen with macOS's own content-sharing picker,
/// so DuoNotch never needs Screen Recording permission and never looks at
/// any window you didn't pick. macOS forgets the choice when DuoNotch quits.
@MainActor
final class WindowMirror: NSObject, ObservableObject, SCContentSharingPickerObserver {
    static let shared = WindowMirror()

    /// One-click choices (only those installed).
    static var favourites: [(id: String, name: String)] {
        [("com.spotify.client", "Spotify"), ("tv.parsec.www", "Parsec")].filter {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.id) != nil
        }
    }

    @Published private(set) var frame: CGImage?
    @Published private(set) var status = "Pick a window to show it here."
    @Published private(set) var sourceName: String?
    @Published private(set) var isLive = false
    /// The app last asked for, so its button shows as selected.
    @Published var targetBundleID: String {
        didSet { UserDefaults.standard.set(targetBundleID, forKey: "mirror.bundleID") }
    }

    private var stream: SCStream?
    private var visibleViewers = 0
    private let output = FrameOutput()
    private let queue = DispatchQueue(label: "duonotch.mirror")
    private var observing = false

    override private init() {
        targetBundleID = UserDefaults.standard.string(forKey: "mirror.bundleID") ?? "com.spotify.client"
        super.init()
        output.onFrame = { image in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if WindowMirror.shared.visibleViewers > 0 { WindowMirror.shared.frame = image }
                }
            }
        }
    }

    var targetName: String {
        Self.favourites.first { $0.id == targetBundleID }?.name
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: targetBundleID)?.deletingPathExtension().lastPathComponent
            ?? "window"
    }

    // MARK: - Visibility (frames are only drawn while the section is on screen)

    func appear() {
        visibleViewers += 1
        if visibleViewers == 1 { Task { await setFrameRate(visible: true) } }
    }

    func disappear() {
        visibleViewers = max(visibleViewers - 1, 0)
        if visibleViewers == 0 { Task { await setFrameRate(visible: false) } }
    }

    // MARK: - Picking

    /// Opens macOS's window picker, narrowed to one app when given.
    func pick(bundleID: String?) {
        if let bundleID { targetBundleID = bundleID }
        let picker = SCContentSharingPicker.shared
        if !observing {
            picker.add(self)
            observing = true
        }
        var config = SCContentSharingPickerConfiguration()
        config.allowedPickerModes = [.singleWindow]
        var excluded = [Bundle.main.bundleIdentifier ?? "com.hawkes.duonotch"]
        if let bundleID {
            // Hide every other running app so only this one's windows are offered.
            excluded += NSWorkspace.shared.runningApplications
                .compactMap(\.bundleIdentifier)
                .filter { $0 != bundleID }
        }
        config.excludedBundleIDs = excluded
        picker.defaultConfiguration = config
        picker.isActive = true
        if let bundleID, NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
            status = "\(targetName) isn't open. Open it, then pick its window."
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
            }
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        picker.present(using: .window)
    }

    func stop() {
        Task { await stopStream() }
        frame = nil
        isLive = false
        sourceName = nil
        status = "Pick a window to show it here."
    }

    func bringSourceToFront() {
        NSRunningApplication.runningApplications(withBundleIdentifier: targetBundleID).first?
            .activate(options: [.activateAllWindows])
    }

    // MARK: - SCContentSharingPickerObserver

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor in
            if !WindowMirror.shared.isLive { WindowMirror.shared.status = "No window picked." }
        }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        Task { @MainActor in await WindowMirror.shared.start(with: filter) }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        Task { @MainActor in WindowMirror.shared.status = "Couldn't open the picker: \(error.localizedDescription)" }
    }

    // MARK: - Capture

    private func start(with filter: SCContentFilter) async {
        await stopStream()
        let rect = filter.contentRect
        let scale = CGFloat(filter.pointPixelScale)
        let longSide: CGFloat = 1280
        let ratio = min(longSide / max(rect.width * scale, rect.height * scale, 1), 1) * scale
        let config = SCStreamConfiguration()
        config.width = max(Int(rect.width * ratio), 2)
        config.height = max(Int(rect.height * ratio), 2)
        config.minimumFrameInterval = CMTime(value: 1, timescale: visibleViewers > 0 ? 30 : 2)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.capturesAudio = false
        do {
            let stream = SCStream(filter: filter, configuration: config, delegate: nil)
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: queue)
            try await stream.startCapture()
            self.stream = stream
            isLive = true
            sourceName = targetName
            status = "Live"
        } catch {
            status = "Couldn't start: \(error.localizedDescription)"
        }
    }

    /// Full frame rate while visible, almost idle while the panel is closed.
    private func setFrameRate(visible: Bool) async {
        guard let stream else { return }
        let config = SCStreamConfiguration()
        config.minimumFrameInterval = CMTime(value: 1, timescale: visible ? 30 : 2)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        try? await stream.updateConfiguration(config)
    }

    private func stopStream() async {
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
