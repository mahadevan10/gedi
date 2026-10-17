import Foundation
import Testing
@testable import GediCore

@Suite struct OpenAIClientTests {
    @Test func postsChatCompletionWithSchemaAndKey() async throws {
        let host = "openai-ok.test"
        StubURLProtocol.stub(host: host, body: Data(#"{"choices":[{"message":{"role":"assistant","content":"{\"speak\":true}"}}]}"#.utf8))
        let client = OpenAIClient(baseURL: URL(string: "https://\(host)/v1beta/openai/")!, apiKey: "K", model: "m", session: StubURLProtocol.session())
        let content = try await client.chat([.system("S"), .user("U")], schema: .object(["type": .string("object")]))
        #expect(content == #"{"speak":true}"#)
        let (req, body) = try #require(StubURLProtocol.lastRequest(host: host))
        #expect(req.url?.path == "/v1beta/openai/chat/completions")
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer K")
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "m")
        let format = try #require(json["response_format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
    }

    @Test func non200Throws() async throws {
        let host = "openai-err.test"
        StubURLProtocol.stub(host: host, status: 429, body: Data("quota".utf8))
        let client = OpenAIClient(baseURL: URL(string: "https://\(host)/")!, apiKey: "K", model: "m", session: StubURLProtocol.session())
        await #expect(throws: OllamaError.self) {
            _ = try await client.chat([.user("U")], schema: .object([:]))
        }
    }

    @Test func configPicksHostedBrainWhenChatURLSet() throws {
        let c = try JSONDecoder().decode(GediConfig.self, from: Data(#"{"chatURL":"https://x.test/","chatAPIKey":"K"}"#.utf8))
        #expect(c.chatModel() is OpenAIClient)
        #expect(GediConfig.default.chatModel() is OpenAIClient)
        let local = try JSONDecoder().decode(GediConfig.self, from: Data(#"{"chatURL":null,"model":"qwen3.5:9b"}"#.utf8))
        #expect(local.chatModel() is OllamaClient)
    }

    @Test func routerFallsThroughToNextProvider() async throws {
        StubURLProtocol.stub(host: "router-limited.test", status: 429, body: Data("quota".utf8))
        StubURLProtocol.stub(host: "router-ok.test", body: Data(#"{"choices":[{"message":{"content":"ok"}}]}"#.utf8))
        let s = StubURLProtocol.session()
        let router = ChatRouter([
            OpenAIClient(baseURL: URL(string: "https://router-limited.test/")!, apiKey: "A", model: "a", session: s),
            OpenAIClient(baseURL: URL(string: "https://router-ok.test/")!, apiKey: "B", model: "b", session: s),
        ])
        #expect(try await router.chat([.user("U")], schema: .object([:])) == "ok")
        let (_, body) = try #require(StubURLProtocol.lastRequest(host: "router-ok.test"))
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "b")

        let allDown = ChatRouter([OpenAIClient(baseURL: URL(string: "https://router-limited.test/")!, apiKey: "A", model: "a", session: s)])
        await #expect(throws: OllamaError.self) { _ = try await allDown.chat([.user("U")], schema: .object([:])) }
    }

    @Test func configBuildsRouterOnlyWithFallbacks() throws {
        #expect(GediConfig.default.chatModel() is OpenAIClient)
        let c = try JSONDecoder().decode(GediConfig.self, from: Data(#"{"fallbacks":[{"chatURL":"https://api.groq.com/openai/v1/","chatAPIKey":"G","model":"llama"}]}"#.utf8))
        let router = try #require(c.chatModel() as? ChatRouter)
        #expect(router.models.count == 2)
        #expect((router.models[1] as? OpenAIClient)?.reasoningEffort == nil)
    }
}
