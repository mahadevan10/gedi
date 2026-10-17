import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: GediController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let c = try GediController()
            controller = c
            c.start()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Gedi could not start"
            alert.informativeText = String(describing: error)
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.shutdown()
    }
}
