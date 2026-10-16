import Foundation

/// One observation of what is in front of the user.
public struct ActivitySnapshot: Equatable, Sendable {
    public var appName: String
    public var bundleID: String
    public var url: String?
    public var title: String?

    public init(appName: String, bundleID: String, url: String? = nil, title: String? = nil) {
        self.appName = appName
        self.bundleID = bundleID
        self.url = url
        self.title = title
    }
}

public enum ActivityKind: String, Equatable, Sendable {
    case shortVideo, video, social, chat, coding, call, other
}

/// A snapshot reduced to what Gedi cares about.
/// `name` is the key time is totalled under ("YouTube Shorts", "Visual Studio Code");
/// `detail` is the page title, used only for the "Now:" line.
public struct ClassifiedActivity: Equatable, Sendable {
    public var kind: ActivityKind
    public var name: String
    public var detail: String?

    public init(kind: ActivityKind, name: String, detail: String? = nil) {
        self.kind = kind
        self.name = name
        self.detail = detail
    }
}

public enum ActivityClassifier {
    public static func classify(_ s: ActivitySnapshot) -> ClassifiedActivity {
        if let raw = s.url, let url = URL(string: raw), let host = url.host?.lowercased() {
            return classifyWeb(host: strip(host), path: url.path.lowercased(), title: s.title, appName: s.appName)
        }
        return ClassifiedActivity(kind: appKind(s.bundleID), name: s.appName, detail: s.title)
    }

    private static func strip(_ host: String) -> String {
        for prefix in ["www.", "m."] where host.hasPrefix(prefix) {
            return String(host.dropFirst(prefix.count))
        }
        return host
    }

    private static func classifyWeb(host: String, path: String, title: String?, appName: String) -> ClassifiedActivity {
        func make(_ kind: ActivityKind, _ name: String) -> ClassifiedActivity {
            ClassifiedActivity(kind: kind, name: name, detail: title)
        }
        switch host {
        case "youtube.com":
            if path.hasPrefix("/shorts") { return make(.shortVideo, "YouTube Shorts") }
            return make(.video, "YouTube")
        case "instagram.com":
            if path.hasPrefix("/reels") || path.hasPrefix("/reel/") { return make(.shortVideo, "Instagram Reels") }
            return make(.social, "Instagram")
        case "facebook.com":
            if path.hasPrefix("/reel") { return make(.shortVideo, "Facebook Reels") }
            return make(.social, "Facebook")
        case "tiktok.com": return make(.shortVideo, "TikTok")
        case "netflix.com": return make(.video, "Netflix")
        case "primevideo.com": return make(.video, "Prime Video")
        case "hotstar.com", "jiohotstar.com": return make(.video, "Hotstar")
        case "x.com", "twitter.com": return make(.social, "X")
        case "reddit.com": return make(.social, "Reddit")
        case "linkedin.com": return make(.social, "LinkedIn")
        case "meet.google.com": return make(.call, "Google Meet")
        case "web.whatsapp.com": return make(.chat, "WhatsApp")
        case "web.telegram.org": return make(.chat, "Telegram")
        case "discord.com": return make(.chat, "Discord")
        case "app.slack.com": return make(.chat, "Slack")
        case "github.com": return make(.coding, "GitHub")
        case "stackoverflow.com": return make(.coding, "Stack Overflow")
        case "developer.apple.com": return make(.coding, "Apple Developer docs")
        case "localhost", "127.0.0.1": return make(.coding, "localhost")
        default: return make(.other, host)
        }
    }

    private static let codingApps: Set<String> = [
        "com.microsoft.VSCode", "com.apple.dt.Xcode", "com.todesktop.230313mzl4w4u92",
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty",
    ]
    private static let callApps: Set<String> = [
        "us.zoom.xos", "com.apple.FaceTime", "com.microsoft.teams2", "com.microsoft.teams",
    ]
    private static let chatApps: Set<String> = [
        "net.whatsapp.WhatsApp", "com.tinyspeck.slackmacgap", "ru.keepcoder.Telegram", "com.hnc.Discord",
    ]

    private static func appKind(_ bundleID: String) -> ActivityKind {
        if codingApps.contains(bundleID) || bundleID.hasPrefix("com.jetbrains.") { return .coding }
        if callApps.contains(bundleID) { return .call }
        if chatApps.contains(bundleID) { return .chat }
        return .other
    }
}
