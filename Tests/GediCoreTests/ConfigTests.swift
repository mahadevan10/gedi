import Foundation
import Testing
@testable import GediCore

@Test func missingKeysFallBackToDefaults() throws {
    let json = #"{"model": "qwen3.5:4b", "commentIntervalSeconds": 45}"#
    let config = try JSONDecoder().decode(GediConfig.self, from: Data(json.utf8))
    #expect(config.model == "qwen3.5:4b")
    #expect(config.commentIntervalSeconds == 45)
    #expect(config.localeID == "ml-IN")
    #expect(config.wakeWords == GediConfig.default.wakeWords)
    #expect(config.ttsPort == 5917)
}

@Test func missingFileGivesDefaults() throws {
    let url = URL(fileURLWithPath: "/nonexistent/gedi/config.json")
    #expect(try GediConfig.load(from: url) == .default)
}

@Test func malformedFileThrows() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("gedi-bad-\(UUID()).json")
    try Data("{not json".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(throws: (any Error).self) { try GediConfig.load(from: url) }
}

@Test func tildeIsExpanded() {
    let expanded = GediPaths.expand("~/Library/Application Support/Gedi/voices")
    #expect(!expanded.hasPrefix("~"))
    #expect(expanded.hasSuffix("/Library/Application Support/Gedi/voices"))
}
