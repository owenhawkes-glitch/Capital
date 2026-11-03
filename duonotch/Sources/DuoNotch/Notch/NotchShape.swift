import SwiftUI

/// Black slab hanging from the top edge: square top corners (flush with the
/// screen edge), rounded bottom corners, small outward "ears" at the top so
/// it blends into the menu bar the way the hardware notch does.
struct NotchShape: Shape {
    var bottomRadius: CGFloat
    var earRadius: CGFloat = 0

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(bottomRadius, rect.height / 2, rect.width / 2)
        let e = min(earRadius, r)

        p.move(to: CGPoint(x: rect.minX - e, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX + e, y: rect.minY))
        // top-right ear curving inward
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + e),
                       control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY),
                       control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r),
                       control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + e))
        p.addQuadCurve(to: CGPoint(x: rect.minX - e, y: rect.minY),
                       control: CGPoint(x: rect.minX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
