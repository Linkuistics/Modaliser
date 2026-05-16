import Foundation
import Testing
@testable import Modaliser

@Suite("(modaliser leader) library")
struct ModaliserLeaderLibraryTests {
    @Test func setGlobalLeaderRunsWithoutError() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser keyboard) (modaliser leader))")
        // No exception → success. Use F18 which is defined in (modaliser keyboard).
        try engine.evaluate("(set-global-leader! F18)")
        try engine.evaluate("(set-global-leader! F18 'modifiers '(shift))")
    }

    @Test func setLocalLeaderRunsWithoutError() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser keyboard) (modaliser leader))")
        try engine.evaluate("(set-local-leader! F17 'arm-when-frontmost '(\"com.example.app\"))")
    }

    @Test func setLeadersBothScopes() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser keyboard) (modaliser leader))")
        try engine.evaluate("""
          (set-leaders! 'global-keycode F18
                        'local-keycode  F17
                        'modifiers '(shift))
        """)
    }

    @Test func setLeadersGlobalOnly() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser keyboard) (modaliser leader))")
        try engine.evaluate("(set-leaders! 'global-keycode F18 'modifiers '(shift))")
    }
}
