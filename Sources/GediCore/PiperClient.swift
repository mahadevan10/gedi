import Foundation

public enum PiperError: Error, Equatable {
    case http(status: Int, body: String)
    case notWAV
}

/// Talks to `python -m piper.http_server`. POST /synthesize {"text": …} → WAV bytes.
public struct PiperClient: Sendable {
    public var baseURL: URL
    public var session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public init(port: Int, session: URLSession = .shared) {
        self.init(baseURL: URL(string: "http://127.0.0.1:\(port)")!, session: session)
    }

    public func synthesize(_ text: String) async throws -> Data {
        var req = URLRequest(url: baseURL.appendingPathComponent("synthesize"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30
        req.httpBody = try JSONEncoder().encode(["text": text])
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard status == 200 else {
            throw PiperError.http(status: status, body: String(decoding: data.prefix(500), as: UTF8.self))
        }
        guard data.count > 44, data.prefix(4) == Data("RIFF".utf8) else { throw PiperError.notWAV }
        return data
    }

    /// True once the server answers GET /info.
    public func isReady() async -> Bool {
        var req = URLRequest(url: baseURL.appendingPathComponent("info"))
        req.timeoutInterval = 2
        guard let (_, response) = try? await session.data(for: req) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }
}
