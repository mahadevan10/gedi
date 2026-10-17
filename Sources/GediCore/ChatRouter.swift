import Foundation
import os

private let log = Logger(subsystem: "com.mahadevan.gedi", category: "brain")

/// One extra OpenAI-compatible provider for `fallbacks` in config.json.
public struct ChatEndpoint: Codable, Equatable, Sendable {
    public var chatURL: URL
    public var chatAPIKey: String?
    public var model: String
    /// Omitted unless set: only some providers accept `reasoning_effort`.
    public var reasoningEffort: String?

    public init(chatURL: URL, chatAPIKey: String? = nil, model: String, reasoningEffort: String? = nil) {
        self.chatURL = chatURL
        self.chatAPIKey = chatAPIKey
        self.model = model
        self.reasoningEffort = reasoningEffort
    }

    func client() -> OpenAIClient {
        var c = OpenAIClient(baseURL: chatURL, apiKey: chatAPIKey ?? "", model: model)
        c.reasoningEffort = reasoningEffort
        return c
    }
}

/// Tries each model in order and returns the first answer; throws the last error if all fail.
// shortcut: always retries the primary first (a 429 costs one fast round-trip), add a cooldown if that latency shows.
public struct ChatRouter: ChatModel {
    public var models: [any ChatModel]

    public init(_ models: [any ChatModel]) { self.models = models }

    public func chat(_ messages: [ChatMessage], schema: JSON) async throws -> String {
        var lastError: Error = OllamaError.http(status: -1, body: "no models")
        for (i, model) in models.enumerated() {
            try Task.checkCancellation()
            do {
                return try await model.chat(messages, schema: schema)
            } catch {
                log.error("brain \(i, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                lastError = error
            }
        }
        throw lastError
    }
}
