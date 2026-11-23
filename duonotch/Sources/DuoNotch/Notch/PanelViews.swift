import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Expanded panel

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct ColumnHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct ExpandedPanel: View {
    @ObservedObject var state: AppState
    let width: CGFloat
    var maxHeight: CGFloat = 1200
    @State private var columnHeight: CGFloat = 300

    private var alongSide: Bool {
        state.panelLayout == .row && (state.placement == .left || state.placement == .right)
    }

    var body: some View {
        VStack(spacing: 8) {
            TabBar(state: state)
                .padding(.horizontal, 14)

            if state.panelLayout == .tabs {
                let tab = state.visibleTabs.contains(state.selectedTab) ? state.selectedTab : (state.visibleTabs.first ?? .claude)
                VStack(spacing: 10) {
                    ForEach(modules(in: tab)) { config in
                        ArrangeTile(state: state, config: config, half: false)
                    }
                }
                .padding(.horizontal, 14)
            } else if alongSide {
                // Runs along the edge: sections stacked top to bottom,
                // scrolling if taller than the screen.
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: PanelMetrics.spacing) {
                        ForEach(shown) { config in
                            ArrangeTile(state: state, config: config, half: true)
                                .frame(width: width - 2 * PanelMetrics.sidePadding, alignment: .top)
                        }
                    }
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: ColumnHeightKey.self, value: proxy.size.height)
                    })
                }
                .frame(height: min(columnHeight, maxHeight - 70))
                .onPreferenceChange(ColumnHeightKey.self) { h in
                    MainActor.assumeIsolated { if abs(h - columnHeight) > 0.5 { columnHeight = h } }
                }
                .padding(.horizontal, PanelMetrics.sidePadding)
            } else if state.panelLayout == .row {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: PanelMetrics.spacing) {
                        ForEach(state.rowColumns, id: \.first!.id) { column in
                            VStack(spacing: PanelMetrics.spacing) {
                                ForEach(column) { config in
                                    ArrangeTile(state: state, config: config, half: true)
                                }
                            }
                            .frame(width: AppState.columnWidth(column), alignment: .top)
                        }
                    }
                }
                .frame(width: width - 2 * PanelMetrics.sidePadding)
            } else {
                VStack(spacing: 10) {
                    ForEach(bentoRows(), id: \.first!.first!.id) { row in
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(row, id: \.first!.id) { stack in
                                VStack(spacing: 10) {
                                    ForEach(stack) { config in
                                        ArrangeTile(state: state, config: config, half: row.count > 1)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .top)
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
            }

            if state.arranging {
                HiddenSectionsTray(state: state)
                    .padding(.horizontal, PanelMetrics.sidePadding)
            }

            HStack {
                Spacer()
                if let last = state.lastRefresh {
                    Text("updated \(last.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
        }
        .padding(.top, 6)
        .frame(width: width)
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
        })
        .onPreferenceChange(ContentHeightKey.self) { height in
            MainActor.assumeIsolated { state.setMeasuredContentHeight(height) }
        }
    }

    /// Enabled sections that have something to show.
    private var shown: [PanelModuleConfig] { state.shownPanelModules }

    private func modules(in tab: NotchTab) -> [PanelModuleConfig] {
        shown.filter { $0.module.tab == tab }
    }

    /// Stacks of cards: full-size stacks get their own row, half-size ones pair up.
    private func bentoRows() -> [[[PanelModuleConfig]]] {
        var rows: [[[PanelModuleConfig]]] = []
        var pending: [PanelModuleConfig]?
        for stack in state.rowColumns {
            let full = stack.contains { $0.cardSize >= .large }
            if full {
                if let p = pending { rows.append([p]); pending = nil }
                rows.append([stack])
            } else if let p = pending {
                rows.append([p, stack]); pending = nil
            } else {
                pending = stack
            }
        }
        if let p = pending { rows.append([p]) }
        return rows
    }
}

struct ModuleView: View {
    @ObservedObject var state: AppState
    let module: PanelModule
    let half: Bool

    var body: some View {
        switch module {
        case .accounts:
            let layout = half ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
            VStack(alignment: .leading, spacing: 6) {
                if state.enabledAccounts.count > 1 {
                    AccountFilterBar(state: state)
                }
                layout {
                    if state.enabledAccounts.isEmpty {
                        EmptyAccountsCard()
                    } else {
                        ForEach(state.shownAccounts) { account in
                            AccountCard(state: state, account: account)
                        }
                    }
                }
            }
        case .approvals:
            ApprovalList(state: state)
        case .projects:
            ProjectsRow(state: state)
        case .media:
            MediaCard()
        case .window:
            WindowMirrorCard()
        case .links:
            LinksCard()
        case .places:
            PlacesCard(state: state)
        case .clocks:
            ClocksCard()
        case .weather:
            WeatherCard()
        case .markets:
            MarketsCard()
        case .files:
            FileShelfView(compact: half)
        case .clipboard:
            ClipboardPage(compact: half)
        }
    }
}

// MARK: - Tab bar

/// Tabs (in tab mode) on the left, pinned apps on the right. In the floating
/// placement the empty middle drags the window and × closes it.
struct TabBar: View {
    @ObservedObject var state: AppState
    @ObservedObject private var apps = AppShortcutStore.shared

    var body: some View {
        HStack(spacing: 4) {
            if state.panelLayout == .tabs {
                ForEach(state.visibleTabs) { tab in
                    Button {
                        state.selectedTab = tab
                    } label: {
                        HStack(spacing: 4) {
                            Text(tab.title)
                            if tab == .claude, !state.pendingPermissions.isEmpty {
                                Circle().fill(Color.yellow).frame(width: 5, height: 5)
                            }
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(state.selectedTab == tab ? Color.white : Color.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(state.selectedTab == tab ? 0.14 : 0)))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            if state.appBarAlignment != .leading {
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 20)
                    .contentShape(Rectangle())
                    .modifier(FloatingDrag(state: state))
            }
            HStack(spacing: 4) {
            if apps.shortcuts.isEmpty {
                    Button("+ apps") { AppState.openSettings() }
                        .buttonStyle(.plain)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(apps.shortcuts) { app in
                        Button {
                            apps.open(app)
                        } label: {
                            VStack(spacing: 1) {
                                Image(nsImage: apps.icon(for: app))
                                    .resizable()
                                    .frame(width: 18, height: 18)
                                Circle()
                                    .fill(apps.isRunning(app) ? Color.white.opacity(0.7) : Color.clear)
                                    .frame(width: 3, height: 3)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(app.name + " — drag to reorder")
                        .reorderSource(id: app.id.uuidString)
                        .reorderTarget(id: app.id.uuidString) { apps.move(dragged: $0, onto: $1) }
                    }
                }

            }
            if state.appBarAlignment != .trailing {
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 20)
                    .contentShape(Rectangle())
                    .modifier(FloatingDrag(state: state))
            }
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { state.arranging.toggle() }
            } label: {
                Text(state.arranging ? "Done" : "Arrange")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(state.arranging ? Color.black : Color.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(state.arranging ? Color.white : Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help("Drag sections to reorder them, hide them or change their width")
            .padding(.trailing, 6)

            if state.placement == .floating && state.floatingOpensOnClick {
                Button {
                    state.floatingOpen = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 6)
                .help("Close")
            }
        }
        .frame(height: 24)
    }
}

func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    content()
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
}

// MARK: - Now playing

struct MediaCard: View {
    @ObservedObject private var media = MediaStore.shared

    var body: some View {
        card {
          VStack(spacing: 0) {
            HStack(spacing: 12) {
                artwork
                    .frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    if let track = media.track {
                        Text(track.title.isEmpty ? "Unknown track" : track.title)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(track.source.appName)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    } else if let source = media.activeSource {
                        Text("Nothing playing").font(.system(size: 13, weight: .semibold))
                        Text("\(source.appName) is open. Press play to start.")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    } else {
                        Text("Nothing playing").font(.system(size: 13, weight: .semibold))
                        Button("Open Spotify") { media.openPlayer() }
                            .buttonStyle(.plain)
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                    }

                    HStack(spacing: 16) {
                        control("backward.fill") { media.previous() }
                        control(media.track?.isPlaying == true ? "pause.fill" : "play.fill", size: 16) { media.playPause() }
                        control("forward.fill") { media.next() }
                    }
                    .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
            if let track = media.track {
                ProgressRow(track: track) { media.seek(to: $0) }
                    .padding(.top, 6)
            }
            if media.activeSource != nil {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.fill")
                        .font(.system(size: 8))
                        .frame(width: 34, alignment: .trailing)
                    VolumeSlider(value: media.volume ?? 50, color: .green) { media.setVolume($0) }
                        .frame(height: 12)
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 8))
                        .frame(width: 34, alignment: .leading)
                }
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
          }
        }
        .onAppear { media.refresh(force: true) }
    }

    @ViewBuilder
    private var artwork: some View {
        if let image = media.artwork {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08))
                Image(systemName: "music.note").font(.system(size: 20)).foregroundStyle(.secondary)
            }
        }
    }

    private func control(_ symbol: String, size: CGFloat = 12, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .offset(x: symbol.hasPrefix("play") ? size * 0.08 : 0)
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - File shelf

struct FileShelfView: View {
    @ObservedObject private var shelf = FileShelf.shared
    let compact: Bool

    var body: some View {
        card {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("File shelf").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    if !shelf.files.isEmpty {
                        Text("\(shelf.files.count)").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !shelf.files.isEmpty {
                        Button("Copy all") { shelf.copyToPasteboard(shelf.files) }
                        Button("Clear") { shelf.clear() }
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 9))

                if shelf.files.isEmpty {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .frame(height: 58)
                        .overlay(
                            Text("Drop files on the notch to park them here.\nDrag them out again to put them anywhere.")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        )
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 8) {
                            ForEach(shelf.files, id: \.self) { url in
                                tile(url)
                            }
                        }
                    }
                    .frame(height: 62)
                }
            }
        }
        .onAppear { shelf.prune() }
    }

    private func tile(_ url: URL) -> some View {
        VStack(spacing: 2) {
            Image(nsImage: shelf.icon(for: url))
                .resizable()
                .frame(width: 32, height: 32)
            Text(url.lastPathComponent)
                .font(.system(size: 8))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 60)
        }
        .frame(width: 62)
        .contentShape(Rectangle())
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .onTapGesture(count: 2) { shelf.open(url) }
        .help("\(url.path)\nDrag out to move it (hold ⌥ to copy). Double-click to open.")
        .contextMenu {
            Button("Open") { shelf.open(url) }
            Button("Show in Finder") { shelf.reveal(url) }
            Button("Copy") { shelf.copyToPasteboard([url]) }
            Divider()
            Button("Remove from shelf") { shelf.remove(url) }
        }
    }
}

