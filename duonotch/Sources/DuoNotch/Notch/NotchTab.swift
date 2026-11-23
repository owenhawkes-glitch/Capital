import Foundation

/// The pages of the expanded notch when it uses tabs.
enum NotchTab: String, CaseIterable, Identifiable, Codable {
    case claude, media, clipboard, files

    var id: String { rawValue }
    var title: String {
        switch self {
        case .claude: return "Claude"
        case .media: return "Music"
        case .clipboard: return "Clipboard"
        case .files: return "Files"
        }
    }
}

/// A section of the expanded panel.
enum PanelModule: String, CaseIterable, Codable, Identifiable {
    case accounts, approvals, projects, media, files, clipboard

    var id: String { rawValue }
    var title: String {
        switch self {
        case .accounts: return "Claude usage and chats"
        case .approvals: return "Approvals"
        case .projects: return "Projects"
        case .media: return "Now playing (Spotify / Music)"
        case .files: return "File shelf"
        case .clipboard: return "Clipboard"
        }
    }
    var tab: NotchTab {
        switch self {
        case .accounts, .approvals, .projects: return .claude
        case .media: return .media
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
        .init(module: .media, enabled: true, fullWidth: false),
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

enum PanelMetrics {
    static let narrowColumn: CGFloat = 280
    static let wideColumn: CGFloat = 380
    static let spacing: CGFloat = 10
    static let sidePadding: CGFloat = 14
}
