import AppKit

/// Bootstrap stub — creates the Scheme engine and loads the root Scheme file.
/// Everything else (activation policy, status bar, permissions, keyboard capture)
/// is handled by the Scheme program via primitives.
final class ModaliserAppDelegate: NSObject, NSApplicationDelegate {
    private var schemeEngine: SchemeEngine?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("Modaliser starting (pid=%d, bundle=%@)", ProcessInfo.processInfo.processIdentifier, Bundle.main.bundlePath)
        do {
            let engine = try SchemeEngine()
            schemeEngine = engine
            try engine.loadRootSchemeFile()
            NSLog("Modaliser launched — Scheme runtime active")
        } catch {
            NSLog("Failed to load Scheme runtime: %@", "\(error)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSLog("Modaliser shutting down")
    }
}
