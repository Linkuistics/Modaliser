import Foundation
import Testing
@testable import Modaliser

/// Tests for `(modaliser muxes tmux)` — the tmux backend behind the
/// (modaliser terminal) façade.
///
/// These tests run without tmux being attached (no live client matching
/// the test process's tty). The shell-out helpers cleanly return #f or
/// empty in that case, which is the contract the façade expects, so we
/// can verify wiring and registration end-to-end without a real session.
/// Hand-verification of the 14 ops against a live iTerm + tmux session
/// is the leaf's separate "Done when" item.
@Suite("(modaliser muxes tmux) library")
struct ModaliserMuxesTmuxLibraryTests {
    @Test func importsAndExposesProcedures() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes tmux))")
        // The only public exports are register! and backend; the ops
        // live on the façade, not here. Both must bind without error.
        _ = try engine.evaluate("register!")
        _ = try engine.evaluate("backend")
    }

    /// (register!) installs the backend into the façade's registry,
    /// keyed by 'tmux + match-key "tmux". With a stubbed host pointing
    /// at the bundle and reporting "tmux" as its foreground command,
    /// the façade walks the path and the leaf is this backend.
    @Test func registerInstallsTmuxBackend() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser dsl) (modaliser state-machine)
                  (modaliser muxes tmux) (modaliser terminal))
        """)
        try engine.evaluate("(register!)")

        // A stub host that claims tmux is in the focused pane. The path
        // walk descends from host into the tmux backend; without a live
        // tmux client the backend's detect-fg returns #f, so it sits at
        // the leaf naturally.
        try engine.evaluate("""
          (define stub-host
            (make-terminal-backend
              'stub-host "Stub" 'host "test.bundle" #f
              (lambda () "tmux")       ; foreground command → descend into tmux
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
            (in-chain? 'tmux))
        """)
        #expect(inChain == .true)
    }

    /// (register!) also wires the digit-pick mode so that the backend's
    /// focus-pane-by-digit symbol ('tmux-pane-digit) names a real tree
    /// for the façade's resolver to hand a procedure-valued 'next.
    @Test func registerInstallsDigitPickTree() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser dsl) (modaliser state-machine)
                  (modaliser muxes tmux))
        """)
        try engine.evaluate("(register!)")
        #expect(try engine.evaluate("(lookup-tree \"tmux-pane-digit\")") != .false)
    }

    /// The exported `backend` record is shape-correct: matches as a mux
    /// against the "tmux" foreground command and reports configured? = #t
    /// (no provisioning required for tmux). This is the contract the
    /// façade reads when resolving the active backend.
    @Test func backendRecordIsShapeCorrect() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser muxes tmux) (modaliser terminal))
        """)
        #expect(try engine.evaluate("(terminal-backend? backend)") == .true)
        // Indirect introspection via the registry: registering and then
        // walking under a host that descends into "tmux" should pick our
        // backend at the leaf. Done above; here we verify the record's
        // `configured?` thunk returns #t by hand-poking the registry
        // path (the supports-* predicates run this).
        try engine.evaluate("(register-backend! backend)")
        try engine.evaluate("""
          (define h
            (make-terminal-backend
              'sh "H" 'host "t.b" #f
              (lambda () "tmux") (lambda () "p")
              (lambda () 'x) (lambda () 'x) (lambda () 'x) (lambda () 'x)
              (lambda () 'x) (lambda () 'x) (lambda () 'x) (lambda () 'x)
              (lambda () 'x) (lambda () 'x) (lambda () 'x) (lambda () 'x)
              (lambda () 'x) (lambda () 'x)
              (lambda () #t)))
          (register-backend! h)
        """)
        // Capability predicates should report support for the move op
        // (tmux's swap-pane gives us all four directions). digit-jump
        // and zoom too.
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
