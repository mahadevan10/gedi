import Foundation

/// What the LLM decided to say. `speak == false` means "stay quiet this time".
/// `clip` is the id of a pre-recorded clip to play instead of synthesising `line`.
public struct GediReply: Codable, Equatable, Sendable {
    public var speak: Bool
    public var line: String
    public var clip: String?

    public init(speak: Bool, line: String, clip: String? = nil) {
        self.speak = speak
        self.line = line
        self.clip = clip
    }

    /// Lenient parser for model output. Accepts clean JSON, JSON wrapped in other text,
    /// or (as a last resort) bare Malayalam text. Returns nil for anything unusable.
    public static func parse(_ raw: String) -> GediReply? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = decode(text) { return r }
        if let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close,
           let r = decode(String(text[open...close])) {
            return r
        }
        if text.unicodeScalars.contains(where: { (0x0D00...0x0D7F).contains($0.value) }) {
            return GediReply(speak: true, line: text)
        }
        return nil
    }

    private static func decode(_ s: String) -> GediReply? {
        guard var r = try? JSONDecoder().decode(GediReply.self, from: Data(s.utf8)) else { return nil }
        r.line = r.line.trimmingCharacters(in: .whitespacesAndNewlines)
        if let c = r.clip?.trimmingCharacters(in: .whitespaces), c.isEmpty || c == "none" { r.clip = nil }
        if r.line.isEmpty && r.clip == nil { r.speak = false }
        return r
    }
}