// MARK: - Clipboard

struct ClipboardPage: View {
    @ObservedObject private var clipboard = ClipboardStore.shared
    let compact: Bool
    private let rowHeight: CGFloat = 20

    private var rows: Int { compact ? 4 : NotchMetrics.clipboardRows }

    var body: some View {
        let layout = compact ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        layout {
            column(title: "Snippets", action: ("Save clipboard", { clipboard.saveCurrentClipboard() })) {
                if clipboard.snippets.isEmpty {
                    hint("Pin a recent copy, or save what's on the clipboard now.")
                }
                ForEach(clipboard.snippets) { snippet in
                    row(text: snippet.displayTitle, full: snippet.text, icon: "xmark", iconHelp: "Remove snippet") {
                        clipboard.removeSnippet(snippet)
                    }
                }
            }
            column(title: "Recent", action: ("Clear", { clipboard.clearHistory() })) {
                if !clipboard.enabled {
                    hint("Clipboard history is off. Turn it on in Settings → Clipboard.")
                } else if clipboard.history.isEmpty {
                    hint("Copy something and it appears here. Kept in memory only.")
                }
                ForEach(clipboard.history) { item in
                    row(text: ClipboardStore.oneLine(item.text), full: item.text, icon: "pin", iconHelp: "Pin as snippet") {
                        clipboard.pin(item)
                    }
                }
            }
        }
    }

