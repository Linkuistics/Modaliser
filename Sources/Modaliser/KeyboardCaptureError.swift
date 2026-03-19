/// Errors that can occur when starting keyboard capture.
enum KeyboardCaptureError: Error, CustomStringConvertible {
    case accessibilityNotTrusted
    case eventTapCreationFailed
    case runLoopSourceCreationFailed

    var description: String {
        switch self {
        case .accessibilityNotTrusted:
            "Accessibility permission not granted"
        case .eventTapCreationFailed:
            "Failed to create CGEvent tap"
        case .runLoopSourceCreationFailed:
            "Failed to create run loop source from event tap"
        }
    }
}
