import Foundation
import IOKit.pwr_mgt
import Combine

/// Keeps the Mac awake (like `caffeinate`) so long Claude runs aren't cut
/// off by sleep. Uses a power assertion that macOS releases automatically
/// if DuoNotch quits.
@MainActor
final class Caffeine: ObservableObject {
    static let shared = Caffeine()

    enum Mode: Equatable {
        case off
        case on(until: Date?)        // nil = until switched off
        case whileChatsRun
    }

    @Published private(set) var mode: Mode = .off
    /// Whether the Mac is being held awake right now.
    @Published private(set) var holding = false
    @Published var keepDisplayOn: Bool = UserDefaults.standard.bool(forKey: "caffeine.display") {
        didSet {
            UserDefaults.standard.set(keepDisplayOn, forKey: "caffeine.display")
            release(); update()
        }
    }

    private var assertionID: IOPMAssertionID = 0
    private var timer: Timer?

    private init() {
        if ProcessInfo.processInfo.environment["DUONOTCH_CAFFEINE"] == "1" {
            DispatchQueue.main.async { Caffeine.shared.set(.on(until: nil)) }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
            MainActor.assumeIsolated { Caffeine.shared.update() }
        }
    }

    var isOn: Bool { mode != .off }

    func toggle() { mode == .off ? set(.on(until: nil)) : set(.off) }

    func set(_ new: Mode) {
        mode = new
        update()
    }

    func keepAwake(hours: Double) { set(.on(until: Date().addingTimeInterval(hours * 3600))) }

    var description: String {
        switch mode {
        case .off: return "Off: your Mac can sleep normally"
        case .on(nil): return "Keeping your Mac awake until you switch it off"
        case .on(let until?):
            return "Keeping your Mac awake until \(until.formatted(date: .omitted, time: .shortened))"
        case .whileChatsRun:
            return holding ? "Keeping your Mac awake while Claude chats run" : "Will keep your Mac awake when a Claude chat runs"
        }
    }

    /// Re-evaluates whether to hold the assertion.
    func update() {
        let shouldHold: Bool
        switch mode {
        case .off:
            shouldHold = false
        case .on(nil):
            shouldHold = true
        case .on(let until?):
            if until <= Date() { mode = .off; shouldHold = false } else { shouldHold = true }
        case .whileChatsRun:
            shouldHold = AppState.shared.sessions.contains { $0.state == .running || $0.state == .waiting }
        }
        if shouldHold && !holding { acquire() }
        if !shouldHold && holding { release() }
    }

    private func acquire() {
        let type = (keepDisplayOn ? kIOPMAssertionTypePreventUserIdleDisplaySleep : kIOPMAssertionTypePreventUserIdleSystemSleep) as CFString
        let reason = "DuoNotch: keeping the Mac awake for Claude Code" as CFString
        if IOPMAssertionCreateWithName(type, IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &assertionID) == kIOReturnSuccess {
            holding = true
        }
    }

    private func release() {
        if holding {
            IOPMAssertionRelease(assertionID)
            holding = false
        }
    }
}
