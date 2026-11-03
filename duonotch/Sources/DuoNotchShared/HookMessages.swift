import Foundation

/// The JSON Claude Code writes to a hook's stdin. Every field is optional so
/// a newer Claude Code that adds or drops fields never breaks decoding.
/// Field names are Claude Code's own (snake_case).
public struct HookPayload: Codable {
    public var session_id: String?
    public var hook_event_name: String?
    public var cwd: String?
    public var transcript_path: String?
    public var permission_mode: String?

    // UserPromptSubmit
    public var prompt: String?

    // PermissionRequest / PreToolUse
    public var tool_name: String?
    public var tool_input: JSONValue?

    // Notification
    public var notification_type: String?
    public var message: String?

    // SessionEnd / SessionStart
    public var reason: String?
    public var source: String?

    public init() {}
}

/// What the hook helper sends to the app: one JSON object per line.
public struct HookEnvelope: Codable {
    public var token: String
    /// Resolved CLAUDE_CONFIG_DIR – this is how we know which login it is.
    public var configDir: String
    /// PID of the `claude` process that ran the hook (the hook's parent).
    public var claudePid: Int32
    public var payload: HookPayload

    public init(token: String, configDir: String, claudePid: Int32, payload: HookPayload) {
        self.token = token
        self.configDir = configDir
        self.claudePid = claudePid
        self.payload = payload
    }
}

/// What the app sends back. For most events it's empty. For
/// `PermissionRequest`, `behavior` is "allow" or "deny"; nil means
/// "let the terminal ask as usual".
public struct HookReply: Codable {
    public var behavior: String?
    public var message: String?

    public init(behavior: String? = nil, message: String? = nil) {
        self.behavior = behavior
        self.message = message
    }
}

public enum ToolSummary {
    /// One-line description of a tool call for the approval row.
    public static func summarize(toolName: String, input: JSONValue?) -> String {
        guard let input else { return toolName }
        switch toolName {
        case "Bash":
            return input["command"]?.stringValue ?? toolName
        case "Edit", "Write", "MultiEdit", "Read", "NotebookEdit":
            return input["file_path"]?.stringValue ?? toolName
        case "WebFetch":
            return input["url"]?.stringValue ?? toolName
        case "WebSearch":
            return input["query"]?.stringValue ?? toolName
        case "Grep", "Glob":
            return input["pattern"]?.stringValue ?? toolName
        default:
            if case .object(let dict) = input {
                for key in dict.keys.sorted() {
                    if let s = dict[key]?.stringValue, !s.isEmpty { return "\(key): \(s)" }
                }
            }
            return toolName
        }
    }
}
