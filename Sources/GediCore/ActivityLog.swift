import Foundation

/// Rolling record of what the user has been doing, built from periodic snapshots.
/// Each `record` call closes the previous entry at `time` and either extends it
/// (same activity) or starts a new one. Gaps longer than `maxGap` (sleep, lock screen)
/// are not counted as activity.
public struct ActivityLog: Sendable {
    public struct Entry: Equatable, Sendable {
        public var activity: ClassifiedActivity
        public var start: Date
        public var end: Date
    }

    public private(set) var entries: [Entry] = []
    public var maxGap: TimeInterval
    public var retention: TimeInterval

    public init(maxGap: TimeInterval = 30, retention: TimeInterval = 3600) {
        self.maxGap = maxGap
        self.retention = retention
    }

    public mutating func record(_ activity: ClassifiedActivity, at time: Date) {
        if var last = entries.last, time.timeIntervalSince(last.end) <= maxGap {
            last.end = time
            if last.activity.name == activity.name && last.activity.kind == activity.kind {
                last.activity.detail = activity.detail
                entries[entries.count - 1] = last
            } else {
                entries[entries.count - 1] = last
                entries.append(Entry(activity: activity, start: time, end: time))
            }
        } else {
            entries.append(Entry(activity: activity, start: time, end: time))
        }
        let cutoff = time.addingTimeInterval(-retention)
        entries.removeAll { $0.end < cutoff }
    }

    /// The activity the user is on now, if the last snapshot is recent.
    public func current(now: Date) -> ClassifiedActivity? {
        guard let last = entries.last, now.timeIntervalSince(last.end) <= maxGap else { return nil }
        return last.activity
    }

    public func summary(now: Date, window: TimeInterval = 900) -> ActivitySummary {
        let windowStart = now.addingTimeInterval(-window)
        var order: [String] = []
        var totals: [String: (ActivityKind, TimeInterval)] = [:]
        for e in entries {
            let s = max(e.start, windowStart)
            let t = min(e.end, now)
            guard t > s else { continue }
            if totals[e.activity.name] == nil { order.append(e.activity.name) }
            let prev = totals[e.activity.name]?.1 ?? 0
            totals[e.activity.name] = (e.activity.kind, prev + t.timeIntervalSince(s))
        }
        let list = order
            .map { ActivitySummary.Total(name: $0, kind: totals[$0]!.0, seconds: totals[$0]!.1) }
            .sorted { $0.seconds > $1.seconds }
        var streak: TimeInterval = 0
        let cur = current(now: now)
        if cur != nil, let last = entries.last { streak = now.timeIntervalSince(last.start) }
        return ActivitySummary(now: now, current: cur, currentStreak: streak, totals: list)
    }
}

public struct ActivitySummary: Equatable, Sendable {
    public struct Total: Equatable, Sendable {
        public var name: String
        public var kind: ActivityKind
        public var seconds: TimeInterval
    }

    public var now: Date
    public var current: ClassifiedActivity?
    public var currentStreak: TimeInterval
    public var totals: [Total]

    public var isInCall: Bool { current?.kind == .call }

    /// The block of text the LLM sees, e.g.
    /// ```
    /// Now: YouTube Shorts — "funny cat" (for 6 min straight)
    /// Last 15 min: YouTube Shorts 12 min, Visual Studio Code 3 min
    /// Local time: Tue 23:40
    /// ```
    public func promptText(timeZone: TimeZone = .current) -> String {
        var lines: [String] = []
        if let c = current {
            var now = "Now: \(c.name)"
            if let d = c.detail, !d.isEmpty, d != c.name { now += " — \"\(String(d.prefix(80)))\"" }
            now += " (for \(Self.minutes(currentStreak)) straight)"
            lines.append(now)
        } else {
            lines.append("Now: away from the computer")
        }
        if !totals.isEmpty {
            let parts = totals.prefix(5).map { "\($0.name) \(Self.minutes($0.seconds))" }
            lines.append("Last 15 min: " + parts.joined(separator: ", "))
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "EEE HH:mm"
        lines.append("Local time: \(f.string(from: now))")
        return lines.joined(separator: "\n")
    }

    static func minutes(_ seconds: TimeInterval) -> String {
        seconds < 60 ? "<1 min" : "\(Int((seconds / 60).rounded())) min"
    }
}
