import AppKit
import SwiftUI
import MenuBentoCore

/// A panel that drops down under the menu bar with the hidden items.
///
/// Clicking one briefly reveals the hidden section, presses the real item
/// so its own menu opens in the right place, and hides the section again
/// once that menu closes.
@MainActor
final class BentoBar {
    static let shared = BentoBar()

    private var panel: NSPanel?
    private var outsideClick: Any?
    private(set) var isOpen = false

    func toggle() { isOpen ? close() : show() }

    func show() {
        let model = AppModel.shared
        Task {
            await model.refresh()
            // No pictures yet? Take them while briefly revealing the items.
            if model.barShowsImages, Permissions.shared.screenRecording, model.state == .hidden,
               model.barItems(in: .hidden).contains(where: { ItemImageCache.shared.image(for: $0.ref) == nil }) {
                model.setState(.showAll)
                try? await Task.sleep(for: .milliseconds(450))
                await model.captureImagesIfAllowed()
                model.setState(.hidden)
                try? await Task.sleep(for: .milliseconds(300))
                await model.refresh()
            }
            present()
        }
    }

    private func present() {
        let model = AppModel.shared
        let host = NSHostingView(rootView: BentoBarView(onPick: { [weak self] item in self?.pick(item) }))
        host.layout()
        let size = host.fittingSize
        let panel = self.panel ?? makePanel()
        panel.contentView = host
        let iconFrame = model.controls.main.button?.window?.frame ?? .zero
        let screen = NSScreen.screens.first { $0.frame.intersects(iconFrame) } ?? NSScreen.main!
        let top = screen.visibleFrame.maxY - 6
        var x = iconFrame.maxX - size.width
        x = min(max(x, screen.frame.minX + 8), screen.frame.maxX - size.width - 8)
        panel.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = reduceMotion ? 0 : 0.18
            panel.animator().alphaValue = 1
        }
        isOpen = true
        outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            Task { @MainActor in BentoBar.shared.close() }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 2)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        self.panel = panel
        return panel
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        if let outsideClick { NSEvent.removeMonitor(outsideClick) }
        outsideClick = nil
        panel?.orderOut(nil)
    }

    /// Reveal in place, press the real item, re-hide when its menu closes.
    private func pick(_ item: MenuBarItem) {
        close()
        let model = AppModel.shared
        let needsAll = model.section(of: item) == .alwaysHidden
        Task {
            model.setState(needsAll ? .showAll : .shown)
            try? await Task.sleep(for: .milliseconds(400))
            let fresh = await model.refresh().first { $0.ref == item.ref } ?? item
            let pressed = await Task.detached { fresh.canPress && MenuBarScanner.press(fresh) }.value
            if !pressed {
                await Task.detached { ItemMover.click(at: CGPoint(x: fresh.frame.midX, y: fresh.frame.midY)) }.value
            }
            // Auto-rehide (HoverWatcher) waits for the menu to close; if
            // it's off, hide once the item's menu has gone.
            if !model.autoRehide {
                try? await Task.sleep(for: .seconds(1))
                while HoverWatcher.menuIsOpen() { try? await Task.sleep(for: .milliseconds(300)) }
                model.setState(.hidden)
            }
        }
    }
}

struct BentoBarView: View {
    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var images = ItemImageCache.shared
    @ObservedObject private var look = BarAppearance.shared
    @State private var showAlways = false
    var onPick: (MenuBarItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            row(model.barItems(in: .hidden), empty: "Nothing hidden yet. Drag items into Hidden in Settings, or ⌘-drag them left of the ‹ separator.")
            if showAlways {
                Divider().opacity(0.4)
                row(model.barItems(in: .alwaysHidden), empty: "Nothing always hidden.")
            }
            HStack(spacing: 10) {
                if !model.barItems(in: .alwaysHidden).isEmpty {
                    Button(showAlways ? "Less" : "Always hidden (\(model.barItems(in: .alwaysHidden).count))") { showAlways.toggle() }
                }
                if !Permissions.shared.accessibility {
                    Text("Grant Accessibility to list items").foregroundStyle(.orange)
                }
                Spacer(minLength: 0)
                Button { SettingsWindow.shared.show(); BentoBar.shared.close() } label: { Image(systemName: "gearshape") }
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(minWidth: 220, maxWidth: 900, alignment: .leading)
        .fixedSize()
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.black.opacity(0.85))
                .overlay(look.enabled && look.theme != .black ? AnyView(ThemeBackground().opacity(0.55).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))) : AnyView(EmptyView()))
        }
        .overlay {
            if look.enabled && look.glowBorder {
                GlowBorder(shape: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private func row(_ items: [MenuBarItem], empty: String) -> some View {
        if items.isEmpty {
            Text(empty).font(.caption).foregroundStyle(.secondary).frame(maxWidth: 360, alignment: .leading)
        } else {
            HStack(spacing: 4) {
                ForEach(items) { item in
                    Button { onPick(item) } label: { cell(item) }
                        .buttonStyle(BarCellStyle())
                        .help(item.name)
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ item: MenuBarItem) -> some View {
        if model.barShowsImages, let image = images.image(for: item.ref) {
            Image(nsImage: image).frame(height: 24)
        } else if item.isOurs {
            Image(systemName: "rectangle.split.2x2").frame(width: 22, height: 24)
        } else {
            HStack(spacing: 4) {
                if let icon = NSRunningApplication(processIdentifier: item.pid)?.icon {
                    Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                }
                Text(item.name).font(.caption).lineLimit(1).frame(maxWidth: 110)
            }
            .padding(.horizontal, 4)
            .frame(height: 24)
        }
    }
}

private struct BarCellStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(configuration.isPressed ? 0.25 : 0.08)))
            .contentShape(Rectangle())
    }
}
