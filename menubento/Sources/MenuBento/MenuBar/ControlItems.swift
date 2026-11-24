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
/// are pushed away. On macOS 27 two things are different from older
/// systems (found by experiment, see README):
///  * an item longer than about half the screen is simply dropped, so the
///    old 10 000 pt trick shows everything instead of hiding it;
///  * items pushed left of roughly the screen's centre aren't drawn.
/// So the separator grows to just under half the screen width, and we
/// check that it really pushed things before trusting it.
@MainActor
final class ControlItems {
    let main: NSStatusItem
    let hiddenSeparator: NSStatusItem
    let alwaysSeparator: NSStatusItem
    private(set) var extras: [UUID: NSStatusItem] = [:]

    var onMainClick: ((NSEvent?) -> Void)?
    var onSeparatorClick: (() -> Void)?

    /// The longest separator the menu bar accepted, learned at run time.
    private var expandLength: CGFloat?
    private static let collapsedLength: CGFloat = 14

    init() {
        // Creation order sets the default order (each new item goes to the
        // left of the previous), so the first launch reads: [AH][H][icon].
        main = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        main.autosaveName = "menubento.main"
        hiddenSeparator = NSStatusBar.system.statusItem(withLength: Self.collapsedLength)
        hiddenSeparator.autosaveName = "menubento.hidden"
        alwaysSeparator = NSStatusBar.system.statusItem(withLength: Self.collapsedLength)
        alwaysSeparator.autosaveName = "menubento.alwaysHidden"

        main.behavior = []
        hiddenSeparator.behavior = []
        alwaysSeparator.behavior = []

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
        switch state {
        case .hidden:
            expand(hiddenSeparator)
            collapse(alwaysSeparator, visible: false)
        case .shown:
            collapse(hiddenSeparator, visible: true)
            expand(alwaysSeparator)
        case .showAll:
            collapse(hiddenSeparator, visible: true)
            collapse(alwaysSeparator, visible: true)
        }
        main.button?.image = Self.symbol(state == .hidden ? "rectangle.split.2x2" : "rectangle.split.2x2.fill", size: 14, description: "MenuBento")
        if state == .hidden { verifyHidden() }
    }

    private func expand(_ item: NSStatusItem) {
        item.button?.image = nil
        item.length = currentExpandLength()
    }

    private func collapse(_ item: NSStatusItem, visible: Bool) {
        item.length = Self.collapsedLength
        let symbol = item === hiddenSeparator ? "chevron.compact.left" : "chevron.left.2"
        item.button?.image = visible ? Self.symbol(symbol, size: item === hiddenSeparator ? 13 : 9, description: "Separator") : nil
        item.button?.alphaValue = item === hiddenSeparator ? 0.8 : 0.5
    }

    private func currentExpandLength() -> CGFloat {
        if let expandLength { return expandLength }
        let screen = screenOfMain ?? NSScreen.main
        return floor((screen?.frame.width ?? 2000) / 2) - 30
    }

    var screenOfMain: NSScreen? {
        guard let frame = main.button?.window?.frame else { return nil }
        return NSScreen.screens.first { $0.frame.intersects(frame) }
    }

    /// When hidden, the always-hidden separator sits left of the expanded
    /// one, so it must have been pushed past the middle of the screen. If it
    /// wasn't, the menu bar refused the length: try a shorter one.
    private func verifyHidden(attempt: Int = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.hiddenSeparator.length > Self.collapsedLength,
                  let screen = self.screenOfMain,
                  let ahFrame = self.alwaysSeparator.button?.window?.frame else { return }
            if ahFrame.maxX < screen.frame.midX + 4 {
                self.expandLength = self.hiddenSeparator.length
                return
            }
            guard attempt < 5 else { return }
            let shorter = floor(self.hiddenSeparator.length * 0.85)
            self.expandLength = shorter
            self.hiddenSeparator.length = shorter
            self.verifyHidden(attempt: attempt + 1)
        }
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
