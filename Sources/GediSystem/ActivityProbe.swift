import AppKit
import Foundation
import GediCore

/// Reads the frontmost app and, for Chrome/Safari, the active tab's URL and title.
/// Only the frontmost browser is queried, so AppleScript never launches a browser.
/// The first query triggers macOS's "Gedi wants to control Google Chrome" prompt.
@MainActor
public struct ActivityProbe {
    public init() {}

    public func snapshot() -> ActivitySnapshot? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let bundleID = app.bundleIdentifier ?? ""
        var snap = ActivitySnapshot(appName: app.localizedName ?? bundleID, bundleID: bundleID)
        switch bundleID {
        case "com.google.Chrome":
            (snap.url, snap.title) = Self.run("tell application id \"com.google.Chrome\" to get {URL, title} of active tab of front window")
        case "com.apple.Safari":
            (snap.url, snap.title) = Self.run("tell application id \"com.apple.Safari\" to get {URL, name} of front document")
        default:
            break
        }
        return snap
    }

    /// Runs a script returning a two-item list. (nil, nil) on any error, e.g. no windows
    /// open or Automation permission denied.
    private static func run(_ source: String) -> (String?, String?) {
        var error: NSDictionary?
        guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error),
              result.numberOfItems == 2 else { return (nil, nil) }
        return (result.atIndex(1)?.stringValue, result.atIndex(2)?.stringValue)
    }
}
