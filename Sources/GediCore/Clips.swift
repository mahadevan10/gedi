import Foundation

/// A line the user recorded in their own Thrissur voice.
/// `use` tells the LLM when the clip fits ("user is on Shorts or Reels").
public struct ClipInfo: Codable, Equatable, Sendable {
    public var id: String
    public var file: String
    public var text: String
    public var use: String

    public init(id: String, file: String, text: String, use: String) {
        self.id = id
        self.file = file
        self.text = text
        self.use = use
    }
}

/// The clips folder: `clips.json` (an array of `ClipInfo`) plus the audio files it names.
public struct ClipLibrary: Sendable {
    public let directory: URL
    /// Only clips whose audio file exists.
    public let clips: [ClipInfo]

    public init(directory: URL, clips: [ClipInfo]) {
        self.directory = directory
        self.clips = clips
    }

    public static func empty(at directory: URL) -> ClipLibrary {
        ClipLibrary(directory: directory, clips: [])
    }

    /// No manifest → empty library. Malformed manifest → throws.
    public static func load(from directory: URL) throws -> ClipLibrary {
        let manifest = directory.appendingPathComponent("clips.json")
        guard FileManager.default.fileExists(atPath: manifest.path) else { return .empty(at: directory) }
        let all = try JSONDecoder().decode([ClipInfo].self, from: Data(contentsOf: manifest))
        let present = all.filter {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent($0.file).path)
        }
        return ClipLibrary(directory: directory, clips: present)
    }

    public func clip(id: String) -> ClipInfo? { clips.first { $0.id == id } }

    public func url(for clip: ClipInfo) -> URL { directory.appendingPathComponent(clip.file) }
}
