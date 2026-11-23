import SwiftUI
import AppKit

/// Hosting-view root: anchors the notch to the edge it lives on.
struct NotchRootView: View {
    @ObservedObject var state: AppState
    let geometry: NotchGeometry

    var body: some View {
        NotchView(state: state, geometry: geometry)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: NotchView.anchor(for: state.placement))
            .environment(\.colorScheme, .dark)
    }
}

struct NotchView: View {
    @ObservedObject var state: AppState
    let geometry: NotchGeometry

    private var expanded: Bool { state.isExpanded }
    private var placement: NotchPlacement { state.placement }
    private var accountCount: Int { max(state.enabledAccounts.count, 1) }

    static func anchor(for placement: NotchPlacement) -> Alignment {
        switch placement {
        case .top: return .top
        case .left: return .leading
        case .right: return .trailing
        case .floating: return .topLeading
        }
    }

    private var size: CGSize {
        expanded
            ? NotchMetrics.expandedSize(geometry, placement: placement, accounts: accountCount, contentHeight: state.measuredContentHeight)
            : NotchMetrics.collapsedSize(geometry, placement: placement, accounts: accountCount)
    }

    private var shape: AnyShape {
        let r: CGFloat = expanded ? 18 : 11
        switch placement {
        case .top:
            return AnyShape(NotchShape(bottomRadius: expanded ? 20 : 10))
        case .left:
            return AnyShape(UnevenRoundedRectangle(bottomTrailingRadius: r, topTrailingRadius: r, style: .continuous))
        case .right:
            return AnyShape(UnevenRoundedRectangle(topLeadingRadius: r, bottomLeadingRadius: r, style: .continuous))
        case .floating:
            return AnyShape(RoundedRectangle(cornerRadius: r, style: .continuous))
        }
    }

    var body: some View {
        ZStack(alignment: Self.anchor(for: placement)) {
            shape.fill(Color.black)

            if placement == .top {
                VStack(spacing: 0) {
                    CollapsedStrip(state: state, geometry: geometry)
                        .frame(width: NotchMetrics.collapsedSize(geometry, placement: .top, accounts: accountCount).width,
                               height: geometry.notchHeight)
                    if expanded {
                        ExpandedPanel(state: state)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            } else if expanded {
                ExpandedPanel(state: state)
                    .transition(.opacity)
            } else {
                CompactPill(state: state, vertical: placement != .floating)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height, alignment: Self.anchor(for: placement))
        .clipShape(shape)
        .overlay(
            placement == .floating
                ? AnyView(shape.stroke(Color.white.opacity(0.12), lineWidth: 1))
                : AnyView(EmptyView())
        )
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: expanded)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: state.measuredContentHeight)
        .foregroundStyle(.white)
        .contextMenu { NotchContextMenu(state: state) }
    }
}

private struct NotchContextMenu: View {
    @ObservedObject var state: AppState

    var body: some View {
        Button("Settings…") { AppState.openSettings() }
        Button("Refresh usage now") { Task { await state.refreshAll() } }
        Button(state.pinnedOpen ? "Unpin" : "Keep open") { state.pinnedOpen.toggle() }
        Menu("Position") {
            ForEach(NotchPlacement.allCases) { option in
                Button {
                    state.placement = option
                } label: {
                    if option == state.placement { Text("✓ \(option.name)") } else { Text(option.name) }
                }
            }
        }
        Divider()
        Button("Quit DuoNotch") { NSApplication.shared.terminate(nil) }
    }
}

/// Drag-to-move for the floating placement.
private struct FloatingDrag: ViewModifier {
    @ObservedObject var state: AppState

    func body(content: Content) -> some View {
        if state.placement == .floating {
            content.gesture(
                DragGesture(minimumDistance: 3, coordinateSpace: .global)
                    .onChanged { _ in state.floatingDragChanged() }
                    .onEnded { _ in state.floatingDragEnded() }
            )
        } else {
            content
        }
    }
}

// MARK: - Compact pill (edges and floating)

/// Rings only, for the side edges (stacked) and the floating panel (in a row).
private struct CompactPill: View {
    @ObservedObject var state: AppState
    let vertical: Bool

