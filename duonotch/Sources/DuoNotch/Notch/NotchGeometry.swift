import AppKit

/// Where the notch lives on screen.
enum NotchPlacement: String, CaseIterable, Identifiable, Codable {
    case top, left, right, floating

    var id: String { rawValue }
    var name: String {
        switch self {
        case .top: return "Top centre (notch)"
        case .left: return "Left edge"
        case .right: return "Right edge"
        case .floating: return "Floating window"
        }
    }
}

/// Where the notch is (or where a fake one should go) on the chosen screen.
struct NotchGeometry {
    let screen: NSScreen
    let hasHardwareNotch: Bool
    /// Width of the camera housing; 0 on screens without one.
    let notchWidth: CGFloat
    /// Height of the camera housing, or the menu bar on screens without one.
    let notchHeight: CGFloat

    /// Top placement prefers the built-in display with a notch; everything
    /// else uses the screen that has the menu bar.
    static func detect(placement: NotchPlacement) -> NotchGeometry? {
        let screens = NSScreen.screens
        let notched = screens.first { $0.safeAreaInsets.top > 0 }
        guard let screen = (placement == .top ? notched : nil) ?? screens.first else { return nil }

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
        // Match the real menu bar so the fake notch doesn't hang below it.
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        let height = menuBar > 0 ? menuBar : NSStatusBar.system.thickness
        return NotchGeometry(
            screen: screen,
            hasHardwareNotch: false,
            notchWidth: 0,
            notchHeight: min(max(height, 22), 40)
        )
    }
}

@MainActor
enum NotchMetrics {
    /// Space either side of the camera housing for one account's ring.
    static let wingWidth: CGFloat = 84
    /// Gap between the two wings on screens without a hardware notch.
    static let fakeGap: CGFloat = 10
    static let expandedWidth: CGFloat = 600
    static let approvalRowHeight: CGFloat = 46
    static let maxVisibleApprovals = 3
    static let sessionRowHeight: CGFloat = 18
    static let maxSessionRows = 4
    static let clipboardRows = 8
    /// Used until the panel has measured itself once.
    static let estimatedContentHeight: CGFloat = 190
    static let sideWidth: CGFloat = 44
    static let floatingHeight: CGFloat = 30

    static func collapsedSize(_ g: NotchGeometry, placement: NotchPlacement, strip: NotchStrip, scale: CGFloat) -> CGSize {
        let base = unscaledCollapsedSize(g, placement: placement, strip: strip)
        guard placement != .top else { return base }
        return CGSize(width: (base.width * scale).rounded(), height: (base.height * scale).rounded())
    }

    static func unscaledCollapsedSize(_ g: NotchGeometry, placement: NotchPlacement, strip: NotchStrip) -> CGSize {
        let items = strip.all
        switch placement {
        case .top:
            return CGSize(width: (g.hasHardwareNotch ? g.notchWidth : fakeGap) + 2 * strip.wingWidth, height: g.notchHeight)
        case .left, .right:
            let h = items.reduce(0) { $0 + $1.height } + NotchStrip.spacing * 1.25 * CGFloat(max(items.count - 1, 0)) + 20
            return CGSize(width: sideWidth, height: max(h, 52))
        case .floating:
            let w = items.reduce(0) { $0 + $1.width } + NotchStrip.spacing * 1.5 * CGFloat(max(items.count - 1, 0)) + 24
            return CGSize(width: max(w, 80), height: floatingHeight)
        }
    }

    static func expandedSize(_ g: NotchGeometry, placement: NotchPlacement, strip: NotchStrip, scale: CGFloat, width: CGFloat, contentHeight: CGFloat) -> CGSize {
        switch placement {
        case .top:
            // Strip across the top, panel hanging below it.
            let collapsed = unscaledCollapsedSize(g, placement: .top, strip: strip)
            return CGSize(width: max(width, collapsed.width), height: g.notchHeight + contentHeight)
        case .left, .right:
            // Strip stays against the edge, panel opens outward beside it.
            let collapsed = collapsedSize(g, placement: placement, strip: strip, scale: scale)
            let maxHeight = g.screen.visibleFrame.height
            return CGSize(width: collapsed.width + width,
                          height: min(max(collapsed.height, contentHeight), maxHeight))
        case .floating:
            return CGSize(width: width, height: contentHeight)
        }
    }

    /// Screen rectangle for the panel. `floatingOrigin` is the top-left
    /// corner in screen coordinates for the floating placement.
    static func frame(_ g: NotchGeometry, placement: NotchPlacement, size: CGSize, floatingOrigin: CGPoint?) -> NSRect {
        let s = g.screen.frame
        let v = g.screen.visibleFrame
        var rect: NSRect
        switch placement {
        case .top:
            rect = NSRect(x: (s.midX - size.width / 2).rounded(), y: s.maxY - size.height, width: size.width, height: size.height)
            return rect
        case .left:
            rect = NSRect(x: s.minX, y: (v.midY - size.height / 2).rounded(), width: size.width, height: size.height)
        case .right:
            rect = NSRect(x: s.maxX - size.width, y: (v.midY - size.height / 2).rounded(), width: size.width, height: size.height)
        case .floating:
            let origin = floatingOrigin ?? CGPoint(x: v.maxX - size.width - 24, y: v.maxY - 24)
            rect = NSRect(x: origin.x, y: origin.y - size.height, width: size.width, height: size.height)
        }
        return clamp(rect, to: screenContaining(rect, fallback: g.screen).visibleFrame)
    }

    private static func clamp(_ r: NSRect, to v: NSRect) -> NSRect {
        var r = r
        r.origin.x = min(max(r.origin.x, v.minX), v.maxX - r.width)
        r.origin.y = min(max(r.origin.y, v.minY), v.maxY - r.height)
        return r
    }

    private static func screenContaining(_ r: NSRect, fallback: NSScreen) -> NSScreen {
        let topLeft = CGPoint(x: r.minX + 1, y: r.maxY - 1)
        return NSScreen.screens.first { $0.frame.contains(topLeft) } ?? fallback
    }
}
