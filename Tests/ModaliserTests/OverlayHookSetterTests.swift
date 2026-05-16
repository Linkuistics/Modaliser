import Foundation
import Testing
@testable import Modaliser

@Suite("State-machine overlay hook setters")
struct OverlayHookSetterTests {
    @Test func setShowOverlayReplacesHook() throws {
        let engine = try SchemeEngine()
        guard let dir = engine.schemeDirectoryPath else {
            Issue.record("Scheme directory not found"); return
        }
        // Load via current include path so the test passes after task 4
        // but before tasks 5+ flip the loader.
        try engine.evaluateFile(dir + "/lib/util.scm")
        try engine.evaluateFile(dir + "/core/keymap.scm")
        try engine.evaluateFile(dir + "/core/state-machine.scm")

        try engine.evaluate("""
          (define show-calls '())
          (set-show-overlay! (lambda (root path)
                               (set! show-calls (cons 'show show-calls))))
          (set-overlay-open! #t)
          (show-overlay 'dummy '())
        """)
        #expect(try engine.evaluate("overlay-open?") == .true)
        #expect(try engine.evaluate("(length show-calls)") == .fixnum(1))
    }
}
