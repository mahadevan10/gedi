import Foundation
import GediCore

public enum PiperServerError: Error, CustomStringConvertible {
    case pythonMissing(String)
    case voiceMissing(String)
    case notReady(log: String)

    public var description: String {
        switch self {
        case .pythonMissing(let p): return "Piper Python not found at \(p). Run scripts/setup.sh."
        case .voiceMissing(let p): return "Piper voice not found at \(p). Run scripts/setup.sh."
        case .notReady(let log): return "Piper server did not start. Log:\n\(log)"
        }
    }
}

/// Runs `python -m piper.http_server` as a child process so the voice stays loaded.
/// If something already answers on the port (e.g. left over from a crash), it is reused.
public final class PiperServer: @unchecked Sendable {
    private let config: GediConfig
    private var process: Process?
    private let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("gedi-piper.log")
    public let client: PiperClient

    public init(config: GediConfig) {
        self.config = config
        self.client = PiperClient(port: config.piperPort)
    }

    public func start(timeout: TimeInterval = 20) async throws {
        if await client.isReady() { return }
        let python = GediPaths.expand(config.piperPython)
        let dataDir = GediPaths.expand(config.piperDataDir)
        let voice = "\(dataDir)/\(config.piperVoice).onnx"
        guard FileManager.default.isExecutableFile(atPath: python) else { throw PiperServerError.pythonMissing(python) }
        guard FileManager.default.fileExists(atPath: voice) else { throw PiperServerError.voiceMissing(voice) }

        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let log = try FileHandle(forWritingTo: logURL)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: python)
        p.arguments = ["-m", "piper.http_server", "-m", config.piperVoice, "--data-dir", dataDir,
                       "--host", "127.0.0.1", "--port", String(config.piperPort)]
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
