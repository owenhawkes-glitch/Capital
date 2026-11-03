import SwiftUI

/// Hosting-view root: pins the notch to the top centre of the panel.
struct NotchRootView: View {
    @ObservedObject var state: AppState
    let geometry: NotchGeometry

    var body: some View {
        VStack(spacing: 0) {
            NotchView(state: state, geometry: geometry)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }
}

struct NotchView: View {
    @ObservedObject var state: AppState
    let geometry: NotchGeometry

    private var expanded: Bool { state.isExpanded }

    private var size: CGSize {
        NotchMetrics.size(geometry, expanded: expanded, pendingCount: state.pendingPermissions.count)
    }

    var body: some View {
        ZStack(alignment: .top) {
            NotchShape(bottomRadius: expanded ? 20 : 11)
                .fill(Color.black)

            VStack(spacing: 0) {
                CollapsedStrip(state: state, geometry: geometry)
                    .frame(width: NotchMetrics.collapsedWidth(geometry), height: geometry.notchHeight)
                if expanded {
                    ExpandedPanel(state: state)
                        .frame(width: size.width)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(NotchShape(bottomRadius: expanded ? 20 : 11))
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: expanded)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: state.pendingPermissions.count)
        .foregroundStyle(.white)
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

private struct ExpandedPanel: View {
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
            .padding(.top, 8)

            if !state.pendingPermissions.isEmpty {
                ApprovalList(state: state)
                    .padding(.horizontal, 14)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                if let last = state.lastRefresh {
                    Text("updated \(last.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
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
