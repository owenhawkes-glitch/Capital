import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Settings → Apps: the icons shown in the expanded notch.
struct AppsSettings: View {
    @ObservedObject private var store = AppShortcutStore.shared
    @State private var candidates: [URL] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Apps you add here appear as icons in the top bar of the expanded notch. Click one to open or switch to it. A dot under the icon means it's running.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Add app…") { addApps() }
                Button("Pick from open apps") { candidates = store.runningCandidates() }
                Spacer()
            }

            if !candidates.isEmpty {
                GroupBox("Open right now") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(candidates, id: \.self) { url in
                                HStack {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                        .resizable().frame(width: 18, height: 18)
                                    Text(url.deletingPathExtension().lastPathComponent)
                                    Spacer()
                                    Button("Add") {
                                        store.add(url: url)
                                        candidates.removeAll { $0 == url }
                                    }
                                    .controlSize(.small)
                                }
                            }
                        }
                        .padding(4)
                    }
                    .frame(maxHeight: 150)
                }
            }

            List {
                ForEach(store.shortcuts) { app in
                    HStack {
                        Image(nsImage: store.icon(for: app)).resizable().frame(width: 20, height: 20)
                        Text(app.name)
                        Text((app.path as NSString).abbreviatingWithTildeInPath)
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Remove") { store.remove(app) }
                            .controlSize(.small)
                    }
                }
                .onMove { store.move(from: $0, to: $1) }
            }
            .frame(minHeight: 200)
            Text("Drag rows to reorder. Roughly ten icons fit next to the tabs.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding()
    }

    private func addApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach { store.add(url: $0) }
    }
}

/// Settings → Clipboard: history on/off and the saved snippets.
struct ClipboardSettings: View {
    @ObservedObject private var clipboard = ClipboardStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Keep a history of copied text", isOn: $clipboard.enabled)
            Text("History lives in memory only and is gone when DuoNotch quits. Copies that password managers mark as private are never recorded. Only text is kept, not images or files.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Picker("Remember the last", selection: $clipboard.historyLimit) {
                Text("10 copies").tag(10)
                Text("20 copies").tag(20)
                Text("50 copies").tag(50)
            }
            .frame(width: 260)
            .disabled(!clipboard.enabled)

            Divider()

            HStack {
                Text("Snippets").font(.headline)
                Spacer()
                Button("Add snippet") {
                    clipboard.snippets.insert(Snippet(title: "New snippet", text: ""), at: 0)
                }
                Button("Save current clipboard") { clipboard.saveCurrentClipboard() }
            }
            Text("Snippets are saved in DuoNotch's preferences file, unencrypted. Don't keep passwords or API keys here.")
                .font(.caption).foregroundStyle(.orange)

            List {
                ForEach($clipboard.snippets) { $snippet in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            TextField("Title (optional)", text: $snippet.title)
                                .textFieldStyle(.roundedBorder)
                            Button("Remove") { clipboard.removeSnippet(snippet) }
                                .controlSize(.small)
                        }
                        TextField("Text to copy", text: $snippet.text, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1...5)
                    }
                    .padding(.vertical, 3)
                }
                .onMove { clipboard.snippets.move(fromOffsets: $0, toOffset: $1) }
            }
            .frame(minHeight: 220)
        }
        .padding()
    }
}
