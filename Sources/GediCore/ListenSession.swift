import Foundation

public enum ListenEvent: Equatable, Sendable {
    /// Wake word heard. Show "listening", play a chime.
    case wake
    /// The user finished speaking. Send this text to the brain.
    case utterance(String)
    /// Wake word with nothing after it, or the follow-up window passed. Back to idle.
    case gaveUp
}

/// Turns a stream of transcription results into wake / utterance events.
///
/// The speech recogniser runs all the time. Each result is the latest guess for the
/// current stretch of speech (`isFinal == false`) or the settled text for it (`isFinal == true`).
/// The user is considered done when the captured text has not changed for `silence` seconds.
///
/// The wake word wins over a reply still being fetched: that reply is dropped and a fresh
/// capture starts. While Gedi is speaking (and `echoTail` seconds after) everything is
/// ignored, so Gedi never wakes itself up by saying "ഗഡീ". That includes the spoken
/// "പറ ഗഡീ" ack after every wake word; capture stays open and its wait restarts after it.
/// shortcut: no barge-in while speaking; needs echo cancellation, which failed on a Bluetooth mic.
public struct ListenSession: Sendable {
    public enum Phase: Equatable, Sendable {
        case idle, capturing, waitingForReply, followUp
    }

    public private(set) var phase: Phase = .idle
    public var silence: TimeInterval
    public var followUpWindow: TimeInterval
    public var maxWaitAfterWake: TimeInterval = 6
    /// The recogniser lags 1–2 s, so Gedi's own words keep arriving after playback ends.
    public var echoTail: TimeInterval = 2
    /// The recogniser's final result for the wake utterance can land after `.utterance`;
    /// it must not count as a second call.
    public var rewakeGrace: TimeInterval = 2

    private let matcher: WakeWordMatcher
    private var committed: [String] = []
    private var pending = ""
    private var lastChange = Date.distantPast
    private var phaseStarted = Date.distantPast
    private var speaking = false
    private var deafUntil = Date.distantPast
    private var utteranceAt = Date.distantPast
    /// Partial results repeat the whole segment so far (it can run for a minute before a
    /// final). Words before `used` were already handled; only later words are new.
    private var used = 0
    private var segmentWords = 0

    public init(matcher: WakeWordMatcher, silence: TimeInterval = 1.5, followUpWindow: TimeInterval = 8) {
        self.matcher = matcher
        self.silence = silence
        self.followUpWindow = followUpWindow
    }

    public var capturedText: String {
        (committed + [pending]).filter { !$0.isEmpty }.joined(separator: " ")
    }

    public mutating func heard(_ text: String, isFinal: Bool, at now: Date) -> ListenEvent? {
        let words = text.split(whereSeparator: \.isWhitespace)
        let fresh = words.dropFirst(used).joined(separator: " ")
        segmentWords = words.count
        defer { if isFinal { used = 0; segmentWords = 0 } }  // next result starts a new segment
        if speaking || now < deafUntil {
            used = words.count
            return nil
        }
        let rewakeBlocked = phase == .waitingForReply && now.timeIntervalSince(utteranceAt) < rewakeGrace
        if phase != .capturing, !rewakeBlocked, let rest = matcher.remainder(after: fresh) {
            used = words.count - rest.split(whereSeparator: \.isWhitespace).count
            enterCapturing(at: now)
            absorb(rest, isFinal: isFinal, at: now)
            return .wake
        }
        switch phase {
        case .idle, .waitingForReply:
            return nil
        case .followUp:
            guard !fresh.isEmpty else { return nil }
            enterCapturing(at: now)
            absorb(fresh, isFinal: isFinal, at: now)
            return nil
        case .capturing:
            absorb(matcher.remainder(after: fresh) ?? fresh, isFinal: isFinal, at: now)
            return nil
        }
    }

    /// Call about every 0.25–1 s.
    public mutating func tick(at now: Date) -> ListenEvent? {
        switch phase {
        case .capturing:
            let text = capturedText
            if text.isEmpty {
                if now.timeIntervalSince(phaseStarted) >= maxWaitAfterWake {
                    phase = .idle
                    used = segmentWords
                    return .gaveUp
                }
            } else if now.timeIntervalSince(lastChange) >= silence {
                phase = .waitingForReply
                utteranceAt = now
                used = segmentWords
                return .utterance(text)
            }
        case .followUp:
            if now.timeIntervalSince(phaseStarted) >= followUpWindow {
                phase = .idle
                return .gaveUp
            }
        case .idle, .waitingForReply:
            break
        }
        return nil
    }

    public mutating func speakingStarted() {
        speaking = true
    }

    /// Call when Gedi stops talking. Also call it when a reply failed and nothing was
    /// said, so the session leaves `waitingForReply`.
    public mutating func speakingEnded(at now: Date) {
        speaking = false
        deafUntil = now.addingTimeInterval(echoTail)
        if phase == .waitingForReply {
            phase = .followUp
            phaseStarted = now
        }
        if phase == .capturing {  // the wake ack: give the user the full wait after we stop talking
            phaseStarted = deafUntil
            lastChange = deafUntil
        }
    }

    private mutating func enterCapturing(at now: Date) {
        phase = .capturing
        committed = []
        pending = ""
        phaseStarted = now
        lastChange = now
    }

    private mutating func absorb(_ piece: String, isFinal: Bool, at now: Date) {
        let before = capturedText
        let trimmed = piece.trimmingCharacters(in: .whitespaces)
        if isFinal {
            if !trimmed.isEmpty { committed.append(trimmed) }
            pending = ""
        } else {
            pending = trimmed
        }
        if capturedText != before { lastChange = now }
    }
}
