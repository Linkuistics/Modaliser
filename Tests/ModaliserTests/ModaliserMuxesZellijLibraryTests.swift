import Foundation
import Testing
@testable import Modaliser

/// Tests for `(modaliser muxes zellij)` — the zellij backend behind the
/// (modaliser terminal) façade.
///
/// These tests run without a zellij session being attached. The shell-out
/// helpers cleanly return #f or empty in that case, which is the
/// contract the façade expects, so we can verify wiring and installation
/// end-to-end without a real session. Hand-verification of the 14 ops
/// against a live iTerm + zellij session is the leaf's separate
/// "Done when" item.
@Suite("(modaliser muxes zellij) library")
struct ModaliserMuxesZellijLibraryTests {
    @Test func importsAndExposesProcedures() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser muxes zellij))")
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
    /// registry, keyed by 'zellij + match-key "zellij". With a stubbed
    /// host pointing at the bundle and reporting "zellij" as its
    /// foreground command, the façade walks the path and the leaf is
    /// this backend. (One replace-wholesale call installs BOTH records —
    /// the façade registry holds exactly what the list carries.)
    @Test func installedBackendResolvesThroughFacade() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser muxes zellij) (modaliser terminal))
        """)

        // A stub host that claims zellij is in the focused pane. The path
        // walk descends from host into the zellij backend; without a live
        // zellij session the backend's detect-fg returns #f, so it sits
        // at the leaf naturally.
        try engine.evaluate("""
          (define stub-host
            (make-terminal-backend
              'stub-host "Stub" 'host "test.bundle" #f
              (lambda () "zellij")     ; foreground command → descend into zellij
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
            (in-chain? 'zellij))
        """)
        #expect(inChain == .true)
    }

    /// ADR-0021's line, read off the fragment itself: (wiring) carries
    /// the context-map entry, the backend record and the machinery-named
    /// digit-jump tree — the last so the backend's focus-pane-by-digit
    /// symbol ('zellij-pane-digit) names a real tree for the façade's
    /// resolver to hand a procedure-valued 'next.
    ///
    /// And NO tree under 'zellij. That absence is the contract, not an
    /// omission: the screen the context entry resolves to is the
    /// configuration's to author, so a library change can never silently
    /// re-take a key the user chose.
    @Test func wiringCarriesIntegrationAndNoScreen() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser fsm)
                  (prefix (modaliser configuration) config:)
                  (modaliser muxes zellij))
        """)
        try engine.evaluate("(define w (config:configuration (wiring)))")
        #expect(try engine.evaluate("""
          (and (equal? (config:configuration-context-ref w "zellij")
                       '((tree . zellij) (backend . zellij)))
               (pair? (config:configuration-tree-ref w 'zellij-pane-digit))
               ;; The one the composition must supply.
               (not (config:configuration-tree-ref w 'zellij)))
        """) == .true)
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
        // Both records go in ONE replace-wholesale install.
        try engine.evaluate("""
          (define h
            (make-terminal-backend
              'sh "H" 'host "t.b" #f
              (lambda () "zellij") (lambda () "p")
              (lambda () 'x) (lambda () 'x) (lambda () 'x) (lambda () 'x)
              (lambda () 'x) (lambda () 'x) (lambda () 'x) (lambda () 'x)
              (lambda () 'x) (lambda () 'x) (lambda () 'x) (lambda () 'x)
              (lambda () 'x) (lambda () 'x)
              (lambda () #t)))
          (terminal-install-backends! (list backend h))
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
