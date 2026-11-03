import SwiftUI

/// Ring that fills clockwise from 12 o'clock. Turns red near the limit.
struct UsageRing: View {
    var fraction: Double
    var color: Color
    var size: CGFloat = 18
    var lineWidth: CGFloat = 3.5

    private var tint: Color {
        if fraction >= 0.95 { return .red }
        if fraction >= 0.8 { return .orange }
        return color
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(min(fraction, 1), 0.001))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.6), value: fraction)
    }
}

/// Horizontal bar used in the expanded card.
struct UsageBar: View {
    var fraction: Double
    var color: Color

    private var tint: Color {
        if fraction >= 0.95 { return .red }
        if fraction >= 0.8 { return .orange }
        return color
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(tint)
                    .frame(width: max(proxy.size.width * min(fraction, 1), 4))
            }
        }
        .frame(height: 5)
        .animation(.easeOut(duration: 0.6), value: fraction)
    }
}

/// Small coloured dot that says what the account's sessions are doing.
struct ActivityDot: View {
    var counts: SessionCounts
    @State private var pulse = false

    var body: some View {
        Group {
            if counts.waiting > 0 {
                Circle().fill(Color.yellow)
                    .scaleEffect(pulse ? 1.25 : 0.8)
                    .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
                    .onAppear { pulse = true }
            } else if counts.running > 0 {
                Circle().fill(Color.green)
                    .opacity(pulse ? 1 : 0.35)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulse)
                    .onAppear { pulse = true }
            } else if counts.idle > 0 {
                Circle().fill(Color.white.opacity(0.5))
            } else {
                Circle().fill(Color.clear)
            }
        }
        .frame(width: 5, height: 5)
    }
}

struct NotchButtonStyle: ButtonStyle {
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(configuration.isPressed ? 0.55 : 0.85)))
            .contentShape(Capsule())
    }
}