    var body: some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 14))
        layout {
            if state.enabledAccounts.isEmpty {
                Text("–").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            ForEach(state.enabledAccounts.prefix(2)) { account in
                let window = state.readings[account.id]?.headline
                let parts = vertical
                    ? AnyLayout(VStackLayout(spacing: 3))
                    : AnyLayout(HStackLayout(spacing: 6))
                parts {
                    ZStack(alignment: .topTrailing) {
                        UsageRing(fraction: window?.fraction ?? 0, color: account.color)
                        ActivityDot(counts: state.counts(for: account.id))
                            .offset(x: 3, y: -2)
                    }
                    Text(window.map { "\($0.percent)%" } ?? "–")
                        .font(.system(size: vertical ? 9 : 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .help(account.label)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .modifier(FloatingDrag(state: state))
    }
}

// MARK: - Collapsed strip (always visible, sits either side of the camera)

private struct CollapsedStrip: View {
    @ObservedObject var state: AppState
    let geometry: NotchGeometry

    var body: some View {
        let accounts = state.enabledAccounts
        HStack(spacing: 0) {
            wing(for: accounts.first, alignment: .trailing)
                .frame(width: NotchMetrics.wingWidth)
            Color.clear
                .frame(width: geometry.hasHardwareNotch ? geometry.notchWidth : NotchMetrics.fakeGap)
            wing(for: accounts.count > 1 ? accounts[1] : nil, alignment: .leading)
                .frame(width: NotchMetrics.wingWidth)
        }
    }

    @ViewBuilder
    private func wing(for account: Account?, alignment: Alignment) -> some View {
        if let account {
            let window = state.readings[account.id]?.headline
            HStack(spacing: 6) {
                if alignment == .trailing { ActivityDot(counts: state.counts(for: account.id)) }
                UsageRing(fraction: window?.fraction ?? 0, color: account.color)
                Text(window.map { "\($0.percent)%" } ?? "–")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(window == nil ? Color.secondary : Color.primary)
                if alignment == .leading { ActivityDot(counts: state.counts(for: account.id)) }
            }
            .frame(maxWidth: .infinity, alignment: alignment)
            .padding(.horizontal, 10)
            .help(account.label)
        } else {
            Text(state.enabledAccounts.isEmpty ? "no login" : "")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: alignment)
                .padding(.horizontal, 10)
        }
    }
}

// MARK: - Expanded panel

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct ExpandedPanel: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(spacing: 8) {
            TabBar(state: state)
                .padding(.horizontal, 14)

            switch state.selectedTab {
            case .claude:
                ClaudePage(state: state)
            case .clipboard:
                ClipboardPage()
                    .padding(.horizontal, 14)
            }

            HStack {
                Spacer()
                if state.selectedTab == .claude, let last = state.lastRefresh {
                    Text("updated \(last.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
        }
        .padding(.top, 6)
        .frame(width: NotchMetrics.expandedWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
        })
        .onPreferenceChange(ContentHeightKey.self) { height in
            MainActor.assumeIsolated { state.setMeasuredContentHeight(height) }
        }
    }
}

/// Page switcher on the left, pinned apps on the right. In the floating
/// placement the empty middle is the handle for dragging the window.
private struct TabBar: View {
    @ObservedObject var state: AppState
    @ObservedObject private var apps = AppShortcutStore.shared

    var body: some View {
        HStack(spacing: 4) {
            ForEach(NotchTab.allCases) { tab in
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

            Color.clear
                .frame(maxWidth: .infinity, minHeight: 20)
                .contentShape(Rectangle())
                .modifier(FloatingDrag(state: state))

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
                    .help(app.name)
                }
            }
        }
        .frame(height: 24)
    }
}

private struct ClaudePage: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                if state.enabledAccounts.isEmpty {
                    EmptyAccountsCard()
                } else {
                    ForEach(state.enabledAccounts) { account in
                        AccountCard(state: state, account: account)
                    }
                }
            }
            .padding(.horizontal, 14)

            if !state.projects.isEmpty {
                ProjectsRow(state: state)
                    .padding(.horizontal, 14)
            }

            if !state.pendingPermissions.isEmpty {
                ApprovalList(state: state)
                    .padding(.horizontal, 14)
            }
        }
    }
}

// MARK: - Clipboard page

private struct ClipboardPage: View {
    @ObservedObject private var clipboard = ClipboardStore.shared
    private let rowHeight: CGFloat = 20

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
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
            .frame(height: CGFloat(NotchMetrics.clipboardRows) * (rowHeight + 2))
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

private struct EmptyAccountsCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No Claude Code login found")
                .font(.system(size: 12, weight: .semibold))
            Text("Run `claude` once, or add a second login with\nCLAUDE_CONFIG_DIR=~/.claude-work claude")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
    }
}

private struct AccountCard: View {
    @ObservedObject var state: AppState
    let account: Account

