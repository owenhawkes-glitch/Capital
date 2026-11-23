import SwiftUI
import AppKit

/// Something that can sit in the closed notch.
enum NotchItemKind: Codable, Hashable {
    case account(String)   // config dir
    case app(UUID)         // AppShortcut id
    case clipboard
    case chats
    case media
    case files
    case link(UUID)        // QuickLink id
    case clock(UUID)       // ClockConfig id
    case ticker(UUID)      // Ticker id
    case weather
    case logo
}

enum NotchSide: String, Codable, CaseIterable, Identifiable {
    case left, right
    var id: String { rawValue }
    var name: String { self == .left ? "Left" : "Right" }
}

struct NotchItem: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var kind: NotchItemKind
    var side: NotchSide
    var enabled: Bool
    /// Ring colour for apps, clipboard and chats. Accounts use their own colour.
    var colorHex: String

    @MainActor
    var width: CGFloat {
        switch kind {
        case .clock(let id):
            guard let clock = ClockStore.shared.clocks.first(where: { $0.id == id }) else { return 0 }
            let label: CGFloat = clock.isLocal && clock.label.isEmpty ? 0 : 26
            switch clock.style {
            case .analog: return 20 + label
            case .digital24: return 44 + label + (clock.showSeconds ? 20 : 0)
            case .digital12: return 58 + label + (clock.showSeconds ? 20 : 0)
            case .flip: return 44 + label
            }
        case .ticker: return 118
        case .weather: return 46
        case .logo: return 20
        case .account: return 62
        case .app: return 22
        case .clipboard, .chats, .files: return 40
        case .media: return 96
        case .link: return 22
        }
    }

    /// Height when stacked on a side edge.
    @MainActor
    var height: CGFloat {
        switch kind {
        case .clock, .weather: return 34
        case .ticker: return 40
        case .logo: return 22
        case .account: return 34
        case .app: return 24
        case .clipboard, .chats, .files: return 32
        case .media, .link: return 24
        }
    }
}

/// The items actually shown, split by side.
struct NotchStrip: Equatable {
    var left: [NotchItem]
    var right: [NotchItem]

    var all: [NotchItem] { left + right }
    static let spacing: CGFloat = 8
    static let padding: CGFloat = 20

    @MainActor
    static func width(of items: [NotchItem]) -> CGFloat {
        guard !items.isEmpty else { return 0 }
        return items.reduce(0) { $0 + $1.width } + spacing * CGFloat(items.count - 1) + padding
    }

    /// Both wings get the wider of the two so the notch stays centred.
    @MainActor
    var wingWidth: CGFloat { max(Self.width(of: left), Self.width(of: right), 40) }
}

