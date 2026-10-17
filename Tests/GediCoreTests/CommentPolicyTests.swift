import Foundation
import Testing
@testable import GediCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let policy = CommentPolicy(interval: 30)

@Test func dueAfterInterval() {
    let s = CommentPolicy.State()
    #expect(!policy.isDue(now: t0.addingTimeInterval(29), lastSpokeAt: t0, state: s))
    #expect(policy.isDue(now: t0.addingTimeInterval(30), lastSpokeAt: t0, state: s))
}

@Test func blockedByAnyQuietReason() {
    let later = t0.addingTimeInterval(600)
    var muted = CommentPolicy.State(); muted.muted = true
    var busy = CommentPolicy.State(); busy.busy = true
    var talking = CommentPolicy.State(); talking.conversing = true
    var call = CommentPolicy.State(); call.inCall = true
    for s in [muted, busy, talking, call] {
        #expect(!policy.isDue(now: later, lastSpokeAt: t0, state: s))
    }
}
