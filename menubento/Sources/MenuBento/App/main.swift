import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        _ = Permissions.shared
        AppModel.shared.start()
        HoverWatcher.shared.start()
        BarOverlay.shared.start()
        let env = ProcessInfo.processInfo.environment
        if env["MENUBENTO_SETTINGS"] == "1" || !UserDefaults.standard.bool(forKey: "model.launchedBefore") {
            UserDefaults.standard.set(true, forKey: "model.launchedBefore")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                SettingsWindow.shared.show(page: Permissions.shared.accessibility ? nil : .permissions)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindow.shared.show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Leave nothing hidden behind us.
        AppModel.shared.setState(.showAll)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
