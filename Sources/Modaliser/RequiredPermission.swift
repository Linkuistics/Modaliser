import AppKit
import ApplicationServices
import CoreGraphics

/// A macOS TCC permission required by Modaliser.
/// Each case owns its own status check, deep-link URL, and TCC-registration call.
enum RequiredPermission: String, CaseIterable {
    case accessibility
    case screenRecording

    var displayName: String {
        switch self {
        case .accessibility: return "Accessibility"
        case .screenRecording: return "Screen Recording"
        }
    }

    var rationale: String {
        switch self {
        case .accessibility:
            return "Capture global keyboard shortcuts and manipulate windows."
        case .screenRecording:
            return "Read window titles for the window switcher."
        }
    }

    var settingsURL: URL {
        switch self {
        case .accessibility:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        case .screenRecording:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        }
    }

    var isGranted: Bool {
        switch self {
        case .accessibility:
            return AXIsProcessTrusted()
        case .screenRecording:
            return CGPreflightScreenCaptureAccess()
        }
    }

    /// Register the bundle with TCC so it appears in the relevant System Settings pane.
    /// Safe to call when already granted.
    ///
    /// Accessibility uses the prompt-less variant of `AXIsProcessTrustedWithOptions`,
    /// which registers without a system dialog. Screen Recording has no equivalent —
    /// `CGPreflightScreenCaptureAccess` only checks status, it doesn't add the bundle
    /// to the Settings list. We have to call `CGRequestScreenCaptureAccess`, which
    /// registers AND fires the system prompt the first time. That prompt is one-time
    /// per code-signing identity; subsequent launches are silent.
    func registerWithTCC() {
        switch self {
        case .accessibility:
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        case .screenRecording:
            if !CGPreflightScreenCaptureAccess() {
                _ = CGRequestScreenCaptureAccess()
            }
        }
    }

    static func parse(symbol: String) -> RequiredPermission? {
        switch symbol {
        case "accessibility": return .accessibility
        case "screen-recording": return .screenRecording
        default: return nil
        }
    }
}
