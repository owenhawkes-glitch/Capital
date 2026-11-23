import Foundation

/// A folder you work in with Claude Code, plus how to start it there.
struct Project: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var path: String
    /// Config dir of the login to use; nil means the default `~/.claude`.
    var accountID: String?
    /// Extra flags appended to `claude`, e.g. "--model opus".
    var extraArgs: String
    /// Free text for the things you always forget about this project.
    var notes: String

    init(name: String, path: String, accountID: String? = nil, extraArgs: String = "", notes: String = "") {
        self.id = UUID()
        self.name = name
        self.path = path
        self.accountID = accountID
        self.extraArgs = extraArgs
        self.notes = notes
    }

    var displayPath: String { (path as NSString).abbreviatingWithTildeInPath }

    /// True when a session's working directory is this project or inside it.
    func contains(cwd: String) -> Bool {
        cwd == path || cwd.hasPrefix(path.hasSuffix("/") ? path : path + "/")
    }

    /// Git repositories directly in the home folder or one level down.
    static func discoverGitRepos() -> [Project] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let skip: Set<String> = ["Library", "Applications", "Movies", "Music", "Pictures", "Public", "node_modules"]
        var found: [Project] = []

        func check(_ dir: URL) {
            if fm.fileExists(atPath: dir.appendingPathComponent(".git").path) {
                found.append(Project(name: dir.lastPathComponent, path: dir.standardizedFileURL.path))
            }
        }

        guard let level1 = try? fm.contentsOfDirectory(at: home, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        for dir in level1 {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  !skip.contains(dir.lastPathComponent) else { continue }
            check(dir)
            if let level2 = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
                for sub in level2 where (try? sub.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    check(sub)
                }
            }
        }
        return found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
