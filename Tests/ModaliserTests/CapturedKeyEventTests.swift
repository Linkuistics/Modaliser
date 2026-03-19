import Testing
import CoreGraphics
@testable import Modaliser

@Suite("CapturedKeyEvent")
struct CapturedKeyEventTests {
    @Test func keyDownEventReportsIsKeyDown() {
        let event = CapturedKeyEvent(
            keyCode: KeyCode.f18,
            isKeyDown: true,
            modifiers: CGEventFlags()
        )
        #expect(event.isKeyDown == true)
        #expect(event.isKeyUp == false)
    }

    @Test func keyUpEventReportsIsKeyUp() {
        let event = CapturedKeyEvent(
            keyCode: KeyCode.f18,
            isKeyDown: false,
            modifiers: CGEventFlags()
        )
        #expect(event.isKeyDown == false)
        #expect(event.isKeyUp == true)
    }

    @Test func capturedKeyEventPreservesKeyCode() {
        let event = CapturedKeyEvent(
            keyCode: KeyCode.escape,
            isKeyDown: true,
            modifiers: CGEventFlags()
        )
        #expect(event.keyCode == KeyCode.escape)
    }

    @Test func capturedKeyEventPreservesModifiers() {
        let modifiers: CGEventFlags = [.maskCommand, .maskShift]
        let event = CapturedKeyEvent(
            keyCode: 0,
            isKeyDown: true,
            modifiers: modifiers
        )
        #expect(event.modifiers.contains(.maskCommand))
        #expect(event.modifiers.contains(.maskShift))
    }
}
