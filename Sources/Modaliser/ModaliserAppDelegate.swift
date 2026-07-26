import AppKit
import os

/// Bootstrap stub — creates the Scheme engine, loads the root Scheme file, and
/// sequences the user-configuration load.
/// Everything else (activation policy, status bar, permissions, keyboard capture)
/// is handled by the Scheme program via primitives.
final class ModaliserAppDelegate: NSObject, NSApplicationDelegate {
    private var schemeEngine: SchemeEngine?

    private static let logger = Logger(subsystem: LogLibrary.subsystem, category: "boot")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("Modaliser starting (pid=%d, bundle=%@)", ProcessInfo.processInfo.processIdentifier, Bundle.main.bundlePath)
        do {
            let engine = try SchemeEngine()
            schemeEngine = engine
            try engine.loadRootSchemeFile()
            try bootConfiguration(engine)
            NSLog("Modaliser launched — Scheme runtime active")
        } catch {
            // Only a failure of Modaliser's own runtime reaches here: a bad
            // user config degrades instead (ADR-0022). Without root.scm there
            // is no status bar and no keyboard capture, so there is nothing to
            // degrade to — surface it and quit.
            NSLog("Failed to load Scheme runtime: %@", "\(error)")
            Self.logger.fault("Scheme runtime failed to load: \(String(describing: error), privacy: .public)")
            presentFatalError(error)
        }
    }

    /// Load the user's configuration and hand the outcome back to `root.scm`,
    /// which builds the status bar around it.
    ///
    /// The paths come from Scheme rather than being restated here: `root.scm`
    /// owns where a user's config lives, and the bundled default is resolved
    /// against the same Scheme directory the engine booted from (the sys/
    /// mirror in production, the bundle in dev).
    private func bootConfiguration(_ engine: SchemeEngine) throws {
        let userConfigPath = try engine.evaluate("user-config-path").asString()
        let fallbackPath = try engine.evaluate("default-config-path").asString()

        let outcome = engine.loadConfiguration(userConfigPath: userConfigPath,
                                               fallbackPath: fallbackPath)
        let status: String
        switch outcome {
        case .loaded: status = "loaded"
        case .degraded: status = "degraded"
        case .failed: status = "failed"
        }
        let message = Self.schemeString(outcome.errorText ?? "")
        try engine.evaluate("(modaliser:config-load-finished! '\(status) \(message))")
    }

    /// Render `text` as a Scheme string literal.
    private static func schemeString(_ text: String) -> String {
        var escaped = ""
        for character in text {
            switch character {
            case "\\": escaped += "\\\\"
            case "\"": escaped += "\\\""
            case "\n": escaped += "\\n"
            default: escaped.append(character)
            }
        }
        return "\"\(escaped)\""
    }

    private func presentFatalError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Modaliser couldn't start"
        alert.informativeText = "\(error)"
        alert.alertStyle = .critical
        // A shadowing library in the user's config directory is the one
        // user-fixable cause of a runtime failure, so offer the way in.
        alert.addButton(withTitle: "Reveal Config in Finder")
        alert.addButton(withTitle: "Quit")
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let configDir = ("~/.config/modaliser" as NSString).expandingTildeInPath
            NSWorkspace.shared.open(URL(fileURLWithPath: configDir))
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
