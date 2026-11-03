import Foundation
import DuoNotchShared

/// Fake accounts, readings and sessions so the notch can be styled without
/// any Claude Code login. Enabled with `DUONOTCH_DEMO=1` or in Settings.
enum DemoData {
    @MainActor
    static func load(into state: AppState) {
        let personal = Account(
            configDir: "/demo/personal",
            label: "owen@personal.example",
            colorHex: AccountPalette.presets[0].hex,
            enabled: true,
            keychainServiceOverride: nil
        )
        let work = Account(
            configDir: "/demo/work",
            label: "owen@work.example",
            colorHex: AccountPalette.presets[1].hex,
            enabled: true,
            keychainServiceOverride: nil
        )

        let now = Date()
        let readings: [String: UsageReading] = [
            personal.id: UsageReading(
                fetchedAt: now,
                session: UsageWindow(fraction: 0.72, resetsAt: now.addingTimeInterval(2 * 3600 + 18 * 60)),
                weekly: UsageWindow(fraction: 0.41, resetsAt: now.addingTimeInterval(4 * 86_400 + 5 * 3600)),
                weeklyOpus: UsageWindow(fraction: 0.18, resetsAt: now.addingTimeInterval(4 * 86_400 + 5 * 3600)),
                weeklySonnet: nil,
                subscriptionType: "max"
            ),
            work.id: UsageReading(
                fetchedAt: now,
                session: UsageWindow(fraction: 0.23, resetsAt: now.addingTimeInterval(55 * 60)),
                weekly: UsageWindow(fraction: 0.88, resetsAt: now.addingTimeInterval(1 * 86_400 + 2 * 3600)),
                weeklyOpus: nil,
                weeklySonnet: nil,
                subscriptionType: "pro"
            ),
        ]

        let sessions: [ClaudeSession] = [
            ClaudeSession(id: "demo-1", accountID: personal.id, cwd: "/Users/demo/code/capital", state: .running,
                          lastEvent: now, endedAt: nil, lastPrompt: "Refactor the globe renderer", completedTurns: 3, claudePid: 0),
            ClaudeSession(id: "demo-2", accountID: personal.id, cwd: "/Users/demo/code/notch", state: .idle,
                          lastEvent: now.addingTimeInterval(-300), endedAt: nil, lastPrompt: nil, completedTurns: 1, claudePid: 0),
            ClaudeSession(id: "demo-3", accountID: work.id, cwd: "/Users/demo/work/api", state: .waiting,
                          lastEvent: now, endedAt: nil, lastPrompt: "Run the migration", completedTurns: 2, claudePid: 0),
            ClaudeSession(id: "demo-4", accountID: work.id, cwd: "/Users/demo/work/web", state: .ended,
                          lastEvent: now.addingTimeInterval(-900), endedAt: now.addingTimeInterval(-900), lastPrompt: nil, completedTurns: 5, claudePid: 0),
        ]

        let pending = [
            PermissionRequest(
                id: UUID(),
                accountID: work.id,
                sessionID: "demo-3",
                toolName: "Bash",
                summary: "npm run migrate -- --env staging",
                cwd: "/Users/demo/work/api",
                createdAt: now,
                reply: { _ in }
            ),
        ]

        state.setDemo(accounts: [personal, work], readings: readings, sessions: sessions, pending: pending)
    }
}
