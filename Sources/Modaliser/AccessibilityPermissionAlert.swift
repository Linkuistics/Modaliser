import AppKit

/// Presents an alert when Accessibility permission is not granted.
/// Offers to open System Settings. Does NOT terminate — the app stays
/// alive so the user can grant permission and use Relaunch from the menu bar.
enum AccessibilityPermissionAlert {

    static func show() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "Modaliser needs Accessibility access to capture global keyboard events.\n\nGrant access in System Settings > Privacy & Security > Accessibility, then use Relaunch from the menu bar icon."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "OK")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
