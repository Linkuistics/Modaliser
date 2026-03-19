import Testing
@testable import Modaliser

@Suite("KeyboardCapture.CaptureError descriptions")
struct KeyboardCaptureErrorTests {
    @Test func accessibilityNotTrustedDescription() {
        let error = KeyboardCapture.CaptureError.accessibilityNotTrusted
        #expect(error.description == "Accessibility permission not granted")
    }

    @Test func eventTapCreationFailedDescription() {
        let error = KeyboardCapture.CaptureError.eventTapCreationFailed
        #expect(error.description == "Failed to create CGEvent tap")
    }

    @Test func runLoopSourceCreationFailedDescription() {
        let error = KeyboardCapture.CaptureError.runLoopSourceCreationFailed
        #expect(error.description == "Failed to create run loop source from event tap")
    }
}
