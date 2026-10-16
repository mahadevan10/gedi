import AppKit

/// Menu-bar item "ഗഡി" with Mute / Comment now / Quit.
@MainActor
final class StatusMenu: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let muteItem = NSMenuItem(title: "Mute comments", action: #selector(toggleMute), keyEquivalent: "")
    private let onMuteChanged: (Bool) -> Void
    private let onCommentNow: () -> Void

    init(onMuteChanged: @escaping (Bool) -> Void, onCommentNow: @escaping () -> Void) {
        self.onMuteChanged = onMuteChanged
        self.onCommentNow = onCommentNow
        super.init()
        item.button?.title = "ഗഡി"
        let menu = NSMenu()
        muteItem.target = self
        menu.addItem(muteItem)
        let now = NSMenuItem(title: "Comment now", action: #selector(commentNow), keyEquivalent: "")
        now.target = self
        menu.addItem(now)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Gedi", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
    }

    @objc private func toggleMute() {
        muteItem.state = muteItem.state == .on ? .off : .on
        onMuteChanged(muteItem.state == .on)
    }

    @objc private func commentNow() {
        onCommentNow()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
