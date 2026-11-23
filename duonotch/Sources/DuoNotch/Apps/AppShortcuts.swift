import AppKit
import Combine

/// An application pinned to the notch.
struct AppShortcut: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var path: String
    var name: String

    var url: URL { URL(fileURLWithPath: path) }
}

/// The apps shown as icons in the expanded notch, plus which are running.
@MainActor
final class AppShortcutStore: ObservableObject {
    static let shared = AppShortcutStore()

    @Published var shortcuts: [AppShortcut] {
        didSet { persist() }
    }
    /// Bundle paths of running apps; refreshed on launch/quit notifications.
    @Published private(set) var runningPaths: Set<String> = []

    private static let key = "appShortcuts.v1"
    private var observers: [NSObjectProtocol] = []
    private var iconCache: [String: NSImage] = [:]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([AppShortcut].self, from: data) {
            shortcuts = decoded
        } else {
            shortcuts = []
        }
        refreshRunning()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { AppShortcutStore.shared.refreshRunning() }
            })
        }
    }

    func add(url: URL) {
        let path = url.standardizedFileURL.path
        guard !shortcuts.contains(where: { $0.path == path }) else { return }
        let name = FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
        shortcuts.append(AppShortcut(path: path, name: name))
    }

    func remove(_ shortcut: AppShortcut) {
        shortcuts.removeAll { $0.id == shortcut.id }
    }

    func move(from source: IndexSet, to destination: Int) {
        shortcuts.move(fromOffsets: source, toOffset: destination)
    }

    /// Puts the dragged app where the target app is.
    func move(dragged: String, onto target: String) {
        guard let from = shortcuts.firstIndex(where: { $0.id.uuidString == dragged }),
              let to = shortcuts.firstIndex(where: { $0.id.uuidString == target }) else { return }
        let item = shortcuts.remove(at: from)
        shortcuts.insert(item, at: to)
    }

    /// Moves an app one place up (-1) or down (+1).
    func shift(_ shortcut: AppShortcut, by delta: Int) {
        guard let i = shortcuts.firstIndex(where: { $0.id == shortcut.id }) else { return }
        let j = i + delta
        guard shortcuts.indices.contains(j) else { return }
        shortcuts.swapAt(i, j)
    }

    func open(_ shortcut: AppShortcut) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: shortcut.url, configuration: config) { _, _ in }
    }

    func isRunning(_ shortcut: AppShortcut) -> Bool {
        runningPaths.contains(shortcut.path)
    }

    /// Show apps in their own colours even when macOS is set to a
    /// monochrome icon style (Clear/Tinted). Off = follow the system style.
    @Published var originalColours: Bool = UserDefaults.standard.object(forKey: "apps.originalColours") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(originalColours, forKey: "apps.originalColours")
            iconCache = [:]
        }
    }

    func icon(for shortcut: AppShortcut) -> NSImage {
        if let cached = iconCache[shortcut.path] { return cached }
        let image = (originalColours ? Self.bundleIcon(at: shortcut.url) : nil)
            ?? NSWorkspace.shared.icon(forFile: shortcut.path)
        iconCache[shortcut.path] = image
        return image
    }

    /// The app's own .icns file, which isn't restyled by the system.
    private static func bundleIcon(at url: URL) -> NSImage? {
        guard let bundle = Bundle(url: url),
              var name = bundle.infoDictionary?["CFBundleIconFile"] as? String else { return nil }
        if !name.hasSuffix(".icns") { name += ".icns" }
        let file = url.appendingPathComponent("Contents/Resources").appendingPathComponent(name)
        return NSImage(contentsOf: file)
    }

    /// Regular apps that are open now and not already pinned, for quick adding.
    func runningCandidates() -> [URL] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { $0.bundleURL?.standardizedFileURL }
            .filter { url in !shortcuts.contains { $0.path == url.path } }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func refreshRunning() {
        runningPaths = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.standardizedFileURL.path })
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(shortcuts) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
