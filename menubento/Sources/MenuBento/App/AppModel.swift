import AppKit
import OSLog
import SwiftUI
import MenuBentoCore

/// Everything MenuBento knows and does.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    private(set) var controls: ControlItems!

    @Published private(set) var state: BarState = .hidden
    /// Every item in the menu bar, ours included, left to right.
    @Published private(set) var items: [MenuBarItem] = []
    /// Set while items are being moved ("Moving Zoom…").
    @Published private(set) var busy: String?
    @Published var lastMessage: String?

    // Settings
    @Published var revealMode: RevealMode { didSet { save(revealMode.rawValue, "model.revealMode") } }
    @Published var showOnHover: Bool { didSet { save(showOnHover, "model.showOnHover") } }
    @Published var autoRehide: Bool { didSet { save(autoRehide, "model.autoRehide") } }
    @Published var rehideDelay: Double { didSet { save(rehideDelay, "model.rehideDelay") } }
    @Published var barShowsImages: Bool { didSet { save(barShowsImages, "model.barImages") } }
    @Published var extras: [ExtraItem] { didSet { saveJSON(extras, "model.extras"); controls?.syncExtras(extras) } }
    @Published var groups: [ItemGroup] { didSet { saveJSON(groups, "model.groups") } }
    @Published var presets: [LayoutPreset] { didSet { saveJSON(presets, "model.presets") } }

    /// Remembered names, so hidden items that have quit still read well.
    private var names: [String: String] = [:]

    private init() {
        let d = UserDefaults.standard
        revealMode = RevealMode(rawValue: d.string(forKey: "model.revealMode") ?? "") ?? .inPlace
        showOnHover = d.bool(forKey: "model.showOnHover")
        autoRehide = d.object(forKey: "model.autoRehide") as? Bool ?? true
        rehideDelay = d.object(forKey: "model.rehideDelay") as? Double ?? 3
        barShowsImages = d.object(forKey: "model.barImages") as? Bool ?? true
        extras = Self.loadJSON("model.extras") ?? []
        groups = Self.loadJSON("model.groups") ?? []
        presets = Self.loadJSON("model.presets") ?? []
    }

    func start() {
        controls = ControlItems()
        controls.onMainClick = { [weak self] event in self?.mainClicked(event) }
        controls.onSeparatorClick = { [weak self] in self?.toggle() }
        controls.syncExtras(extras)
        // Start hidden only once the menu bar has placed our items.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.setState(.hidden)
            Task {
                await self?.placeBoostersIfNeeded()
                await self?.refresh()
            }
        }
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            Task { @MainActor in
                let model = AppModel.shared
                if model.busy == nil && SettingsWindow.shared.isVisible { await model.refresh() }
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                await AppModel.shared.refresh()
            }
        }
    }

    // MARK: - Showing and hiding

    func setState(_ new: BarState) {
        state = new
        controls.apply(new)
        HoverWatcher.shared.stateChanged()
        if new != .hidden {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                Task { await AppModel.shared.captureImagesIfAllowed() }
            }
        }
        BarOverlay.shared.setNeedsUpdate()
        // Again once the menu bar has laid the items out at their new places.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { BarOverlay.shared.setNeedsUpdate() }
    }

    func toggle() {
        setState(state == .hidden ? .shown : .hidden)
    }

    private func mainClicked(_ event: NSEvent?) {
        // The live keyboard state is more reliable than the click's flags.
        let flags = (event?.modifierFlags ?? []).union(NSEvent.modifierFlags)
        let isRight = event?.type == .rightMouseUp || flags.contains(.control)
        if isRight {
            controls.popUpMenu(MainMenu.build(model: self))
            return
        }
        let option = flags.contains(.option)
        if option {
            BentoBar.shared.close()
            setState(state == .showAll ? .hidden : .showAll)
        } else if revealMode == .bar {
            BentoBar.shared.toggle()
        } else {
            toggle()
        }
    }

    // MARK: - Reading the menu bar

    @discardableResult
    func refresh() async -> [MenuBarItem] {
        guard let controls else { return [] }
        let pid = getpid()
        let scanned = await Task.detached { MenuBarScanner.scan(skipping: pid) }.value
        let ours = controls.ourItems(extrasConfig: extras)
        let all = (scanned + ours).sorted { $0.frame.minX < $1.frame.minX }
        for item in all { names[item.ref.id] = item.name }
        items = all
        BarOverlay.shared.setNeedsUpdate()
        return all
    }

    private func frame(_ ref: ItemRef, in list: [MenuBarItem]? = nil) -> CGRect? {
        (list ?? items).first { $0.ref == ref }?.frame
    }

    func section(of item: MenuBarItem, in list: [MenuBarItem]? = nil) -> MenuSection {
        guard let h = frame(OurItems.hidden, in: list), let ah = frame(OurItems.alwaysHidden, in: list) else { return .visible }
        if item.ref == OurItems.hidden || item.ref == OurItems.main { return .visible }
        if item.ref == OurItems.alwaysHidden { return .hidden }
        if item.midX >= h.maxX - 1 { return .visible }
        if item.midX >= ah.maxX - 1 { return .hidden }
        return .alwaysHidden
    }

    /// Items in a section, left to right, without the separators.
    func items(in section: MenuSection) -> [MenuBarItem] {
        items.filter { $0.ref != OurItems.hidden && $0.ref != OurItems.alwaysHidden && self.section(of: $0) == section }
    }

    /// What the MenuBento bar lists: other apps' items only.
    func barItems(in section: MenuSection) -> [MenuBarItem] {
        items(in: section).filter { !$0.isOurs }
    }

    var order: [ItemRef] { items.map(\.ref) }

    func name(for ref: ItemRef) -> String { names[ref.id] ?? ref.key }

    // MARK: - Moving

    /// Moves `refs` into a section (at its right-hand end for Hidden and
    /// Always hidden, at its left-hand end for Visible).
    func move(_ refs: [ItemRef], to section: MenuSection) async {
        var target = order.filter { !refs.contains($0) }
        let insertAt: Int
        switch section {
        case .alwaysHidden: insertAt = target.firstIndex(of: OurItems.alwaysHidden) ?? 0
        case .hidden: insertAt = target.firstIndex(of: OurItems.hidden) ?? 0
        case .visible: insertAt = (target.firstIndex(of: OurItems.hidden) ?? -1) + 1
        }
        target.insert(contentsOf: refs, at: insertAt)
        await arrange(to: target, label: refs.count == 1 ? "Moving \(name(for: refs[0]))…" : "Moving \(refs.count) items…")
    }

    /// Rearranges the menu bar to match `target` (left to right) with as
    /// few Cmd-drags as possible. Items not in `target` stay where they
    /// are; items in `target` that aren't running are skipped.
    @discardableResult
    func arrange(to target: [ItemRef], label: String) async -> Bool {
        guard busy == nil else { return false }
        guard AXIsProcessTrusted() else {
            lastMessage = "Moving items needs Accessibility permission (Settings → Permissions)."
            return false
        }
        busy = label
        BentoBar.shared.close()
        let previous = state
        setState(.showAll)
        try? await Task.sleep(for: .milliseconds(500))
        var current = await refresh()

        let present = Set(current.map(\.ref))
        let wanted = target.filter { present.contains($0) }
        let pinned = Set(current.filter(\.isFixed).map(\.ref))
        var settled = ArrangePlanner.stable(current: current.map(\.ref), target: wanted, pinned: pinned)
        var moves = 0, failures: [String] = []

        // Right to left, so each item's right-hand neighbour is settled.
        for ref in wanted.reversed() where !settled.contains(ref) {
            guard let source = current.first(where: { $0.ref == ref }), !source.isFixed,
                  let anchor = ArrangePlanner.anchor(for: ref, target: wanted, settled: settled) else { continue }
            busy = "Moving \(source.name)…"
            var placed = false
            for attempt in 0..<3 {
                let nudge: CGFloat = [0, -4, 4][attempt]
                func frameOf(_ r: ItemRef) -> CGRect? { current.first { $0.ref == r }?.frame }
                let placement: Placement?
                switch anchor {
                case .leftOf(let other): placement = frameOf(other).map { .leftOf($0) }
                case .rightOf(let other): placement = frameOf(other).map { .rightOf($0) }
                }
                guard let from = frameOf(ref), let placement else { break }
                await Task.detached { ItemMover.drag(from: from, to: placement, nudge: nudge) }.value
                moves += 1
                try? await Task.sleep(for: .milliseconds(250))
                current = await refresh()
                if ArrangePlanner.isPlaced(ref, current: current.map(\.ref), target: wanted, settled: settled) {
                    placed = true
                    break
                }
            }
            if placed { settled.insert(ref) } else { failures.append(source.name) }
        }

        setState(previous)
        try? await Task.sleep(for: .milliseconds(400))
        await refresh()
        busy = nil
        await placeBoostersIfNeeded()
        lastMessage = failures.isEmpty
            ? (moves == 0 ? "Already in place." : "Done.")
            : "Couldn't move: \(failures.joined(separator: ", ")). macOS may not allow these to move."
        return failures.isEmpty
    }

    // MARK: - Boosters

    private var placingBoosters = false

    /// Puts each separator's booster immediately to its left (one ⌘-drag
    /// each). Needed on first launch, and again whenever the separators have
    /// been moved, or items dropped between a booster and its separator.
    /// Without Accessibility the separators work alone, which hides less.
    func placeBoostersIfNeeded() async {
        guard !placingBoosters, busy == nil, AXIsProcessTrusted(), !controls.boostersPlaced else { return }
        placingBoosters = true
        controls.apply(.showAll)
        controls.setBoostersGrabbable(true)
        try? await Task.sleep(for: .milliseconds(400))
        for _ in 0..<3 {
            guard let (booster, separator) = controls.misplacedBoosters.first,
                  let from = controls.frame(of: booster), let to = controls.frame(of: separator),
                  let wanted = booster.button?.accessibilityLabel() else { break }
            // Only drag if the pointer would really pick up the booster;
            // a stale frame must never move a separator or someone's item.
            let moved = await Task.detached { () -> Bool in
                let start = CGPoint(x: from.midX, y: from.midY)
                guard ItemMover.label(at: start) == wanted else { return false }
                return ItemMover.drag(from: from, to: .leftOf(to))
            }.value
            if !moved { break }
            try? await Task.sleep(for: .milliseconds(400))
        }
        controls.setBoostersGrabbable(false)
        controls.apply(state)
        placingBoosters = false
    }

    /// Puts MenuBento's own items back in their standard order with every
    /// other item in Hidden:
    ///   [booster][«] … every other item … [booster][‹][MenuBento icon]
    /// Only MenuBento's own items are dragged; each drag first checks the
    /// item under the pointer really is the one being moved.
    func hideEverything() async {
        guard busy == nil else { return }
        guard AXIsProcessTrusted() else {
            lastMessage = "Resetting the layout needs Accessibility permission (Settings → Permissions)."
            return
        }
        busy = "Resetting the layout…"
        BentoBar.shared.close()
        controls.apply(.showAll)
        controls.setBoostersGrabbable(true)
        try? await Task.sleep(for: .milliseconds(700))

        // 0. The icon right of every movable item, just left of the items
        //    macOS keeps fixed (Control Centre, the clock).
        let before = await refresh()
        log("reset: icon \(controls.frame(of: controls.main).map { Int($0.minX) } ?? -1), fixed \(before.filter(\.isFixed).map { "\($0.name)@\(Int($0.frame.minX))" })")
        if let icon = controls.frame(of: controls.main),
           before.contains(where: { !$0.isOurs && !$0.isFixed && $0.frame.minX > icon.maxX && $0.frame.width < 400 }),
           let fixed = before.filter({ $0.isFixed && $0.frame.minX > icon.minX }).min(by: { $0.frame.minX < $1.frame.minX }) {
            await safeDrag(controls.main, to: .leftOf(fixed.frame))
        }
        // 1. The Hidden separator immediately left of the icon.
        if let icon = controls.frame(of: controls.main), let sep = controls.frame(of: controls.hiddenSeparator),
           !(sep.maxX <= icon.minX + 1 && icon.minX - sep.maxX < 16) {
            await safeDrag(controls.hiddenSeparator, to: .leftOf(icon))
        }
        // 2. The Always-hidden separator left of everything else.
        let others = await refresh().filter { !$0.isOurs && $0.frame.width < 400 }
        if let leftmost = others.min(by: { $0.frame.minX < $1.frame.minX }),
           let sep = controls.frame(of: controls.alwaysSeparator), sep.minX > leftmost.frame.minX {
            await safeDrag(controls.alwaysSeparator, to: .leftOf(leftmost.frame))
        }
        // 3. Each booster immediately left of its separator.
        for (booster, separator) in [(controls.hiddenBooster, controls.hiddenSeparator), (controls.alwaysBooster, controls.alwaysSeparator)] {
            if let b = controls.frame(of: booster), let s = controls.frame(of: separator) {
                let gap = s.minX - b.maxX
                if gap < -1 || gap > 16 { await safeDrag(booster, to: .leftOf(s)) }
            }
        }
        controls.setBoostersGrabbable(false)
        busy = nil
        setState(.hidden)
        try? await Task.sleep(for: .milliseconds(500))
        await refresh()
        lastMessage = controls.boostersPlaced ? "Everything is hidden. Click the icon to show." : "Couldn't put everything in place; try again."
    }

    /// ⌘-drags one of MenuBento's own items, but only if the pointer would
    /// really pick that item up.
    private func safeDrag(_ item: NSStatusItem, to placement: Placement) async {
        guard let from = controls.frame(of: item), let wanted = item.button?.accessibilityLabel() else { return }
        let result = await Task.detached { () -> String in
            let found = ItemMover.label(at: CGPoint(x: from.midX, y: from.midY))
            guard found == wanted else { return "skipped: found \(found ?? "nothing") instead" }
            return ItemMover.drag(from: from, to: placement) ? "moved" : "drag failed"
        }.value
        log("drag \(wanted) from \(Int(from.midX)) to \(Int(placement.point.x)): \(result)")
        try? await Task.sleep(for: .milliseconds(450))
    }

    /// Diagnostics for layout changes, readable with
    /// `log stream --predicate 'subsystem == "com.hawkes.menubento"'`.
    func log(_ message: String) {
        Logger(subsystem: "com.hawkes.menubento", category: "layout").notice("\(message, privacy: .public)")
    }

    // MARK: - Groups

    func setGroup(_ id: UUID, hidden: Bool) async {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        await refresh()
        var group = groups[index]
        let present = group.members.filter { ref in items.contains { $0.ref == ref } }
        if hidden {
            for ref in present {
                if let item = items.first(where: { $0.ref == ref }) { group.savedSections[ref.id] = section(of: item) }
            }
            group.isHidden = true
            groups[index] = group
            await move(present, to: .alwaysHidden)
        } else {
            group.isHidden = false
            groups[index] = group
            let toHidden = present.filter { group.savedSections[$0.id] == .hidden }
            let toVisible = present.filter { (group.savedSections[$0.id] ?? .visible) == .visible }
            if !toHidden.isEmpty { await move(toHidden, to: .hidden) }
            if !toVisible.isEmpty { await move(toVisible, to: .visible) }
        }
    }

    // MARK: - Spacers and dividers

    func addExtra(_ kind: ExtraItem.Kind) {
        let extra = ExtraItem(kind: kind)
        extras.append(extra)
        // New status items appear at the far left (in Always hidden). Bring
        // it to the start of the Visible section so it can be seen.
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            await refresh()
            if AXIsProcessTrusted() { await move([extra.ref], to: .visible) }
        }
    }

    // MARK: - Presets

    func savePreset(named name: String, includeLook: Bool) async {
        await refresh()
        presets.append(currentLayout(named: name, includeLook: includeLook))
    }

    func overwritePreset(_ id: UUID) async {
        await refresh()
        guard let i = presets.firstIndex(where: { $0.id == id }) else { return }
        let old = presets[i]
        var fresh = currentLayout(named: old.name, includeLook: old.appearance != nil)
        fresh.id = old.id
        presets[i] = fresh
    }

    private func currentLayout(named name: String, includeLook: Bool) -> LayoutPreset {
        LayoutPreset(name: name,
                     entries: items.filter { !$0.isFixed }.map { PresetEntry(ref: $0.ref, name: $0.name) },
                     extras: extras,
                     appearance: includeLook ? BarAppearance.shared.snapshot : nil)
    }

    func applyPreset(_ id: UUID) async {
        guard let preset = presets.first(where: { $0.id == id }) else { return }
        if let look = preset.appearance { BarAppearance.shared.snapshot = look }
        if extras != preset.extras {
            extras = preset.extras
            try? await Task.sleep(for: .milliseconds(500))
        }
        for entry in preset.entries { names[entry.ref.id] = names[entry.ref.id] ?? entry.name }
        await arrange(to: preset.entries.map(\.ref), label: "Applying “\(preset.name)”…")
    }

    // MARK: - Item pictures

    func captureImagesIfAllowed() async {
        guard barShowsImages, Permissions.shared.screenRecording, state != .hidden else { return }
        let list = await refresh()
        // Everything that's drawn right now; the cache skips off-screen items.
        await ItemImageCache.shared.capture(list.filter { !$0.isOurs })
    }

    // MARK: - Persistence

    private func save(_ value: Any, _ key: String) { UserDefaults.standard.set(value, forKey: key) }

    private func saveJSON<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }

    private static func loadJSON<T: Decodable>(_ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
