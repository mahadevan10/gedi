import AVFoundation
import Foundation
import Speech

public enum SpeechError: Error, CustomStringConvertible {
    case noAudioFormat
    case micDenied

    public var description: String {
        switch self {
        case .noAudioFormat: return "Speech recogniser offered no audio format."
        case .micDenied: return "Microphone access denied. Allow it in System Settings → Privacy & Security → Microphone."
        }
    }
}

/// Apple's on-device recogniser (SpeechAnalyzer, macOS 26+). For ml-IN it writes
/// Malayalam in Latin letters ("gadi ennu enth pani cheyyanam").
public enum SpeechModels {
    static func transcriber(_ localeID: String) -> SpeechTranscriber {
        SpeechTranscriber(locale: Locale(identifier: localeID), transcriptionOptions: [],
                          reportingOptions: [.volatileResults], attributeOptions: [])
    }

    /// Downloads the language model if needed (one-time, ~a few hundred MB, system-managed).
    public static func ensureInstalled(localeID: String) async throws {
        let t = transcriber(localeID)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [t]) {
            try await request.downloadAndInstall()
        }
    }

    /// Transcribes an audio file. Used by `gedi-debug transcribe` and for wake-word calibration.
    public static func transcribe(file url: URL, localeID: String) async throws -> String {
        let t = transcriber(localeID)
        try await ensureInstalled(localeID: localeID)
        let analyzer = SpeechAnalyzer(modules: [t])
        let file = try AVAudioFile(forReading: url)
        let reader = Task {
            var finals: [String] = []
            for try await r in t.results where r.isFinal { finals.append(String(r.text.characters)) }
            return finals.joined(separator: " ")
        }
        if let last = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: last)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        return try await reader.value
    }

    public static func requestMicAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }
}

/// Always-on microphone → SpeechAnalyzer. Calls `onResult(text, isFinal)` from a
/// background task for every recogniser update, and `onStop(error)` if the stream ends.
public final class LiveTranscriber: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var converter: AVAudioConverter?
    private var resultsTask: Task<Void, Never>?

    public init() {}

    public func start(
        localeID: String,
        onResult: @escaping @Sendable (String, Bool) -> Void,
        onStop: @escaping @Sendable (Error?) -> Void
    ) async throws {
        guard await SpeechModels.requestMicAccess() else { throw SpeechError.micDenied }
        try await SpeechModels.ensureInstalled(localeID: localeID)
        let transcriber = SpeechModels.transcriber(localeID)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        guard let target = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw SpeechError.noAudioFormat
        }

        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        input = continuation
        resultsTask = Task {
            do {
                for try await r in transcriber.results { onResult(String(r.text.characters), r.isFinal) }
                onStop(nil)
            } catch {
                onStop(error)
            }
        }
        try await analyzer.start(inputSequence: stream)

        let node = engine.inputNode
        let micFormat = node.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: micFormat, to: target)
        node.installTap(onBus: 0, bufferSize: 4096, format: micFormat) { [weak self] buffer, _ in
            self?.feed(buffer, from: micFormat, to: target)
        }
        engine.prepare()
        try engine.start()
    }

    private func feed(_ buffer: AVAudioPCMBuffer, from source: AVAudioFormat, to target: AVAudioFormat) {
        guard let converter else { return }
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * target.sampleRate / source.sampleRate) + 1
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        if error == nil, out.frameLength > 0 { input?.yield(AnalyzerInput(buffer: out)) }
    }

    public func stop() async {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        input?.finish()
        input = nil
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        resultsTask?.cancel()
        analyzer = nil
    }
}
