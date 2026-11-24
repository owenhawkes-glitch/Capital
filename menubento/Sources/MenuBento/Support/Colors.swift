import SwiftUI
import AppKit

// Copied from DuoNotch (Accounts/Account.swift and Settings), not linked.

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

    /// "#RRGGBB" for this colour (sRGB).
    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .white
        return String(format: "#%02X%02X%02X", Int(ns.redComponent * 255), Int(ns.greenComponent * 255), Int(ns.blueComponent * 255))
    }
}

/// Edits a "#RRGGBB" string with the system colour picker.
func hexColorBinding(_ hex: Binding<String>) -> Binding<Color> {
    Binding(get: { Color(hex: hex.wrappedValue == ExtraItem.glowColor ? "#E6E6E6" : hex.wrappedValue) },
            set: { hex.wrappedValue = $0.hexString })
}

/// True when macOS asks apps to keep still (Accessibility → Display).
var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
