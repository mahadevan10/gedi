import Foundation

/// v1 rule for unprompted comments: every `interval` seconds, measured from the end of
/// Gedi's last speech, unless something says to stay quiet. Later versions can replace
/// this with "let the model decide" (GediReply.speak already supports that).
public struct CommentPolicy: Sendable {
    public var interval: TimeInterval

    public init(interval: TimeInterval) {
        self.interval = interval
    }

    public struct State: Sendable {
        public var muted = false
        /// Generating or speaking right now.
        public var busy = false
        /// The user is talking to Gedi (wake word heard, follow-up window open).
        public var conversing = false
        public var inCall = false
        public init() {}
    }

    public func isDue(now: Date, lastSpokeAt: Date, state: State) -> Bool {
        if state.muted || state.busy || state.conversing || state.inCall { return false }
        return now.timeIntervalSince(lastSpokeAt) >= interval
    }
}
