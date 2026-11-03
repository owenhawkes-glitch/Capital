import Foundation

/// Constants and paths shared between the app and the `duonotch-hook` helper.
public enum HookWire {
    /// Loopback TCP port the app listens on for hook events.
    public static let port: UInt16 = 47123

    /// Name of the hook helper executable (lives next to the app binary).
    public static let hookBinaryName = "duonotch-hook"

    /// ~/Library/Application Support/DuoNotch
    public static var appSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("DuoNotch", isDirectory: true)
    }

    /// Random shared secret so only hooks started on this Mac can talk to the app.
    public static var tokenFile: URL {
        appSupportDirectory.appendingPathComponent("hook-token")
    }

    public static func readToken() -> String? {
        guard let raw = try? String(contentsOf: tokenFile, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// `~/.claude` – what Claude Code uses when CLAUDE_CONFIG_DIR is unset.
    public static func defaultConfigDir() -> String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude").standardizedFileURL.path
    }

    /// Resolves a CLAUDE_CONFIG_DIR value the way Claude Code does:
    /// unset/empty → ~/.claude, "~" expanded, path standardised.
    public static func resolveConfigDir(_ raw: String?) -> String {
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else {
            return defaultConfigDir()
        }
        let expanded = (raw as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }
}
