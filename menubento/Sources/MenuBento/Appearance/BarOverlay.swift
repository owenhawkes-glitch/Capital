import AppKit
import SwiftUI
import MenuBentoCore

/// Where things are in one screen's menu bar, in that bar's own
/// coordinates (x from the screen's left edge, y from the top).
struct BarGeometry: Equatable {
    var width: CGFloat = 0
    var barHeight: CGFloat = 24
    /// Left edge of the status items that are drawn.
    var statusLeft: CGFloat = 0
    /// Right edge of the frontmost app's menus, when known.
    var menusRight: CGFloat?
    /// Items and menus that get their own dark cell in Cells mode.
    var cells: [CGRect] = []
}

@MainActor
final class OverlayState: ObservableObject {
    @Published var geometry = BarGeometry()
    @Published var hovered = false
}

/// Colours the menu bar.
///
/// On this Mac's macOS 27 the menu bar is opaque, so a window behind it
/// can't be seen (checked with a test window). The overlay therefore sits
/// just above the bar and ignores the mouse, so every click still goes to
/// the real menus and items. "Behind the bar" is still offered for
/// see-through menu bars.
@MainActor
final class BarOverlay {
    static let shared = BarOverlay()

    private var windows: [CGDirectDisplayID: (NSPanel, OverlayState)] = [:]
    private var timer: Timer?
    private var pending = false
    private var menuFrames: [CGRect] = []
    private var observers: [Any] = []

    func start() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in BarOverlay.shared.rebuild() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in BarOverlay.shared.setNeedsUpdate() }
        })
        observers.append(center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in BarOverlay.shared.setNeedsUpdate() }
        })
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in BarOverlay.shared.setNeedsUpdate() }
        }
        rebuild()
    }

    func hoverChanged(_ inBar: Bool) {
        for (_, (_, state)) in windows where state.hovered != inBar { state.hovered = inBar }
    }

    func setNeedsUpdate() {
        guard !pending else { return }
        pending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            Task { @MainActor in
                BarOverlay.shared.pending = false
                await BarOverlay.shared.update()
            }
        }
    }

    private func rebuild() {
        for (_, (panel, _)) in windows { panel.orderOut(nil) }
        windows = [:]
        setNeedsUpdate()
    }

    private func update() async {
        let look = BarAppearance.shared
        guard look.enabled else {
            for (_, (panel, _)) in windows { panel.orderOut(nil) }
            return
        }
        if look.shape == .split || look.fillMode == .cells {
            menuFrames = await Task.detached { MenuBarScanner.appMenuFrames() }.value
        }
        for screen in NSScreen.screens {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { continue }
            let (panel, state) = windows[id] ?? makeWindow(id)
            let barHeight = max(screen.frame.maxY - screen.visibleFrame.maxY, NSStatusBar.system.thickness)
            let shadowRoom: CGFloat = look.shadow ? 14 : 0
            let frame = NSRect(x: screen.frame.minX, y: screen.frame.maxY - barHeight - shadowRoom,
                               width: screen.frame.width, height: barHeight + shadowRoom)
            if panel.frame != frame { panel.setFrame(frame, display: true) }
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(look.layer == .above ? .statusWindow : .mainMenuWindow)) + (look.layer == .above ? 0 : -1))
            let geometry = geometry(for: screen, barHeight: barHeight)
            if state.geometry != geometry { state.geometry = geometry }
            state.hovered = HoverWatcher.shared.mouseInMenuBar
            panel.orderFrontRegardless()
        }
    }

    private func makeWindow(_ id: CGDirectDisplayID) -> (NSPanel, OverlayState) {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        let state = OverlayState()
        panel.contentView = NSHostingView(rootView: OverlayView(state: state))
        windows[id] = (panel, state)
        return (panel, state)
    }

    /// Works out the regions from MenuBento's own items (always known) and,
    /// with Accessibility, every other item and the app menus.
    private func geometry(for screen: NSScreen, barHeight: CGFloat) -> BarGeometry {
        let model = AppModel.shared
        let topLeft = screen.frame.flippedToTopLeft
        var g = BarGeometry(width: screen.frame.width, barHeight: barHeight)
        guard let controls = model.controls else { return g }

        // Status items are mirrored on every display's bar, the same
        // distance from the right edge, so measure from the right.
        let itemScreen = controls.screenOfMain ?? screen
        let itemTopLeft = itemScreen.frame.flippedToTopLeft
        let mid = itemTopLeft.midX
        var lefts: [CGFloat] = []
        var cells: [CGRect] = []
        for item in model.items where item.frame.minX >= mid - 2 && item.frame.maxX <= itemTopLeft.maxX + 1 {
            if item.frame.width > itemTopLeft.width / 4 { continue } // an expanded separator
            lefts.append(item.frame.minX)
            cells.append(item.frame)
        }
        if let main = controls.frame(of: controls.main) { lefts.append(main.minX) }
        if let h = controls.frame(of: controls.hiddenSeparator) {
            lefts.append(h.width > 40 ? h.maxX : h.minX)
        }
        let leftMost = lefts.filter { $0 >= mid - 2 }.min() ?? (itemTopLeft.maxX - 200)
        g.statusLeft = screen.frame.width - (itemTopLeft.maxX - leftMost)
        let shift = topLeft.maxX - itemTopLeft.maxX
        g.cells = cells.map { CGRect(x: $0.minX + shift - topLeft.minX, y: 0, width: $0.width, height: barHeight) }

        // App menus only show on the screen with the active menu bar; use
        // them where they fall.
        let menus = menuFrames.filter { topLeft.contains(CGPoint(x: $0.midX, y: $0.midY)) }
        if let right = menus.map(\.maxX).max() {
            g.menusRight = right - topLeft.minX
            g.cells += menus.map { CGRect(x: $0.minX - topLeft.minX, y: 0, width: $0.width, height: barHeight) }
        }
        return g
    }
}

