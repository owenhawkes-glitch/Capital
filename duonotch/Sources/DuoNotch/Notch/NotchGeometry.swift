import AppKit

/// Where the notch is (or where a fake one should go) on the chosen screen.
struct NotchGeometry {
    let screen: NSScreen
    let hasHardwareNotch: Bool
    /// Width of the camera housing; 0 on screens without one.
    let notchWidth: CGFloat
    /// Height of the camera housing, or the height of the fake notch.
    let notchHeight: CGFloat

    /// Prefers the built-in display with a notch, otherwise the menu-bar screen.
    static func detect() -> NotchGeometry? {
        let screens = NSScreen.screens
        guard let screen = screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? screens.first else {
            return nil
        }
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = screen.frame.width - left.width - right.width
            return NotchGeometry(
                screen: screen,
                hasHardwareNotch: true,
                notchWidth: max(width, 0),
                notchHeight: screen.safeAreaInsets.top
            )
        }
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        return NotchGeometry(
            screen: screen,
            hasHardwareNotch: false,
            notchWidth: 0,
            notchHeight: max(menuBar, 32)
        )
    }
}

/// What the expanded panel has to make room for.
struct NotchLayoutInfo: Equatable {
    var pendingCount: Int
    var sessionRows: Int
    var showsProjects: Bool
}

enum NotchMetrics {
    /// Space either side of the camera housing for one account's ring.
    static let wingWidth: CGFloat = 92
    /// Gap between the two wings on screens without a hardware notch.
    static let fakeGap: CGFloat = 14
    static let expandedBaseWidth: CGFloat = 600
    static let approvalRowHeight: CGFloat = 46
    static let maxVisibleApprovals = 3
    static let sessionRowHeight: CGFloat = 18
    static let maxSessionRows = 4
    static let projectsRowHeight: CGFloat = 34

    static func collapsedWidth(_ g: NotchGeometry) -> CGFloat {
        (g.hasHardwareNotch ? g.notchWidth : fakeGap) + 2 * wingWidth
    }

    static func expandedWidth(_ g: NotchGeometry) -> CGFloat {
        max(expandedBaseWidth, collapsedWidth(g))
    }

    static func expandedHeight(_ g: NotchGeometry, layout: NotchLayoutInfo) -> CGFloat {
        var height = g.notchHeight + 186
        if layout.sessionRows > 0 {
            height += CGFloat(layout.sessionRows) * sessionRowHeight + 8
        }
        if layout.showsProjects {
            height += projectsRowHeight + 6
        }
        let visible = min(layout.pendingCount, maxVisibleApprovals)
        if visible > 0 {
            height += CGFloat(visible) * approvalRowHeight + 18
        }
        return height
    }

    static func size(_ g: NotchGeometry, expanded: Bool, layout: NotchLayoutInfo) -> CGSize {
        expanded
            ? CGSize(width: expandedWidth(g), height: expandedHeight(g, layout: layout))
            : CGSize(width: collapsedWidth(g), height: g.notchHeight)
    }

    /// Screen-space rectangle of the drawn shape, hanging from the top edge.
    static func frame(_ g: NotchGeometry, size: CGSize) -> NSRect {
        let s = g.screen.frame
        return NSRect(x: (s.midX - size.width / 2).rounded(), y: s.maxY - size.height, width: size.width, height: size.height)
    }
}
