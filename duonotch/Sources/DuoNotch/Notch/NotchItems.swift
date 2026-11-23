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

    var width: CGFloat {
        switch kind {
        case .account: return 62
        case .app: return 22
        case .clipboard, .chats, .files: return 40
        case .media: return 96
        }
    }

    /// Height when stacked on a side edge.
    var height: CGFloat {
        switch kind {
        case .account: return 34
        case .app: return 24
        case .clipboard, .chats, .files: return 32
        case .media: return 24
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

    static func width(of items: [NotchItem]) -> CGFloat {
        guard !items.isEmpty else { return 0 }
        return items.reduce(0) { $0 + $1.width } + spacing * CGFloat(items.count - 1) + padding
    }

    /// Both wings get the wider of the two so the notch stays centred.
    var wingWidth: CGFloat { max(Self.width(of: left), Self.width(of: right), 40) }
}

/// One item drawn in the closed notch.
struct NotchItemView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var apps = AppShortcutStore.shared
    @ObservedObject private var clipboard = ClipboardStore.shared
    @ObservedObject private var media = MediaStore.shared
    @ObservedObject private var shelf = FileShelf.shared
    let item: NotchItem
    var vertical = false

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
                    ZStack {
                        Circle().stroke(Color(hex: item.colorHex).opacity(apps.isRunning(app) ? 1 : 0.3), lineWidth: 2)
                        Image(nsImage: apps.icon(for: app)).resizable().frame(width: 13, height: 13)
                    }
                    .frame(width: 19, height: 19)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(app.name + (apps.isRunning(app) ? " (running)" : ""))
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
            HStack(spacing: 6) {
            Button { media.playPause() } label: {
                ZStack {
                    Circle().stroke(Color(hex: item.colorHex).opacity(playing ? 1 : 0.35), lineWidth: 2)
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Color(hex: item.colorHex))
                }
                .frame(width: 18, height: 18)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(media.track.map { "\($0.title) · \($0.artist)" } ?? "Play / pause")
            .reorderSource(id: item.id.uuidString)
            if !vertical {
                VolumeSlider(value: media.volume ?? 50, color: Color(hex: item.colorHex)) { media.setVolume($0) }
                    .frame(width: 66, height: 14)
                    .onAppear { media.refresh() }
            }
            }
        case .files:
            Button { state.show(tab: .files) } label: {
                badge(symbol: "tray.full", count: shelf.files.count,
                      color: Color(hex: item.colorHex), active: !shelf.files.isEmpty)
            }
            .buttonStyle(.plain)
            .help("File shelf: \(shelf.files.count) files. Drop files on the notch to park them.")
        }
    }

    private func accountView(_ account: Account) -> some View {
        let window = state.readings[account.id]?.headline
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 3)) : AnyLayout(HStackLayout(spacing: 5))
        return layout {
            ZStack(alignment: .topTrailing) {
                UsageRing(fraction: window?.fraction ?? 0, color: account.color)
                ActivityDot(counts: state.counts(for: account.id)).offset(x: 3, y: -2)
            }
            Text(window.map { "\($0.percent)%" } ?? "–")
                .font(.system(size: vertical ? 9 : 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(window == nil ? Color.secondary : Color.primary)
        }
        .help(account.label)
    }

    private func badge(symbol: String, count: Int, color: Color, active: Bool) -> some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: 4))
        return layout {
            ZStack {
                Circle().stroke(color.opacity(active ? 1 : 0.3), lineWidth: 2)
                Image(systemName: symbol).font(.system(size: 7, weight: .bold)).foregroundStyle(color)
            }
            .frame(width: 17, height: 17)
            Text("\(count)")
                .font(.system(size: vertical ? 9 : 11, weight: .semibold, design: .rounded))
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
