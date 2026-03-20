import AppKit

/// Shows an alert when Scheme config evaluation fails.
enum ConfigErrorAlert {

    /// Display an alert with the config error message.
    /// Does not terminate — the app continues with whatever config was loaded.
    static func show(error: Error) {
        let alert = NSAlert()
        alert.messageText = "Config Error"
        alert.informativeText = "Failed to load config.scm:\n\n\(error)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