/// One item drawn in the closed notch.
struct NotchItemView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var apps = AppShortcutStore.shared
    @ObservedObject private var clipboard = ClipboardStore.shared
    @ObservedObject private var media = MediaStore.shared
    @ObservedObject private var shelf = FileShelf.shared
    @ObservedObject private var links = LinkStore.shared
    @ObservedObject private var clocks = ClockStore.shared
    @ObservedObject private var weather = WeatherStore.shared
    @ObservedObject private var markets = MarketStore.shared
    @ObservedObject private var look = AppearanceStore.shared
    let item: NotchItem
    var vertical = false
    /// Real layout scale (not a zoom), so icons and text stay sharp.
    var scale: CGFloat = 1

    private func px(_ v: CGFloat) -> CGFloat { (v * scale).rounded() }

    var body: some View {
        if case .media = item.kind {
            content
        } else {
            content.reorderSource(id: item.id.uuidString)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .account(let id):
            if let account = state.accounts.first(where: { $0.id == id }) {
                accountView(account)
            }
        case .app(let id):
            if let app = apps.shortcuts.first(where: { $0.id == id }) {
                Button { apps.open(app) } label: {
                    imageRing(Image(nsImage: apps.icon(for: app)), active: apps.isRunning(app))
                }
                .buttonStyle(.plain)
                .help(app.name + (apps.isRunning(app) ? " (running)" : ""))
            }
        case .link(let id):
            if let link = links.links.first(where: { $0.id == id }) {
                Button { links.open(link) } label: {
                    if let icon = links.icon(for: link) {
                        imageRing(Image(nsImage: icon), active: true)
                    } else {
                        symbolRing("link", color: Color(hex: item.colorHex), active: true)
                    }
                }
                .buttonStyle(.plain)
                .help("\(link.title)\n\(link.url)")
            }
        case .clipboard:
            Button { state.show(tab: .clipboard) } label: {
                badge(symbol: "doc.on.clipboard", count: clipboard.history.count,
                      color: Color(hex: item.colorHex), active: !clipboard.history.isEmpty)
            }
            .buttonStyle(.plain)
            .help("Clipboard: \(clipboard.history.count) recent, \(clipboard.snippets.count) snippets")
        case .chats:
            let running = state.sessions.filter { $0.state == .running }.count
            let waiting = state.sessions.filter { $0.state == .waiting }.count
            Button { state.show(tab: .claude) } label: {
                badge(symbol: "bubble.left.and.bubble.right", count: running + waiting,
                      color: waiting > 0 ? .yellow : Color(hex: item.colorHex), active: running + waiting > 0)
            }
            .buttonStyle(.plain)
            .help("\(running) running, \(waiting) waiting on you")
        case .media:
            let playing = media.track?.isPlaying == true
            HStack(spacing: px(6)) {
                Button { media.playPause() } label: {
                    symbolRing(playing ? "pause.fill" : "play.fill", color: Color(hex: item.colorHex), active: playing)
                }
                .buttonStyle(.plain)
                .help(media.track.map { "\($0.title) · \($0.artist)" } ?? "Play / pause")
                .reorderSource(id: item.id.uuidString)
                if !vertical {
                    VolumeSlider(value: media.volume ?? 50, color: Color(hex: item.colorHex)) { media.setVolume($0) }
                        .frame(width: px(66), height: px(14))
                        .onAppear { media.refresh() }
                }
            }
        case .clock(let id):
            if let clock = clocks.clocks.first(where: { $0.id == id }) {
                let face = ClockFace(clock: clock, size: px(vertical ? 16 : 17), color: .white)
                let layout = vertical ? AnyLayout(VStackLayout(spacing: px(2))) : AnyLayout(HStackLayout(spacing: px(4)))
                layout {
                    if !(clock.isLocal && clock.label.isEmpty) {
                        Text(Self.short(clock))
                            .font(.system(size: px(8), weight: .bold, design: .rounded))
                            .foregroundStyle(Color(hex: item.colorHex))
                    }
                    face
                }
                .help("\(clock.label.isEmpty ? clock.timeZone.identifier : clock.label)")
            }
        case .weather:
            let layout = vertical ? AnyLayout(VStackLayout(spacing: px(2))) : AnyLayout(HStackLayout(spacing: px(4)))
            Button { state.show(tab: .widgets) } label: {
                layout {
                    Image(systemName: WeatherStore.symbol(weather.code, day: weather.isDay))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: px(12)))
                    Text(weather.temp(weather.temperature))
                        .font(.system(size: px(vertical ? 9 : 11), weight: .semibold, design: .rounded))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(weather.resolvedName.isEmpty ? weather.city : weather.resolvedName)
            .onAppear { weather.refreshIfStale() }
        case .ticker(let id):
            if let ticker = markets.tickers.first(where: { $0.id == id }) {
                let quote = markets.quotes[ticker.symbol]
                let up = (quote?.change ?? 0) >= 0
                Button { markets.open(ticker) } label: {
                    let layout = vertical ? AnyLayout(VStackLayout(spacing: px(1))) : AnyLayout(HStackLayout(spacing: px(4)))
                    layout {
                        Text(ticker.name)
                            .font(.system(size: px(vertical ? 7 : 9), weight: .bold, design: .rounded))
                            .foregroundStyle(Color(hex: item.colorHex))
                            .lineLimit(1)
                        Text(quote.map { MarketStore.format($0.price) } ?? "–")
                            .font(.system(size: px(vertical ? 8 : 10), weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Image(systemName: up ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                            .font(.system(size: px(6)))
                            .foregroundStyle(up ? Color.green : Color.red)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(ticker.name) \(quote.map { String(format: "%+.2f%%", $0.change) } ?? "") — open on TradingView")
            }
        case .logo:
            Button { AppState.openSettings() } label: {
                Group {
                    if let image = look.logoImage {
                        Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: px(4), style: .continuous))
                    } else {
                        Image(systemName: look.logoSymbol)
                            .resizable().aspectRatio(contentMode: .fit)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color(hex: item.colorHex))
                    }
                }
                .frame(width: px(15), height: px(15))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        case .files:
            Button { state.show(tab: .files) } label: {
                badge(symbol: "tray.full", count: shelf.files.count,
                      color: Color(hex: item.colorHex), active: !shelf.files.isEmpty)
            }
            .buttonStyle(.plain)
            .help("File shelf: \(shelf.files.count) files. Drop files on the notch to park them.")
        }
    }

    static func short(_ clock: ClockConfig) -> String {
        let source = clock.label.isEmpty ? (clock.timeZone.identifier.components(separatedBy: "/").last ?? "") : clock.label
        let words = source.replacingOccurrences(of: "_", with: " ").split(separator: " ")
        if words.count > 1 { return words.prefix(2).map { String($0.prefix(1)) }.joined().uppercased() }
        return String(source.prefix(3)).uppercased()
    }

    /// An app or site icon inside a coloured ring, drawn at full resolution.
    private func imageRing(_ image: Image, active: Bool) -> some View {
        ZStack {
            Circle().stroke(Color(hex: item.colorHex).opacity(active ? 1 : 0.3), lineWidth: max(2, 2 * scale))
            image
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .aspectRatio(contentMode: .fit)
                .frame(width: px(13), height: px(13))
                .clipShape(RoundedRectangle(cornerRadius: px(3), style: .continuous))
        }
        .frame(width: px(19), height: px(19))
        .contentShape(Circle())
    }

    private func symbolRing(_ symbol: String, color: Color, active: Bool) -> some View {
        ZStack {
            Circle().stroke(color.opacity(active ? 1 : 0.35), lineWidth: max(2, 2 * scale))
            Image(systemName: symbol)
                .font(.system(size: px(7), weight: .bold))
                .foregroundStyle(color)
                // A play triangle's weight sits left of its box; nudge it so it looks centred.
                .offset(x: symbol.hasPrefix("play") ? 0.8 * scale : 0)
        }
        .frame(width: px(18), height: px(18))
        .contentShape(Circle())
    }

    private func accountView(_ account: Account) -> some View {
        let window = state.readings[account.id]?.headline
        let layout = vertical ? AnyLayout(VStackLayout(spacing: px(3))) : AnyLayout(HStackLayout(spacing: px(5)))
        return layout {
            ZStack(alignment: .topTrailing) {
                UsageRing(fraction: window?.fraction ?? 0, color: account.color, size: px(18), lineWidth: 3.5 * scale)
                ActivityDot(counts: state.counts(for: account.id))
                    .scaleEffect(scale)
                    .offset(x: px(3), y: px(-2))
            }
            Text(window.map { "\($0.percent)%" } ?? "–")
                .font(.system(size: px(vertical ? 9 : 11), weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(window == nil ? Color.secondary : Color.primary)
        }
        .help(account.label)
    }

    private func badge(symbol: String, count: Int, color: Color, active: Bool) -> some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: px(2))) : AnyLayout(HStackLayout(spacing: px(4)))
        return layout {
            ZStack {
                Circle().stroke(color.opacity(active ? 1 : 0.3), lineWidth: max(2, 2 * scale))
                Image(systemName: symbol).font(.system(size: px(7), weight: .bold)).foregroundStyle(color)
            }
            .frame(width: px(17), height: px(17))
            Text("\(count)")
                .font(.system(size: px(vertical ? 9 : 11), weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(active ? Color.primary : Color.secondary)
        }
        .contentShape(Rectangle())
    }
}

/// A small horizontal volume slider for the closed notch.
struct VolumeSlider: View {
    var value: Double          // 0…100
    var color: Color
    var onChange: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let fraction = min(max(value / 100, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18)).frame(height: 4)
                Capsule().fill(color).frame(width: max(w * fraction, 4), height: 4)
                Circle().fill(Color.white)
                    .frame(width: 9, height: 9)
                    .offset(x: max(min(w * fraction - 4.5, w - 9), 0))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                onChange(min(max(g.location.x / w, 0), 1) * 100)
            })
        }
        .help("Volume \(Int(value))%")
    }
}
