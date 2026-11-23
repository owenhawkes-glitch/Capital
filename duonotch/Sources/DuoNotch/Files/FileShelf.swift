import AppKit
import Combine
import UniformTypeIdentifiers

/// Files parked on the notch. Only references are kept; nothing is copied.
@MainActor
final class FileShelf: ObservableObject {
    static let shared = FileShelf()

    @Published private(set) var files: [URL] {
        didSet { persist() }
    }

    private static let key = "fileShelf.v1"

    private init() {
        let paths = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
        files = paths.map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func add(_ urls: [URL]) {
        for url in urls where !files.contains(url) {
            files.insert(url.standardizedFileURL, at: 0)
        }
    }

    func remove(_ url: URL) { files.removeAll { $0 == url } }
    func clear() { files = [] }

    /// Drops any files that were moved or deleted since they were parked.
    func prune() {
        let alive = files.filter { FileManager.default.fileExists(atPath: $0.path) }
        if alive != files { files = alive }
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func copyToPasteboard(_ urls: [URL]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls as [NSURL])
    }

    func icon(for url: URL) -> NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }

    /// Accepts file URLs from a SwiftUI drop.
    func accept(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { return false }
        for provider in fileProviders {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { FileShelf.shared.add([url]) }
                }
            }
        }
        return true
    }

    private func persist() {
        UserDefaults.standard.set(files.map(\.path), forKey: Self.key)
    }
}
