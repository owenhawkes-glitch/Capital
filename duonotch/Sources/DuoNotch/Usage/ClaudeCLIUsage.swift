import Foundation
import DuoNotchShared

/// Reads usage by asking the installed `claude` for `/usage` — the same
/// numbers Claude Code shows. Claude Code reads its own login, so DuoNotch
/// never touches the keychain and macOS never prompts. No model is called.
enum ClaudeCLIUsage {
    enum CLIError: Error, LocalizedError {
        case notInstalled, timedOut, failed(String), unreadable

        var errorDescription: String? {
            switch self {
            case .notInstalled: return "Couldn't find the claude command"
            case .timedOut: return "claude /usage took too long"
            case .failed(let message): return message
            case .unreadable: return "Couldn't read claude /usage output"
            }
        }
    }

    /// Path to `claude`, found once.
    static let executable: String? = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude",
                          "\(home)/.claude/local/claude", "\(home)/.npm-global/bin/claude"]
        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) { return found }
        // Fall back to the login shell's PATH.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "command -v claude"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        let path = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? nil : path
    }()

    static func fetch(configDir: String) async throws -> UsageReading {
        guard let exe = executable else { throw CLIError.notInstalled }
        let output = try await run(exe, configDir: configDir)
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["result"] as? String else { throw CLIError.unreadable }
        if (json["is_error"] as? Bool) == true { throw CLIError.failed(text.components(separatedBy: "\n").first ?? text) }
        var reading = parse(text)
        reading.subscriptionType = plan(configDir: configDir)
        if reading.session == nil && reading.weekly == nil {
            throw CLIError.failed(text.components(separatedBy: "\n").first ?? "No usage reported")
        }
        return reading
    }

    // MARK: - Parsing

    /// Lines like:
    ///   Current session: 22% used · resets Nov 24 at 1:50am (Europe/London)
    ///   Current week (all models): 0% used · resets Nov 30 at 11pm (Europe/London)
    ///   Current week (Fable): 0% used · resets Nov 30 at 11pm (Europe/London)
    static func parse(_ text: String, now: Date = Date()) -> UsageReading {
        var reading = UsageReading(fetchedAt: now, session: nil, weekly: nil, weeklyOpus: nil, weeklySonnet: nil, subscriptionType: nil)
        let pattern = #"^Current (session|week \(([^)]+)\)):\s*(\d+(?:\.\d+)?)% used(?:\s*·\s*resets (.+?)(?:\s*\(([^)]+)\))?)?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return reading }
        let ns = text as NSString
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            func group(_ i: Int) -> String? {
                let r = match.range(at: i)
                return r.location == NSNotFound ? nil : ns.substring(with: r)
            }
            guard let percent = group(3).flatMap(Double.init) else { continue }
            let resets = group(4).flatMap { resetDate($0, zone: group(5), now: now) }
            let window = UsageWindow(fraction: min(max(percent / 100, 0), 1), resetsAt: resets)
            if group(1) == "session" {
                reading.session = window
            } else if let model = group(2) {
                if model.lowercased() == "all models" {
                    reading.weekly = window
                } else {
                    reading.modelWeeks[model] = window
                }
            }
        }
        return reading
    }

    static func resetDate(_ raw: String, zone: String?, now: Date) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone.flatMap(TimeZone.init(identifier:)) ?? .current
        formatter.defaultDate = now
        let cleaned = raw.replacingOccurrences(of: "am", with: "AM").replacingOccurrences(of: "pm", with: "PM")
        for format in ["MMM d 'at' h:mma", "MMM d 'at' ha", "MMM d, h:mma", "MMM d, ha", "h:mma", "ha"] {
            formatter.dateFormat = format
            guard var date = formatter.date(from: cleaned) else { continue }
            // No year (or no date) in the text: pick the next occurrence.
            if date < now.addingTimeInterval(-3600) {
                let step: Calendar.Component = format.hasPrefix("h") ? .day : .year
                date = Calendar.current.date(byAdding: step, value: 1, to: date) ?? date
            }
            return date
        }
        return nil
    }

    /// Plan name from the login's own profile (no keychain needed).
    static func plan(configDir: String) -> String? {
        var files = [URL(fileURLWithPath: configDir).appendingPathComponent(".claude.json")]
        if configDir == HookWire.defaultConfigDir() {
            files.insert(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json"), at: 0)
        }
        for file in files {
            guard let data = try? Data(contentsOf: file),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let account = json["oauthAccount"] as? [String: Any] else { continue }
            if let name = account["planDisplayName"] as? String, !name.isEmpty { return name }
            if let type = account["organizationType"] as? String {
                return type.replacingOccurrences(of: "claude_", with: "")
            }
        }
        return nil
    }

    // MARK: - Running claude

    private static func run(_ exe: String, configDir: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: exe)
                process.arguments = ["-p", "/usage", "--output-format", "json", "--no-session-persistence"]
                var env = ProcessInfo.processInfo.environment
                if configDir == HookWire.defaultConfigDir() {
                    env.removeValue(forKey: "CLAUDE_CONFIG_DIR")
                } else {
                    env["CLAUDE_CONFIG_DIR"] = configDir
                }
                // Tells duonotch-hook to ignore this run, so it isn't shown as a chat.
                env["DUONOTCH_INTERNAL"] = "1"
                process.environment = env
                let dir = HookWire.appSupportDirectory.appendingPathComponent("usage", isDirectory: true)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                process.currentDirectoryURL = dir
                let out = Pipe()
                process.standardOutput = out
                process.standardError = FileHandle.nullDevice
                process.standardInput = FileHandle.nullDevice
                do { try process.run() } catch {
                    continuation.resume(throwing: CLIError.failed(error.localizedDescription))
                    return
                }
                let deadline = DispatchTime.now() + 45
                let done = DispatchSemaphore(value: 0)
                var data = Data()
                DispatchQueue.global().async {
                    data = out.fileHandleForReading.readDataToEndOfFile()
                    done.signal()
                }
                if done.wait(timeout: deadline) == .timedOut {
                    process.terminate()
                    continuation.resume(throwing: CLIError.timedOut)
                    return
                }
                process.waitUntilExit()
                continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
            }
        }
    }
}
