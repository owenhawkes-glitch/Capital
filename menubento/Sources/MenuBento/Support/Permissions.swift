import AppKit
import ApplicationServices
import CoreGraphics

/// The two permissions MenuBento can use, and why.
@MainActor
final class Permissions: ObservableObject {
    static let shared = Permissions()

    /// Needed to list other apps' menu bar items, to move them (synthetic
    /// Cmd-drags) and to click hidden items from the MenuBento bar.
    @Published private(set) var accessibility = AXIsProcessTrusted()
    /// Only needed to show pictures of hidden items in the MenuBento bar.
    @Published private(set) var screenRecording = CGPreflightScreenCaptureAccess()

    private var timer: Timer?

    private init() {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in Permissions.shared.check() }
        }
    }

    func check() {
        let ax = AXIsProcessTrusted()
        if ax != accessibility { accessibility = ax }
        let sr = CGPreflightScreenCaptureAccess()
        if sr != screenRecording { screenRecording = sr }
    }

    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        open("Privacy_Accessibility")
    }

    func requestScreenRecording() {
        if !CGRequestScreenCaptureAccess() { open("Privacy_ScreenCapture") }
    }

    func open(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    static let accessibilityWhy = """
    MenuBento uses Accessibility to see which items other apps have in the menu bar, to move them for you \
    (it holds ⌘ and drags them, exactly as you would) and to click a hidden item from the MenuBento bar. \
    It never reads window contents, typing or other apps' data.
    """

    static let screenRecordingWhy = """
    Screen Recording is only used to take a picture of the menu bar so the MenuBento bar can show hidden items \
    as they really look. Without it the bar shows each app's icon instead, or you can reveal hidden items in \
    place in the menu bar, which needs no Screen Recording at all.
    """
}
