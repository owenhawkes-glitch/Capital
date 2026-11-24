import SwiftUI
import Combine

// Themes, mesh drift and the travelling glow are copied from DuoNotch's
// Appearance/Appearance.swift and adapted to the menu bar.

enum BarTheme: String, Codable, CaseIterable, Identifiable {
    case black, aurora, sunset, neon, ocean, forest, lavender, dusk, custom

    var id: String { rawValue }
    var name: String {
        switch self {
        case .black: return "Black (plain)"
        case .aurora: return "Aurora — colourful"
        case .sunset: return "Sunset — colourful"
        case .neon: return "Neon — colourful"
        case .ocean: return "Ocean — calm"
        case .forest: return "Forest — calm"
        case .lavender: return "Lavender — calm"
        case .dusk: return "Dusk — calm"
        case .custom: return "Custom — your colours"
        }
    }
    var calm: Bool { [.ocean, .forest, .lavender, .dusk].contains(self) }

    /// Nine mesh colours, row by row (3×3).
    @MainActor
    var colors: [Color] {
        if self == .custom {
            let hexes = BarAppearance.shared.customHexes
            let a = Color(hex: hexes[0]), b = Color(hex: hexes[1]), c = Color(hex: hexes[2])
            let dark = Color(hex: BarAppearance.darken(hexes[1], 0.12))
            let mid = Color(hex: BarAppearance.darken(hexes[0], 0.35))
            return [dark, mid, dark, a, b, c, dark, Color(hex: BarAppearance.darken(hexes[2], 0.35)), dark]
        }
        func c(_ hex: String) -> Color { Color(hex: hex) }
        switch self {
        case .black: return Array(repeating: .black, count: 9)
        case .aurora: return [c("#0B1026"), c("#1B3A6B"), c("#0B1026"), c("#13A38B"), c("#7B3FE4"), c("#1FC8DB"), c("#0B1026"), c("#2A1B5C"), c("#0B1026")]
        case .sunset: return [c("#1A0B1E"), c("#6B1F4A"), c("#1A0B1E"), c("#F06B3B"), c("#C2305A"), c("#F5A623"), c("#1A0B1E"), c("#4A1238"), c("#1A0B1E")]
        case .neon:   return [c("#07070F"), c("#00E5FF"), c("#07070F"), c("#FF2BD6"), c("#3B1CFF"), c("#00FF9D"), c("#07070F"), c("#6A00FF"), c("#07070F")]
        case .ocean:  return [c("#06121C"), c("#0E2C40"), c("#06121C"), c("#123B52"), c("#1A5A6E"), c("#0F3446"), c("#06121C"), c("#0B2233"), c("#06121C")]
        case .forest: return [c("#08130D"), c("#163324"), c("#08130D"), c("#1E4430"), c("#2D5B3E"), c("#183A28"), c("#08130D"), c("#11281B"), c("#08130D")]
        case .lavender: return [c("#110D1A"), c("#2A2142"), c("#110D1A"), c("#3A2C5C"), c("#4E3D78"), c("#33285A"), c("#110D1A"), c("#221A36"), c("#110D1A")]
        case .dusk:   return [c("#0F0D14"), c("#2B2233"), c("#0F0D14"), c("#3D2B3D"), c("#4A3550"), c("#2E2640"), c("#0F0D14"), c("#1E1A28"), c("#0F0D14")]
        case .custom: return []
        }
    }

    var symbol: String {
        switch self {
        case .custom: return "paintpalette.fill"
        case .black, .aurora: return "sparkles"
        case .sunset: return "sun.horizon.fill"
        case .neon: return "bolt.fill"
        case .ocean: return "water.waves"
        case .forest: return "leaf.fill"
        case .lavender: return "moon.stars.fill"
        case .dusk: return "moon.haze.fill"
        }
    }

    /// Bright colours from the theme (dividers, glow).
    @MainActor
    var accentColors: [Color] {
        switch self {
        case .custom: return BarAppearance.shared.customHexes.map { Color(hex: $0) } + [Color(hex: BarAppearance.shared.customHexes[0])]
        case .black: return [Color(hex: "#FF6BA8"), Color(hex: "#4C9BFF"), Color(hex: "#3FD08A"), Color(hex: "#F5C542")]
        default: return [colors[3], colors[4], colors[5], colors[1]]
        }
    }

    /// Seconds per full drift cycle: calm themes move slowly.
    @MainActor
    var period: Double { (calm ? 26 : 11) / BarAppearance.shared.animationSpeed }
}

/// Which parts of the bar get the theme.
enum BarShape: String, Codable, CaseIterable, Identifiable {
    case full, island, split
    var id: String { rawValue }
    var name: String {
        switch self {
        case .full: return "Whole bar"
        case .island: return "Island (status items)"
        case .split: return "Split (menus + items)"
        }
    }
}

