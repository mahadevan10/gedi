import Foundation
import Testing
@testable import GediCore

private let clip = ClipInfo(id: "shorts_again", file: "s.m4a", text: "പിന്നേം ഷോർട്സ്?", use: "user is on Shorts")

@Test func systemPromptStartsWithPersonaAndHasRules() {
    let p = PromptBuilder(persona: "You are Gedi.\n").systemPrompt()
    #expect(p.hasPrefix("You are Gedi.\n\n## Output rules"))
    #expect(p.contains("Always set \"clip\" to \"none\"."))
    #expect(!p.contains("Recorded clips:"))
}

@Test func systemPromptListsClips() {
    let p = PromptBuilder(persona: "P", clips: [clip]).systemPrompt()
    #expect(p.contains("Recorded clips:\n- shorts_again: \"പിന്നേം ഷോർട്സ്?\" (use when: user is on Shorts)"))
}

@Test func commentMessagesIncludeActivityAndRecentLines() {
    let m = PromptBuilder(persona: "P").commentMessages(activity: "Now: YouTube Shorts", recentLines: ["ഒന്ന്", "രണ്ട്"])
    #expect(m.count == 2)
    #expect(m[0].role == "system")
    #expect(m[1].role == "user")
    #expect(m[1].content.contains("What the user is doing:\nNow: YouTube Shorts"))
    #expect(m[1].content.contains("Your recent lines (do not repeat these):\n- ഒന്ന്\n- രണ്ട്"))
}

@Test func commentMessagesWithNoHistory() {
    let m = PromptBuilder(persona: "P").commentMessages(activity: "A", recentLines: [])
    #expect(m[1].content.contains("You have not said anything yet."))
}

@Test func replyMessagesCarryConversation() {
    let convo: [ChatMessage] = [.user("earlier"), .assistant(#"{"speak":true,"line":"x","clip":"none"}"#)]
    let m = PromptBuilder(persona: "P").replyMessages(activity: "A", utterance: "innu enth pani cheyyanam", conversation: convo)
    #expect(m.map(\.role) == ["system", "user", "assistant", "user"])
    #expect(m[3].content.contains("The user just called you and said: \"innu enth pani cheyyanam\"\n(Their words come from speech recognition"))
}

@Test func schemaRestrictsClipIDs() throws {
    let schema = PromptBuilder(persona: "P", clips: [clip]).responseSchema()
    let enc = JSONEncoder()
    enc.outputFormatting = .sortedKeys
    let s = String(decoding: try enc.encode(schema), as: UTF8.self)
    #expect(s.contains(#""enum":["none","shorts_again"]"#))
    #expect(s.contains(#""required":["speak","line","clip"]"#))
}
