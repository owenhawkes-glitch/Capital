import SwiftUI
import AppKit

/// Settings → Notch: what the closed notch shows, where, and in which colour.
struct NotchLayoutSettings: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject private var apps = AppShortcutStore.shared
    @State private var presetName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose what the closed notch shows. The notch gets longer as you switch more on, and stays centred, so both sides grow to the wider one. Use the arrows or drag rows to change the order.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Text("Each position (top, left, right, floating) keeps its own items and order. You're editing: \(state.placement.name).")
                .font(.caption.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button("Add spacer") { state.addSeparator(divider: false) }
                Button("Add divider") { state.addSeparator(divider: true) }
                Spacer()
                Text("Gap between icons")
                Picker("", selection: $state.notchItemSpacing) {
                    Text("Tight").tag(4.0)
                    Text("Normal").tag(8.0)
                    Text("Relaxed").tag(12.0)
                    Text("Roomy").tag(16.0)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 280)
            }

            GroupBox("Presets") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        TextField("Name, e.g. Trading or Coding", text: $presetName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 240)
                        Button("Save as new preset") {
                            state.savePreset(named: presetName)
                            presetName = ""
                        }
                        Spacer()
                        if let active = state.activePreset {
                            Button("Save changes to \u{201C}\(active.name)\u{201D}") { state.updatePreset(active) }
                                .keyboardShortcut("s", modifiers: [.command])
                        }
                    }
                    if state.notchPresets.isEmpty {
                        Text("Save a layout, then apply it to any position with one click. To edit one later: apply it, change the items below, then click Save changes.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach($state.notchPresets) { $preset in
                        HStack(spacing: 8) {
                            Image(systemName: state.activePresetID == preset.id ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(state.activePresetID == preset.id ? Color.accentColor : Color.secondary)
                            TextField("Name", text: $preset.name)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 180)
                            Text("\(preset.items.filter(\.enabled).count) items")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Apply") { state.applyPreset(preset) }
                                .help("Load this layout into \(state.placement.name) to use or edit it")
                            Button("Overwrite with current") { state.updatePreset(preset) }
                                .help("Replace this preset with the layout below")
                            Button { state.deletePreset(preset) } label: { Image(systemName: "trash") }
                                .buttonStyle(.plain)
                                .help("Delete preset")
                        }
                        .controlSize(.small)
                    }
                }
                .padding(4)
            }

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
                                if case .divider = item.kind {
                                    Text("Match notch glow").tag(NotchItem.glowColor)
                                }
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
                            if item.kind.isSeparator {
                                Button { state.removeNotchItem(item) } label: { Image(systemName: "trash") }
                                    .buttonStyle(.plain)
                                    .help("Remove")
                            }
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
            .frame(minHeight: 260)

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
        case .link(let id): return LinkStore.shared.links.first { $0.id == id }.map { "Link: \($0.title)" }
        case .clock(let id): return ClockStore.shared.clocks.first { $0.id == id }.map { "Clock: \($0.label.isEmpty ? ($0.isLocal ? "Local" : $0.timeZoneID) : $0.label) (\($0.style.name))" }
        case .ticker(let id): return MarketStore.shared.tickers.first { $0.id == id }.map { "Ticker: \($0.name)" }
        case .weather: return "Weather"
        case .caffeine: return "Keep awake (caffeinate)"
        case .spacer: return "Spacer (empty gap)"
        case .divider: return "Divider (thin line)"
        case .logo: return "Notch icon (choose it in Appearance)"
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
        case .clock:
            symbolRing("clock", item.colorHex)
        case .ticker:
            symbolRing("chart.line.uptrend.xyaxis", item.colorHex)
        case .weather:
            Image(systemName: "cloud.sun.fill").symbolRenderingMode(.multicolor)
        case .caffeine:
            Image(systemName: "cup.and.saucer.fill").foregroundStyle(.orange)
        case .spacer:
            Image(systemName: "arrow.left.and.right").foregroundStyle(.secondary)
        case .divider:
            if item.colorHex == NotchItem.glowColor {
                GlowFill(shape: Capsule()).frame(width: 3, height: 16)
            } else {
                Capsule().fill(Color(hex: item.colorHex)).frame(width: 2, height: 16)
            }
        case .logo:
            Image(systemName: AppearanceStore.shared.logoSymbol).foregroundStyle(Color(hex: item.colorHex))
        case .link(let id):
            if let link = LinkStore.shared.links.first(where: { $0.id == id }), let icon = LinkStore.shared.icon(for: link) {
                ZStack {
                    Circle().stroke(Color(hex: item.colorHex), lineWidth: 2)
                    Image(nsImage: icon).resizable().frame(width: 12, height: 12)
                }
            } else {
                symbolRing("link", item.colorHex)
            }
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