/// How the theme covers the bar.
enum FillMode: String, Codable, CaseIterable, Identifiable {
    case tint, cells, outline
    var id: String { rawValue }
    var name: String {
        switch self {
        case .tint: return "Tint"
        case .cells: return "Cells"
        case .outline: return "Glow only"
        }
    }
    var help: String {
        switch self {
        case .tint: return "A see-through wash of colour over the bar."
        case .cells: return "Solid colour with every menu and item sitting in its own dark cell (needs Accessibility to find them; falls back to Tint)."
        case .outline: return "No fill: just the shape's glowing edge and shadow."
        }
    }
}

/// Where the appearance window sits.
enum OverlayLayer: String, Codable, CaseIterable, Identifiable {
    case above, behind
    var id: String { rawValue }
    var name: String {
        switch self {
        case .above: return "Over the bar (works with any bar)"
        case .behind: return "Behind the bar (only for a see-through menu bar)"
        }
    }
}

@MainActor
final class BarAppearance: ObservableObject {
    static let shared = BarAppearance()

    @Published var enabled: Bool { didSet { save(enabled, "look.enabled") } }
    @Published var theme: BarTheme { didSet { save(theme.rawValue, "look.theme") } }
    @Published var customHexes: [String] { didSet { save(customHexes, "look.customHexes") } }
    @Published var shape: BarShape { didSet { save(shape.rawValue, "look.shape") } }
    @Published var fillMode: FillMode { didSet { save(fillMode.rawValue, "look.fill") } }
    @Published var layer: OverlayLayer { didSet { save(layer.rawValue, "look.layer") } }
    /// 0.1…0.8: how strongly Tint colours the bar.
    @Published var tintOpacity: Double { didSet { save(tintOpacity, "look.tint") } }
    @Published var cornerRadius: Double { didSet { save(cornerRadius, "look.corner") } }
    @Published var glowBorder: Bool { didSet { save(glowBorder, "look.glow") } }
    @Published var shadow: Bool { didSet { save(shadow, "look.shadow") } }
    /// Keep the bar untouched until the pointer is over it.
    @Published var plainUntilHovered: Bool { didSet { save(plainUntilHovered, "look.plainUntilHovered") } }
    /// 0.5 (slow) … 2 (fast): theme drift and glow speed.
    @Published var animationSpeed: Double { didSet { save(animationSpeed, "look.speed") } }

    private init() {
        let d = UserDefaults.standard
        enabled = d.bool(forKey: "look.enabled")
        theme = BarTheme(rawValue: d.string(forKey: "look.theme") ?? "") ?? .aurora
        customHexes = d.stringArray(forKey: "look.customHexes").flatMap { $0.count == 3 ? $0 : nil } ?? ["#FF6BA8", "#7B3FE4", "#2FD1C8"]
        shape = BarShape(rawValue: d.string(forKey: "look.shape") ?? "") ?? .split
        fillMode = FillMode(rawValue: d.string(forKey: "look.fill") ?? "") ?? .tint
        layer = OverlayLayer(rawValue: d.string(forKey: "look.layer") ?? "") ?? .above
        let tint = d.double(forKey: "look.tint")
        tintOpacity = tint > 0 ? tint : 0.35
        cornerRadius = d.object(forKey: "look.corner") as? Double ?? 8
        glowBorder = d.object(forKey: "look.glow") as? Bool ?? true
        shadow = d.object(forKey: "look.shadow") as? Bool ?? true
        plainUntilHovered = d.bool(forKey: "look.plainUntilHovered")
        let speed = d.double(forKey: "look.speed")
        animationSpeed = speed > 0 ? speed : 1
    }

    /// Everything about the look, for presets.
    var snapshot: AppearanceSnapshot {
        get {
            AppearanceSnapshot(enabled: enabled, theme: theme, customHexes: customHexes, shape: shape, fillMode: fillMode,
                               tintOpacity: tintOpacity, cornerRadius: cornerRadius, glowBorder: glowBorder, shadow: shadow,
                               plainUntilHovered: plainUntilHovered, animationSpeed: animationSpeed)
        }
        set {
            enabled = newValue.enabled; theme = newValue.theme; customHexes = newValue.customHexes
            shape = newValue.shape; fillMode = newValue.fillMode; tintOpacity = newValue.tintOpacity
            cornerRadius = newValue.cornerRadius; glowBorder = newValue.glowBorder; shadow = newValue.shadow
            plainUntilHovered = newValue.plainUntilHovered; animationSpeed = newValue.animationSpeed
        }
    }

