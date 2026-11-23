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
    @ObservedObject private var look = AppearanceStore.shared
    let geometry: NotchGeometry

    private var expanded: Bool { state.isExpanded }
    private var placement: NotchPlacement { state.placement }

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
            ? NotchMetrics.expandedSize(geometry, placement: placement, strip: state.strip, scale: state.notchScale, width: state.panelContentWidth(maxWidth: geometry.screen.visibleFrame.width - 40), contentHeight: state.measuredContentHeight)
            : NotchMetrics.collapsedSize(geometry, placement: placement, strip: state.strip, scale: state.notchScale)
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
            NotchBackground(expanded: expanded)
                .clipShape(shape)

            if placement == .top {
                VStack(spacing: 0) {
                    CollapsedStrip(state: state, geometry: geometry)
                        .frame(width: NotchMetrics.collapsedSize(geometry, placement: .top, strip: state.strip, scale: state.notchScale).width,
                               height: geometry.notchHeight)
                    if expanded {
                        ExpandedPanel(state: state, width: state.panelContentWidth(maxWidth: geometry.screen.visibleFrame.width - 40), maxHeight: geometry.screen.visibleFrame.height - 20)
                            .transition(look.openStyle.transition(edge: .top))
                    }
                }
            } else if expanded && (placement == .left || placement == .right) {
                let pill = NotchMetrics.collapsedSize(geometry, placement: placement, strip: state.strip, scale: state.notchScale)
                HStack(spacing: 0) {
                    if placement == .left {
                        CompactPill(state: state, vertical: true)
                            .frame(width: pill.width, height: min(pill.height, size.height))
                    }
                    ExpandedPanel(state: state, width: state.panelContentWidth(maxWidth: geometry.screen.visibleFrame.width - 40), maxHeight: geometry.screen.visibleFrame.height - 20)
                        .transition(look.openStyle.transition(edge: placement == .left ? .leading : .trailing))
                    if placement == .right {
                        CompactPill(state: state, vertical: true)
                            .frame(width: pill.width, height: min(pill.height, size.height))
                    }
                }
            } else if expanded {
                ExpandedPanel(state: state, width: state.panelContentWidth(maxWidth: geometry.screen.visibleFrame.width - 40), maxHeight: geometry.screen.visibleFrame.height - 20)
                    .transition(look.openStyle.transition(edge: .top))
            } else {
                CompactPill(state: state, vertical: placement != .floating)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height, alignment: Self.anchor(for: placement))
        .clipShape(shape)
        .overlay(
            placement == .floating && !look.glowBorder
                ? AnyView(shape.stroke(Color.white.opacity(0.12), lineWidth: 1))
                : AnyView(EmptyView())
        )
        .overlay(GlowBorder(shape: shape))
        .animation(look.openAnimationValue, value: expanded)
        .animation(look.openAnimationValue, value: state.measuredContentHeight)
        .foregroundStyle(.white)
        .contextMenu { NotchContextMenu(state: state) }
        .onDrop(of: [.fileURL], isTargeted: $state.fileDragOver) { providers in
            let accepted = FileShelf.shared.accept(providers)
            if accepted, state.isEnabled(.files) { state.show(tab: .files) }
            return accepted
        }
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
        Menu(Caffeine.shared.isOn ? "Keep awake ☕︎ (on)" : "Keep awake") {
            Button("Until I switch it off") { Caffeine.shared.set(.on(until: nil)) }
            Button("For 1 hour") { Caffeine.shared.keepAwake(hours: 1) }
            Button("For 2 hours") { Caffeine.shared.keepAwake(hours: 2) }
            Button("For 4 hours") { Caffeine.shared.keepAwake(hours: 4) }
            Button("For 8 hours") { Caffeine.shared.keepAwake(hours: 8) }
            Button("While Claude chats are running") { Caffeine.shared.set(.whileChatsRun) }
            Divider()
            Button((Caffeine.shared.keepDisplayOn ? "✓ " : "") + "Keep the screen on too") { Caffeine.shared.keepDisplayOn.toggle() }
            Button("Off") { Caffeine.shared.set(.off) }.disabled(!Caffeine.shared.isOn)
        }
        if !state.notchPresets.isEmpty {
            Menu("Layout preset") {
                ForEach(state.notchPresets) { preset in
                    Button(preset.name) { state.applyPreset(preset) }
                }
            }
        }
        if state.placement != .top {
            Menu("Size") {
                ForEach([("Small", 0.85), ("Normal", 1.0), ("Large", 1.35), ("Extra large", 1.7)], id: \.1) { option in
                    Button((state.notchScale == option.1 ? "✓ " : "") + option.0) { state.notchScale = option.1 }
                }
            }
        }
        Divider()
        Button("Quit DuoNotch") { NSApplication.shared.terminate(nil) }
    }
}

