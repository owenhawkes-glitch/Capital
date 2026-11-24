import AppKit
import SwiftUI
import MenuBentoCore

/// MenuBento's own status items.
///
/// Right to left: the MenuBento icon, the Hidden separator, the Always
/// hidden separator. Everything between the two separators is the Hidden
/// section; everything left of the second one is Always hidden.
///
/// Hiding works by making a separator very long so the items to its left
/// are pushed off the left edge of the screen. On macOS 27 an item longer
/// than about half the screen is simply dropped (so the old 10 000 pt
/// trick shows everything instead of hiding it). One separator therefore
/// can't push far enough on its own: items end up near the middle of the
/// bar, under a notch or in plain view. Each separator has a "booster", an
/// invisible item that sits immediately to its left. Together they're as
/// long as the distance to the screen's left edge, split into two pieces
/// that are each under the limit.
@MainActor
final class ControlItems {
    let main: NSStatusItem
    let hiddenSeparator: NSStatusItem
    let alwaysSeparator: NSStatusItem
    /// Invisible items that must sit immediately left of each separator.
    let hiddenBooster: NSStatusItem
    let alwaysBooster: NSStatusItem
    private(set) var extras: [UUID: NSStatusItem] = [:]

    var onMainClick: ((NSEvent?) -> Void)?
    var onSeparatorClick: (() -> Void)?

    private static let collapsedLength: CGFloat = 14
    /// A booster at rest: present but invisible.
    private static let boosterRest: CGFloat = 1
    private var lastState: BarState = .showAll

    init() {
        // Creation order sets the default order (each new item goes to the
        // left of the previous), so the first launch reads: [AH][H][icon].
        main = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        main.autosaveName = "menubento.main"
        hiddenSeparator = NSStatusBar.system.statusItem(withLength: Self.collapsedLength)
        hiddenSeparator.autosaveName = "menubento.hidden"
        alwaysSeparator = NSStatusBar.system.statusItem(withLength: Self.collapsedLength)
        alwaysSeparator.autosaveName = "menubento.alwaysHidden"
        hiddenBooster = NSStatusBar.system.statusItem(withLength: Self.boosterRest)
        hiddenBooster.autosaveName = "menubento.hidden.booster"
        alwaysBooster = NSStatusBar.system.statusItem(withLength: Self.boosterRest)
        alwaysBooster.autosaveName = "menubento.alwaysHidden.booster"

        for item in [main, hiddenSeparator, alwaysSeparator, hiddenBooster, alwaysBooster] { item.behavior = [] }
        hiddenBooster.button?.setAccessibilityLabel("MenuBento hidden section booster")
        alwaysBooster.button?.setAccessibilityLabel("MenuBento always-hidden section booster")

        if let button = main.button {
            button.image = Self.symbol("rectangle.split.2x2", size: 14, description: "MenuBento")
            button.target = self
            button.action = #selector(mainClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("MenuBento")
        }
        for (item, label) in [(hiddenSeparator, "MenuBento hidden section"), (alwaysSeparator, "MenuBento always-hidden section")] {
            item.button?.target = self
            item.button?.action = #selector(separatorClicked)
            item.button?.setAccessibilityLabel(label)
        }
    }

    // MARK: - State

    func apply(_ state: BarState) {
        lastState = state
        switch state {
        case .hidden:
            collapse(alwaysSeparator, visible: false)
            alwaysBooster.length = Self.boosterRest
            expand(hiddenSeparator, booster: hiddenBooster)
        case .shown:
            collapse(hiddenSeparator, visible: true)
            hiddenBooster.length = Self.boosterRest
            expand(alwaysSeparator, booster: alwaysBooster)
        case .showAll:
            collapse(hiddenSeparator, visible: true)
            collapse(alwaysSeparator, visible: true)
            hiddenBooster.length = Self.boosterRest
            alwaysBooster.length = Self.boosterRest
        }
        main.button?.image = Self.symbol(state == .hidden ? "rectangle.split.2x2" : "rectangle.split.2x2.fill", size: 14, description: "MenuBento")
    }

