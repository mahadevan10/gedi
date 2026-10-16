import Foundation
import Testing
@testable import GediCore

@Test func sendsExpectedRequestAndReturnsContent() async throws {
    let host = "ollama-ok.test"
    StubURLProtocol.stub(host: host, body: Data(#"{"message":{"role":"assistant","content":"{\"speak\":true}"},"done":true}"#.utf8))
    let client = OllamaClient(baseURL: URL(string: "http://\(host):11434")!, model: "qwen3.5:9b", session: StubURLProtocol.session())

    let content = try await client.chat([.system("S"), .user("U")], schema: .object(["type": .string("object")]))

    #expect(content == #"{"speak":true}"#)
    let (req, body) = try #require(StubURLProtocol.lastRequest(host: host))
    #expect(req.url?.path == "/api/chat")
    #expect(req.httpMethod == "POST")
    let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(json["model"] as? String == "qwen3.5:9b")
    #expect(json["stream"] as? Bool == false)
    #expect(json["think"] as? Bool == false)
    #expect(json["keep_alive"] as? String == "30m")
    let options = try #require(json["options"] as? [String: Any])
    #expect(options["num_predict"] as? Int == 160)
    #expect(options["num_ctx"] as? Int == 4096)
    let messages = try #require(json["messages"] as? [[String: String]])
    #expect(messages == [["role": "system", "content": "S"], ["role": "user", "content": "U"]])
    #expect((json["format"] as? [String: Any])?["type"] as? String == "object")
}

@Test func httpErrorIsThrown() async throws {
    let host = "ollama-404.test"
    StubURLProtocol.stub(host: host, status: 404, body: Data(#"{"error":"model 'x' not found"}"#.utf8))
    let client = OllamaClient(baseURL: URL(string: "http://\(host)")!, model: "x", session: StubURLProtocol.session())
    await #expect(throws: OllamaError.http(status: 404, body: #"{"error":"model 'x' not found"}"#)) {
        _ = try await client.chat([.user("hi")], schema: .null)
    }
}
