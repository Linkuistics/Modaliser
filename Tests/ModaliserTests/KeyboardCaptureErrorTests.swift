import Testing
@testable import Modaliser

@Suite("KeyboardCaptureError descriptions")
struct KeyboardCaptureErrorTests {
    @Test func accessibilityNotTrustedDescription() {
        let error = KeyboardCaptureError.accessibilityNotTrusted
        #expect(error.description == "Accessibility permission not granted")
    }

    @Test func eventTapCreationFailedDescription() {
        let error = KeyboardCaptureError.eventTapCreationFailed
        #expect(error.description == "Failed to create CGEvent tap")
    }

    @Test func runLoopSourceCreationFailedDescription() {
        let error = KeyboardCaptureError.runLoopSourceCreationFailed
        #expect(error.description == "Failed to create run loop source from event tap")
    }
}
