import Foundation

/// User-tunable settings. Read from `~/Library/Application Support/Gedi/config.json`;
/// any key missing from the file falls back to `GediConfig.default`.
public struct GediConfig: Codable, Equatable, Sendable {
    public var model: String
    public var ollamaURL: URL
    public var commentIntervalSeconds: Double
    public var localeID: String
    public var wakeWords: [String]
    public var silenceSeconds: Double
    public var followUpSeconds: Double
    public var piperPython: String
    public var piperVoice: String
    public var piperDataDir: String
    public var piperPort: Int
    /// OpenAI-compatible hosted brain (Gemini by default); `null` in config.json → local Ollama.
    public var chatURL: URL?
    public var chatAPIKey: String?
    /// Tried in order when the main brain fails (rate limit, outage, bad reply).
    public var fallbacks: [ChatEndpoint]

    public init(
        model: String,
        ollamaURL: URL,
        commentIntervalSeconds: Double,
        localeID: String,
        wakeWords: [String],
        silenceSeconds: Double,
        followUpSeconds: Double,
        piperPython: String,
        piperVoice: String,
        piperDataDir: String,
        piperPort: Int,
        chatURL: URL? = nil,
        chatAPIKey: String? = nil,
        fallbacks: [ChatEndpoint] = []
    ) {
        self.model = model
        self.ollamaURL = ollamaURL
        self.commentIntervalSeconds = commentIntervalSeconds
        self.localeID = localeID
        self.wakeWords = wakeWords
        self.silenceSeconds = silenceSeconds
        self.followUpSeconds = followUpSeconds
        self.piperPython = piperPython
        self.piperVoice = piperVoice
        self.piperDataDir = piperDataDir
        self.piperPort = piperPort
        self.chatURL = chatURL
        self.chatAPIKey = chatAPIKey
        self.fallbacks = fallbacks
    }

    public static let `default` = GediConfig(
        model: "gemini-flash-latest",
        ollamaURL: URL(string: "http://127.0.0.1:11434")!,
        commentIntervalSeconds: 30,
        localeID: "ml-IN",
        wakeWords: ["gadi", "gadhi", "gade", "gedi", "gedhi", "gede", "ഗഡി", "ഗെഡി"],
        silenceSeconds: 1.5,
        followUpSeconds: 8,
        piperPython: "~/Library/Application Support/Gedi/piper-venv/bin/python",
        piperVoice: "ml_IN-arjun-medium",
        piperDataDir: "~/Library/Application Support/Gedi/voices",
        piperPort: 5917,
        chatURL: URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/")!
    )

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GediConfig.default
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? d.model
        ollamaURL = try c.decodeIfPresent(URL.self, forKey: .ollamaURL) ?? d.ollamaURL
        commentIntervalSeconds = try c.decodeIfPresent(Double.self, forKey: .commentIntervalSeconds) ?? d.commentIntervalSeconds
        localeID = try c.decodeIfPresent(String.self, forKey: .localeID) ?? d.localeID
        wakeWords = try c.decodeIfPresent([String].self, forKey: .wakeWords) ?? d.wakeWords
        silenceSeconds = try c.decodeIfPresent(Double.self, forKey: .silenceSeconds) ?? d.silenceSeconds
        followUpSeconds = try c.decodeIfPresent(Double.self, forKey: .followUpSeconds) ?? d.followUpSeconds
        piperPython = try c.decodeIfPresent(String.self, forKey: .piperPython) ?? d.piperPython
        piperVoice = try c.decodeIfPresent(String.self, forKey: .piperVoice) ?? d.piperVoice
        piperDataDir = try c.decodeIfPresent(String.self, forKey: .piperDataDir) ?? d.piperDataDir
        piperPort = try c.decodeIfPresent(Int.self, forKey: .piperPort) ?? d.piperPort
        // Present-but-null must stay nil (Ollama), so only an absent key takes the default.
        chatURL = c.contains(.chatURL) ? try c.decodeIfPresent(URL.self, forKey: .chatURL) : d.chatURL
        chatAPIKey = try c.decodeIfPresent(String.self, forKey: .chatAPIKey)
        fallbacks = try c.decodeIfPresent([ChatEndpoint].self, forKey: .fallbacks) ?? d.fallbacks
    }

    /// The brain this config asks for: hosted when `chatURL` is set, local Ollama otherwise,
    /// wrapped in a `ChatRouter` when `fallbacks` lists backups.
    public func chatModel() -> any ChatModel {
        let primary: any ChatModel = chatURL.map { OpenAIClient(baseURL: $0, apiKey: chatAPIKey ?? "", model: model) }
            ?? OllamaClient(baseURL: ollamaURL, model: model)
        return fallbacks.isEmpty ? primary : ChatRouter([primary] + fallbacks.map { $0.client() })
    }

    /// Missing file → defaults. Malformed file → throws (so a typo is reported, not silently ignored).
    public static func load(from url: URL) throws -> GediConfig {
        guard FileManager.default.fileExists(atPath: url.path) else { return .default }
        return try JSONDecoder().decode(GediConfig.self, from: Data(contentsOf: url))
    }
}

/// Where Gedi keeps user files.
public enum GediPaths {
    public static var supportDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Gedi", isDirectory: true)
    }
    /// `GEDI_CONFIG=/path/to/config.json` overrides the location (handy for testing).
    public static var configFile: URL {
        if let override = ProcessInfo.processInfo.environment["GEDI_CONFIG"], !override.isEmpty {
            return URL(fileURLWithPath: expand(override))
        }
        return supportDir.appendingPathComponent("config.json")
    }
    public static var personaFile: URL { supportDir.appendingPathComponent("persona.md") }
    public static var clipsDir: URL { supportDir.appendingPathComponent("clips", isDirectory: true) }

    /// Expands a leading `~` in paths from the config file.
    public static func expand(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}
