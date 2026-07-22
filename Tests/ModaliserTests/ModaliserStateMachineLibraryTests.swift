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

    // run-on-leave's reason-vs-no-reason dispatch is gated by a host-injected
    // arity predicate (set-on-leave-accepts-reason!) so the library stays
    // host-portable. The default — no host install — must assume nullary, the
    // legacy behaviour: a 0-arg on-leave hook is called with no args.
    @Test func runOnLeaveDefaultPredicateCallsNullaryHook() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser state-machine))")
        try engine.evaluate("""
          (define nullary-called #f)
          (define n (list (cons 'on-leave (lambda () (set! nullary-called #t)))))
          (run-on-leave n 'confirm)
        """)
        #expect(try engine.evaluate("nullary-called") == .true)
    }

    // With the host's real arity predicate installed (mirroring root.scm's boot
    // wiring), a 1-arg on-leave hook receives the exit reason and a 0-arg hook
    // is still called with none — never an arity error.
    @Test func runOnLeaveInstalledPredicateDispatchesByArity() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser state-machine))")
        try engine.evaluate(
          "(set-on-leave-accepts-reason! (lambda (t) (procedure-arity-includes? t 1)))")
        // 1-arg hook receives the reason.
        try engine.evaluate("""
          (define reason-seen 'unset)
          (define n1 (list (cons 'on-leave (lambda (r) (set! reason-seen r)))))
          (run-on-leave n1 'confirm)
        """)
        #expect(try engine.evaluate("(eq? reason-seen 'confirm)") == .true)
        // 0-arg hook is called with no args (no arity error).
        try engine.evaluate("""
          (define nullary-called #f)
          (define n0 (list (cons 'on-leave (lambda () (set! nullary-called #t)))))
          (run-on-leave n0 'cancel)
        """)
        #expect(try engine.evaluate("nullary-called") == .true)
    }

    // Regression for narrowed-legend-k45: navigate-to-path (the overlay's
    // read-only "current node at path" rendering contract, retained after
    // dispatch-cutover-k11 for render-overlay-body/push-overlay-update/
    // current-node-renderer, all in ui/overlay.scm) only ever walked the
    // PERMANENT alist tree via find-child — blind to a PROVIDED (visit-
    // scoped) resting state, since one is never part of that tree, only
    // %fsm-visit-provided for the Visit that minted it. A live TestAnyware
    // pass on herdr's jump-label narrowing found this in the wild: the new
    // narrowed Jump-legend panel (jump-prefix-state's payload carrying
    // 'renderer 'panel-grid + a 'children category) rendered as an EMPTY
    // overlay body the instant a leader narrowed, even though
    // fsm-resolved-payload (fsm.sld) already resolves that exact payload
    // correctly — because navigate-to-path never consulted it. This is a
    // minimal fixture reproducing the same shape (a root's 'provider
    // minting one provided resting state one level down), independent of
    // herdr, proving navigate-to-path now falls back to the provided
    // state's own resolved payload instead of #f.
    @Test func navigateToPathFallsBackToProvidedRestingStatesPayload() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine) (modaliser fsm))")
        try engine.evaluate(#"""
          (register-tree! 'narrow-fallback-test
            'provider (lambda ()
                        (list (cons 'edges (list (edge "a" "narrow-fallback-test/a")))
                              (cons 'states
                                (list (provided-state "narrow-fallback-test/a"
                                        'payload (list (cons 'renderer 'panel-grid)
                                                       (cons 'children
                                                         (list (panel "Jump"
                                                                 (list (cons 'type 'stub-block))))))
                                        (edge 'up 'narrow-fallback-test)))))))
          (modal-enter (lookup-tree "narrow-fallback-test") F18)
          (define RESOLVED
            (navigate-to-path (lookup-tree "narrow-fallback-test") (list "a")))
        """#)
        #expect(try engine.evaluate("(not (eq? RESOLVED #f))") == .true)
        #expect(try engine.evaluate("(eq? (node-renderer RESOLVED) 'panel-grid)") == .true)
        #expect(try engine.evaluate("(length (node-children RESOLVED))") == .fixnum(1))
        #expect(try engine.evaluate(
            "(equal? (node-label (car (node-children RESOLVED))) \"Jump\")") == .true)
        try engine.evaluate("(modal-exit)")
    }

    // A path with no static child AND no live provided state at that id
    // (a genuinely unknown key, or a root with no 'scope at all) must keep
    // degrading to #f exactly as before — the fallback only ever ADDS a
    // resolution path, never changes an existing #f into something else
    // spurious.
    @Test func navigateToPathStillReturnsFalseForAnUnknownKey() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine))")
        try engine.evaluate("(register-tree! 'no-provider-test (key \"a\" \"A\" (lambda () 'ok)))")
        #expect(try engine.evaluate(
            "(navigate-to-path (lookup-tree \"no-provider-test\") (list \"z\"))") == .false)
    }
}
