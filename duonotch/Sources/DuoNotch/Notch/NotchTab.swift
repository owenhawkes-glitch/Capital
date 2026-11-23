/// The pages of the expanded notch.
enum NotchTab: String, CaseIterable, Identifiable {
    case claude, clipboard

    var id: String { rawValue }
    var title: String {
        switch self {
        case .claude: return "Claude"
        case .clipboard: return "Clipboard"
        }
    }
}
