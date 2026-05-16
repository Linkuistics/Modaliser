import Foundation
import Testing
@testable import Modaliser

@Suite("(modaliser keymap) library")
struct ModaliserKeymapLibraryTests {
    @Test func modifierPredicatesReadBitmask() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser keymap) (modaliser keyboard))")
        #expect(try engine.evaluate("(has-cmd? MOD-CMD)") == .true)
        #expect(try engine.evaluate("(has-shift? MOD-CMD)") == .false)
        #expect(try engine.evaluate(
            "(has-shift? (bitwise-ior MOD-CMD MOD-SHIFT))") == .true)
        #expect(try engine.evaluate("(has-alt? 0)") == .false)
    }
}
