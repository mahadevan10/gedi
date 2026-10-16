import AVFoundation
import Foundation

/// Plays one sound at a time and returns when it finishes.
@MainActor
public final class AudioOut: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var finished: CheckedContinuation<Void, Never>?

    public override init() {}

    public func play(data: Data) async throws {
        try await play(AVAudioPlayer(data: data))
    }

    public func play(url: URL) async throws {
        try await play(AVAudioPlayer(contentsOf: url))
    }

    private func play(_ p: AVAudioPlayer) async {
        stop()
        p.delegate = self
        player = p
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            finished = c
            if !p.play() { finish() }
        }
    }

    public func stop() {
        player?.stop()
        finish()
    }

    private func finish() {
        player = nil
        finished?.resume()
        finished = nil
    }

    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.finish() }
    }

    nonisolated public func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in self.finish() }
    }
}
