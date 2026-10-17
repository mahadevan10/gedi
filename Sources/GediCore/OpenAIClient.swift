import Foundation

/// Calls an OpenAI-compatible `/chat/completions` (e.g. Gemini's `…/v1beta/openai/`) with a JSON-schema `response_format`.
public struct OpenAIClient: ChatModel {
    public var baseURL: URL
    public var apiKey: String
    public var model: String
    public var session: URLSession
    public var temperature: Double = 0.9
    /// Higher than Ollama's 160: Malayalam costs several tokens per word on hosted tokenizers.
    public var maxTokens: Int = 512
    /// Gemini 2.5 Flash thinks by default, which eats `max_tokens` and adds latency.
    public var reasoningEffort: String? = "none"

    public init(baseURL: URL, apiKey: String, model: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    struct Request: Encodable {
        struct ResponseFormat: Encodable {
            struct Schema: Encodable {
                let name: String
                let schema: JSON
            }
            let type = "json_schema"
            let json_schema: Schema
        }
        let model: String
        let messages: [ChatMessage]
        let temperature: Double
        let max_tokens: Int
        let reasoning_effort: String?
        let response_format: ResponseFormat
    }

    struct Response: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
        }
        let choices: [Choice]
    }

    public func chat(_ messages: [ChatMessage], schema: JSON) async throws -> String {
        var req = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 60
        req.httpBody = try JSONEncoder().encode(Request(
            model: model,
            messages: messages,
            temperature: temperature,
            max_tokens: maxTokens,
            reasoning_effort: reasoningEffort,
            response_format: .init(json_schema: .init(name: "reply", schema: schema))
        ))
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard status == 200 else {
            throw OllamaError.http(status: status, body: String(decoding: data, as: UTF8.self))
        }
        let content = try JSONDecoder().decode(Response.self, from: data).choices.first?.message.content
        guard let content else { throw OllamaError.http(status: status, body: String(decoding: data, as: UTF8.self)) }
        return content
    }
}