    static func darken(_ hex: String, _ factor: Double) -> String {
        let c = Color(hex: hex).hexString
        var value: UInt64 = 0
        Scanner(string: String(c.dropFirst())).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) * factor, g = Double((value >> 8) & 0xFF) * factor, b = Double(value & 0xFF) * factor
        return String(format: "#%02X%02X%02X", Int(r), Int(g), Int(b))
    }

    /// The colours travelling around the edge (also used by glow dividers).
    var glowColors: [Color] {
        theme == .black
            ? [Color(hex: "#FF6BA8"), Color(hex: "#4C9BFF"), Color(hex: "#3FD08A"), Color(hex: "#F5C542"), Color(hex: "#FF6BA8")]
            : theme.colors.filter { $0 != .black } + [theme.colors[1]]
    }

    /// Where the glow is right now (degrees), so dividers move in step.
    static func glowAngle(at date: Date) -> Double {
        if reduceMotion { return 30 }
        let period = 8 / BarAppearance.shared.animationSpeed
        return date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period * 360
    }

    private func save(_ value: Any?, _ key: String) {
        if let value { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
    }
}

struct AppearanceSnapshot: Codable, Equatable {
    var enabled: Bool
    var theme: BarTheme
    var customHexes: [String]
    var shape: BarShape
    var fillMode: FillMode
    var tintOpacity: Double
    var cornerRadius: Double
    var glowBorder: Bool
    var shadow: Bool
    var plainUntilHovered: Bool
    var animationSpeed: Double
}

/// The theme's fill: black, or a slowly drifting mesh gradient. Still when
/// Reduce Motion is on.
struct ThemeBackground: View {
    @ObservedObject private var look = BarAppearance.shared

    var body: some View {
        if look.theme == .black {
            Color.black
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: reduceMotion)) { context in
                let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate * 2 * .pi / look.theme.period
                if #available(macOS 15.0, *) {
                    MeshGradient(width: 3, height: 3, points: Self.points(t), colors: look.theme.colors, smoothsColors: true)
                } else {
                    LinearGradient(colors: [look.theme.colors[3], look.theme.colors[4], look.theme.colors[5]],
                                   startPoint: UnitPoint(x: 0.5 + 0.5 * cos(t), y: 0),
                                   endPoint: UnitPoint(x: 0.5 - 0.5 * cos(t), y: 1))
                }
            }
        }
    }

    static func points(_ t: Double) -> [SIMD2<Float>] {
        func w(_ base: Float, _ amp: Float, _ phase: Double) -> Float { base + amp * Float(sin(t + phase)) }
        return [
            [0, 0], [w(0.5, 0.18, 0), 0], [1, 0],
            [0, w(0.5, 0.2, 1.3)], [w(0.5, 0.22, 2.1), w(0.5, 0.2, 0.7)], [1, w(0.5, 0.2, 2.9)],
            [0, 1], [w(0.5, 0.18, 1.7), 1], [1, 1],
        ]
    }
}

/// A soft glow that travels around a shape's edge.
struct GlowBorder<S: Shape>: View {
    let shape: S
    @ObservedObject private var look = BarAppearance.shared

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let angle = BarAppearance.glowAngle(at: context.date)
            shape
                .stroke(AngularGradient(colors: look.glowColors, center: .center, angle: .degrees(angle)), lineWidth: 1.5)
                .blur(radius: 0.6)
                .opacity(look.theme.calm ? 0.6 : 0.9)
        }
        .allowsHitTesting(false)
    }
}

/// Fills a shape with the glow's bright colours, sliding along it in step
/// with the glow around the bar (used by "match the glow" dividers).
struct GlowFill<S: Shape>: View {
    let shape: S
    @ObservedObject private var look = BarAppearance.shared

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let phase = BarAppearance.glowAngle(at: context.date) / 360
            let bright = look.theme.accentColors
            let colors = bright + bright + [bright[0]]
            shape
                .fill(LinearGradient(colors: colors,
                                     startPoint: UnitPoint(x: 0.5, y: -phase * 2),
                                     endPoint: UnitPoint(x: 0.5, y: 2 - phase * 2)))
                .shadow(color: bright[Int(phase * Double(bright.count)) % bright.count].opacity(0.8), radius: 2.5)
        }
    }
}

/// A small swatch of a theme for the settings grid.
struct ThemeSwatch: View {
    let theme: BarTheme
    var body: some View {
        if theme == .black {
            Color.black
        } else if #available(macOS 15.0, *) {
            MeshGradient(width: 3, height: 3, points: [[0, 0], [0.5, 0], [1, 0], [0, 0.5], [0.55, 0.45], [1, 0.5], [0, 1], [0.5, 1], [1, 1]],
                         colors: theme.colors)
        } else {
            LinearGradient(colors: Array(theme.colors[3...5]), startPoint: .leading, endPoint: .trailing)
        }
    }
}
