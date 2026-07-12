import Foundation
import Testing
@testable import Modaliser

/// Tests for `(modaliser muxes zellij)` — the zellij backend behind the
/// (modaliser terminal) façade.
///
/// These tests run without a zellij session being attached. The shell-out
/// helpers cleanly return #f or empty in that case, which is the
/// contract the façade expects, so we can verify wiring and registration
/// end-to-end without a real session. Hand-verification of the 14 ops
/// against a live iTerm + zellij session is the leaf's separate
/// "Done when" item.
@Suite("(modaliser muxes zellij) library")
struct ModaliserMuxesZellijLibraryTests {
    @Test func importsAndExposesProcedures() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes zellij))")
        // The only public exports are register! and backend; the ops
        // live on the façade, not here. Both must bind without error.
        _ = try engine.evaluate("register!")
        _ = try engine.evaluate("backend")
    }

    /// (register!) installs the backend into the façade's registry,
    /// keyed by 'zellij + match-key "zellij". With a stubbed host
    /// pointing at the bundle and reporting "zellij" as its foreground
    /// command, the façade walks the path and the leaf is this backend.
    @Test func registerInstallsZellijBackend() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser dsl) (modaliser state-machine)
                  (modaliser muxes zellij) (modaliser terminal))
        """)
        try engine.evaluate("(register!)")

        // A stub host that claims zellij is in the focused pane. The path
        // walk descends from host into the zellij backend; without a live
        // zellij session the backend's detect-fg returns #f, so it sits
        // at the leaf naturally.
        try engine.evaluate("""
          (define stub-host
            (make-terminal-backend
              'stub-host "Stub" 'host "test.bundle"
              (lambda () "zellij")     ; foreground command → descend into zellij
              (lambda () "host-1")
              (lambda () 'x) (lambda () 'x) (lambda () 'x) (lambda () 'x)
              (lambda () 'x) (lambda () 'x) (lambda () 'x) (lambda () 'x)
              (lambda () 'x) (lambda () 'x) (lambda () 'x) (lambda () 'x)
              (lambda () 'x) (lambda () 'x)
              (lambda () #t)))
          (register-backend! stub-host)
        """)

        let pathLen = try engine.evaluate("""
          (parameterize ((current-frontmost-bundle-id
                           (lambda () "test.bundle")))
            (length (focused-terminal-path)))
        """)
        #expect(pathLen == .fixnum(2))

        let inChain = try engine.evaluate("""
          (parameterize ((current-frontmost-bundle-id
                           (lambda () "test.bundle")))
            (in-chain? 'zellij))
        """)
        #expect(inChain == .true)
    }

    /// (register!) also wires the digit-pick mode so that the backend's
    /// focus-pane-by-digit symbol ('zellij-pane-digit) names a real tree
    /// for the façade's resolver to hand a procedure-valued 'next.
    @Test func registerInstallsDigitPickTree() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser dsl) (modaliser state-machine)
                  (modaliser muxes zellij))
        """)
        try engine.evaluate("(register!)")
        #expect(try engine.evaluate("(lookup-tree \"zellij-pane-digit\")") != .false)
    }

    /// The exported `backend` record is shape-correct: matches as a mux
    /// against the "zellij" foreground command and reports
    /// configured? = #t (no provisioning required). This is the contract
    /// the façade reads when resolving the active backend.
    @Test func backendRecordIsShapeCorrect() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser muxes zellij) (modaliser terminal))
        """)
        #expect(try engine.evaluate("(terminal-backend? backend)") == .true)
        try engine.evaluate("(register-backend! backend)")
        try engine.evaluate("""
          (define h
            (make-terminal-backend
              'sh "H" 'host "t.b"
              (lambda () "zellij") (lambda () "p")
              (lambda () 'x) (lambda () 'x) (lambda () 'x) (lambda () 'x)
              (lambda () 'x) (lambda () 'x) (lambda () 'x) (lambda () 'x)
              (lambda () 'x) (lambda () 'x) (lambda () 'x) (lambda () 'x)
              (lambda () 'x) (lambda () 'x)
              (lambda () #t)))
          (register-backend! h)
        """)
        // All four capability predicates should report support: zellij
        // gives us the full 14-op surface (all 12 splits/focus/move +
        // digit-jump + toggle-fullscreen for zoom).
        for predicate in [
            "(supports-splits?)",
            "(supports-move-pane?)",
            "(supports-digit-jump?)",
            "(supports-zoom?)"
        ] {
            #expect(try engine.evaluate("""
              (parameterize ((current-frontmost-bundle-id (lambda () "t.b")))
                \(predicate))
            """) == .true, "expected \(predicate) ⇒ #t")
        }
    }
}
