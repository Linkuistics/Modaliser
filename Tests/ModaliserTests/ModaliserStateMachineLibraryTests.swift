import Foundation
import Testing
@testable import Modaliser

@Suite("(modaliser state-machine) library")
struct ModaliserStateMachineLibraryTests {
    @Test func overlayOpenMutabilitySmoke() throws {
        // overlay-open? is now a thunk — (overlay-open?) reads the live value.
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser state-machine))")
        #expect(try engine.evaluate("(overlay-open?)") == .false)
        try engine.evaluate("(set-overlay-open! #t)")
        #expect(try engine.evaluate("(overlay-open?)") == .true)
        try engine.evaluate("(set-overlay-open! #f)")
        #expect(try engine.evaluate("(overlay-open?)") == .false)
    }

    @Test func hideOverlayLambdaSeesLiveState() throws {
        // Verify that a lambda defined when overlay is closed correctly
        // reads the live value via (overlay-open?) when called after opening.
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser state-machine))")
        // Install lambda using (overlay-open?) thunk — compiled when overlay is #f
        try engine.evaluate("""
          (set-hide-overlay! (lambda ()
            (when (overlay-open?)
              (set-overlay-open! #f))))
        """)
        // Open the overlay after installing the lambda
        try engine.evaluate("(set-overlay-open! #t)")
        #expect(try engine.evaluate("(overlay-open?)") == .true)
        // Call hide-overlay — the lambda should see #t via the thunk
        try engine.evaluate("(hide-overlay)")
        #expect(try engine.evaluate("(overlay-open?)") == .false)
    }

    @Test func setHideOverlayLambdaCalledDirectly() throws {
        // Verify the installed lambda is actually called
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser state-machine))")
        try engine.evaluate("""
          (define closed #f)
          (set-hide-overlay! (lambda () (set! closed #t)))
        """)
        try engine.evaluate("(hide-overlay)")
        #expect(try engine.evaluate("closed") == .true)
    }

    @Test func registerTreeAndLookupRoundtrip() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser state-machine))
          (register-tree! 'global
            (list (cons 'kind 'command)
                  (cons 'key "s")
                  (cons 'label "Safari")
                  (cons 'action (lambda () 'ok))))
        """)
        #expect(try engine.evaluate("(lookup-tree \"global\")") != .false)
    }

    @Test func setOverlayDelayMutatesParameter() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser state-machine))")
        try engine.evaluate("(set-overlay-delay! 0.25)")
        #expect(try engine.evaluate("(= modal-overlay-delay 0.25)") == .true)
    }
}
