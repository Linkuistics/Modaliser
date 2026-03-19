import ApplicationServices

/// Checks and requests macOS Accessibility permissions required for CGEvent tap.
enum AccessibilityPermission {
    /// Returns true if the process has Accessibility access.
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the user to grant Accessibility access if not already granted.
    /// Shows the system permission dialog with a prompt pointing to System Settings.
    /// Returns true if already trusted.
    @discardableResult
    static func requestIfNeeded() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
