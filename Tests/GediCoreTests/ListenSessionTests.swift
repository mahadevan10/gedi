import Foundation
import Testing
@testable import GediCore

// Transcripts are romanized, the way Apple's ml-IN recogniser writes Malayalam.
private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }
private func session() -> ListenSession {
    ListenSession(matcher: WakeWordMatcher(wakeWords: ["gadi", "gadhi"]), silence: 1.5, followUpWindow: 8)
}

@Test func ignoresSpeechWithoutWakeWord() {
    var s = session()
    #expect(s.heard("innu mazhayaanu", isFinal: true, at: at(0)) == nil)
    #expect(s.phase == .idle)
}

@Test func wakeThenUtteranceAfterSilence() {
    var s = session()
    #expect(s.heard("gadi", isFinal: false, at: at(0)) == .wake)
    #expect(s.heard("gadi ennu", isFinal: false, at: at(0.5)) == nil)
    #expect(s.heard("gadi ennu enth pani cheyyanam", isFinal: false, at: at(1.0)) == nil)
    #expect(s.tick(at: at(2.0)) == nil)                         // only 1 s of silence
    #expect(s.tick(at: at(2.6)) == .utterance("ennu enth pani cheyyanam"))
    #expect(s.phase == .waitingForReply)
}

@Test func finalResultsAccumulateAcrossSegments() {
    var s = session()
    _ = s.heard("gadhi ennu", isFinal: true, at: at(0))
    _ = s.heard("enth cheyyanam", isFinal: false, at: at(0.8))
    _ = s.heard("enth cheyyanam", isFinal: true, at: at(1.0))   // same text → not a change
    #expect(s.tick(at: at(2.4)) == .utterance("ennu enth cheyyanam"))
}

@Test func repeatedIdenticalResultsDoNotResetSilence() {
    var s = session()
    _ = s.heard("gadi vaa", isFinal: false, at: at(0))
    _ = s.heard("gadi vaa", isFinal: false, at: at(1.0))
    #expect(s.tick(at: at(1.6)) == .utterance("vaa"))
}

@Test func wakeAloneGivesUpAfterTimeout() {
    var s = session()
    #expect(s.heard("gadhi", isFinal: true, at: at(0)) == .wake)
    #expect(s.tick(at: at(5)) == nil)
    #expect(s.tick(at: at(6)) == .gaveUp)
    #expect(s.phase == .idle)
}

@Test func followUpNeedsNoWakeWord() {
    var s = session()
    _ = s.heard("gadi vaa", isFinal: true, at: at(0))
    _ = s.tick(at: at(2))                                       // utterance
    s.speakingStarted()
    #expect(s.heard("yenthootta gadi", isFinal: true, at: at(3)) == nil)  // Gedi's own voice: ignored
    s.speakingEnded(at: at(5))
    #expect(s.phase == .followUp)
    #expect(s.heard("pinne", isFinal: false, at: at(5.2)) == nil)        // inside echo tail: ignored
    #expect(s.phase == .followUp)
    _ = s.heard("pinne enthund", isFinal: false, at: at(6))
    #expect(s.phase == .capturing)
    #expect(s.tick(at: at(7.6)) == .utterance("pinne enthund"))
}

@Test func followUpWindowExpires() {
    var s = session()
    _ = s.heard("gadi vaa", isFinal: true, at: at(0))
    _ = s.tick(at: at(2))
    s.speakingEnded(at: at(3))
    #expect(s.tick(at: at(10)) == nil)
    #expect(s.tick(at: at(11)) == .gaveUp)
    #expect(s.phase == .idle)
}

@Test func gediSpeakingNeverWakesItself() {
    var s = session()
    s.speakingStarted()
    #expect(s.heard("yenthootta gadi", isFinal: true, at: at(0)) == nil)
    s.speakingEnded(at: at(1))
    #expect(s.heard("gadi", isFinal: true, at: at(1.3)) == nil)   // echo tail
    #expect(s.heard("gadi", isFinal: true, at: at(2)) == .wake)
}