    private func column<Content: View>(title: String, action: (String, () -> Void), @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Button(action.0, action: action.1)
                    .buttonStyle(.plain)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) { content() }
            }
            .frame(height: CGFloat(rows) * (rowHeight + 2))
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func row(text: String, full: String, icon: String, iconHelp: String, iconAction: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Button {
                clipboard.copy(full)
            } label: {
                Text(clipboard.lastCopiedText == full ? "Copied" : text)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(clipboard.lastCopiedText == full ? Color.green : Color.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(full.count > 400 ? String(full.prefix(400)) + "…" : full)
            Button(action: iconAction) {
                Image(systemName: icon).font(.system(size: 8))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(iconHelp)
        }
        .padding(.horizontal, 6)
        .frame(height: rowHeight)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.05)))
    }
}

/// Elapsed / total with a bar you can click to jump.
struct ProgressRow: View {
    let track: MediaStore.Track
    let seek: (Double) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = track.elapsed(at: context.date)
            let duration = track.duration ?? 0
            HStack(spacing: 8) {
                Text(Self.time(elapsed))
                    .frame(width: 34, alignment: .trailing)
                GeometryReader { proxy in
                    let fraction = duration > 0 ? elapsed / duration : 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15))
                        Capsule().fill(Color.white.opacity(0.85))
                            .frame(width: max(proxy.size.width * fraction, 3))
                    }
                    .frame(height: 4)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { tap in
                        guard duration > 0 else { return }
                        seek(min(max(tap.location.x / proxy.size.width, 0), 1) * duration)
                    })
                }
                .frame(height: 12)
                Text(duration > 0 ? Self.time(duration) : "–:––")
                    .frame(width: 34, alignment: .leading)
            }
            .font(.system(size: 9, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
    }

    static func time(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.down))
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Arrange mode

