import Foundation
import Testing
@testable import GediCore

/// Returns queued replies in order and records every request.
private actor FakeModel: ChatModel {
    var replies: [String]
    var requests: [[ChatMessage]] = []
    init(_ replies: [String]) { self.replies = replies }
    func chat(_ messages: [ChatMessage], schema: JSON) async throws -> String {
        requests.append(messages)
        return replies.isEmpty ? "" : replies.removeFirst()
    }
}

private func line(_ s: String) -> String { #"{"speak": true, "line": "\#(s)", "clip": "none"}"# }

@Test func commentRemembersLinesAndSendsThemNextTime() async throws {
    let model = FakeModel([line("ഒന്ന്"), line("രണ്ട്")])
    let brain = GediBrain(model: model, builder: PromptBuilder(persona: "P"))

    let first = try await brain.comment(activity: "A")
    #expect(first?.line == "ഒന്ന്")
    _ = try await brain.comment(activity: "A")

    let requests = await model.requests
    #expect(requests[1][1].content.contains("- ഒന്ന്"))
    #expect(await brain.recentLines == ["ഒന്ന്", "രണ്ട്"])
}

@Test func recentLinesAreCappedAtFive() async throws {
    let model = FakeModel((1...7).map { line("l\($0)") })
    let brain = GediBrain(model: model, builder: PromptBuilder(persona: "P"))
    for _ in 1...7 { _ = try await brain.comment(activity: "A") }
    #expect(await brain.recentLines == ["l3", "l4", "l5", "l6", "l7"])
}

@Test func silentReplyIsNotRemembered() async throws {
    let brain = GediBrain(model: FakeModel([#"{"speak": false, "line": "", "clip": "none"}"#]), builder: PromptBuilder(persona: "P"))
    let r = try await brain.comment(activity: "A")
    #expect(r?.speak == false)
    #expect(await brain.recentLines.isEmpty)
}

@Test func unusableOutputGivesNil() async throws {
    let brain = GediBrain(model: FakeModel(["Sorry, I can't."]), builder: PromptBuilder(persona: "P"))
    #expect(try await brain.comment(activity: "A") == nil)
}

@Test func replyKeepsConversationAndEndClearsIt() async throws {
    let model = FakeModel([line("ആദ്യം"), line("പിന്നെ")])
    let brain = GediBrain(model: model, builder: PromptBuilder(persona: "P"))

    _ = try await brain.reply(to: "ചോദ്യം ഒന്ന്", activity: "A")
    _ = try await brain.reply(to: "ചോദ്യം രണ്ട്", activity: "A")

    let second = await model.requests[1]
    #expect(second.map(\.role) == ["system", "user", "assistant", "user"])
    #expect(second[1].content == "ചോദ്യം ഒന്ന്")
    #expect(second[2].content == #"{"clip":"none","line":"ആദ്യം","speak":true}"#)

    await brain.endConversation()
    #expect(await brain.conversation.isEmpty)
}