    /// Grows the separator and its booster so that together they reach
    /// past the left edge of the screen. The separator's right edge doesn't
    /// move when it grows (it's pinned by the items to its right).
    private func expand(_ separator: NSStatusItem, booster: NSStatusItem) {
        separator.button?.image = nil
        let screen = screenOfMain ?? NSScreen.main
        let screenFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 2000, height: 1000)
        let limit = floor(screenFrame.width / 2) - 30
        let rightEdge = separator.button?.window?.frame.maxX ?? screenFrame.maxX
        let needed = rightEdge - screenFrame.minX + 60
        let first = min(limit, needed)
        separator.length = first
        booster.length = boostersPlaced ? max(Self.boosterRest, min(limit, needed - first)) : Self.boosterRest
    }

    /// True when each booster sits immediately left of its separator (it
    /// may not after you or a preset rearranges the menu bar). Only
    /// meaningful while the separators are collapsed.
    var boostersPlaced: Bool {
        misplacedBoosters.isEmpty
    }

    /// (booster, separator) pairs where the booster isn't right next to
    /// its separator.
    var misplacedBoosters: [(NSStatusItem, NSStatusItem)] {
        [(hiddenBooster, hiddenSeparator), (alwaysBooster, alwaysSeparator)].filter { booster, separator in
            guard let b = booster.button?.window?.frame, let s = separator.button?.window?.frame else { return false }
            // macOS leaves a small gap between items; anything else in
            // between would need at least ~20 pt.
            let gap = s.minX - b.maxX
            return gap < -1 || gap > 16
        }
    }

    /// Makes the boosters grabbable for a drag, or puts them back to rest.
    func setBoostersGrabbable(_ grabbable: Bool) {
        for booster in [hiddenBooster, alwaysBooster] {
            booster.length = grabbable ? 10 : Self.boosterRest
        }
        if !grabbable { apply(lastState) }
    }

    private func collapse(_ item: NSStatusItem, visible: Bool) {
        item.length = Self.collapsedLength
        let symbol = item === hiddenSeparator ? "chevron.compact.left" : "chevron.left.2"
        item.button?.image = visible ? Self.symbol(symbol, size: item === hiddenSeparator ? 13 : 9, description: "Separator") : nil
        item.button?.alphaValue = item === hiddenSeparator ? 0.8 : 0.5
    }

    var screenOfMain: NSScreen? {
        guard let frame = main.button?.window?.frame else { return nil }
        return NSScreen.screens.first { $0.frame.intersects(frame) }
    }

    // MARK: - Frames (top-left global coordinates, like Accessibility)

    func frame(of item: NSStatusItem) -> CGRect? {
        guard let f = item.button?.window?.frame, f.width > 0 else { return nil }
        return f.flippedToTopLeft
    }

    /// Our items as MenuBarItems, so they can be listed and moved.
    func ourItems(extrasConfig: [ExtraItem]) -> [MenuBarItem] {
        var out: [MenuBarItem] = []
        func add(_ item: NSStatusItem, _ ref: ItemRef, _ name: String) {
            guard let f = frame(of: item) else { return }
            out.append(MenuBarItem(ref: ref, pid: getpid(), frame: f, name: name, appName: "MenuBento",
                                   isFixed: false, isOurs: true, canPress: false))
        }
        add(main, OurItems.main, "MenuBento")
        add(hiddenSeparator, OurItems.hidden, "Hidden separator")
        add(alwaysSeparator, OurItems.alwaysHidden, "Always-hidden separator")
        for extra in extrasConfig {
            if let item = extras[extra.id] { add(item, extra.ref, extra.name) }
        }
        return out
    }

    // MARK: - Spacers and dividers

    func syncExtras(_ config: [ExtraItem]) {
        let wanted = Set(config.map(\.id))
        for (id, item) in extras where !wanted.contains(id) {
            NSStatusBar.system.removeStatusItem(item)
            extras[id] = nil
        }
        for extra in config {
            let item: NSStatusItem
            if let existing = extras[extra.id] {
                item = existing
            } else {
                item = NSStatusBar.system.statusItem(withLength: 10)
                item.autosaveName = extra.autosaveName
                item.behavior = []
                extras[extra.id] = item
            }
            let width: CGFloat = extra.kind == .spacer ? CGFloat(extra.width) : (extra.style == .dots ? 14 : 9)
            item.length = width
            guard let button = item.button else { continue }
            button.subviews.forEach { $0.removeFromSuperview() }
            button.image = nil
            button.title = ""
            button.setAccessibilityLabel(extra.name)
            if extra.kind == .divider {
                let host = PassThroughHostingView(rootView: DividerGlyph(extra: extra))
                host.frame = NSRect(x: 0, y: 0, width: width, height: NSStatusBar.system.thickness)
                host.autoresizingMask = [.width, .height]
                button.addSubview(host)
            }
        }
    }

    // MARK: - Clicks

    @objc private func mainClicked() { onMainClick?(NSApp.currentEvent) }
    @objc private func separatorClicked() { onSeparatorClick?() }

    func popUpMenu(_ menu: NSMenu) {
        main.menu = menu
        main.button?.performClick(nil)
        main.menu = nil
    }

    static func symbol(_ name: String, size: CGFloat, description: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: description)?
            .withSymbolConfiguration(.init(pointSize: size, weight: .medium))
        image?.isTemplate = true
        return image
    }
}

/// A hosting view that lets clicks through to the status button.
final class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// How a divider looks in the menu bar.
struct DividerGlyph: View {
    let extra: ExtraItem

    var body: some View {
        Group {
            switch extra.style {
            case .line: paint(Capsule()).frame(width: 2, height: 14)
            case .thick: paint(Capsule()).frame(width: 3.5, height: 16)
            case .dot: paint(Circle()).frame(width: 5, height: 5)
            case .dots:
                VStack(spacing: 2.5) {
                    ForEach(0..<3, id: \.self) { _ in paint(Circle()).frame(width: 3, height: 3) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func paint<S: Shape>(_ shape: S) -> some View {
        if extra.colorHex == ExtraItem.glowColor {
            GlowFill(shape: shape)
        } else {
            shape.fill(Color(hex: extra.colorHex))
        }
    }
}
