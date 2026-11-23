import Foundation

/// The pages of the expanded notch when it uses tabs.
enum NotchTab: String, CaseIterable, Identifiable, Codable {
    case claude, widgets, markets, media, clipboard, files, links

    var id: String { rawValue }
    var title: String {
        switch self {
        case .claude: return "Claude"
        case .widgets: return "Time & weather"
        case .markets: return "Markets"
        case .media: return "Media"
        case .clipboard: return "Clipboard"
        case .files: return "Files"
        case .links: return "Links"
        }
    }
}

/// A section of the expanded panel.
enum PanelModule: String, CaseIterable, Codable, Identifiable {
    case accounts, approvals, projects, clocks, weather, markets, media, window, links, files, clipboard

    var id: String { rawValue }
    var title: String {
        switch self {
        case .accounts: return "Claude usage and chats"
        case .approvals: return "Approvals"
        case .projects: return "Projects"
        case .media: return "Now playing (Spotify / Music)"
        case .window: return "Live window (watch a Spotify podcast, any app)"
        case .links: return "Quick links"
        case .clocks: return "Clocks / world time"
        case .weather: return "Weather"
        case .markets: return "Markets (tickers)"
        case .files: return "File shelf"
        case .clipboard: return "Clipboard"
        }
    }
    var tab: NotchTab {
        switch self {
        case .accounts, .approvals, .projects: return .claude
        case .media, .window: return .media
        case .links: return .links
        case .clocks, .weather: return .widgets
        case .markets: return .markets
        case .files: return .files
        case .clipboard: return .clipboard
        }
    }
}

struct PanelModuleConfig: Codable, Identifiable, Equatable {
    var module: PanelModule
    var enabled: Bool
    var fullWidth: Bool
    var id: String { module.rawValue }

    static let defaults: [PanelModuleConfig] = [
        .init(module: .accounts, enabled: true, fullWidth: true),
        .init(module: .approvals, enabled: true, fullWidth: true),
        .init(module: .projects, enabled: true, fullWidth: true),
        .init(module: .clocks, enabled: true, fullWidth: false),
        .init(module: .weather, enabled: true, fullWidth: false),
        .init(module: .markets, enabled: true, fullWidth: false),
        .init(module: .media, enabled: true, fullWidth: false),
        .init(module: .window, enabled: false, fullWidth: true),
        .init(module: .links, enabled: true, fullWidth: false),
        .init(module: .files, enabled: true, fullWidth: false),
        .init(module: .clipboard, enabled: true, fullWidth: true),
    ]
}

enum PanelLayoutStyle: String, Codable, CaseIterable, Identifiable {
    case tabs, row, all
    var id: String { rawValue }
    var name: String {
        switch self {
        case .tabs: return "Tabs"
        case .row: return "Side by side (one long row)"
        case .all: return "Stacked grid"
        }
    }
}

@MainActor
enum PanelMetrics {
    /// Compact density shrinks the columns.
    static var compact = false
    static var narrowColumn: CGFloat { compact ? 236 : 280 }
    static var wideColumn: CGFloat { compact ? 320 : 380 }
    static let spacing: CGFloat = 10
    static let sidePadding: CGFloat = 14
}
