import AppKit

MainActor.assumeIsolated {
    let args = CommandLine.arguments
    if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
        do {
            try Snapshot.write(to: URL(fileURLWithPath: args[i + 1]))
            exit(0)
        } catch {
            print("snapshot failed: \(error)")
            exit(1)
        }
    }

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)  // menu-bar app: no Dock icon
    app.run()
}
