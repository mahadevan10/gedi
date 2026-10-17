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
/// While Gedi is speaking (and `echoTail` seconds after) everything is ignored, so Gedi
/// never wakes itself up by saying "ഗഡീ".
public struct ListenSession: Sendable {
    public enum Phase: Equatable, Sendable {
        case idle, capturing, waitingForReply, followUp
    }

    public private(set) var phase: Phase = .idle
    public var silence: TimeInterval
    public var followUpWindow: TimeInterval
    public var maxWaitAfterWake: TimeInterval = 6
    public var echoTail: TimeInterval = 0.7

    private let matcher: WakeWordMatcher
    private var committed: [String] = []
    private var pending = ""
    private var lastChange = Date.distantPast
    private var phaseStarted = Date.distantPast
    private var speaking = false
    private var deafUntil = Date.distantPast

    public init(matcher: WakeWordMatcher, silence: TimeInterval = 1.5, followUpWindow: TimeInterval = 8) {
        self.matcher = matcher
        self.silence = silence
        self.followUpWindow = followUpWindow
    }

    public var capturedText: String {
        (committed + [pending]).filter { !$0.isEmpty }.joined(separator: " ")
    }

    public mutating func heard(_ text: String, isFinal: Bool, at now: Date) -> ListenEvent? {
        if speaking || now < deafUntil { return nil }
        switch phase {
        case .idle:
            guard let rest = matcher.remainder(after: text) else { return nil }
            enterCapturing(at: now)
            absorb(rest, isFinal: isFinal, at: now)
            return .wake
        case .followUp:
            let piece = matcher.remainder(after: text) ?? text
            guard !piece.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            enterCapturing(at: now)
            absorb(piece, isFinal: isFinal, at: now)
            return nil
        case .capturing:
            absorb(matcher.remainder(after: text) ?? text, isFinal: isFinal, at: now)
            return nil
        case .waitingForReply:
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
                    return .gaveUp
                }
            } else if now.timeIntervalSince(lastChange) >= silence {
                phase = .waitingForReply
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
