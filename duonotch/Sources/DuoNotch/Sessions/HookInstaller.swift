import Foundation
import DuoNotchShared

/// Adds (or removes) the `duonotch-hook` entries in a login's
/// `settings.json`. Existing hooks from other tools are left untouched; only
/// groups whose command mentions `duonotch-hook` are replaced.
enum HookInstaller {
    static let events = ["SessionStart", "UserPromptSubmit", "Stop", "SessionEnd", "Notification", "PermissionRequest"]

    /// Seconds Claude Code waits for the PermissionRequest hook before
    /// falling back to its own terminal prompt.
    static let permissionTimeout = 300

    enum InstallError: Error, LocalizedError {
        case hookBinaryMissing
        case unreadableSettings(String)

        var errorDescription: String? {
            switch self {
            case .hookBinaryMissing:
                return "duonotch-hook was not found next to the app binary. Build with `make bundle`."
            case .unreadableSettings(let path):
                return "\(path) exists but is not a JSON object"
            }
        }
    }

    static var hookBinaryURL: URL? {
        guard let exe = Bundle.main.executableURL else { return nil }
        let url = exe.deletingLastPathComponent().appendingPathComponent(HookWire.hookBinaryName)
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    static func settingsURL(for configDir: String) -> URL {
        URL(fileURLWithPath: configDir).appendingPathComponent("settings.json")
    }

    static func isInstalled(configDir: String) -> Bool {
        guard let root = try? readSettings(configDir: configDir),
              let hooks = root["hooks"] as? [String: Any] else { return false }
        for event in events {
            let groups = hooks[event] as? [[String: Any]] ?? []
            guard groups.contains(where: isOurs) else { return false }
        }
        return true
    }

    static func install(configDir: String) throws {
        guard let binary = hookBinaryURL else { throw InstallError.hookBinaryMissing }
        var root = try readSettings(configDir: configDir) ?? [:]
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let command = "\"\(binary.path)\""

        for event in events {
            var groups = (hooks[event] as? [[String: Any]] ?? []).filter { !isOurs($0) }
            var hook: [String: Any] = ["type": "command", "command": command]
            hook["timeout"] = event == "PermissionRequest" ? permissionTimeout : 10
            groups.append(["hooks": [hook]])
            hooks[event] = groups
        }
        root["hooks"] = hooks
        try writeSettings(root, configDir: configDir)
    }

    static func uninstall(configDir: String) throws {
        guard var root = try readSettings(configDir: configDir),
              var hooks = root["hooks"] as? [String: Any] else { return }
        for event in events {
            let groups = (hooks[event] as? [[String: Any]] ?? []).filter { !isOurs($0) }
            if groups.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = groups }
        }
        if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
        try writeSettings(root, configDir: configDir)
    }

    // MARK: - Private

    private static func isOurs(_ group: [String: Any]) -> Bool {
        let hooks = group["hooks"] as? [[String: Any]] ?? []
        return hooks.contains { ($0["command"] as? String)?.contains(HookWire.hookBinaryName) == true }
    }

    private static func readSettings(configDir: String) throws -> [String: Any]? {
        let url = settingsURL(for: configDir)
        guard let data = try? Data(contentsOf: url) else { return nil }
        if data.trimmed.isEmpty { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InstallError.unreadableSettings(url.path)
        }
        return object
    }

    private static func writeSettings(_ root: [String: Any], configDir: String) throws {
        let url = settingsURL(for: configDir)
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: url.path) {
            let backup = url.deletingLastPathComponent().appendingPathComponent("settings.json.duonotch-backup")
            if !fm.fileExists(atPath: backup.path) {
                try? fm.copyItem(at: url, to: backup)
            }
        }
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }
}

private extension Data {
    var trimmed: String {
        (String(data: self, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
