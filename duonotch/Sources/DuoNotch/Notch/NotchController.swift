import AppKit
import SwiftUI
import Combine

/// Owns the borderless panel that hangs from the top of the screen.
@MainActor
final class NotchController {
    private let state: AppState
    private let panel: NSPanel
    private var hosting: NSHostingView<NotchRootView>?
    private var geometry: NotchGeometry?
    private var cancellables = Set<AnyCancellable>()
    private var hoverTimer: Timer?
    private var collapseWorkItem: DispatchWorkItem?
    private var frameWorkItem: DispatchWorkItem?
    private var lastExpanded = false

    init(state: AppState) {
        self.state = state

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Above the menu bar so the slab covers the hardware notch.
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

        rebuild()

        state.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.syncFrame() } }
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

    private func rebuild() {
        guard let geometry = NotchGeometry.detect() else {
            panel.orderOut(nil)
            self.geometry = nil
            return
        }
        self.geometry = geometry
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
        lastExpanded = state.isExpanded
        panel.setFrame(currentFrame(), display: true)
        panel.orderFrontRegardless()
    }

    private func currentFrame() -> NSRect {
        guard let geometry else { return .zero }
        let size = NotchMetrics.size(geometry, expanded: state.isExpanded, pendingCount: state.pendingPermissions.count)
        return NotchMetrics.frame(geometry, size: size)
    }

    /// Grow the window immediately so the SwiftUI expansion has room; shrink
    /// it only after the collapse animation has finished.
    private func syncFrame() {
        guard geometry != nil else { return }
        let target = currentFrame()
        let expanded = state.isExpanded
        frameWorkItem?.cancel()

        if expanded || target.size.width > panel.frame.size.width || target.size.height > panel.frame.size.height {
            if panel.frame != target { panel.setFrame(target, display: true) }
        } else if lastExpanded != expanded || panel.frame != target {
            let item = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let final = self.currentFrame()
                    if self.panel.frame != final { self.panel.setFrame(final, display: true) }
                }
            }
            frameWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: item)
        }
        lastExpanded = expanded
    }

    // MARK: - Hover

    private func updateHover() {
        guard let geometry else { return }
        let size = NotchMetrics.size(geometry, expanded: state.isExpanded, pendingCount: state.pendingPermissions.count)
        let rect = NotchMetrics.frame(geometry, size: size).insetBy(dx: -6, dy: -6)
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
