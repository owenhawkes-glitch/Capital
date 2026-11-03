import Foundation

/// One rate-limit window: how much of it is used and when it resets.
struct UsageWindow: Equatable {
    /// 0…1
    var fraction: Double
    var resetsAt: Date?

    var percent: Int { Int((fraction * 100).rounded()) }
}

struct UsageReading: Equatable {
    var fetchedAt: Date
    /// The rolling 5-hour "current session" window Claude Code's /usage leads with.
    var session: UsageWindow?
    /// The 7-day window across all models.
    var weekly: UsageWindow?
    /// The 7-day Opus-only window, where the plan has one.
    var weeklyOpus: UsageWindow?
    var weeklySonnet: UsageWindow?
    var subscriptionType: String?

    /// What the small collapsed ring shows.
    var headline: UsageWindow? { session ?? weekly }
}

enum Formatting {
    static func remaining(until date: Date?, from now: Date = Date()) -> String {
        guard let date else { return "–" }
        let seconds = Int(date.timeIntervalSince(now))
        if seconds <= 0 { return "now" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(String(format: "%02d", minutes))m" }
        return "\(minutes)m"
    }

    static func planName(_ subscriptionType: String?) -> String {
        guard let s = subscriptionType, !s.isEmpty else { return "" }
        return s.prefix(1).uppercased() + s.dropFirst()
    }
}
