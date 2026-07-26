import Foundation
import Testing
@testable import Modaliser

/// Tests for `(modaliser muxes tmux)` — the tmux backend behind the
/// (modaliser terminal) façade.
///
/// These tests run without tmux being attached (no live client matching
/// the test process's tty). The shell-out helpers cleanly return #f or
/// empty in that case, which is the contract the façade expects, so we
/// can verify wiring and installation end-to-end without a real session.
/// Hand-verification of the 14 ops against a live iTerm + tmux session
/// is the leaf's separate "Done when" item.
@Suite("(modaliser muxes tmux) library")
struct ModaliserMuxesTmuxLibraryTests {
    @Test func importsAndExposesProcedures() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes tmux))")
        // `wiring` and `backend` are the integration; the fourteen ops
        // are the verbs a user's screen binds (ADR-0021). All must bind
        // without error — each op name is public contract now.
        _ = try engine.evaluate("wiring")
        _ = try engine.evaluate("backend")
        for op in [
            "focus-pane-left", "focus-pane-right", "focus-pane-up", "focus-pane-down",
            "split-pane-left", "split-pane-right", "split-pane-up", "split-pane-down",
            "move-pane-left", "move-pane-right", "move-pane-up", "move-pane-down",
            "toggle-pane-zoom"
        ] {
            #expect(try engine.evaluate("(procedure? \(op))") == .true,
                    "expected \(op) to be an exported 0-arg op")
        }
    }

    /// terminal-install-backends! installs the backend into the façade's
    /// registry, keyed by 'tmux + match-key "tmux". With a stubbed host
    /// pointing at the bundle and reporting "tmux" as its foreground
    /// command, the façade walks the path and the leaf is this backend.
    /// (One replace-wholesale call installs BOTH records — the façade
    /// registry holds exactly what the list carries.)
    @Test func installedBackendResolvesThroughFacade() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser muxes tmux) (modaliser terminal))
        """)

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
          (terminal-install-backends! (list backend stub-host))
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

    /// ADR-0021's line, read off the fragment itself: (wiring) carries
    /// the context-map entry, the backend record and the machinery-named
    /// digit-jump tree — the last so the backend's focus-pane-by-digit
    /// symbol ('tmux-pane-digit) names a real tree for the façade's
    /// resolver to hand a procedure-valued 'next.
    ///
    /// And NO tree under 'tmux. That absence is the contract, not an
    /// omission: the screen the context entry resolves to is the
    /// configuration's to author — `Scheme/examples/tmux.scm` is the
    /// shipped one, load-tested by ConfigDslTests.
    @Test func wiringCarriesIntegrationAndNoScreen() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser fsm)
                  (prefix (modaliser configuration) config:)
                  (modaliser muxes tmux))
        """)
        try engine.evaluate("(define w (config:configuration (wiring)))")
        #expect(try engine.evaluate("""
          (and (equal? (config:configuration-context-ref w "tmux")
                       '((tree . tmux) (backend . tmux)))
               (pair? (config:configuration-tree-ref w 'tmux-pane-digit))
               ;; The one the composition must supply.
               (not (config:configuration-tree-ref w 'tmux)))
        """) == .true)
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
        // Indirect introspection via the registry: installing and then
        // walking under a host that descends into "tmux" should pick our
        // backend at the leaf; here we verify the record's `configured?`
        // thunk returns #t by hand-poking the registry path (the
        // supports-* predicates run this). Both records go in ONE
        // replace-wholesale install.
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
          (terminal-install-backends! (list backend h))
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
