import Testing
@testable import Modaliser

@Suite("KeyCode constants")
struct KeyCodeTests {
    @Test func f17HasCorrectValue() {
        #expect(KeyCode.f17 == 64)
    }

    @Test func f18HasCorrectValue() {
        #expect(KeyCode.f18 == 79)
    }

    @Test func escapeHasCorrectValue() {
        #expect(KeyCode.escape == 53)
    }

    @Test func deleteHasCorrectValue() {
        #expect(KeyCode.delete == 51)
    }

    @Test func returnKeyHasCorrectValue() {
        #expect(KeyCode.returnKey == 36)
    }

    @Test func spaceHasCorrectValue() {
        #expect(KeyCode.space == 49)
    }

    @Test func tabHasCorrectValue() {
        #expect(KeyCode.tab == 48)
    }

    @Test func f19HasCorrectValue() {
        #expect(KeyCode.f19 == 80)
    }

    @Test func f20HasCorrectValue() {
        #expect(KeyCode.f20 == 90)
    }
}
