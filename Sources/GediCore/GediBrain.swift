import Foundation

/// Decides what Gedi says. Remembers its own recent lines (to avoid repeats) and the
/// current conversation (so follow-up questions make sense).
public actor GediBrain {
    private let model: any ChatModel
    private var builder: PromptBuilder
    public private(set) var recentLines: [String] = []
    public private(set) var conversation: [ChatMessage] = []
    private let maxRecentLines = 5
    private let maxConversationMessages = 6

    public init(model: any ChatModel, builder: PromptBuilder) {
        self.model = model
        self.builder = builder
    }

    public func updateClips(_ clips: [ClipInfo]) {
        builder.clips = clips
    }

    /// Unprompted comment about the activity (or about `event`). Nil if the model output was unusable.
    public func comment(activity: String, event: String? = nil) async throws -> GediReply? {
        let messages = builder.commentMessages(activity: activity, recentLines: recentLines, event: event)
        let raw = try await model.chat(messages, schema: builder.responseSchema())
        guard let reply = GediReply.parse(raw) else { return nil }
        if reply.speak { remember(reply.line) }
        return reply
    }

    /// Answer to something the user said after "gedeee".
    public func reply(to utterance: String, activity: String) async throws -> GediReply? {
        let messages = builder.replyMessages(activity: activity, utterance: utterance, conversation: conversation)
        let raw = try await model.chat(messages, schema: builder.responseSchema())
        try Task.checkCancellation()  // superseded by a newer call: keep it out of the conversation
        guard let reply = GediReply.parse(raw) else { return nil }
        conversation.append(.user(utterance))
        conversation.append(.assistant(Self.encode(reply)))
        if conversation.count > maxConversationMessages {
            conversation.removeFirst(conversation.count - maxConversationMessages)
        }
        if reply.speak { remember(reply.line) }
        return reply
    }

    /// Forget the conversation once the user has stopped talking to Gedi.
    public func endConversation() {
        conversation.removeAll()
    }

    private func remember(_ line: String) {
        recentLines.append(line)
        if recentLines.count > maxRecentLines { recentLines.removeFirst() }
    }

    private static func encode(_ reply: GediReply) -> String {
        var r = reply
        if r.clip == nil { r.clip = "none" }
        let enc = JSONEncoder()
        enc.outputFormatting = .sortedKeys
        return (try? String(decoding: enc.encode(r), as: UTF8.self)) ?? reply.line
    }
}
