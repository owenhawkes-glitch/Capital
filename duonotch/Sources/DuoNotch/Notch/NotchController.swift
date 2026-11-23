import AppKit
import SwiftUI
import Combine

/// Owns the borderless panel that shows the notch, wherever it is placed.
@MainActor
final class NotchController {
    private let state: AppState
    private let panel: NSPanel
    private var hosting: NSHostingView<NotchRootView>?
    private var geometry: NotchGeometry?
    private var placement: NotchPlacement
    private var cancellables = Set<AnyCancellable>()
    private var hoverTimer: Timer?
    private var collapseWorkItem: DispatchWorkItem?
    private var frameWorkItem: DispatchWorkItem?

    init(state: AppState) {
        self.state = state
        self.placement = state.placement

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Above the menu bar so the slab can cover the hardware notch.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.titleVisibility = .hidden
        panel.becomesKeyOnlyIfNeeded = true

        state.panelTopLeft = { [weak self] in
            guard let frame = self?.panel.frame else { return .zero }
            return CGPoint(x: frame.minX, y: frame.maxY)
        }

        rebuild()

        // App shortcuts live in their own store; new ones need notch items.
        AppShortcutStore.shared.$shortcuts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated {
                self?.state.reconcileNotchItems()
                self?.syncFrame()
            } }
            .store(in: &cancellables)

        state.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.stateChanged() } }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.rebuild() } }
            .store(in: &cancellables)

        hoverTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateHover() }
        }
    }

    func show() {
        panel.orderFrontRegardless()
    }

    // MARK: - Layout

    private func stateChanged() {
        if state.placement != placement {
            placement = state.placement
            rebuild()
        } else {
            syncFrame()
        }
    }

    private func rebuild() {
        guard let geometry = NotchGeometry.detect(placement: state.placement) else {
            panel.orderOut(nil)
            self.geometry = nil
            return
        }
        self.geometry = geometry
        panel.hasShadow = state.placement == .floating
        let root = NotchRootView(state: state, geometry: geometry)
        if let hosting {
            hosting.rootView = root
        } else {
            let hosting = NSHostingView(rootView: root)
            hosting.wantsLayer = true
            hosting.layer?.backgroundColor = NSColor.clear.cgColor
            panel.contentView = hosting
            self.hosting = hosting
        }
        panel.setFrame(currentFrame(), display: true)
        panel.orderFrontRegardless()
    }

    private func currentFrame() -> NSRect {
        guard let geometry else { return .zero }
        let strip = state.strip
        let size = state.isExpanded
            ? NotchMetrics.expandedSize(geometry, placement: state.placement, strip: strip, contentHeight: state.measuredContentHeight)
            : NotchMetrics.collapsedSize(geometry, placement: state.placement, strip: strip)
        return NotchMetrics.frame(geometry, placement: state.placement, size: size, floatingOrigin: state.floatingOrigin)
    }

    /// Grow or move the window at once; shrink it only after the collapse
    /// animation has finished so the content isn't cut off mid-animation.
    private func syncFrame() {
        guard geometry != nil else { return }
        // objectWillChange fires before the new values land; read them next turn.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.applyFrame() }
        }
    }

    private func applyFrame() {
        let target = currentFrame()
        let current = panel.frame
        guard target != current else { return }
        frameWorkItem?.cancel()
        let shrinking = target.width < current.width || target.height < current.height
        if !shrinking || state.dragging {
            panel.setFrame(target, display: true)
        } else {
            let item = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let final = self.currentFrame()
                    if self.panel.frame != final { self.panel.setFrame(final, display: true) }
                }
            }
            frameWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
        }
    }

    // MARK: - Hover

    private func updateHover() {
        guard geometry != nil, !state.dragging else { return }
        let rect = currentFrame().insetBy(dx: -4, dy: -4)
        let inside = rect.contains(NSEvent.mouseLocation)

        if inside {
            collapseWorkItem?.cancel()
            collapseWorkItem = nil
            if !state.hovering { state.hovering = true }
        } else if state.hovering, collapseWorkItem == nil {
            let item = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    self?.state.hovering = false
                    self?.collapseWorkItem = nil
                }
            }
            collapseWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
        }
    }
}
