import Foundation
import MenuBentoCore

/// The three parts of the menu bar MenuBento manages.
enum MenuSection: String, Codable, CaseIterable, Identifiable {
    case visible, hidden, alwaysHidden
    var id: String { rawValue }
    var name: String {
        switch self {
        case .visible: return "Visible"
        case .hidden: return "Hidden"
        case .alwaysHidden: return "Always hidden"
        }
    }
    var help: String {
        switch self {
        case .visible: return "Always in the menu bar."
        case .hidden: return "Shown when you click (or hover) MenuBento, or in the MenuBento bar."
        case .alwaysHidden: return "Only shown with ⌥-click on MenuBento, or from the MenuBento bar's second row."
        }
    }
    var symbol: String {
        switch self {
        case .visible: return "eye"
        case .hidden: return "eye.slash"
        case .alwaysHidden: return "lock"
        }
    }
}

/// What's showing right now.
enum BarState: Equatable {
    /// Hidden and always-hidden items are pushed out of sight.
    case hidden
    /// Hidden items are back in the menu bar.
    case shown
    /// Everything, including always-hidden items.
    case showAll
}

/// How hidden items are shown when you click MenuBento.
enum RevealMode: String, Codable, CaseIterable, Identifiable {
    case inPlace, bar
    var id: String { rawValue }
    var name: String {
        switch self {
        case .inPlace: return "In the menu bar"
        case .bar: return "In the MenuBento bar"
        }
    }
}

/// Our own extra status items: blank spacers and drawn dividers.
struct ExtraItem: Codable, Identifiable, Equatable, Hashable {
    /// Special colour value: draw with the glow's moving colours.
    static let glowColor = "glow"

    enum Kind: String, Codable { case spacer, divider }
    enum Style: String, Codable, CaseIterable, Identifiable {
        case line, thick, dot, dots
        var id: String { rawValue }
        var name: String {
            switch self {
            case .line: return "Line"
            case .thick: return "Thick line"
            case .dot: return "Dot"
            case .dots: return "Three dots"
            }
        }
    }

    var id: UUID = UUID()
    var kind: Kind
    /// Spacer width in points.
    var width: Double = 14
    var style: Style = .line
    /// "#RRGGBB" or `glowColor`.
    var colorHex: String = ExtraItem.glowColor

    var autosaveName: String { "menubento.extra.\(id.uuidString)" }
    var ref: ItemRef { ItemRef(owner: OurItems.owner, key: "extra.\(id.uuidString)") }
    var name: String { kind == .spacer ? "Spacer (\(Int(width)) pt)" : "Divider – \(style.name)\(colorHex == Self.glowColor ? ", glow" : "")" }
}

/// MenuBento's own items, by ref.
enum OurItems {
    static let owner = "menubento"
    static let main = ItemRef(owner: owner, key: "main")
    static let hidden = ItemRef(owner: owner, key: "hidden")
    static let alwaysHidden = ItemRef(owner: owner, key: "alwaysHidden")
}

/// A named set of items that can be hidden or shown in one click.
struct ItemGroup: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var symbol: String = "square.stack.3d.up"
    var members: [ItemRef] = []
    /// True while the group's items are parked in Always hidden.
    var isHidden = false
    /// Where each member was before the group was hidden, by ref id.
    var savedSections: [String: MenuSection] = [:]

    static let symbols = ["square.stack.3d.up", "briefcase", "cloud", "bubble.left.and.bubble.right", "hammer",
                          "chart.line.uptrend.xyaxis", "music.note", "gamecontroller", "lock.shield", "sparkles"]
}

/// One item's place in a saved layout.
struct PresetEntry: Codable, Equatable {
    var ref: ItemRef
    var name: String
}

/// A saved layout: the order of everything (MenuBento's separators mark
/// the sections), the spacers and dividers, and optionally the look.
struct LayoutPreset: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    /// Left to right.
    var entries: [PresetEntry]
    var extras: [ExtraItem]
    var appearance: AppearanceSnapshot?
    var saved: Date = Date()

    func count(in section: MenuSection) -> Int {
        let refs = entries.map(\.ref)
        let ah = refs.firstIndex(of: OurItems.alwaysHidden) ?? -1
        let h = refs.firstIndex(of: OurItems.hidden) ?? -1
        let mine = refs.enumerated().filter { $0.element.owner != OurItems.owner }
        switch section {
        case .alwaysHidden: return mine.filter { $0.offset < ah }.count
        case .hidden: return mine.filter { $0.offset > ah && $0.offset < h }.count
        case .visible: return mine.filter { $0.offset > h }.count
        }
    }
}
