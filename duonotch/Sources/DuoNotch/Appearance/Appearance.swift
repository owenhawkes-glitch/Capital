import SwiftUI
import Combine

enum NotchTheme: String, Codable, CaseIterable, Identifiable {
    case black, aurora, sunset, neon, ocean, forest, lavender, dusk

    var id: String { rawValue }
    var name: String {
        switch self {
        case .black: return "Black (classic notch)"
        case .aurora: return "Aurora — colourful"
        case .sunset: return "Sunset — colourful"
        case .neon: return "Neon — colourful"
        case .ocean: return "Ocean — calm"
        case .forest: return "Forest — calm"
        case .lavender: return "Lavender — calm"
        case .dusk: return "Dusk — calm"
        }
    }
    var calm: Bool { [.ocean, .forest, .lavender, .dusk].contains(self) }

    /// Nine mesh colours, row by row (3×3).
    var colors: [Color] {
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
        }
    }

    /// Seconds per full drift cycle: calm themes move slowly.
    var period: Double { calm ? 26 : 11 }
}

enum OpenAnimation: String, Codable, CaseIterable, Identifiable {
    case spring, smooth, bouncy, snappy, gentle
    var id: String { rawValue }
    var name: String {
        switch self {
        case .spring: return "Spring"
        case .smooth: return "Smooth"
        case .bouncy: return "Bouncy"
        case .snappy: return "Snappy"
        case .gentle: return "Gentle"
        }
    }
    var animation: Animation {
        switch self {
        case .spring: return .spring(response: 0.32, dampingFraction: 0.86)
        case .smooth: return .easeInOut(duration: 0.3)
        case .bouncy: return .spring(response: 0.42, dampingFraction: 0.62)
        case .snappy: return .spring(response: 0.2, dampingFraction: 0.95)
        case .gentle: return .easeInOut(duration: 0.55)
        }
    }
}

@MainActor
final class AppearanceStore: ObservableObject {
    static let shared = AppearanceStore()

    @Published var theme: NotchTheme { didSet { save(theme.rawValue, "appearance.theme") } }
    @Published var glowBorder: Bool { didSet { save(glowBorder, "appearance.glow") } }
    @Published var openAnimation: OpenAnimation { didSet { save(openAnimation.rawValue, "appearance.animation") } }
    /// SF Symbol for the notch icon item.
    @Published var logoSymbol: String { didSet { save(logoSymbol, "appearance.logoSymbol") } }
    /// Optional custom image file used instead of the symbol.
    @Published var logoImagePath: String? { didSet { save(logoImagePath, "appearance.logoImage") } }

    static let logoChoices = ["sparkles", "bolt.fill", "moon.stars.fill", "flame.fill", "leaf.fill", "star.fill",
                              "heart.fill", "waveform", "cpu", "chart.line.uptrend.xyaxis", "globe.europe.africa.fill",
                              "music.note", "gamecontroller.fill", "terminal.fill", "apple.logo"]

    private init() {
        let d = UserDefaults.standard
        theme = NotchTheme(rawValue: d.string(forKey: "appearance.theme") ?? "") ?? .black
        glowBorder = d.bool(forKey: "appearance.glow")
        openAnimation = OpenAnimation(rawValue: d.string(forKey: "appearance.animation") ?? "") ?? .spring
        logoSymbol = d.string(forKey: "appearance.logoSymbol") ?? "sparkles"
        logoImagePath = d.string(forKey: "appearance.logoImage")
    }

    var logoImage: NSImage? {
        guard let logoImagePath else { return nil }
        return NSImage(contentsOfFile: logoImagePath)
    }

    private func save(_ value: Any?, _ key: String) {
        if let value { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
    }
}

/// The notch's fill: black, or a slowly drifting mesh gradient.
struct NotchBackground: View {
    @ObservedObject private var look = AppearanceStore.shared
    var expanded: Bool

    var body: some View {
        if look.theme == .black {
            Color.black
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate * 2 * .pi / look.theme.period
                Group {
                    if #available(macOS 15.0, *) {
                        MeshGradient(width: 3, height: 3, points: Self.points(t), colors: look.theme.colors, smoothsColors: true)
                    } else {
                        LinearGradient(colors: [look.theme.colors[3], look.theme.colors[4], look.theme.colors[5]],
                                       startPoint: UnitPoint(x: 0.5 + 0.5 * cos(t), y: 0),
                                       endPoint: UnitPoint(x: 0.5 - 0.5 * cos(t), y: 1))
                    }
                }
                // Keep text readable on the open panel.
                .overlay(Color.black.opacity(expanded ? 0.42 : 0.15))
            }
        }
    }

    private static func points(_ t: Double) -> [SIMD2<Float>] {
        func w(_ base: Float, _ amp: Float, _ phase: Double) -> Float { base + amp * Float(sin(t + phase)) }
        return [
            [0, 0], [w(0.5, 0.18, 0), 0], [1, 0],
            [0, w(0.5, 0.2, 1.3)], [w(0.5, 0.22, 2.1), w(0.5, 0.2, 0.7)], [1, w(0.5, 0.2, 2.9)],
            [0, 1], [w(0.5, 0.18, 1.7), 1], [1, 1],
        ]
    }
}

/// An optional soft glow that travels around the notch's edge.
struct GlowBorder<S: Shape>: View {
    let shape: S
    @ObservedObject private var look = AppearanceStore.shared

    var body: some View {
        if look.glowBorder {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let angle = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 8) / 8 * 360
                let colors = look.theme == .black
                    ? [Color(hex: "#FF6BA8"), Color(hex: "#4C9BFF"), Color(hex: "#3FD08A"), Color(hex: "#F5C542"), Color(hex: "#FF6BA8")]
                    : look.theme.colors.filter { $0 != .black } + [look.theme.colors[1]]
                shape
                    .stroke(AngularGradient(colors: colors, center: .center, angle: .degrees(angle)), lineWidth: 1.5)
                    .blur(radius: 0.6)
                    .opacity(look.theme.calm ? 0.6 : 0.9)
            }
            .allowsHitTesting(false)
        }
    }
}
