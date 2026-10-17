import Testing
@testable import GediCore

/// Deterministic RNG so walking tests are repeatable.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Test func walksRightAtSpeed() {
    var w = Walker(x: 100)
    w.restChancePerSecond = 0
    var rng = SplitMix64(state: 1)
    w.step(dt: 0.5, minX: 0, maxX: 1000, random: &rng)
    #expect(w.x == 120)
    #expect(w.facingRight)
}

@Test func turnsAroundAtEdges() {
    var w = Walker(x: 990)
    w.restChancePerSecond = 0
    var rng = SplitMix64(state: 1)
    w.step(dt: 1, minX: 0, maxX: 1000, random: &rng)
    #expect(w.x == 1000)
    #expect(!w.facingRight)
    w.step(dt: 1, minX: 0, maxX: 1000, random: &rng)
    #expect(w.x == 960)
}

@Test func staysInsideBoundsOverLongRun() {
    var w = Walker(x: 50)
    var rng = SplitMix64(state: 42)
    for _ in 0..<10_000 {
        w.step(dt: 1.0 / 30, minX: 0, maxX: 300, random: &rng)
        #expect(w.x >= 0 && w.x <= 300)
    }
}

@Test func talkingStopsMovementThenRests() {
    var w = Walker(x: 100)
    var rng = SplitMix64(state: 7)
    w.setTalking(true)
    w.step(dt: 2, minX: 0, maxX: 1000, random: &rng)
    #expect(w.x == 100)
    #expect(w.mode == .talking)
    w.setTalking(false)
    guard case .resting = w.mode else { Issue.record("expected resting, got \(w.mode)"); return }
    w.step(dt: 1, minX: 0, maxX: 1000, random: &rng)
    #expect(w.x == 100)
    w.step(dt: 1, minX: 0, maxX: 1000, random: &rng)
    #expect(w.mode == .walking)
}

@Test func frameAlternatesWhileWalking() {
    var w = Walker(x: 100)
    w.restChancePerSecond = 0
    var rng = SplitMix64(state: 1)
    var seen = Set<String>()
    for _ in 0..<12 {
        w.step(dt: 1.0 / 12, minX: 0, maxX: 1000, random: &rng)
        seen.insert("\(w.frame)")
    }
    #expect(seen == ["walk1", "walk2"])
}

@Test func spriteFramesAreWellFormed() {
    for frame in SpriteFrame.allCases {
        let rows = SpriteArt.rows(frame)
        #expect(rows.count == SpriteArt.height, "\(frame) height")
        for row in rows {
            #expect(row.count == SpriteArt.width, "\(frame) row '\(row)'")
            for ch in row where ch != "." {
                #expect(SpriteArt.palette[ch] != nil, "\(frame) unknown pixel \(ch)")
            }
        }
    }
}

@Test func pinnedStaysPutButStillTalks() {
    var w = Walker(x: 100)
    w.restChancePerSecond = 0
    w.pinned = true
    var rng = SplitMix64(state: 1)
    w.setTalking(true)
    var seen = Set<String>()
    for _ in 0..<10 {
        w.step(dt: 0.1, minX: 0, maxX: 1000, random: &rng)
        seen.insert("\(w.frame)")
    }
    #expect(w.x == 100)
    #expect(seen == ["talk", "idle"])
    w.setTalking(false)
    w.step(dt: 5, minX: 0, maxX: 1000, random: &rng)
    #expect(w.x == 100)
    w.pinned = false
    w.step(dt: 0.5, minX: 0, maxX: 1000, random: &rng)
    w.step(dt: 0.5, minX: 0, maxX: 1000, random: &rng)  // first step only ends the rest
    #expect(w.x != 100)
}
