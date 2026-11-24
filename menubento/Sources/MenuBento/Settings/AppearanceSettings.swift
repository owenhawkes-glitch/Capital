import SwiftUI

/// Settings → Appearance: colours, shapes and glow for the menu bar.
/// Theme grid and custom colours adapted from DuoNotch.
struct AppearanceSettings: View {
    @ObservedObject private var look = BarAppearance.shared
    @ObservedObject private var permissions = Permissions.shared

    var body: some View {
        Form {
            Section {
                Toggle("Colour the menu bar", isOn: $look.enabled)
            }
            Section("Theme") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach(BarTheme.allCases) { theme in
                        Button { look.theme = theme } label: {
                            VStack(spacing: 4) {
                                ThemeSwatch(theme: theme)
                                    .frame(height: 34)
                                    .overlay(Image(systemName: theme.symbol).font(.system(size: 13)).foregroundStyle(.white.opacity(0.85)))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(look.theme == theme ? Color.accentColor : Color.clear, lineWidth: 2))
                                Text(theme.name).font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                if look.theme == .custom {
                    HStack {
                        Text("Custom colours")
                        ForEach(0..<3, id: \.self) { i in
                            ColorPicker("", selection: hexColorBinding(Binding(
                                get: { look.customHexes[i] },
                                set: { var h = look.customHexes; h[i] = $0; look.customHexes = h })), supportsOpacity: false)
                                .labelsHidden()
                        }
                    }
                }
            }
            .disabled(!look.enabled)
            Section("Shape and fill") {
                Picker("Shape", selection: $look.shape) {
                    ForEach(BarShape.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                if look.shape == .split && !permissions.accessibility {
                    Text("The menus island needs Accessibility to find where the app's menus end; until then only the right-hand island is drawn.")
                        .font(.caption).foregroundStyle(.orange)
                }
                Picker("Fill", selection: $look.fillMode) {
                    ForEach(FillMode.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(look.fillMode.help).font(.caption).foregroundStyle(.secondary)
                if look.fillMode == .tint {
                    HStack {
                        Text("Strength")
                        Slider(value: $look.tintOpacity, in: 0.1...0.8, step: 0.05).frame(maxWidth: 240)
                        Text("\(Int(look.tintOpacity * 100))%").monospacedDigit()
                    }
                }
                if look.shape != .full {
                    HStack {
                        Text("Corner radius")
                        Slider(value: $look.cornerRadius, in: 0...14, step: 1).frame(maxWidth: 240)
                        Text("\(Int(look.cornerRadius))").monospacedDigit()
                    }
                }
                Toggle("Glowing edge that slowly travels around the shape", isOn: $look.glowBorder)
                Toggle("Shadow under the bar", isOn: $look.shadow)
                Toggle("Stay plain until the pointer is over the menu bar", isOn: $look.plainUntilHovered)
            }
            .disabled(!look.enabled)
            Section("Animation") {
                HStack {
                    Text("Speed")
                    Slider(value: $look.animationSpeed, in: 0.5...2, step: 0.25) {
                        EmptyView()
                    } minimumValueLabel: { Text("Slow").font(.caption) } maximumValueLabel: { Text("Fast").font(.caption) }
                    Text(String(format: "%.2g×", look.animationSpeed)).monospacedDigit().frame(width: 36)
                }
                Text(reduceMotion
                     ? "Reduce Motion is on in macOS, so colours and glow are standing still."
                     : "Colours drift and the glow travels. Both stop when Reduce Motion is on (System Settings → Accessibility → Display).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .disabled(!look.enabled)
            Section("Advanced") {
                Picker("Layer", selection: $look.layer) {
                    ForEach(OverlayLayer.allCases) { Text($0.name).tag($0) }
                }
                Text("The colour is drawn in a click-through window. “Over the bar” works everywhere; “Behind the bar” only shows if your menu bar is see-through.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .disabled(!look.enabled)
        }
        .formStyle(.grouped)
    }
}
