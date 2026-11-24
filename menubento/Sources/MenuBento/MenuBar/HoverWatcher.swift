import AppKit
import MenuBentoCore

/// Polls the pointer (no permission needed) to:
///  * reveal hidden items when you rest on the empty bar just left of the
///    visible items, or on the MenuBento icon ("show on hover");
///  * hide them again a few seconds after you leave the menu bar, unless a
///    menu is open ("auto-rehide");
///  * tell the appearance overlay when the bar is hovered.
@MainActor
final class HoverWatcher {
    static let shared = HoverWatcher()

    private(set) var mouseInMenuBar = false
    private var hoverSince: Date?
    private var outsideSince: Date?
    private var timer: Timer?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in HoverWatcher.shared.tick() }
        }
    }

    func stateChanged() {
        outsideSince = nil
        hoverSince = nil
    }

    private func tick() {
        let model = AppModel.shared
        guard let controls = model.controls else { return }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) else { return }
        let barHeight = max(screen.frame.maxY - screen.visibleFrame.maxY, NSStatusBar.system.thickness)
        let inBar = mouse.y >= screen.frame.maxY - barHeight - 1
        if inBar != mouseInMenuBar {
            mouseInMenuBar = inBar
            BarOverlay.shared.hoverChanged(inBar)
        }
        guard model.busy == nil else { return }

        // Show on hover.
        if model.showOnHover, model.state == .hidden, inBar,
           let h = controls.hiddenSeparator.button?.window?.frame,
           let icon = controls.main.button?.window?.frame {
            let zone = (h.maxX - 140)...(h.maxX + 2)
            if zone.contains(mouse.x) || (icon.minX...icon.maxX).contains(mouse.x) {
                if let since = hoverSince {
                    if Date().timeIntervalSince(since) > 0.3 { model.setState(.shown) }
                } else {
                    hoverSince = Date()
                }
            } else {
                hoverSince = nil
            }
        } else {
            hoverSince = nil
        }

        // Auto-rehide.
        if model.autoRehide, model.state != .hidden, !BentoBar.shared.isOpen, !SettingsWindow.shared.isDragging {
            if inBar || Self.menuIsOpen() {
                outsideSince = nil
            } else if let since = outsideSince {
                if Date().timeIntervalSince(since) > model.rehideDelay { model.setState(.hidden) }
            } else {
                outsideSince = Date()
            }
        } else {
            outsideSince = nil
        }
    }

    /// True while any app has a menu open (pop-up menu windows are listed
    /// with their level even without Screen Recording permission).
    static func menuIsOpen() -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return false }
        let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        return list.contains { ($0[kCGWindowLayer as String] as? Int) == menuLevel }
    }
}
