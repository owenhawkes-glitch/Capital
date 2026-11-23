import SwiftUI

/// Settings → Panel: what the expanded notch shows and how it's laid out.
struct PanelSettings: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Layout", selection: $state.panelLayout) {
                ForEach(PanelLayoutStyle.allCases) { Text($0.name).tag($0) }
            }
            .pickerStyle(.radioGroup)

            Text({
                switch state.panelLayout {
                case .tabs: return "Sections are grouped into tabs: Claude, Music, Files and Clipboard."
                case .row: return "Every section becomes a column, all in one long row as tall as one section. Made for wide monitors; it scrolls sideways if it's wider than the screen."
                case .all: return "Every section shows at once in a grid. Half-width sections sit side by side."
                }
            }())
                .font(.caption).foregroundStyle(.secondary)

            Picker("Width", selection: $state.panelWidth) {
                Text("Standard").tag(600.0)
                Text("Wide").tag(820.0)
                Text("Extra wide").tag(1040.0)
            }
            .pickerStyle(.segmented)
            .frame(width: 360)
            .disabled(state.panelLayout == .row)

            Text("Sections").font(.headline).padding(.top, 4)
            List {
                ForEach($state.panelModules) { $config in
                    HStack(spacing: 10) {
                        Toggle("", isOn: $config.enabled).labelsHidden()
                        Text(config.module.title)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Picker("", selection: $config.fullWidth) {
                            Text(state.panelLayout == .row ? "Narrow" : "Half").tag(false)
                            Text(state.panelLayout == .row ? "Wide" : "Full").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 110)
                        .disabled(state.panelLayout == .tabs)
                        OrderButtons(
                            canMoveUp: state.panelModules.first?.id != config.id,
                            canMoveDown: state.panelModules.last?.id != config.id,
                            up: { shift(config, by: -1) },
                            down: { shift(config, by: 1) }
                        )
                    }
                    .opacity(config.enabled ? 1 : 0.6)
                }
                .onMove { state.panelModules.move(fromOffsets: $0, toOffset: $1) }
            }
            .frame(minHeight: 230)

            Text("Approvals only appear while Claude is waiting on one. Turning a section off hides its tab too.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding()
    }

    private func shift(_ config: PanelModuleConfig, by delta: Int) {
        guard let i = state.panelModules.firstIndex(where: { $0.id == config.id }),
              state.panelModules.indices.contains(i + delta) else { return }
        state.panelModules.swapAt(i, i + delta)
    }
}
