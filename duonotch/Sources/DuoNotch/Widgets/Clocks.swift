import SwiftUI
import Combine

enum ClockStyle: String, Codable, CaseIterable, Identifiable {
    case analog, digital12, digital24, flip
    var id: String { rawValue }
    var name: String {
        switch self {
        case .analog: return "Simple (hands only)"
        case .digital12: return "Digital 12-hour"
        case .digital24: return "Digital 24-hour"
        case .flip: return "Flip clock"
        }
    }
}

struct ClockConfig: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var label: String
    var timeZoneID: String
    var style: ClockStyle
    var showSeconds = false

    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }
    var isLocal: Bool { timeZoneID == TimeZone.current.identifier }
}

@MainActor
final class ClockStore: ObservableObject {
    static let shared = ClockStore()

    @Published var clocks: [ClockConfig] {
        didSet {
            if let data = try? JSONEncoder().encode(clocks) { UserDefaults.standard.set(data, forKey: "clocks.v1") }
        }
    }

    static let worldPresets: [(String, String)] = [
        ("London", "Europe/London"), ("New York", "America/New_York"), ("Chicago", "America/Chicago"),
        ("Los Angeles", "America/Los_Angeles"), ("Frankfurt", "Europe/Berlin"), ("Dubai", "Asia/Dubai"),
        ("Singapore", "Asia/Singapore"), ("Hong Kong", "Asia/Hong_Kong"), ("Tokyo", "Asia/Tokyo"),
        ("Sydney", "Australia/Sydney"),
    ]

    private init() {
        if let data = UserDefaults.standard.data(forKey: "clocks.v1"),
           let decoded = try? JSONDecoder().decode([ClockConfig].self, from: data) {
            clocks = decoded
        } else {
            clocks = [ClockConfig(label: "", timeZoneID: TimeZone.current.identifier, style: .digital24)]
        }
    }

    func add(label: String, zone: String, style: ClockStyle = .digital24) {
        clocks.append(ClockConfig(label: label, timeZoneID: zone, style: style))
    }

    func remove(_ clock: ClockConfig) { clocks.removeAll { $0.id == clock.id } }

    func move(dragged: String, onto target: String) {
        guard let from = clocks.firstIndex(where: { $0.id.uuidString == dragged }),
              let to = clocks.firstIndex(where: { $0.id.uuidString == target }) else { return }
        let item = clocks.remove(at: from)
        clocks.insert(item, at: to)
    }
}

// MARK: - Faces

/// One clock face at any size. `size` is the height of the face.
struct ClockFace: View {
    let clock: ClockConfig
    var size: CGFloat = 18
    var color: Color = .white

    var body: some View {
        TimelineView(.periodic(from: .now, by: clock.showSeconds || clock.style == .analog ? 1 : 5)) { context in
            let parts = Self.components(context.date, clock.timeZone)
            switch clock.style {
            case .analog:
                AnalogFace(hour: parts.hour, minute: parts.minute, second: clock.showSeconds ? parts.second : nil, color: color)
                    .frame(width: size, height: size)
            case .digital12, .digital24:
                digital(parts)
            case .flip:
                FlipTime(hour: clock.style == .flip ? parts.hour : parts.hour, minute: parts.minute, size: size, color: color)
            }
        }
    }

    private func digital(_ p: (hour: Int, minute: Int, second: Int)) -> some View {
        let h = clock.style == .digital12 ? (p.hour % 12 == 0 ? 12 : p.hour % 12) : p.hour
        let main = clock.style == .digital12 ? "\(h):\(String(format: "%02d", p.minute))" : String(format: "%02d:%02d", h, p.minute)
        return HStack(alignment: .firstTextBaseline, spacing: size * 0.12) {
            Text(main + (clock.showSeconds ? String(format: ":%02d", p.second) : ""))
                .font(.system(size: size * 0.72, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            if clock.style == .digital12 {
                Text(p.hour < 12 ? "AM" : "PM")
                    .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(color)
        .animation(.easeInOut(duration: 0.3), value: p.minute)
    }

    static func components(_ date: Date, _ zone: TimeZone) -> (hour: Int, minute: Int, second: Int) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let c = cal.dateComponents([.hour, .minute, .second], from: date)
        return (c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }
}

/// A clean dial with just hour and minute hands (and optional seconds).
struct AnalogFace: View {
    let hour: Int
    let minute: Int
    let second: Int?
    var color: Color = .white

    var body: some View {
        Canvas { ctx, size in
            let r = min(size.width, size.height) / 2
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let line = max(r * 0.12, 1)
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r + line / 2, y: c.y - r + line / 2, width: 2 * r - line, height: 2 * r - line)),
                       with: .color(color.opacity(0.9)), lineWidth: line)
            func hand(_ fraction: Double, _ length: CGFloat, _ width: CGFloat, _ shade: Color) {
                let angle = fraction * 2 * .pi - .pi / 2
                var p = Path()
                p.move(to: c)
                p.addLine(to: CGPoint(x: c.x + cos(angle) * length, y: c.y + sin(angle) * length))
                ctx.stroke(p, with: .color(shade), style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
            let m = Double(minute) + Double(second ?? 0) / 60
            hand((Double(hour % 12) + m / 60) / 12, r * 0.5, max(line * 1.1, 1.2), color)
            hand(m / 60, r * 0.75, max(line * 0.85, 1), color)
            if let second { hand(Double(second) / 60, r * 0.8, max(line * 0.4, 0.6), .orange) }
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - line, y: c.y - line, width: 2 * line, height: 2 * line)), with: .color(color))
        }
    }
}

/// HH MM on dark cards that flip when they change.
struct FlipTime: View {
    let hour: Int
    let minute: Int
    let size: CGFloat
    var color: Color = .white

    var body: some View {
        HStack(spacing: size * 0.12) {
            FlipCard(text: String(format: "%02d", hour), size: size, color: color)
            FlipCard(text: String(format: "%02d", minute), size: size, color: color)
        }
    }
}

struct FlipCard: View {
    let text: String
    let size: CGFloat
    var color: Color = .white

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.22), Color(white: 0.12)], startPoint: .top, endPoint: .bottom))
            Text(text)
                .font(.system(size: size * 0.7, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .id(text)
                .transition(.asymmetric(
                    insertion: .modifier(active: FlipEffect(angle: -90), identity: FlipEffect(angle: 0)),
                    removal: .modifier(active: FlipEffect(angle: 90), identity: FlipEffect(angle: 0))))
            Rectangle().fill(Color.black.opacity(0.55)).frame(height: max(size * 0.03, 0.75))
        }
        .frame(width: size * 1.05, height: size)
        .clipped()
        .animation(.easeInOut(duration: 0.45), value: text)
    }
}

struct FlipEffect: ViewModifier, Animatable {
    var angle: Double
    var animatableData: Double { get { angle } set { angle = newValue } }
    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .opacity(abs(angle) > 85 ? 0 : 1)
    }
}

// MARK: - Panel card

struct ClocksCard: View {
    @ObservedObject private var store = ClockStore.shared

    var body: some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Clocks").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                FlowLayout(spacing: 14) {
                    ForEach(store.clocks) { clock in
                        VStack(spacing: 4) {
                            ClockFace(clock: clock, size: clock.style == .analog ? 44 : 30)
                            Text(clock.label.isEmpty ? (clock.isLocal ? "Local" : clock.timeZone.identifier.components(separatedBy: "/").last ?? "") : clock.label)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .reorderSource(id: clock.id.uuidString)
                        .reorderTarget(id: clock.id.uuidString) { store.move(dragged: $0, onto: $1) }
                    }
                }
            }
        }
    }
}
