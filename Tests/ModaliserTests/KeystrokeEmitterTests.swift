import Testing
@testable import Modaliser

@Suite("KeystrokeEmitter")
struct KeystrokeEmitterTests {

    // MARK: - Character to key code lookup

    @Test func keyCodeForLetters() {
        #expect(KeystrokeEmitter.keyCode(for: "a") == 0)
        #expect(KeystrokeEmitter.keyCode(for: "s") == 1)
        #expect(KeystrokeEmitter.keyCode(for: "z") == 6)
        #expect(KeystrokeEmitter.keyCode(for: "m") == 46)
    }

    @Test func keyCodeForDigits() {
        #expect(KeystrokeEmitter.keyCode(for: "0") == 29)
        #expect(KeystrokeEmitter.keyCode(for: "1") == 18)
        #expect(KeystrokeEmitter.keyCode(for: "9") == 25)
    }

    @Test func keyCodeForPunctuation() {
        #expect(KeystrokeEmitter.keyCode(for: " ") == 49)
        #expect(KeystrokeEmitter.keyCode(for: "-") == 27)
        #expect(KeystrokeEmitter.keyCode(for: "/") == 44)
    }

    @Test func keyCodeIsCaseInsensitive() {
        #expect(KeystrokeEmitter.keyCode(for: "A") == 0)
        #expect(KeystrokeEmitter.keyCode(for: "T") == 17)
    }

    @Test func keyCodeForUnknownCharacterReturnsNil() {
        #expect(KeystrokeEmitter.keyCode(for: "€") == nil)
        #expect(KeystrokeEmitter.keyCode(for: "🎹") == nil)
    }

    // MARK: - Named key lookup

    @Test func namedKeyArrows() {
        #expect(KeystrokeEmitter.keyCode(forNamedKey: "left") == 123)
        #expect(KeystrokeEmitter.keyCode(forNamedKey: "right") == 124)
        #expect(KeystrokeEmitter.keyCode(forNamedKey: "up") == 126)
        #expect(KeystrokeEmitter.keyCode(forNamedKey: "down") == 125)
    }

    @Test func namedKeySpecials() {
        #expect(KeystrokeEmitter.keyCode(forNamedKey: "return") == 36)
        #expect(KeystrokeEmitter.keyCode(forNamedKey: "tab") == 48)
        #expect(KeystrokeEmitter.keyCode(forNamedKey: "escape") == 53)
        #expect(KeystrokeEmitter.keyCode(forNamedKey: "space") == 49)
        #expect(KeystrokeEmitter.keyCode(forNamedKey: "delete") == 51)
    }

    @Test func namedKeyAliases() {
        #expect(KeystrokeEmitter.keyCode(forNamedKey: "enter") == 36)
        #expect(KeystrokeEmitter.keyCode(forNamedKey: "esc") == 53)
        #expect(KeystrokeEmitter.keyCode(forNamedKey: "backspace") == 51)
    }

    @Test func namedKeyIsCaseInsensitive() {
        #expect(KeystrokeEmitter.keyCode(forNamedKey: "Left") == 123)
        #expect(KeystrokeEmitter.keyCode(forNamedKey: "RETURN") == 36)
    }

    @Test func namedKeyForUnknownReturnsNil() {
        #expect(KeystrokeEmitter.keyCode(forNamedKey: "nonexistent") == nil)
    }

    @Test func namedKeyModifiers() {
        #expect(KeystrokeEmitter.keyCode(forNamedKey: "ctrl") == 59)
        #expect(KeystrokeEmitter.keyCode(forNamedKey: "control") == 59)
        #expect(KeystrokeEmitter.keyCode(forNamedKey: "shift") == 56)
        #expect(KeystrokeEmitter.keyCode(forNamedKey: "cmd") == 55)
        #expect(KeystrokeEmitter.keyCode(forNamedKey: "command") == 55)
        #expect(KeystrokeEmitter.keyCode(forNamedKey: "alt") == 58)
        #expect(KeystrokeEmitter.keyCode(forNamedKey: "option") == 58)
    }

    // MARK: - Modifier key codes (bracket-order helper)

    @Test func modifierKeyCodesSingleFlag() {
        #expect(KeystrokeEmitter.modifierKeyCodes(in: .maskControl).map(\.0) == [59])
    }

    @Test func modifierKeyCodesMultipleFlagsAreOrdered() {
        let codes = KeystrokeEmitter.modifierKeyCodes(in: [.maskCommand, .maskControl, .maskShift]).map(\.0)
        #expect(codes == [59, 56, 55])  // control, shift, command — stable order, not insertion order
    }

    @Test func modifierKeyCodesEmpty() {
        #expect(KeystrokeEmitter.modifierKeyCodes(in: []).isEmpty)
    }

    // MARK: - Modifier flag for a keycode (held-modifier tracking)

    @Test func modifierFlagForModifierKeycodes() {
        #expect(KeystrokeEmitter.modifierFlag(forKeyCode: 59) == .maskControl)
        #expect(KeystrokeEmitter.modifierFlag(forKeyCode: 56) == .maskShift)
        #expect(KeystrokeEmitter.modifierFlag(forKeyCode: 55) == .maskCommand)
        #expect(KeystrokeEmitter.modifierFlag(forKeyCode: 58) == .maskAlternate)
    }

    @Test func modifierFlagForNonModifierIsEmpty() {
        #expect(KeystrokeEmitter.modifierFlag(forKeyCode: 48) == [])  // tab
        #expect(KeystrokeEmitter.modifierFlag(forKeyCode: 0) == [])   // a
    }

    // MARK: - Consistency with KeyCodeMapping

    @Test func characterLookupMatchesKeyCodeMapping() throws {
        // Verify the reverse mapping is consistent with the forward mapping
        let letters = "abcdefghijklmnopqrstuvwxyz"
        let engine = try SchemeEngine()
        for char in letters {
            let charStr = String(char)
            if let keyCode = KeystrokeEmitter.keyCode(for: charStr) {
                let forward = try engine.evaluate("(keycode->char \(keyCode))")
                if let mappedStr = try? forward.asString() {
                    #expect(mappedStr == charStr, "Mismatch for '\(charStr)': keyCode \(keyCode) maps back to '\(mappedStr)'")
                }
            }
        }
    }
}
