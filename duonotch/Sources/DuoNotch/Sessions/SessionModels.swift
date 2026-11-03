import Foundation
import DuoNotchShared

enum SessionState: String {
    /// Claude is working on a turn.
    case running
    /// Claude is waiting on you (permission prompt or a question).
    case waiting
    /// Open, last turn finished, waiting for your next prompt.
    case idle
    /// The session ended (SessionEnd) or its process went away.
    case ended
}

/// One Claude Code conversation, as seen through hooks.
struct ClaudeSession: Identifiable, Equatable {
    let id: String            // Claude Code's session_id
    var accountID: String     // config dir
    var cwd: String
    var state: SessionState
    var lastEvent: Date
    var endedAt: Date?
    var lastPrompt: String?
    var completedTurns: Int = 0
    var claudePid: Int32

    var projectName: String {
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? cwd : name
    }
}

struct SessionCounts: Equatable {
    var running = 0
    var waiting = 0
    var idle = 0
    var done = 0

    var open: Int { running + waiting + idle }
    var isEmpty: Bool { running + waiting + idle + done == 0 }
}

enum PermissionDecision {
    case allow
    case deny
    /// Hand the question back to the terminal prompt.
    case askInTerminal
}

/// A tool call Claude Code is asking permission for, parked until you
/// answer it in the notch (or the hook times out and the terminal asks).
struct PermissionRequest: Identifiable {
    let id: UUID
    let accountID: String
    let sessionID: String
    let toolName: String
    let summary: String
    let cwd: String
    let createdAt: Date
    let reply: (HookReply) -> Void
}
