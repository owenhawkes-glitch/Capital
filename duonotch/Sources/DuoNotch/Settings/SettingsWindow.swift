import AppKit
import SwiftUI

/// Our own Settings window. The SwiftUI `Settings` scene can only be opened
/// through the responder chain of a key window, and the notch panel is
/// never key, so we manage the window ourselves.
@MainActor
final class SettingsWindow {
    static let shared = SettingsWindow()

    private var window: NSWindow?

    func show(state: AppState) {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView().environmentObject(state))
            let window = NSWindow(contentViewController: hosting)
            window.title = "DuoNotch Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 620, height: 560))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
