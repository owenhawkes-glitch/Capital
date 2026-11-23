import AppKit
import DuoNotchShared

/// Opens a terminal in a project folder and starts Claude Code there with
/// the chosen login. Works by writing a small `.command` script and asking
/// Terminal (or iTerm2) to open it, so no Automation permission is needed.
enum ProjectLauncher {
    enum TerminalApp: String, CaseIterable, Identifiable {
        case terminal = "com.apple.Terminal"
        case iterm = "com.googlecode.iterm2"

        var id: String { rawValue }
        var name: String {
            switch self {
            case .terminal: return "Terminal"
            case .iterm: return "iTerm2"
            }
        }
    }

    enum LaunchError: Error, LocalizedError {
        case terminalNotInstalled(String)
        case folderMissing(String)

        var errorDescription: String? {
            switch self {
            case .terminalNotInstalled(let name): return "\(name) is not installed"
            case .folderMissing(let path): return "Folder not found: \(path)"
            }
        }
    }

    /// The exact command line, for showing and copying.
    static func commandLine(for project: Project, account: Account?) -> String {
        var parts: [String] = ["cd \(shellQuote(project.displayPath)) &&"]
        if let account, !account.isDefault {
            parts.append("CLAUDE_CONFIG_DIR=\(shellQuote(account.displayPath))")
        }
        parts.append("claude")
        let args = project.extraArgs.trimmingCharacters(in: .whitespaces)
        if !args.isEmpty { parts.append(args) }
        return parts.joined(separator: " ")
    }

    static func launch(_ project: Project, account: Account?, terminal: TerminalApp) throws {
        guard FileManager.default.fileExists(atPath: project.path) else {
            throw LaunchError.folderMissing(project.displayPath)
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: terminal.rawValue) else {
            throw LaunchError.terminalNotInstalled(terminal.name)
        }

        var lines: [String] = [
            "#!/bin/zsh -il",
            "# Written by DuoNotch – launches Claude Code for \(project.name)",
            "cd \(shellQuote(project.path)) || exit 1",
            "export DUONOTCH_LABEL=\(shellQuote(project.name))",
        ]
        if let account, !account.isDefault {
            lines.append("export CLAUDE_CONFIG_DIR=\(shellQuote(account.configDir))")
        }
        let args = project.extraArgs.trimmingCharacters(in: .whitespaces)
        lines.append("claude\(args.isEmpty ? "" : " " + args)")
        lines.append("exec zsh -il")   // keep the window usable after Claude exits

        let dir = HookWire.appSupportDirectory.appendingPathComponent("launch", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent("\(slug(project.name)).command")
        try (lines.joined(separator: "\n") + "\n").write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open([script], withApplicationAt: appURL, configuration: config) { _, _ in }
    }

    // MARK: - Helpers

    static func shellQuote(_ s: String) -> String {
        if s.hasPrefix("~/") {
            // Keep a leading ~ unquoted so the shell expands it.
            return "~/" + "'" + s.dropFirst(2).replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func slug(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let result = String(cleaned)
        return result.isEmpty ? "project" : result
    }
}

/// Brings the terminal tab that owns a Claude Code process to the front.
/// Uses AppleScript, so macOS asks once for permission to control Terminal.
enum TerminalRaiser {
    static func raise(claudePid: Int32, terminal: ProjectLauncher.TerminalApp) {
        guard claudePid > 0, let tty = ttyName(of: claudePid) else { return }
        let source: String
        switch terminal {
        case .terminal:
            source = """
            tell application "Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(tty)" then
                            set selected tab of w to t
                            set index of w to 1
                            activate
                            return
                        end if
                    end repeat
                end repeat
            end tell
            """
        case .iterm:
            source = """
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(tty)" then
                                select t
                                select w
                                activate
                                return
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            """
        }
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
        }
    }

    /// "/dev/ttys003" for a running process, via `ps`.
    private static func ttyName(of pid: Int32) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "tty=", "-p", String(pid)]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty, raw != "??" else { return nil }
        return raw.hasPrefix("/dev/") ? raw : "/dev/\(raw)"
    }
}