/// A section, plus — while arranging — a frame you drag to reorder, with
/// buttons to hide it or switch its width. Its own controls are paused.
struct ArrangeTile: View {
    @ObservedObject var state: AppState
    let config: PanelModuleConfig
    let half: Bool
    @State private var dropZone: DropZone?
    @State private var tileHeight: CGFloat = 100

    enum DropZone { case before, under }

    var body: some View {
        if state.arranging {
            ModuleView(state: state, module: config.module, half: half)
                .allowsHitTesting(false)
                .opacity(0.55)
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal")
                        Text(config.module.title).lineLimit(1)
                        Spacer(minLength: 4)
                        Button { state.resize(config.module, by: -1) } label: { Image(systemName: "minus") }
                            .disabled(config.cardSize == .small)
                            .help("Smaller")
                        Text(config.cardSize.name).frame(minWidth: 14)
                        Button { state.resize(config.module, by: 1) } label: { Image(systemName: "plus") }
                            .disabled(config.cardSize == .xlarge)
                            .help("Bigger")
                        Menu {
                            Button("Own column") { state.unstack(config.module) }
                                .disabled(!state.isStacked(config.module))
                            Divider()
                            ForEach(state.shownPanelModules.filter { $0.module != config.module }) { other in
                                Button("Under \(other.module.shortTitle)") {
                                    withAnimation(.easeOut(duration: 0.2)) { state.stack(config.module, under: other.module) }
                                }
                            }
                        } label: {
                            Image(systemName: "rectangle.split.1x2")
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("Put this card under another card")
                        Button { state.setModule(config.module, enabled: false) } label: { Image(systemName: "eye.slash") }
                            .help("Hide this section")
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.75)))
                    .padding(6)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 11)
                        .strokeBorder(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                )
                .overlay(alignment: dropZone == .under ? .bottom : .top) {
                    if let dropZone {
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(height: 3)
                            .padding(.horizontal, 8)
                            .overlay(
                                Text(dropZone == .under ? "Drop to stack under" : "Drop to place before")
                                    .font(.system(size: 8, weight: .bold))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Capsule().fill(Color.accentColor))
                            )
                    }
                }
                .background(GeometryReader { proxy in
                    Color.clear.onAppear { tileHeight = proxy.size.height }
                        .onChange(of: proxy.size.height) { _, h in tileHeight = h }
                })
                .contentShape(Rectangle())
                .reorderSource(id: config.module.rawValue)
                .onDrop(of: [.duoNotchReorder], delegate: ModuleDropDelegate(
                    targetID: config.module.rawValue, height: tileHeight, state: state, zone: $dropZone))
        } else {
            ModuleView(state: state, module: config.module, half: half)
        }
    }
}

/// Hidden sections, shown while arranging so they can be brought back.
struct HiddenSectionsTray: View {
    @ObservedObject var state: AppState

