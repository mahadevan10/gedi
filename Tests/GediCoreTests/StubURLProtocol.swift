import Foundation

/// Intercepts URLSession requests in tests. Each test uses its own `host` key so
/// tests running in parallel do not see each other's stubs.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Stub {
        var status: Int
        var body: Data
    }

    nonisolated(unsafe) private static var stubs: [String: Stub] = [:]
    nonisolated(unsafe) private static var captured: [String: URLRequest] = [:]
    nonisolated(unsafe) private static var capturedBodies: [String: Data] = [:]
    private static let lock = NSLock()

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    static func stub(host: String, status: Int = 200, body: Data) {
        lock.withLock { stubs[host] = Stub(status: status, body: body) }
    }

    static func lastRequest(host: String) -> (URLRequest, Data)? {
        lock.withLock {
            guard let r = captured[host] else { return nil }
            return (r, capturedBodies[host] ?? Data())
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host ?? ""
        let body = request.httpBody ?? Self.readStream(request.httpBodyStream)
        let stub: Stub? = Self.lock.withLock {
            Self.captured[host] = request
            Self.capturedBodies[host] = body
            return Self.stubs[host]
        }
        guard let stub else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: stub.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readStream(_ stream: InputStream?) -> Data {
        guard let stream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}
