import Foundation
import Testing
@testable import GediCore

private let fakeWAV = Data("RIFF".utf8) + Data(repeating: 0, count: 100)

@Test func synthesizePostsTextAndReturnsWAV() async throws {
    let host = "piper-ok.test"
    StubURLProtocol.stub(host: host, body: fakeWAV)
    let client = PiperClient(baseURL: URL(string: "http://\(host):5917")!, session: StubURLProtocol.session())

    let wav = try await client.synthesize("എന്തൂട്ടാ ഗഡീ")

    #expect(wav == fakeWAV)
    let (req, body) = try #require(StubURLProtocol.lastRequest(host: host))
    #expect(req.url?.path == "/synthesize")
    #expect(req.httpMethod == "POST")
    #expect(try JSONDecoder().decode([String: String].self, from: body) == ["text": "എന്തൂട്ടാ ഗഡീ"])
}

@Test func nonWAVBodyIsRejected() async {
    let host = "piper-html.test"
    StubURLProtocol.stub(host: host, body: Data("<html>oops</html>".utf8))
    let client = PiperClient(baseURL: URL(string: "http://\(host)")!, session: StubURLProtocol.session())
    await #expect(throws: PiperError.notWAV) { _ = try await client.synthesize("x") }
}

@Test func serverErrorIsThrown() async {
    let host = "piper-500.test"
    StubURLProtocol.stub(host: host, status: 500, body: Data("No text provided".utf8))
    let client = PiperClient(baseURL: URL(string: "http://\(host)")!, session: StubURLProtocol.session())
    await #expect(throws: PiperError.http(status: 500, body: "No text provided")) { _ = try await client.synthesize("") }
}

@Test func readiness() async {
    let up = "piper-up.test"
    StubURLProtocol.stub(host: up, body: Data("{}".utf8))
    #expect(await PiperClient(baseURL: URL(string: "http://\(up)")!, session: StubURLProtocol.session()).isReady())
    // No stub registered for this host → connection error → not ready.
    #expect(await !PiperClient(baseURL: URL(string: "http://piper-down.test")!, session: StubURLProtocol.session()).isReady())
}
