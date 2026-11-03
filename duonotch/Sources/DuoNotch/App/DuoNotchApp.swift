import SwiftUI
import AppKit

@main
struct DuoNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(state)
        } label: {
            if state.showMenuBarText {
                Text(state.menuBarText)
            } else {
                Image(systemName: "circle.lefthalf.filled")
            }
        }

        Settings {
            SettingsView()
                .environmentObject(state)
        }
    }
}

private struct MenuContent: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ForEach(state.enabledAccounts) { account in
            Text("\(account.label): \(state.summaryLine(for: account))")
        }
        if state.enabledAccounts.isEmpty {
            Text("No Claude Code login found")
        }
        Divider()
        Button("Refresh now") { Task { await state.refreshAll() } }
        Button(state.pinnedOpen ? "Unpin notch" : "Pin notch open") { state.pinnedOpen.toggle() }
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Divider()
        Button("Quit DuoNotch") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notch: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let state = AppState.shared
        state.start()
        notch = NotchController(state: state)
        notch?.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.stop()
    }
}
