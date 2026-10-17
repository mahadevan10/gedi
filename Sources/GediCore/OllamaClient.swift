import Foundation

/// Anything that can turn chat messages into a raw reply string. Lets tests swap in a fake.
public protocol ChatModel: Sendable {
    func chat(_ messages: [ChatMessage], schema: JSON) async throws -> String
}

public enum OllamaError: Error, Equatable {
    case http(status: Int, body: String)
}

/// Calls Ollama's `/api/chat` with streaming and thinking off and a JSON-schema `format`.
public struct OllamaClient: ChatModel {
    public var baseURL: URL
    public var model: String
    public var session: URLSession
    public var temperature: Double = 0.9
    public var maxTokens: Int = 160
    public var contextLength: Int = 4096
    /// Keeps the model loaded between the 30 s comments so there is no reload delay.
    public var keepAlive: String = "30m"

    public init(baseURL: URL, model: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.model = model
        self.session = session
    }

    struct Request: Encodable {
        struct Options: Encodable {
            let temperature: Double
            let num_predict: Int
            let num_ctx: Int
        }
        let model: String
        let messages: [ChatMessage]
        let stream: Bool
        let think: Bool
        let format: JSON
        let keep_alive: String
        let options: Options
    }

    struct Response: Decodable {
        struct Message: Decodable { let content: String }
        let message: Message
    }

    public func chat(_ messages: [ChatMessage], schema: JSON) async throws -> String {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 120
        req.httpBody = try JSONEncoder().encode(Request(
            model: model,
            messages: messages,
            stream: false,
            think: false,
            format: schema,
            keep_alive: keepAlive,
            options: .init(temperature: temperature, num_predict: maxTokens, num_ctx: contextLength)
        ))
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard status == 200 else {
            throw OllamaError.http(status: status, body: String(decoding: data, as: UTF8.self))
        }
        return try JSONDecoder().decode(Response.self, from: data).message.content
    }
}
