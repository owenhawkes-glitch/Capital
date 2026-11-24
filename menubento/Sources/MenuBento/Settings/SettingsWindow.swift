import AppKit
import SwiftUI

/// Our own Settings window (an accessory app has no Settings scene to
/// open). Adapted from DuoNotch's SettingsWindow.
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()

    private var window: NSWindow?
    var isVisible: Bool { window?.isVisible == true }
    var isDragging: Bool { ReorderState.shared.draggingID != nil }

    func show(page: SettingsPage? = nil) {
        if let page { SettingsRouter.shared.page = page }
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            let window = NSWindow(contentViewController: hosting)
            window.title = "MenuBento Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 960, height: 680))
            window.center()
            window.delegate = self
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        Task { await AppModel.shared.refresh() }
    }
}

@MainActor
final class SettingsRouter: ObservableObject {
    static let shared = SettingsRouter()
    @Published var page: SettingsPage =
        SettingsPage(rawValue: ProcessInfo.processInfo.environment["MENUBENTO_SETTINGS_PAGE"] ?? "") ?? .items
}

enum SettingsPage: String, CaseIterable, Identifiable {
    case items, groups, extras, hidden, appearance, presets, permissions, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .items: return "Menu bar items"
        case .groups: return "Groups"
        case .extras: return "Spacers & dividers"
        case .hidden: return "Hidden items"
        case .appearance: return "Appearance"
        case .presets: return "Presets"
        case .permissions: return "Permissions"
        case .about: return "About"
        }
    }
    var symbol: String {
        switch self {
        case .items: return "menubar.rectangle"
        case .groups: return "square.stack.3d.up"
        case .extras: return "arrow.left.and.right"
        case .hidden: return "eye.slash"
        case .appearance: return "paintpalette"
        case .presets: return "square.stack"
        case .permissions: return "lock.shield"
        case .about: return "info.circle"
        }
    }
}

/// Sidebar settings. A plain HStack rather than NavigationSplitView, which
/// renders blank in an NSHostingController window owned by an accessory app.
struct SettingsView: View {
    @ObservedObject private var router = SettingsRouter.shared
    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var permissions = Permissions.shared

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(SettingsPage.allCases) { item in
                        Button {
                            router.page = item
                        } label: {
                            HStack {
                                Label(item.title, systemImage: item.symbol)
                                Spacer()
                                if item == .permissions && !permissions.accessibility {
                                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 6)
                                .fill(router.page == item ? Color.accentColor.opacity(0.25) : Color.clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
            }
            .frame(width: 200)
            .background(Color.secondary.opacity(0.06))

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(router.page.title).font(.title2.bold())
                    Spacer()
                    if let busy = model.busy {
                        ProgressView().controlSize(.small)
                        Text(busy).font(.callout).foregroundStyle(.secondary)
                    } else if let message = model.lastMessage {
                        Text(message).font(.callout).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 4)
                Group {
                    switch router.page {
                    case .items: ItemsSettings()
                    case .groups: GroupsSettings()
                    case .extras: ExtrasSettings()
                    case .hidden: HiddenSettings()
                    case .appearance: AppearanceSettings()
                    case .presets: PresetsSettings()
                    case .permissions: PermissionsSettings()
                    case .about: AboutSettings()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(minWidth: 900, minHeight: 620)
    }
}

/// Shown on pages that can't work without Accessibility.
struct NeedsAccessibility: View {
    @ObservedObject private var permissions = Permissions.shared

    var body: some View {
        if !permissions.accessibility {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.shield").font(.title2).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Accessibility permission needed").font(.headline)
                    Text(Permissions.accessibilityWhy).font(.callout).fixedSize(horizontal: false, vertical: true)
                    Button("Grant Accessibility…") { permissions.requestAccessibility() }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.1)))
        }
    }
}
