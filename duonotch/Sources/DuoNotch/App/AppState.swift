import Foundation
import AppKit
import Combine
import DuoNotchShared

/// Everything the notch, the menu bar item and Settings read from.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    // MARK: Accounts

    @Published var accounts: [Account] {
        didSet { persistAccounts() }
    }

    var enabledAccounts: [Account] { accounts.filter(\.enabled) }

    // MARK: Readings

    @Published private(set) var readings: [String: UsageReading] = [:]
    @Published private(set) var errors: [String: String] = [:]
    @Published private(set) var lastRefresh: Date?

    // MARK: Sessions & approvals

    @Published private(set) var sessions: [ClaudeSession] = []
    @Published private(set) var pendingPermissions: [PermissionRequest] = []
    @Published private(set) var hooksInstalled: [String: Bool] = [:]
    @Published private(set) var serverStatus = "not started"

    // MARK: Notch presentation

    @Published var hovering = false
    @Published var pinnedOpen = false
    @Published private(set) var peeking = false

    var isExpanded: Bool {
        pinnedOpen || hovering || peeking || !pendingPermissions.isEmpty
    }

    // MARK: Preferences (persisted in UserDefaults)

    @Published var demoMode: Bool {
        didSet {
            defaults.set(demoMode, forKey: Keys.demoMode)
            if started { applyMode() }
        }
    }
    @Published var pollIntervalSeconds: Int {
        didSet { defaults.set(pollIntervalSeconds, forKey: Keys.pollInterval) }
    }
    @Published var peekOnFinish: Bool {
        didSet { defaults.set(peekOnFinish, forKey: Keys.peekOnFinish) }
    }
    @Published var showMenuBarText: Bool {
        didSet { defaults.set(showMenuBarText, forKey: Keys.menuBarText) }
    }

    // MARK: - Private state

    private enum Keys {
        static let accounts = "accounts.v1"
        static let demoMode = "demoMode"
        static let pollInterval = "pollIntervalSeconds"
        static let peekOnFinish = "peekOnFinish"
        static let menuBarText = "showMenuBarText"
    }

    private let defaults = UserDefaults.standard
    private let client = ClaudeUsageClient()
    private var server: HookServer?
    private var pollTask: Task<Void, Never>?
    private var housekeepingTimer: Timer?
    private var peekTask: Task<Void, Never>?
    private var backoffUntil: [String: Date] = [:]
    private var backoffSeconds: [String: TimeInterval] = [:]
    private var started = false

    private init() {
        let stored = UserDefaults.standard
        let interval = stored.integer(forKey: Keys.pollInterval)
        pollIntervalSeconds = interval > 0 ? interval : 300
        peekOnFinish = stored.object(forKey: Keys.peekOnFinish) as? Bool ?? true
        showMenuBarText = stored.bool(forKey: Keys.menuBarText)
        demoMode = stored.bool(forKey: Keys.demoMode)
            || ProcessInfo.processInfo.environment["DUONOTCH_DEMO"] == "1"
        accounts = Self.loadPersistedAccounts()
    }

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true
        applyMode()
        housekeepingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            MainActor.assumeIsolated { AppState.shared.housekeeping() }
        }
    }

    func stop() {
        pollTask?.cancel()
        server?.stop()
        housekeepingTimer?.invalidate()
    }

    private func applyMode() {
        pollTask?.cancel()
        pollTask = nil
        server?.stop()
        server = nil
        readings = [:]
        errors = [:]
        sessions = []
        pendingPermissions.forEach { $0.reply(HookReply()) }
        pendingPermissions = []

        if demoMode {
            DemoData.load(into: self)
            serverStatus = "demo mode"
            return
        }

        accounts = Self.loadPersistedAccounts()
        mergeDiscoveredAccounts()
        startServer()
        refreshHooksInstalled()
        startPolling()
    }

    // MARK: - Accounts

    func mergeDiscoveredAccounts() {
        var merged = accounts
        for dir in AccountDiscovery.discoverConfigDirs() where !merged.contains(where: { $0.configDir == dir }) {
            merged.append(makeAccount(configDir: dir, index: merged.count))
        }
        if merged != accounts { accounts = merged }
    }

    /// Hooks can arrive from a config directory we have not seen (for
    /// example one outside the home folder). Add it so its sessions show.
    private func ensureAccount(configDir: String) {
        guard !accounts.contains(where: { $0.configDir == configDir }) else { return }
        accounts.append(makeAccount(configDir: configDir, index: accounts.count))
        refreshHooksInstalled()
    }

    private func makeAccount(configDir: String, index: Int) -> Account {
        let label = AccountDiscovery.emailHint(for: configDir) ?? AccountDiscovery.slugLabel(for: configDir)
        return Account(
            configDir: configDir,
            label: label,
            colorHex: AccountPalette.preset(at: index).hex,
            enabled: true,
            keychainServiceOverride: nil
        )
    }

    func removeAccount(_ account: Account) {
        accounts.removeAll { $0.id == account.id }
        readings[account.id] = nil
        errors[account.id] = nil
    }

    private static func loadPersistedAccounts() -> [Account] {
        guard let data = UserDefaults.standard.data(forKey: Keys.accounts),
              let decoded = try? JSONDecoder().decode([Account].self, from: data) else { return [] }
        return decoded
    }

    private func persistAccounts() {
        guard !demoMode else { return }
        if let data = try? JSONEncoder().encode(accounts) {
            defaults.set(data, forKey: Keys.accounts)
        }
    }

    // MARK: - Usage polling

    private var anySessionRunning: Bool {
        sessions.contains { $0.state == .running }
    }

    private func startPolling() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshAll()
                let interval = self.anySessionRunning ? 30 : max(self.pollIntervalSeconds, 30)
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func refreshAll() async {
        guard !demoMode else { return }
        // Pick up a login created since launch, and hooks installed by hand.
        mergeDiscoveredAccounts()
        refreshHooksInstalled()
        for account in enabledAccounts {
            await refresh(account)
        }
        lastRefresh = Date()
    }

    func refresh(_ account: Account) async {
        if let until = backoffUntil[account.id], until > Date() { return }

        let loaded = await Task.detached(priority: .utility) {
            CredentialStore.load(for: account)
        }.value

        let credentials: OAuthCredentials
        switch loaded {
        case .failure(let error):
            errors[account.id] = error.localizedDescription
            return
        case .success(let creds):
            credentials = creds
        }

        if credentials.isExpired {
            errors[account.id] = "Token expired – run `\(account.launchHint)` once to refresh it"
            return
        }

        do {
            var reading = try await client.fetch(accessToken: credentials.accessToken)
            reading.subscriptionType = credentials.subscriptionType
            readings[account.id] = reading
            errors[account.id] = nil
            backoffSeconds[account.id] = nil
            backoffUntil[account.id] = nil
        } catch UsageError.rateLimited(let retryAfter) {
            let previous = backoffSeconds[account.id] ?? 30
            let next = min(max(retryAfter ?? previous * 2, 60), 900)
            backoffSeconds[account.id] = next
            backoffUntil[account.id] = Date().addingTimeInterval(next)
            errors[account.id] = "Rate limited – retrying in \(Int(next))s"
        } catch {
            errors[account.id] = error.localizedDescription
        }
    }

    // MARK: - Hook server

    private func startServer() {
        guard let token = ensureToken() else {
            serverStatus = "could not create hook token"
            return
        }
        let server = HookServer(token: token)
        server.onStatus = { status in
            Task { @MainActor in AppState.shared.serverStatus = status }
        }
        server.onEnvelope = { envelope, reply in
            Task { @MainActor in AppState.shared.handle(envelope, reply: reply) }
        }
        server.start()
        self.server = server
    }

    private func ensureToken() -> String? {
        if let existing = HookWire.readToken() { return existing }
        let dir = HookWire.appSupportDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        do {
            try Data(token.utf8).write(to: HookWire.tokenFile, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: HookWire.tokenFile.path)
            return token
        } catch {
            return nil
        }
    }

    func refreshHooksInstalled() {
        var result: [String: Bool] = [:]
        for account in accounts {
            result[account.id] = HookInstaller.isInstalled(configDir: account.configDir)
        }
        hooksInstalled = result
    }

    // MARK: - Hook events

    private func handle(_ envelope: HookEnvelope, reply: @escaping (HookReply) -> Void) {
        let accountID = envelope.configDir
        ensureAccount(configDir: accountID)

        let payload = envelope.payload
        let sessionID = payload.session_id ?? "pid-\(envelope.claudePid)"
        var session = sessions.first { $0.id == sessionID } ?? ClaudeSession(
            id: sessionID,
            accountID: accountID,
            cwd: payload.cwd ?? "",
            state: .idle,
            lastEvent: Date(),
            endedAt: nil,
            lastPrompt: nil,
            completedTurns: 0,
            claudePid: envelope.claudePid
        )
        session.lastEvent = Date()
        session.claudePid = envelope.claudePid
        if let cwd = payload.cwd, !cwd.isEmpty { session.cwd = cwd }

        var replied = false
        switch payload.hook_event_name {
        case "SessionStart":
            session.state = .idle
            session.endedAt = nil
        case "UserPromptSubmit":
            session.state = .running
            session.lastPrompt = payload.prompt
        case "Stop":
            session.state = .idle
            session.completedTurns += 1
            if peekOnFinish { peek() }
        case "SessionEnd":
            session.state = .ended
            session.endedAt = Date()
        case "Notification":
            switch payload.notification_type {
            case "permission_prompt":
                session.state = .waiting
                peek()
            case "idle_prompt":
                session.state = .idle
            default:
                break
            }
        case "PermissionRequest":
            session.state = .waiting
            let toolName = payload.tool_name ?? "Tool"
            pendingPermissions.append(PermissionRequest(
                id: UUID(),
                accountID: accountID,
                sessionID: sessionID,
                toolName: toolName,
                summary: ToolSummary.summarize(toolName: toolName, input: payload.tool_input),
                cwd: session.cwd,
                createdAt: Date(),
                reply: reply
            ))
            replied = true
            NSSound(named: "Tink")?.play()
        default:
            break
        }

        upsert(session)
        if !replied { reply(HookReply()) }
    }

    private func upsert(_ session: ClaudeSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
    }

    func resolve(_ requestID: UUID, decision: PermissionDecision) {
        guard let index = pendingPermissions.firstIndex(where: { $0.id == requestID }) else { return }
        let request = pendingPermissions.remove(at: index)
        switch decision {
        case .allow:
            request.reply(HookReply(behavior: "allow"))
        case .deny:
            request.reply(HookReply(behavior: "deny", message: "Denied from DuoNotch"))
        case .askInTerminal:
            request.reply(HookReply())
        }
        if let sIndex = sessions.firstIndex(where: { $0.id == request.sessionID }) {
            sessions[sIndex].state = decision == .deny ? .idle : .running
            sessions[sIndex].lastEvent = Date()
        }
    }

    func counts(for accountID: String) -> SessionCounts {
        var counts = SessionCounts()
        for session in sessions where session.accountID == accountID {
            switch session.state {
            case .running: counts.running += 1
            case .waiting: counts.waiting += 1
            case .idle: counts.idle += 1
            case .ended: counts.done += 1
            }
        }
        return counts
    }

    func sessions(for accountID: String) -> [ClaudeSession] {
        sessions.filter { $0.accountID == accountID }
            .sorted { $0.lastEvent > $1.lastEvent }
    }

    // MARK: - Peek

    func peek(for seconds: TimeInterval = 5) {
        peekTask?.cancel()
        peeking = true
        peekTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.peeking = false
        }
    }

    // MARK: - Housekeeping

    private func housekeeping() {
        guard !demoMode else { return }
        let now = Date()

        // Permission requests the hook has already given up on.
        let stale = pendingPermissions.filter { now.timeIntervalSince($0.createdAt) > 290 }
        if !stale.isEmpty {
            stale.forEach { $0.reply(HookReply()) }
            pendingPermissions.removeAll { request in stale.contains { $0.id == request.id } }
        }

        // Sessions whose `claude` process is gone count as done.
        for index in sessions.indices where sessions[index].state != .ended {
            if !Self.processExists(sessions[index].claudePid) {
                sessions[index].state = .ended
                sessions[index].endedAt = now
            }
        }

        // Forget finished sessions after an hour, silent ones after eight.
        sessions.removeAll { session in
            if let endedAt = session.endedAt { return now.timeIntervalSince(endedAt) > 3_600 }
            return now.timeIntervalSince(session.lastEvent) > 8 * 3_600
        }
    }

    private static func processExists(_ pid: Int32) -> Bool {
        guard pid > 0 else { return true }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    // MARK: - Menu bar

    var menuBarText: String {
        let parts = enabledAccounts.compactMap { account -> String? in
            guard let window = readings[account.id]?.headline else { return nil }
            return "\(window.percent)%"
        }
        return parts.isEmpty ? "–" : parts.joined(separator: " · ")
    }

    func summaryLine(for account: Account) -> String {
        if let error = errors[account.id], readings[account.id] == nil { return error }
        guard let reading = readings[account.id] else { return "no reading yet" }
        var parts: [String] = []
        if let s = reading.session { parts.append("session \(s.percent)% · resets in \(Formatting.remaining(until: s.resetsAt))") }
        if let w = reading.weekly { parts.append("week \(w.percent)%") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Demo support

    func setDemo(accounts: [Account], readings: [String: UsageReading], sessions: [ClaudeSession], pending: [PermissionRequest]) {
        self.accounts = accounts
        self.readings = readings
        self.sessions = sessions
        self.pendingPermissions = pending
        self.errors = [:]
        self.hooksInstalled = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, true) })
        self.lastRefresh = Date()
    }

    func resolveAllDemo() {
        pendingPermissions = []
    }
}
