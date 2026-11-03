import Foundation
import DuoNotchShared

/// Finds Claude Code config directories in the home folder: `~/.claude`
/// plus any `~/.claude-<slug>` created with `CLAUDE_CONFIG_DIR`.
enum AccountDiscovery {
    static func discoverConfigDirs() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: home,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { return [] }

        var dirs: [String] = []
        for url in items {
            let name = url.lastPathComponent
            guard name == ".claude" || name.hasPrefix(".claude-") else { continue }
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { continue }
            dirs.append(url.standardizedFileURL.path)
        }
        let defaultDir = HookWire.defaultConfigDir()
        return dirs.sorted { a, b in
            if a == defaultDir { return true }
            if b == defaultDir { return false }
            return a < b
        }
    }

    /// Claude Code stores the signed-in account's email in `.claude.json`
    /// (`~/.claude.json` for the default login, `<configDir>/.claude.json`
    /// for custom ones). Used only as a friendly default label.
    static func emailHint(for configDir: String) -> String? {
        var candidates = [URL(fileURLWithPath: configDir).appendingPathComponent(".claude.json")]
        if configDir == HookWire.defaultConfigDir() {
            candidates.append(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json"))
        }
        for url in candidates {
            guard let data = try? Data(contentsOf: url),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let oauth = root["oauthAccount"] as? [String: Any] else { continue }
            if let email = oauth["emailAddress"] as? String, !email.isEmpty { return email }
        }
        return nil
    }

    /// A short default label: the slug after `.claude-`, or "Default".
    static func slugLabel(for configDir: String) -> String {
        let name = URL(fileURLWithPath: configDir).lastPathComponent
        if name == ".claude" { return "Default" }
        let slug = name.dropFirst(".claude-".count)
        return slug.isEmpty ? name : slug.prefix(1).uppercased() + String(slug.dropFirst())
    }
}
