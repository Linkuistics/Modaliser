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
            // Surface config errors visibly — silent failure left the user
            // wondering why the overlay never showed. The alert blocks
            // until acknowledged; "Open Config" opens the user's config
            // in the default app so the line/column references in the
            // error message can be acted on immediately.
            NSLog("Failed to load Scheme runtime: %@", "\(error)")
            presentConfigError(error)
        }
    }

    private func presentConfigError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Modaliser couldn't load your configuration"
        alert.informativeText = "\(error)"
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Open Config")
        alert.addButton(withTitle: "Quit")
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let configPath = ("~/.config/modaliser/config.scm" as NSString).expandingTildeInPath
            NSWorkspace.shared.open(URL(fileURLWithPath: configPath))
        }
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSLog("Modaliser shutting down")
    }

    /// If we're inside a modal session (e.g. the permission onboarding panel), stop it
    /// so the run loop can unwind cleanly. Required for system-initiated quits such as
    /// the "Quit & Reopen" prompt that macOS shows after granting Screen Recording.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if NSApp.modalWindow != nil {
            NSApp.stopModal()
        }
        return .terminateNow
    }
}