/// What the overlay draws.
struct OverlayView: View {
    @ObservedObject var state: OverlayState
    @ObservedObject private var look = BarAppearance.shared

    var body: some View {
        let g = state.geometry
        let visible = !look.plainUntilHovered || state.hovered
        ZStack(alignment: .topLeading) {
            ForEach(Array(islands(g).enumerated()), id: \.offset) { _, rect in
                island(rect, g)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .opacity(visible ? 1 : 0)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: visible)
        .allowsHitTesting(false)
    }

    private func islands(_ g: BarGeometry) -> [CGRect] {
        let h = g.barHeight
        switch look.shape {
        case .full:
            return [CGRect(x: 0, y: 0, width: g.width, height: h)]
        case .island:
            return [CGRect(x: g.statusLeft - 8, y: 2, width: g.width - g.statusLeft + 4, height: h - 4)]
        case .split:
            var out: [CGRect] = []
            if let right = g.menusRight { out.append(CGRect(x: 4, y: 2, width: right + 8, height: h - 4)) }
            out.append(CGRect(x: g.statusLeft - 8, y: 2, width: g.width - g.statusLeft + 4, height: h - 4))
            return out
        }
    }

    @ViewBuilder
    private func island(_ rect: CGRect, _ g: BarGeometry) -> some View {
        let radius = look.shape == .full ? 0 : min(look.cornerRadius, rect.height / 2)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let opaque = look.layer == .behind
        ZStack {
            if look.shadow {
                // A thin strip along the bottom edge casts the shadow below
                // the bar without covering anything in it.
                Rectangle()
                    .fill(Color.black.opacity(0.01))
                    .frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .shadow(color: .black.opacity(0.55), radius: 6, y: 4)
            }
            switch look.fillMode {
            case .tint:
                ThemeBackground().opacity(opaque ? 1 : look.tintOpacity).clipShape(shape)
            case .cells:
                if g.cells.isEmpty {
                    ThemeBackground().opacity(opaque ? 1 : look.tintOpacity).clipShape(shape)
                } else {
                    ThemeBackground()
                        .clipShape(shape)
                        .mask(CellMask(holes: g.cells.map { $0.offsetBy(dx: -rect.minX, dy: -rect.minY) }))
                }
            case .outline:
                Color.clear
            }
            if look.glowBorder {
                GlowBorder(shape: shape.inset(by: 0.75))
            }
        }
        .frame(width: max(rect.width, 0), height: max(rect.height, 0))
        .offset(x: rect.minX, y: rect.minY)
    }
}

/// White everywhere except rounded holes around each item.
private struct CellMask: View {
    let holes: [CGRect]

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            context.blendMode = .destinationOut
            for hole in holes {
                let r = CGRect(x: hole.minX - 3, y: 3, width: hole.width + 6, height: size.height - 6)
                context.fill(Path(roundedRect: r, cornerRadius: min(7, r.height / 2)), with: .color(.white))
            }
        }
    }
}
