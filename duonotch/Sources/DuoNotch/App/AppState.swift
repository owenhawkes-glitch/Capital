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

    // MARK: Projects

    @Published var projects: [Project] {
        didSet { persistProjects() }
    }
    @Published var terminalApp: ProjectLauncher.TerminalApp {
        didSet { defaults.set(terminalApp.rawValue, forKey: Keys.terminalApp) }
    }
    @Published var launchMessage: String?

    // MARK: Notch presentation

    @Published var hovering = false
    @Published var pinnedOpen = false
    @Published private(set) var peeking = false
    /// True while the floating panel is being dragged, so it doesn't collapse.
    @Published var dragging = false
    @Published var selectedTab: NotchTab = .claude
    /// What the closed notch shows, in order, and on which side.
    @Published var notchItems: [NotchItem] = [] {
        didSet { persistNotchItems() }
    }
    /// Height the expanded content asked for last time it was laid out.
    @Published var measuredContentHeight: CGFloat = NotchMetrics.estimatedContentHeight

    /// Opens only on hover by default. Peeks and approvals open it only when
    /// the matching setting is on.
    var isExpanded: Bool {
        if pinnedOpen || dragging || fileDragOver { return true }
        if placement == .floating && floatingOpensOnClick { return floatingOpen }
        return hovering || peeking || (openForApprovals && !pendingPermissions.isEmpty)
    }

    /// Floating window opened by a click; stays open until closed.
    @Published var floatingOpen = false
    /// Files are being dragged over the notch.
    @Published var fileDragOver = false

    // MARK: Panel layout (persisted)

    @Published var panelModules: [PanelModuleConfig] {
        didSet { saveCodable(panelModules, Keys.panelModules) }
    }
    @Published var panelLayout: PanelLayoutStyle {
        didSet { defaults.set(panelLayout.rawValue, forKey: Keys.panelLayout) }
    }
    @Published var panelWidth: Double {
        didSet { defaults.set(panelWidth, forKey: Keys.panelWidth) }
    }
    @Published var floatingOpensOnClick: Bool {
        didSet { defaults.set(floatingOpensOnClick, forKey: Keys.floatingClick) }
    }

    func isEnabled(_ module: PanelModule) -> Bool {
        panelModules.contains { $0.module == module && $0.enabled }
    }

    /// Tabs shown in tab mode, in the order their first section appears.
    var visibleTabs: [NotchTab] {
        var tabs: [NotchTab] = []
        for config in panelModules where config.enabled && !tabs.contains(config.module.tab) {
            tabs.append(config.module.tab)
        }
        return tabs
    }

    func show(tab: NotchTab) {
        selectedTab = tab
        if placement == .floating && floatingOpensOnClick { floatingOpen = true }
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
    @Published var openForApprovals: Bool {
        didSet { defaults.set(openForApprovals, forKey: Keys.openForApprovals) }
    }
    @Published var placement: NotchPlacement {
        didSet { defaults.set(placement.rawValue, forKey: Keys.placement) }
    }
    /// Top-left corner of the floating panel, in screen coordinates.
    @Published var floatingOrigin: CGPoint? {
        didSet {
            if let p = floatingOrigin {
                defaults.set([p.x, p.y], forKey: Keys.floatingOrigin)
            } else {
                defaults.removeObject(forKey: Keys.floatingOrigin)
            }
        }
    }
    @Published var showMenuBarText: Bool {
        didSet { defaults.set(showMenuBarText, forKey: Keys.menuBarText) }
    }

    // MARK: - Private state

    private enum Keys {
        static let accounts = "accounts.v1"
        static let demoMode = "demoMode"
        static let pollInterval = "pollIntervalSeconds"
        static let peekOnFinish = "peekOnFinish.v2"
        static let openForApprovals = "openForApprovals"
        static let placement = "placement"
        static let floatingOrigin = "floatingOrigin"
        static let notchItems = "notchItems.v1"
        static let panelModules = "panelModules.v1"
        static let panelLayout = "panelLayout"
        static let panelWidth = "panelWidth"
        static let floatingClick = "floatingOpensOnClick"
        static let menuBarText = "showMenuBarText"
        static let projects = "projects.v1"
        static let terminalApp = "terminalApp"
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
        peekOnFinish = stored.bool(forKey: Keys.peekOnFinish)
        openForApprovals = stored.bool(forKey: Keys.openForApprovals)
        placement = NotchPlacement(rawValue: stored.string(forKey: Keys.placement) ?? "") ?? .top
        if let xy = stored.array(forKey: Keys.floatingOrigin) as? [Double], xy.count == 2 {
            floatingOrigin = CGPoint(x: xy[0], y: xy[1])
        } else {
            floatingOrigin = nil
        }
        // Debug aids for screenshots: start open, and on a given tab.
        pinnedOpen = ProcessInfo.processInfo.environment["DUONOTCH_OPEN"] == "1"
        selectedTab = NotchTab(rawValue: ProcessInfo.processInfo.environment["DUONOTCH_TAB"] ?? "") ?? .claude
        showMenuBarText = stored.bool(forKey: Keys.menuBarText)
        demoMode = stored.bool(forKey: Keys.demoMode)
            || ProcessInfo.processInfo.environment["DUONOTCH_DEMO"] == "1"
        accounts = Self.loadPersistedAccounts()
        projects = Self.loadPersistedProjects()
        notchItems = Self.loadPersistedNotchItems()
        var modules = Self.loadCodable([PanelModuleConfig].self, Keys.panelModules) ?? PanelModuleConfig.defaults
        for d in PanelModuleConfig.defaults where !modules.contains(where: { $0.module == d.module }) { modules.append(d) }
        panelModules = modules
        panelLayout = PanelLayoutStyle(rawValue: stored.string(forKey: Keys.panelLayout) ?? "") ?? .tabs
        let width = stored.double(forKey: Keys.panelWidth)
        panelWidth = width >= 500 ? width : 600
        floatingOpensOnClick = stored.object(forKey: Keys.floatingClick) as? Bool ?? true
        terminalApp = ProjectLauncher.TerminalApp(rawValue: stored.string(forKey: Keys.terminalApp) ?? "") ?? .terminal
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
        projects = Self.loadPersistedProjects()
        notchItems = Self.loadPersistedNotchItems()
        mergeDiscoveredAccounts()
        reconcileNotchItems()
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
        reconcileNotchItems()
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
        if let label = envelope.label?.trimmingCharacters(in: .whitespaces), !label.isEmpty {
            session.label = label
        }

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
                if openForApprovals { peek() }
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

    // MARK: - Projects

    func addProject(_ project: Project) {
        guard !projects.contains(where: { $0.path == project.path }) else { return }
        projects.append(project)
    }

    func removeProject(_ project: Project) {
        projects.removeAll { $0.id == project.id }
    }

    func account(for project: Project) -> Account? {
        if let id = project.accountID, let match = accounts.first(where: { $0.id == id }) { return match }
        return accounts.first { $0.isDefault } ?? accounts.first
    }

    func launch(_ project: Project) {
        do {
            try ProjectLauncher.launch(project, account: account(for: project), terminal: terminalApp)
            launchMessage = "Opened \(project.name) in \(terminalApp.name)"
        } catch {
            launchMessage = error.localizedDescription
        }
    }

    /// The project whose folder contains this working directory, preferring
    /// the most specific match.
    func project(matching cwd: String) -> Project? {
        projects.filter { $0.contains(cwd: cwd) }
            .max { $0.path.count < $1.path.count }
    }

    /// Label → matching project → first prompt → folder name.
    func displayName(for session: ClaudeSession) -> String {
        if let label = session.label, !label.isEmpty { return label }
        if let project = project(matching: session.cwd) { return project.name }
        if let prompt = session.lastPrompt?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " "), !prompt.isEmpty {
            return prompt.count > 34 ? String(prompt.prefix(33)) + "…" : prompt
        }
        return session.projectName
    }

    func raiseTerminal(for session: ClaudeSession) {
        TerminalRaiser.raise(claudePid: session.claudePid, terminal: terminalApp)
    }

    private static func loadPersistedProjects() -> [Project] {
        guard let data = UserDefaults.standard.data(forKey: Keys.projects),
              let decoded = try? JSONDecoder().decode([Project].self, from: data) else { return [] }
        return decoded
    }

    private func persistProjects() {
        guard !demoMode else { return }
        if let data = try? JSONEncoder().encode(projects) {
            defaults.set(data, forKey: Keys.projects)
        }
    }

    // MARK: - Notch items

    /// Items that are switched on and still point at something that exists.
    var strip: NotchStrip {
        let apps = AppShortcutStore.shared.shortcuts
        let visible = notchItems.filter { item in
            guard item.enabled else { return false }
            switch item.kind {
            case .account(let id): return accounts.contains { $0.id == id && $0.enabled }
            case .app(let id): return apps.contains { $0.id == id }
            case .clipboard, .chats, .media, .files: return true
            }
        }
        return NotchStrip(left: visible.filter { $0.side == .left },
                          right: visible.filter { $0.side == .right })
    }

    /// Adds an item for every account and pinned app that doesn't have one.
    /// The first two accounts are shown by default, one on each side; apps,
    /// clipboard and chats start hidden until switched on in Settings.
    func reconcileNotchItems() {
        var items = notchItems
        func has(_ kind: NotchItemKind) -> Bool { items.contains { $0.kind == kind } }
        for (index, account) in accounts.enumerated() where !has(.account(account.id)) {
            let shownAccounts = items.filter { if case .account = $0.kind { return $0.enabled }; return false }
            let side: NotchSide = shownAccounts.contains { $0.side == .left } ? .right : .left
            items.append(NotchItem(kind: .account(account.id), side: side,
                                   enabled: shownAccounts.count < 2, colorHex: AccountPalette.preset(at: index).hex))
        }
        for (index, app) in AppShortcutStore.shared.shortcuts.enumerated() where !has(.app(app.id)) {
            items.append(NotchItem(kind: .app(app.id), side: .right, enabled: false,
                                   colorHex: AccountPalette.preset(at: index + 2).hex))
        }
        if !has(.clipboard) {
            items.append(NotchItem(kind: .clipboard, side: .left, enabled: false, colorHex: AccountPalette.presets[3].hex))
        }
        if !has(.media) {
            items.append(NotchItem(kind: .media, side: .right, enabled: true, colorHex: AccountPalette.presets[2].hex))
        }
        if !has(.files) {
            items.append(NotchItem(kind: .files, side: .left, enabled: false, colorHex: AccountPalette.presets[5].hex))
        }
        if !has(.chats) {
            items.append(NotchItem(kind: .chats, side: .left, enabled: false, colorHex: AccountPalette.presets[2].hex))
        }
        if items != notchItems { notchItems = items }
    }

    private static func loadPersistedNotchItems() -> [NotchItem] {
        guard let data = UserDefaults.standard.data(forKey: Keys.notchItems),
              let decoded = try? JSONDecoder().decode([NotchItem].self, from: data) else { return [] }
        return decoded
    }

    private func persistNotchItems() {
        guard !demoMode else { return }
        if let data = try? JSONEncoder().encode(notchItems) {
            defaults.set(data, forKey: Keys.notchItems)
        }
    }

    private func saveCodable<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    private static func loadCodable<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    // MARK: - Notch layout

    /// Supplied by the notch controller: the panel's current top-left corner.
    var panelTopLeft: (() -> CGPoint)?
    private var dragStartMouse: CGPoint = .zero
    private var dragStartOrigin: CGPoint = .zero

    func floatingDragChanged() {
        let mouse = NSEvent.mouseLocation
        if !dragging {
            dragging = true
            dragStartMouse = mouse
            dragStartOrigin = panelTopLeft?() ?? floatingOrigin ?? mouse
        }
        floatingOrigin = CGPoint(x: dragStartOrigin.x + mouse.x - dragStartMouse.x,
                                 y: dragStartOrigin.y + mouse.y - dragStartMouse.y)
    }

    func floatingDragEnded() {
        // Keep the clamped position the panel actually ended up at.
        if let topLeft = panelTopLeft?() { floatingOrigin = topLeft }
        dragging = false
    }

    func setMeasuredContentHeight(_ height: CGFloat) {
        let rounded = height.rounded(.up)
        if abs(rounded - measuredContentHeight) > 0.5 { measuredContentHeight = rounded }
    }

    // MARK: - Settings window

    /// Opens the Settings scene even when the menu bar icon is hidden
    /// behind the hardware notch.
    static func openSettings() {
        SettingsWindow.shared.show(state: AppState.shared)
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

    func setDemo(accounts: [Account], readings: [String: UsageReading], sessions: [ClaudeSession], pending: [PermissionRequest], projects: [Project] = []) {
        self.notchItems = []
        self.accounts = accounts
        self.projects = projects
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
