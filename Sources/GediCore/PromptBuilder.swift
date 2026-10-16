import Foundation

public struct ChatMessage: Codable, Equatable, Sendable {
    public var role: String
    public var content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }

    public static func system(_ s: String) -> ChatMessage { ChatMessage(role: "system", content: s) }
    public static func user(_ s: String) -> ChatMessage { ChatMessage(role: "user", content: s) }
    public static func assistant(_ s: String) -> ChatMessage { ChatMessage(role: "assistant", content: s) }
}

/// Turns persona + activity + history into Ollama chat messages and a reply schema.
public struct PromptBuilder: Sendable {
    public var persona: String
    public var clips: [ClipInfo]

    public init(persona: String, clips: [ClipInfo] = []) {
        self.persona = persona
        self.clips = clips
    }

    public func systemPrompt() -> String {
        var rules = """
        ## Output rules (always follow)
        - Reply with JSON only: {"speak": true or false, "line": "<what you say>", "clip": "<clip id or none>"}
        - "line" is Malayalam script only, at most 2 short sentences.
        - Never repeat or reword one of your recent lines. Say something new.
        - Set "speak" to false only if you truly have nothing to say.
        """
        if clips.isEmpty {
            rules += "\n- Always set \"clip\" to \"none\"."
        } else {
            rules += "\n- \"clip\": the id of one recorded clip below if it fits the moment perfectly, otherwise \"none\". When you pick a clip, put its text in \"line\"."
            rules += "\n\nRecorded clips:"
            for c in clips {
                rules += "\n- \(c.id): \"\(c.text)\" (use when: \(c.use))"
            }
        }
        return persona.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" + rules
    }

    /// Unprompted comment on the timer.
    public func commentMessages(activity: String, recentLines: [String]) -> [ChatMessage] {
        var user = "What the user is doing:\n\(activity)\n\n"
        if recentLines.isEmpty {
            user += "You have not said anything yet.\n"
        } else {
            user += "Your recent lines (do not repeat these):\n"
            user += recentLines.map { "- \($0)" }.joined(separator: "\n") + "\n"
        }
        user += "\nSay one new short line about what they are doing right now."
        return [.system(systemPrompt()), .user(user)]
    }

    /// Reply when the user called "gedeee" and said something.
    /// `conversation` holds earlier user/assistant turns of this chat.
    public func replyMessages(activity: String, utterance: String, conversation: [ChatMessage]) -> [ChatMessage] {
        let user = """
        What the user is doing:
        \(activity)

        The user just called you and said: "\(utterance)"
        (Their words come from speech recognition, written in Manglish, and may contain mistakes.)
        Reply to them directly.
        """
        return [.system(systemPrompt())] + conversation + [.user(user)]
    }

    /// JSON schema for Ollama's `format`, restricting `clip` to known ids.
    public func responseSchema() -> JSON {
        .object([
            "type": .string("object"),
            "properties": .object([
                "speak": .object(["type": .string("boolean")]),
                "line": .object(["type": .string("string")]),
                "clip": .object([
                    "type": .string("string"),
                    "enum": .array(([JSON.string("none")]) + clips.map { .string($0.id) }),
                ]),
            ]),
            "required": .array([.string("speak"), .string("line"), .string("clip")]),
        ])
    }
}
