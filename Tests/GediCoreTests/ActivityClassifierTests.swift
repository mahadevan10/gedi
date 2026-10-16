import Testing
@testable import GediCore

private func chrome(_ url: String, _ title: String = "t") -> ActivitySnapshot {
    ActivitySnapshot(appName: "Google Chrome", bundleID: "com.google.Chrome", url: url, title: title)
}

@Test func youtubeShortsIsShortVideo() {
    let a = ActivityClassifier.classify(chrome("https://www.youtube.com/shorts/abc123", "funny cat"))
    #expect(a == ClassifiedActivity(kind: .shortVideo, name: "YouTube Shorts", detail: "funny cat"))
}

@Test func youtubeWatchIsVideo() {
    #expect(ActivityClassifier.classify(chrome("https://youtube.com/watch?v=x")).kind == .video)
}

@Test func instagramReelsVsFeed() {
    #expect(ActivityClassifier.classify(chrome("https://www.instagram.com/reels/xyz/")).name == "Instagram Reels")
    #expect(ActivityClassifier.classify(chrome("https://www.instagram.com/reel/xyz/")).kind == .shortVideo)
    #expect(ActivityClassifier.classify(chrome("https://www.instagram.com/")).kind == .social)
}

@Test func mobileHostPrefixIsStripped() {
    #expect(ActivityClassifier.classify(chrome("https://m.youtube.com/shorts/q")).kind == .shortVideo)
}

@Test func meetIsCall() {
    #expect(ActivityClassifier.classify(chrome("https://meet.google.com/abc-defg-hij")).kind == .call)
}

@Test func unknownSiteUsesHostAsName() {
    let a = ActivityClassifier.classify(chrome("https://news.ycombinator.com/item?id=1"))
    #expect(a.kind == .other)
    #expect(a.name == "news.ycombinator.com")
}

@Test func codingAppsWithoutURL() {
    let vscode = ActivitySnapshot(appName: "Visual Studio Code", bundleID: "com.microsoft.VSCode")
    #expect(ActivityClassifier.classify(vscode) == ClassifiedActivity(kind: .coding, name: "Visual Studio Code"))
    let idea = ActivitySnapshot(appName: "IntelliJ IDEA", bundleID: "com.jetbrains.intellij")
    #expect(ActivityClassifier.classify(idea).kind == .coding)
}

@Test func zoomIsCall() {
    let zoom = ActivitySnapshot(appName: "zoom.us", bundleID: "us.zoom.xos")
    #expect(ActivityClassifier.classify(zoom).kind == .call)
}

@Test func unknownAppIsOther() {
    let notes = ActivitySnapshot(appName: "Notes", bundleID: "com.apple.Notes")
    #expect(ActivityClassifier.classify(notes) == ClassifiedActivity(kind: .other, name: "Notes"))
}