    var body: some View {
        let hidden = state.panelModules.filter { !$0.enabled }
        HStack(spacing: 6) {
            Text(hidden.isEmpty ? "Drag sections to reorder. Everything is showing." : "Hidden:")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            ForEach(hidden) { config in
                Button {
                    state.setModule(config.module, enabled: true)
                } label: {
                    Label(config.module.title, systemImage: "plus")
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }
}

// MARK: - Live window

struct WindowMirrorCard: View {
    @ObservedObject private var mirror = WindowMirror.shared

    var body: some View {
        card {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("Live").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    ForEach(WindowMirror.favourites, id: \.id) { fav in
                        Button(fav.name) { mirror.pick(bundleID: fav.id) }
                            .buttonStyle(.plain)
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(mirror.isLive && mirror.targetBundleID == fav.id ? Color.white.opacity(0.22) : Color.white.opacity(0.06)))
                            .help("Pick a \(fav.name) window to show here")
                    }
                    Button("Other…") { mirror.pick(bundleID: nil) }
                        .buttonStyle(.plain)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if mirror.isLive {
                        Button("Stop") { mirror.stop() }
                            .buttonStyle(.plain)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05))
                    if let frame = mirror.frame {
                        Image(decorative: frame, scale: 2)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .onTapGesture { mirror.bringSourceToFront() }
                            .help("Click to switch to \(mirror.sourceName ?? "it")")
                    } else {
                        Text(mirror.status)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(10)
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
            }
        }
        .onAppear { mirror.appear() }
        .onDisappear { mirror.disappear() }
    }
}

// MARK: - Links

struct LinksCard: View {
    @ObservedObject private var store = LinkStore.shared

    var body: some View {
        card {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Links").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Edit") { AppState.openSettings() }
                        .buttonStyle(.plain).font(.system(size: 9)).foregroundStyle(.secondary)
                }
                if store.links.isEmpty {
                    Button("Add Google links") { store.addGooglePresets() }
                        .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.blue)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(store.links) { link in
                            Button { store.open(link) } label: {
                                HStack(spacing: 5) {
                                    if let icon = store.icon(for: link) {
                                        Image(nsImage: icon).resizable().interpolation(.high).frame(width: 14, height: 14)
                                    } else {
                                        Image(systemName: "link").font(.system(size: 9))
                                    }
                                    Text(link.title).font(.system(size: 10, weight: .medium)).lineLimit(1)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.white.opacity(0.1)))
                                .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .help(link.url)
                            .reorderSource(id: link.id.uuidString)
                            .reorderTarget(id: link.id.uuidString) { store.move(dragged: $0, onto: $1) }
                        }
                    }
                }
            }
        }
    }
}

/// Wraps chips onto as many lines as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, maxWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Both / A / B switch for the Claude section.
struct AccountFilterBar: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 4) {
            chip("Both", color: nil, selected: state.accountFilter == nil) { state.accountFilter = nil }
            ForEach(state.enabledAccounts) { account in
                chip(account.label, color: account.color, selected: state.accountFilter == account.id) {
                    state.accountFilter = account.id
                }
            }
            Spacer()
        }
    }

    private func chip(_ title: String, color: Color?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let color { Circle().fill(color).frame(width: 6, height: 6) }
                Text(title).lineLimit(1).truncationMode(.middle)
            }
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(selected ? Color.white : Color.secondary)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .frame(maxWidth: 170)
            .background(Capsule().fill(Color.white.opacity(selected ? 0.18 : 0.05)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Drops onto a card: the top half places the dragged card before it, the
/// bottom half stacks it underneath.
struct ModuleDropDelegate: DropDelegate {
    let targetID: String
    let height: CGFloat
    let state: AppState
    @Binding var zone: ArrangeTile.DropZone?

    private func zoneFor(_ info: DropInfo) -> ArrangeTile.DropZone {
        info.location.y > height * 0.5 ? .under : .before
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let z = zoneFor(info)
        if zone != z { zone = z }
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) { zone = nil }

    func performDrop(info: DropInfo) -> Bool {
        let under = zoneFor(info) == .under
        zone = nil
        MainActor.assumeIsolated {
            if let dragged = ReorderState.shared.draggingID {
                withAnimation(.easeOut(duration: 0.2)) {
                    state.moveModule(dragged: dragged, onto: targetID, under: under)
                }
            }
            ReorderState.shared.draggingID = nil
        }
        return true
    }
}
