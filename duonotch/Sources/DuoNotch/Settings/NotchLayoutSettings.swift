import SwiftUI
import AppKit

/// Settings → Notch: what the closed notch shows, where, and in which colour.
struct NotchLayoutSettings: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject private var apps = AppShortcutStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose what the closed notch shows. The notch gets longer as you switch more on, and stays centred, so both sides grow to the wider one. Use the arrows or drag rows to change the order.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Text("App rings are solid while the app is running. The chats ring turns amber when a chat is waiting on you. Add more apps in the Apps tab.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List {
                ForEach($state.notchItems) { $item in
                    if let name = name(for: item) {
                        HStack(spacing: 10) {
                            Toggle("", isOn: $item.enabled).labelsHidden()
                            preview(for: item)
                                .frame(width: 22, height: 22)
                            Text(name)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Picker("", selection: colorBinding(for: $item)) {
                                ForEach(AccountPalette.presets) { preset in
                                    Text(preset.name).tag(preset.hex)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 110)
                            Picker("", selection: $item.side) {
                                ForEach(NotchSide.allCases) { Text($0.name).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 110)
                            .disabled(state.placement != .top)
                            OrderButtons(
                                canMoveUp: state.notchItems.first?.id != item.id,
                                canMoveDown: state.notchItems.last?.id != item.id,
                                up: { shift(item, by: -1) },
                                down: { shift(item, by: 1) }
                            )
                        }
                        .opacity(item.enabled ? 1 : 0.6)
                    }
                }
                .onMove { state.notchItems.move(fromOffsets: $0, toOffset: $1) }
            }
            .frame(minHeight: 300)

            if state.placement != .top {
                Text("Left/right only applies to the top position. On an edge or floating, items show in list order.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .onAppear { state.reconcileNotchItems() }
    }

    /// Moves past rows that are hidden (deleted accounts or apps) so each
    /// click visibly moves the item.
    private func shift(_ item: NotchItem, by delta: Int) {
        var items = state.notchItems
        guard var i = items.firstIndex(where: { $0.id == item.id }) else { return }
        var j = i + delta
        while items.indices.contains(j), name(for: items[j]) == nil { j += delta }
        guard items.indices.contains(j) else { return }
        while i != j {
            let next = i + delta
            items.swapAt(i, next)
            i = next
        }
        state.notchItems = items
    }

    /// nil hides rows whose account or app no longer exists.
    private func name(for item: NotchItem) -> String? {
        switch item.kind {
        case .account(let id): return state.accounts.first { $0.id == id }.map { "Claude: \($0.label)" }
        case .app(let id): return apps.shortcuts.first { $0.id == id }?.name
        case .clipboard: return "Clipboard"
        case .chats: return "Chats running / waiting"
        case .media: return "Play / pause (Spotify, Music)"
        case .files: return "File shelf"
        }
    }

    @ViewBuilder
    private func preview(for item: NotchItem) -> some View {
        switch item.kind {
        case .account(let id):
            let account = state.accounts.first { $0.id == id }
            UsageRing(fraction: state.readings[id]?.headline?.fraction ?? 0.6, color: account?.color ?? .gray, size: 16)
        case .app(let id):
            ZStack {
                Circle().stroke(Color(hex: item.colorHex), lineWidth: 2)
                if let app = apps.shortcuts.first(where: { $0.id == id }) {
                    Image(nsImage: apps.icon(for: app)).resizable().frame(width: 12, height: 12)
                }
            }
        case .clipboard:
            symbolRing("doc.on.clipboard", item.colorHex)
        case .chats:
            symbolRing("bubble.left.and.bubble.right", item.colorHex)
        case .media:
            symbolRing("play.fill", item.colorHex)
        case .files:
            symbolRing("tray.full", item.colorHex)
        }
    }

    private func symbolRing(_ symbol: String, _ hex: String) -> some View {
        ZStack {
            Circle().stroke(Color(hex: hex), lineWidth: 2)
            Image(systemName: symbol).font(.system(size: 7, weight: .bold)).foregroundStyle(Color(hex: hex))
        }
    }

    /// Account rows edit the account's own colour so the cards match.
    private func colorBinding(for item: Binding<NotchItem>) -> Binding<String> {
        if case .account(let id) = item.wrappedValue.kind,
           let index = state.accounts.firstIndex(where: { $0.id == id }) {
            return Binding(get: { state.accounts[index].colorHex },
                           set: { state.accounts[index].colorHex = $0 })
        }
        return item.colorHex
    }
}