/// Drag-to-move for the floating placement.
struct FloatingDrag: ViewModifier {
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

/// The chosen items, stacked on a side edge or in a row when floating.
private struct CompactPill: View {
    @ObservedObject var state: AppState
    let vertical: Bool

    var body: some View {
        let items = state.strip.all
        let scale = state.notchScale
        let layout = vertical ? AnyLayout(VStackLayout(spacing: NotchStrip.spacing * 1.25 * scale)) : AnyLayout(HStackLayout(spacing: NotchStrip.spacing * 1.5 * scale))
        layout {
            if items.isEmpty {
                Text("–").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                NotchItemView(state: state, item: item, vertical: vertical, scale: scale)
                    .reorderTarget(id: item.id.uuidString) { state.moveNotchItem(dragged: $0, onto: $1) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            if state.placement == .floating && state.floatingOpensOnClick { state.floatingOpen = true }
        }
        .modifier(FloatingDrag(state: state))
    }
}

// MARK: - Collapsed strip (always visible, sits either side of the camera)

private struct CollapsedStrip: View {
    @ObservedObject var state: AppState
    let geometry: NotchGeometry

    var body: some View {
        let strip = state.strip
        if !geometry.hasHardwareNotch {
            // Screens without a camera notch: all items in one centred row.
            HStack(spacing: NotchStrip.spacing) {
                ForEach(strip.all) { item in
                    NotchItemView(state: state, item: item)
                        .reorderTarget(id: item.id.uuidString) { state.moveNotchItem(dragged: $0, onto: $1) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            split(strip)
        }
    }

    private func split(_ strip: NotchStrip) -> some View {
        HStack(spacing: 0) {
            wing(strip.left, alignment: .trailing)
                .frame(width: strip.wingWidth)
            Color.clear
                .frame(width: geometry.hasHardwareNotch ? geometry.notchWidth : NotchMetrics.fakeGap)
            wing(strip.right, alignment: .leading)
                .frame(width: strip.wingWidth)
        }
    }

    private func wing(_ items: [NotchItem], alignment: Alignment) -> some View {
        let side: NotchSide = alignment == .trailing ? .left : .right
        return HStack(spacing: NotchStrip.spacing) {
            ForEach(items) { item in
                NotchItemView(state: state, item: item)
                    .reorderTarget(id: item.id.uuidString) { state.moveNotchItem(dragged: $0, onto: $1) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        .padding(.horizontal, NotchStrip.padding / 2)
        .contentShape(Rectangle())
        // Dropping on an empty part of a wing moves the item to that side.
        .onDrop(of: [.duoNotchReorder], delegate: WingDropDelegate(side: side, state: state))
    }
}

private struct WingDropDelegate: DropDelegate {
    let side: NotchSide
    let state: AppState

    func dropEntered(info: DropInfo) {
        MainActor.assumeIsolated {
            guard let dragged = ReorderState.shared.draggingID else { return }
            withAnimation(.easeOut(duration: 0.15)) { state.moveNotchItem(dragged: dragged, toSide: side) }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        MainActor.assumeIsolated { ReorderState.shared.draggingID = nil }
        return true
    }
}

struct EmptyAccountsCard: View {
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

struct AccountCard: View {
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
                ForEach(reading.modelWeeks.keys.sorted(), id: \.self) { model in
                    if let window = reading.modelWeeks[model] {
                        UsageRow(title: model, window: window, color: account.color)
                    }
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
struct ProjectsRow: View {
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

struct ApprovalList: View {
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
