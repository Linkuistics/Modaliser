import Foundation
import Testing
@testable import Modaliser

@Suite("State-machine overlay hook setters")
struct OverlayHookSetterTests {
    @Test func setShowOverlayReplacesHook() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser state-machine))")

        try engine.evaluate("""
          (define show-calls '())
          (set-show-overlay! (lambda (root path)
                               (set! show-calls (cons 'show show-calls))))
          (set-overlay-open! #t)
          (show-overlay 'dummy '())
        """)
        #expect(try engine.evaluate("(overlay-open?)") == .true)
        #expect(try engine.evaluate("(length show-calls)") == .fixnum(1))
    }
}
