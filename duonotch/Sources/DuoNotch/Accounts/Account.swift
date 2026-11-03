import SwiftUI
import DuoNotchShared

/// One Claude Code login. Claude Code keeps each login in its own config
/// directory (`~/.claude` by default, or whatever CLAUDE_CONFIG_DIR points
/// at), so the config directory *is* the account identity.
struct Account: Identifiable, Codable, Equatable {
    var id: String { configDir }

    var configDir: String
    var label: String
    var colorHex: String
    var enabled: Bool
    /// Set this if the keychain item for this login has an unexpected name.
    var keychainServiceOverride: String?

    var color: Color { Color(hex: colorHex) }

    var displayPath: String { (configDir as NSString).abbreviatingWithTildeInPath }

    var isDefault: Bool { configDir == HookWire.defaultConfigDir() }

    /// The `CLAUDE_CONFIG_DIR=… claude` incantation that starts this login.
    var launchHint: String {
        isDefault ? "claude" : "CLAUDE_CONFIG_DIR=\(displayPath) claude"
    }
}

struct ColorPreset: Identifiable, Equatable {
    var id: String { hex }
    let name: String
    let hex: String
}

enum AccountPalette {
    static let presets: [ColorPreset] = [
        ColorPreset(name: "Orange", hex: "#F0883E"),
        ColorPreset(name: "Blue", hex: "#4C9BFF"),
        ColorPreset(name: "Green", hex: "#3FD08A"),
        ColorPreset(name: "Purple", hex: "#A77BFF"),
        ColorPreset(name: "Pink", hex: "#FF6BA8"),
        ColorPreset(name: "Teal", hex: "#2FD1C8"),
        ColorPreset(name: "Yellow", hex: "#F5C542"),
        ColorPreset(name: "Off-white", hex: "#E6E6E6"),
    ]

    static func preset(at index: Int) -> ColorPreset {
        presets[index % presets.count]
    }
}

extension Color {
    init(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r, g, b: Double
        if cleaned.count == 6 {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
        } else {
            r = 0.9; g = 0.9; b = 0.9
        }
        self.init(red: r, green: g, blue: b)
    }
}
