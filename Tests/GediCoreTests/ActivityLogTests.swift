import Foundation
import Testing
@testable import GediCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let shorts = ClassifiedActivity(kind: .shortVideo, name: "YouTube Shorts", detail: "cat")
private let code = ClassifiedActivity(kind: .coding, name: "Visual Studio Code")

/// Records `activity` every 5 s from `from` (seconds after t0) up to and including `to`.
private func poll(_ log: inout ActivityLog, _ activity: ClassifiedActivity, from: Int, to: Int) {
    for s in stride(from: from, through: to, by: 5) {
        log.record(activity, at: t0.addingTimeInterval(TimeInterval(s)))
    }
}

@Test func sameActivityMergesIntoOneEntry() {
    var log = ActivityLog()
    poll(&log, shorts, from: 0, to: 60)
    #expect(log.entries.count == 1)
    #expect(log.entries[0].end.timeIntervalSince(log.entries[0].start) == 60)
}

@Test func switchingClosesPreviousEntryAtSwitchTime() {
    var log = ActivityLog()
    poll(&log, code, from: 0, to: 180)      // 3 min coding
    poll(&log, shorts, from: 185, to: 485)  // switch at 185, Shorts until 485
    let s = log.summary(now: t0.addingTimeInterval(485))
    #expect(s.totals.map(\.name) == ["YouTube Shorts", "Visual Studio Code"])
    #expect(s.totals[0].seconds == 300)
    #expect(s.totals[1].seconds == 185)
    #expect(s.current == shorts)
    #expect(s.currentStreak == 300)
}

@Test func gapIsNotCountedAsActivity() {
    var log = ActivityLog(maxGap: 30)
    poll(&log, code, from: 0, to: 60)
    log.record(code, at: t0.addingTimeInterval(660))  // laptop slept 10 min
    #expect(log.entries.count == 2)
    let s = log.summary(now: t0.addingTimeInterval(660))
    #expect(s.totals[0].seconds == 60)
}

@Test func nothingCurrentAfterLongSilence() {
    var log = ActivityLog(maxGap: 30)
    poll(&log, code, from: 0, to: 60)
    let s = log.summary(now: t0.addingTimeInterval(200))
    #expect(s.current == nil)
    #expect(s.isInCall == false)
}

@Test func windowClipsOldActivity() {
    var log = ActivityLog()
    poll(&log, code, from: 0, to: 1200)  // 20 min
    let s = log.summary(now: t0.addingTimeInterval(1200), window: 900)
    #expect(s.totals[0].seconds == 900)
}

@Test func retentionDropsOldEntries() {
    var log = ActivityLog(maxGap: 30, retention: 100)
    poll(&log, code, from: 0, to: 10)
    poll(&log, shorts, from: 200, to: 210)
    #expect(log.entries.map(\.activity.name) == ["YouTube Shorts"])
}

@Test func promptTextFormat() {
    var log = ActivityLog()
    poll(&log, code, from: 0, to: 180)
    poll(&log, shorts, from: 185, to: 545)
    let text = log.summary(now: t0.addingTimeInterval(545)).promptText(timeZone: TimeZone(identifier: "Asia/Kolkata")!)
    #expect(text == """
    Now: YouTube Shorts — "cat" (for 6 min straight)
    Last 15 min: YouTube Shorts 6 min, Visual Studio Code 3 min
    Local time: Fri 13:39
    """)
}

@Test func promptTextWhenAway() {
    let s = ActivityLog().summary(now: t0)
    #expect(s.promptText(timeZone: TimeZone(identifier: "UTC")!).hasPrefix("Now: away from the computer"))
}
