import Foundation
import GediCore

public enum PiperServerError: Error, CustomStringConvertible {
    case pythonMissing(String)
    case scriptMissing(String)
    case notReady(log: String)

    public var description: String {
        switch self {
        case .pythonMissing(let p): return "TTS Python not found at \(p). Run scripts/setup.sh."
        case .scriptMissing(let p): return "TTS server script not found at \(p). Run scripts/setup.sh."
        case .notReady(let log): return "TTS server did not start. Log:\n\(log)"
        }
    }
}

/// Runs `parler_server.py` (Indic-Parler-TTS behind Piper's HTTP API) as a child process
/// so the model stays loaded.
/// If something already answers on the port (e.g. left over from a crash), it is reused.
public final class PiperServer: @unchecked Sendable {
    private let config: GediConfig
    private var process: Process?
    private let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("gedi-piper.log")
    public let client: PiperClient

    public init(config: GediConfig) {
        self.config = config
        self.client = PiperClient(port: config.ttsPort)
    }

    /// Loading the model and its warm-up run take a while, hence the long timeout.
    public func start(timeout: TimeInterval = 180) async throws {
        if await client.isReady() { return }
        let python = GediPaths.expand(config.ttsPython)
        let script = GediPaths.expand(config.ttsScript)
        guard FileManager.default.isExecutableFile(atPath: python) else { throw PiperServerError.pythonMissing(python) }
        guard FileManager.default.fileExists(atPath: script) else { throw PiperServerError.scriptMissing(script) }

        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let log = try FileHandle(forWritingTo: logURL)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: python)
        p.arguments = ["-I", script, "--host", "127.0.0.1", "--port", String(config.ttsPort)]
        p.standardOutput = log
        p.standardError = log
        try p.run()
        process = p

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await client.isReady() { return }
            if !p.isRunning { break }
            try await Task.sleep(for: .milliseconds(250))
        }
        stop()
        throw PiperServerError.notReady(log: (try? String(contentsOf: logURL, encoding: .utf8)) ?? "")
    }

    public func stop() {
        if let p = process, p.isRunning { p.terminate() }
        process = nil
    }
}
