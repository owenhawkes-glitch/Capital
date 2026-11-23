import SwiftUI
import AppKit

/// How an icon moves.
enum IconAnimation: String, Codable, CaseIterable, Identifiable {
    case none, pulse, breathe, bounce, wiggle, rotate, colour
    var id: String { rawValue }
    var name: String {
        switch self {
        case .none: return "Still"
        case .pulse: return "Pulse"
        case .breathe: return "Breathe"
        case .bounce: return "Bounce"
        case .wiggle: return "Wiggle"
        case .rotate: return "Rotate"
        case .colour: return "Colour cycle"
        }
    }
}

/// Applies a looping SF Symbol effect, unless animations are off or macOS
/// is set to reduce motion.
struct SymbolAnimation: ViewModifier {
    let style: IconAnimation
    var active = true
    @ObservedObject private var look = AppearanceStore.shared

    private var enabled: Bool {
        active && style != .none && look.animatedIcons && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func body(content: Content) -> some View {
        if !enabled {
            content
        } else {
            switch style {
            case .none:
                content
            case .pulse:
                content.symbolEffect(.pulse, isActive: true)
            case .colour:
                content.symbolEffect(.variableColor.iterative.reversing, isActive: true)
            case .breathe:
                if #available(macOS 15.0, *) {
                    content.symbolEffect(.breathe, isActive: true)
                } else {
                    content.symbolEffect(.pulse, isActive: true)
                }
            case .bounce:
                if #available(macOS 15.0, *) {
                    content.symbolEffect(.bounce, options: .repeat(.periodic(delay: 1.4)), isActive: true)
                } else {
                    content.symbolEffect(.pulse, isActive: true)
                }
            case .wiggle:
                if #available(macOS 15.0, *) {
                    content.symbolEffect(.wiggle, options: .repeat(.periodic(delay: 1.8)), isActive: true)
                } else {
                    content.symbolEffect(.pulse, isActive: true)
                }
            case .rotate:
                if #available(macOS 15.0, *) {
                    content.symbolEffect(.rotate, options: .speed(0.25), isActive: true)
                } else {
                    content.symbolEffect(.pulse, isActive: true)
                }
            }
        }
    }
}

/// A gentle breathing scale for custom images (which can't use symbol effects).
struct ImageBreathe: ViewModifier {
    var active: Bool
    @ObservedObject private var look = AppearanceStore.shared

    func body(content: Content) -> some View {
        if active && look.animatedIcons && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                content.scaleEffect(1 + 0.06 * sin(t * 2 * .pi / 3.2))
            }
        } else {
            content
        }
    }
}

extension View {
    func animatedSymbol(_ style: IconAnimation, active: Bool = true) -> some View {
        modifier(SymbolAnimation(style: style, active: active))
    }
}

extension WeatherStore {
    /// A calm movement that suits the conditions.
    static func animation(for code: Int, day: Bool) -> IconAnimation {
        switch code {
        case 0: return day ? .rotate : .breathe
        case 51...67, 71...77, 80...86: return .colour
        case 95...99: return .pulse
        default: return .breathe
        }
    }
}
