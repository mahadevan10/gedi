import Foundation
import GediCore

/// Speaks a reply: a recorded clip if the model picked one that exists, otherwise Piper TTS.
@MainActor
public final class GediVoice {
    private let piper: PiperClient
    private let audio: AudioOut
    public var clips: ClipLibrary

    public init(piper: PiperClient, clips: ClipLibrary) {
        self.piper = piper
        self.clips = clips
        self.audio = AudioOut()
    }

    /// The text to show in the speech bubble for this reply.
    public func displayText(for reply: GediReply) -> String {
        if let id = reply.clip, let clip = clips.clip(id: id) { return clip.text }
        return reply.line
    }

    /// Returns when playback ends.
    public func say(_ reply: GediReply) async throws {
        if let id = reply.clip, let clip = clips.clip(id: id) {
            try await audio.play(url: clips.url(for: clip))
            return
        }
        guard !reply.line.isEmpty else { return }
        try await audio.play(data: try await piper.synthesize(reply.line))
    }

    public func stop() {
        audio.stop()
    }
}