    var body: some View {
        let reading = state.readings[account.id]
        let counts = state.counts(for: account.id)
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Circle().fill(account.color).frame(width: 7, height: 7)
                Text(account.label)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Text(Formatting.planName(reading?.subscriptionType))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if let reading {
                UsageRow(title: "Session", window: reading.session, color: account.color)
                UsageRow(title: "Week", window: reading.weekly, color: account.color)
                if let opus = reading.weeklyOpus {
                    UsageRow(title: "Opus", window: opus, color: account.color)
                }
            } else {
                Text(state.errors[account.id] ?? "Waiting for first reading…")
                    .font(.system(size: 10))
                    .foregroundStyle(state.errors[account.id] == nil ? Color.secondary : Color.orange)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if reading != nil, let error = state.errors[account.id] {
                Text(error)
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }

            SessionsRow(counts: counts, hooksInstalled: state.hooksInstalled[account.id] ?? false)

            let visible = state.sessions(for: account.id).prefix(NotchMetrics.maxSessionRows)
            if !visible.isEmpty {
                VStack(spacing: 2) {
                    ForEach(visible) { session in
                        SessionRow(state: state, session: session)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
    }
}

/// One chat: state dot, name, turns, how long since it last did anything.
/// Clicking brings its terminal tab to the front.
private struct SessionRow: View {
    @ObservedObject var state: AppState
    let session: ClaudeSession

    private var tint: Color {
        switch session.state {
        case .running: return .green
        case .waiting: return .yellow
        case .idle: return Color.white.opacity(0.55)
        case .ended: return Color.blue.opacity(0.8)
        }
    }

    var body: some View {
        Button {
            state.raiseTerminal(for: session)
        } label: {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 5, height: 5)
                Text(state.displayName(for: session))
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Text(session.completedTurns == 1 ? "1 turn" : "\(session.completedTurns) turns")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(Formatting.age(since: session.lastEvent))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
            .opacity(session.state == .ended ? 0.6 : 1)
            .frame(height: NotchMetrics.sessionRowHeight - 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(session.cwd)\nClick to show this terminal")
    }
}

// MARK: - Projects

/// Chips for your projects. Click one to open a terminal there with the
/// right login and start Claude Code.
private struct ProjectsRow: View {
    @ObservedObject var state: AppState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Text("Open")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 2)
                ForEach(state.projects) { project in
                    Button {
                        state.launch(project)
                    } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(state.account(for: project)?.color ?? .gray)
                                .frame(width: 6, height: 6)
                            Text(project.name)
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("\(ProjectLauncher.commandLine(for: project, account: state.account(for: project)))\(project.notes.isEmpty ? "" : "\n\n" + project.notes)")
                }
            }
            .padding(.vertical, 2)
        }
        .frame(height: 28)
    }
}

private struct UsageRow: View {
    let title: String
    let window: UsageWindow?
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            UsageBar(fraction: window?.fraction ?? 0, color: color)
            Text(window.map { "\($0.percent)%" } ?? "–")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(width: 34, alignment: .trailing)
            Text(window.map { Formatting.remaining(until: $0.resetsAt) } ?? "")
                .font(.system(size: 9))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
        }
    }
}

private struct SessionsRow: View {
    let counts: SessionCounts
    let hooksInstalled: Bool

    var body: some View {
        HStack(spacing: 6) {
            if counts.isEmpty {
                Text(hooksInstalled ? "no sessions" : "hooks not installed · see Settings")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            } else {
                if counts.running > 0 { pill("\(counts.running) running", .green) }
                if counts.waiting > 0 { pill("\(counts.waiting) waiting", .yellow) }
                if counts.idle > 0 { pill("\(counts.idle) idle", Color.white.opacity(0.6)) }
                if counts.done > 0 { pill("\(counts.done) done", Color.blue.opacity(0.9)) }
            }
            Spacer(minLength: 0)
        }
    }

    private func pill(_ text: String, _ tint: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(tint).frame(width: 5, height: 5)
            Text(text).font(.system(size: 9, weight: .medium))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }
}

// MARK: - Approvals

private struct ApprovalList: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(spacing: 6) {
            ForEach(state.pendingPermissions.prefix(NotchMetrics.maxVisibleApprovals)) { request in
                ApprovalRow(state: state, request: request)
            }
            if state.pendingPermissions.count > NotchMetrics.maxVisibleApprovals {
                Text("+\(state.pendingPermissions.count - NotchMetrics.maxVisibleApprovals) more waiting")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ApprovalRow: View {
    @ObservedObject var state: AppState
    let request: PermissionRequest

    private var account: Account? {
        state.accounts.first { $0.id == request.accountID }
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(account?.color ?? .gray).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(request.toolName).font(.system(size: 11, weight: .semibold))
                    Text("· \(URL(fileURLWithPath: request.cwd).lastPathComponent)")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Text(request.summary)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 6)
            Button("Terminal") { state.resolve(request.id, decision: .askInTerminal) }
                .buttonStyle(NotchButtonStyle(tint: Color.white.opacity(0.25)))
            Button("Deny") { state.resolve(request.id, decision: .deny) }
                .buttonStyle(NotchButtonStyle(tint: .red))
            Button("Allow") { state.resolve(request.id, decision: .allow) }
                .buttonStyle(NotchButtonStyle(tint: .green))
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 10)
        .frame(height: NotchMetrics.approvalRowHeight - 6)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.09)))
    }
}
