import AppKit
import Combine

/// A web link pinned to the notch (Google Docs, Gmail, dashboards…).
struct QuickLink: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var url: String

    var resolvedURL: URL? {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        if trimmed.contains("://") { return URL(string: trimmed) }
        return URL(string: "https://" + trimmed)
    }
}

@MainActor
final class LinkStore: ObservableObject {
    static let shared = LinkStore()

    @Published var links: [QuickLink] {
        didSet { persist() }
    }
    @Published private(set) var icons: [String: NSImage] = [:]

    private static let key = "quickLinks.v1"
    private var loading: Set<String> = []

    static let googlePresets: [QuickLink] = [
        QuickLink(title: "Google", url: "https://www.google.com"),
        QuickLink(title: "Gmail", url: "https://mail.google.com"),
        QuickLink(title: "Calendar", url: "https://calendar.google.com"),
        QuickLink(title: "Drive", url: "https://drive.google.com"),
        QuickLink(title: "Docs", url: "https://docs.google.com/document"),
        QuickLink(title: "Sheets", url: "https://docs.google.com/spreadsheets"),
        QuickLink(title: "Meet", url: "https://meet.google.com"),
    ]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([QuickLink].self, from: data) {
            links = decoded
        } else {
            links = []
        }
    }

    func add(_ link: QuickLink) {
        guard !links.contains(where: { $0.url == link.url }) else { return }
        links.append(link)
    }

    func addGooglePresets() { Self.googlePresets.forEach(add) }

    func remove(_ link: QuickLink) { links.removeAll { $0.id == link.id } }

    func move(dragged: String, onto target: String) {
        guard let from = links.firstIndex(where: { $0.id.uuidString == dragged }),
              let to = links.firstIndex(where: { $0.id.uuidString == target }) else { return }
        let item = links.remove(at: from)
        links.insert(item, at: to)
    }

    func open(_ link: QuickLink) {
        if let url = link.resolvedURL { NSWorkspace.shared.open(url) }
    }

    /// The site's own icon (apple-touch-icon, then favicon.ico), fetched
    /// straight from that site and kept in memory.
    func icon(for link: QuickLink) -> NSImage? {
        guard let host = link.resolvedURL?.host else { return nil }
        if let image = icons[host] { return image }
        if !loading.contains(host) {
            loading.insert(host)
            Task { await fetchIcon(host: host) }
        }
        return nil
    }

    private func fetchIcon(host: String) async {
        let candidates = ["https://\(host)/apple-touch-icon.png", "https://\(host)/favicon.ico"]
        for candidate in candidates {
            guard let url = URL(string: candidate),
                  let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let image = NSImage(data: data), image.size.width > 0 else { continue }
            icons[host] = image
            return
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(links) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
