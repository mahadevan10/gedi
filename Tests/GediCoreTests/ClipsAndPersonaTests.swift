import Foundation
import Testing
@testable import GediCore

private func tempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gedi-test-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

@Test func noManifestGivesEmptyLibrary() throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    #expect(try ClipLibrary.load(from: dir).clips.isEmpty)
}

@Test func clipsWithMissingAudioAreDropped() throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    try Data("fake".utf8).write(to: dir.appendingPathComponent("shorts.m4a"))
    let manifest = """
    [
      {"id": "shorts_again", "file": "shorts.m4a", "text": "പിന്നേം ഷോർട്സ്?", "use": "user is on Shorts"},
      {"id": "missing", "file": "nope.m4a", "text": "x", "use": "never"}
    ]
    """
    try Data(manifest.utf8).write(to: dir.appendingPathComponent("clips.json"))
    let lib = try ClipLibrary.load(from: dir)
    #expect(lib.clips.map(\.id) == ["shorts_again"])
    #expect(lib.clip(id: "shorts_again")?.text == "പിന്നേം ഷോർട്സ്?")
    #expect(lib.clip(id: "missing") == nil)
    #expect(lib.url(for: lib.clips[0]).lastPathComponent == "shorts.m4a")
}

@Test func malformedManifestThrows() throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    try Data("[{".utf8).write(to: dir.appendingPathComponent("clips.json"))
    #expect(throws: (any Error).self) { try ClipLibrary.load(from: dir) }
}

@Test func personaFallsBackToDefault() throws {
    #expect(Persona.load(from: URL(fileURLWithPath: "/nonexistent/persona.md")) == Persona.defaultText)
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("persona.md")
    try Data("  \n".utf8).write(to: file)
    #expect(Persona.load(from: file) == Persona.defaultText)
    try Data("You are Gedi.".utf8).write(to: file)
    #expect(Persona.load(from: file) == "You are Gedi.")
}
