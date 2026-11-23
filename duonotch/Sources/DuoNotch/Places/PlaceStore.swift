import AppKit
import SwiftUI
import Combine
import UniformTypeIdentifiers

/// A file or folder you want one click away: open it, copy its path,
/// show it in Finder, or open a terminal there.
struct Place: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var path: String

    var url: URL { URL(fileURLWithPath: path) }
    var displayPath: String { (path as NSString).abbreviatingWithTildeInPath }
    var isFolder: Bool {
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &dir) && dir.boolValue
    }
    var exists: Bool { FileManager.default.fileExists(atPath: path) }
}

@MainActor
final class PlaceStore: ObservableObject {
    static let shared = PlaceStore()

    @Published var places: [Place] {
        didSet { if let data = try? JSONEncoder().encode(places) { UserDefaults.standard.set(data, forKey: "places.v1") } }
    }
    @Published private(set) var lastCopied: UUID?

    private init() {
        if let data = UserDefaults.standard.data(forKey: "places.v1"),
           let decoded = try? JSONDecoder().decode([Place].self, from: data) {
            places = decoded
        } else {
            places = []
        }
    }

    func add(_ urls: [URL]) {
        for url in urls {
            let path = url.standardizedFileURL.path
            guard !places.contains(where: { $0.path == path }) else { continue }
            places.append(Place(name: url.lastPathComponent, path: path))
        }
    }

    func remove(_ place: Place) { places.removeAll { $0.id == place.id } }

    func move(dragged: String, onto target: String) {
        guard let from = places.firstIndex(where: { $0.id.uuidString == dragged }),
              let to = places.firstIndex(where: { $0.id.uuidString == target }) else { return }
        let item = places.remove(at: from)
        places.insert(item, at: to)
    }

    func open(_ place: Place) { NSWorkspace.shared.open(place.url) }
    func reveal(_ place: Place) { NSWorkspace.shared.activateFileViewerSelecting([place.url]) }

    func copyPath(_ place: Place) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(place.path, forType: .string)
        lastCopied = place.id
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            if self?.lastCopied == place.id { self?.lastCopied = nil }
        }
    }

    /// Opens a new terminal window in the folder (or the file's folder).
    func openTerminal(_ place: Place, terminal: ProjectLauncher.TerminalApp) {
        let folder = place.isFolder ? place.url : place.url.deletingLastPathComponent()
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: terminal.rawValue) else { return }
        NSWorkspace.shared.open([folder], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
    }

    func icon(for place: Place) -> NSImage { NSWorkspace.shared.icon(forFile: place.path) }

    func accept(_ providers: [NSItemProvider]) -> Bool {
        let files = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        for provider in files {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { MainActor.assumeIsolated { PlaceStore.shared.add([url]) } }
            }
        }
        return !files.isEmpty
    }

    func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        if panel.runModal() == .OK { add(panel.urls) }
    }
}

/// Panel section: your saved paths.
struct PlacesCard: View {
    @ObservedObject private var store = PlaceStore.shared
    @ObservedObject var state: AppState

    var body: some View {
        card {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Places").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Add…") { store.choose() }
                        .buttonStyle(.plain).font(.system(size: 9)).foregroundStyle(.secondary)
                }
                if store.places.isEmpty {
                    Text("Drop files or folders here, or click Add, to keep their paths one click away.")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(store.places) { place in
                    HStack(spacing: 6) {
                        Image(nsImage: store.icon(for: place)).resizable().interpolation(.high).frame(width: 16, height: 16)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(place.name).font(.system(size: 10, weight: .medium)).lineLimit(1)
                            Text(store.lastCopied == place.id ? "Path copied" : place.displayPath)
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundStyle(store.lastCopied == place.id ? Color.green : (place.exists ? Color.secondary : Color.red))
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer(minLength: 4)
                        iconButton("doc.on.doc", "Copy path") { store.copyPath(place) }
                        iconButton("folder", "Show in Finder") { store.reveal(place) }
                        iconButton("terminal", "Open \(state.terminalApp.name) here") { store.openTerminal(place, terminal: state.terminalApp) }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.05)))
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { store.open(place) }
                    .help("\(place.path)\nDouble-click to open")
                    .contextMenu {
                        Button("Open") { store.open(place) }
                        Button("Copy path") { store.copyPath(place) }
                        Button("Show in Finder") { store.reveal(place) }
                        Button("Open \(state.terminalApp.name) here") { store.openTerminal(place, terminal: state.terminalApp) }
                        Divider()
                        Button("Remove") { store.remove(place) }
                    }
                    .reorderSource(id: place.id.uuidString)
                    .reorderTarget(id: place.id.uuidString) { store.move(dragged: $0, onto: $1) }
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { store.accept($0) }
    }

    private func iconButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 9)).frame(width: 18, height: 16).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
    }
}

/// Settings → Places.
struct PlacesSettings: View {
    @ObservedObject private var store = PlaceStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Files and folders whose paths you want one click away. In the open notch you can copy a path, show it in Finder, open a terminal there, or double-click to open it. You can also drop files onto the Places section.")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Add file or folder…") { store.choose() }
                Spacer()
            }
            List {
                ForEach($store.places) { $place in
                    HStack {
                        Image(nsImage: store.icon(for: place)).resizable().frame(width: 18, height: 18)
                        TextField("Name", text: $place.name).frame(width: 160)
                        Text(place.displayPath).font(.system(.caption, design: .monospaced))
                            .foregroundStyle(place.exists ? Color.secondary : Color.red)
                            .lineLimit(1).truncationMode(.middle)
                            .textSelection(.enabled)
                        Spacer()
                        Button("Copy path") { store.copyPath(place) }.controlSize(.small)
                        Button("Remove") { store.remove(place) }.controlSize(.small)
                    }
                }
                .onMove { store.places.move(fromOffsets: $0, toOffset: $1) }
            }
            .frame(minHeight: 300)
            .onDrop(of: [.fileURL], isTargeted: nil) { store.accept($0) }
        }
        .padding()
    }
}
