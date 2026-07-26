import Foundation
import Testing
import LispKit
@testable import Modaliser

// The Handoff (handoff-k10, ADR-0018, docs/specs/configuration-value.md
// "The Handoff"): (modaliser:start! config) — the one effectful moment.
// Build-value-then-handoff on a fresh engine context: the pure lower +
// closure validation run first, then the graph installs
// (fsm-install-graph!), the value's backend records enter the terminal
// façade's registry (so the REAL focused-terminal-path is the step-in
// chain source), settings apply, and the leaders arm from the installed
// value — each armed handler resolving through resolve-activation
// against the installed value and the live chain. One-shot: a second
// call errors; a config failing anywhere before the first effect leaves
// the engine cleanly empty (the defined config-error state) and a
// corrected retry succeeds. The live app still boots through the old
// registration path — nothing here touches it.
@Suite("The Handoff (modaliser:start! / configured leader path)")
struct ModaliserHandoffLibraryTests {

    private func loaded() throws -> SchemeEngine {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser util)
                  (modaliser fsm)
                  (modaliser configuration)
                  (modaliser terminal)
                  (modaliser fsm)
                  (modaliser event-dispatch)
                  (modaliser handoff))
        """)
        try engine.evaluate("(import (modaliser dsl))")
        // Decodable-error helper (same shape as ConfigurationLoweringTests).
        try engine.evaluate("""
          (define (catch-irritants thunk)
            (guard (e (#t (error-object-irritants e)))
              (thunk)
              'no-error))
        """)
        // Toy backends whose foreground probes read mutable cells, so a
        // test can shape the chain that the REAL focused-terminal-path
        // walk (through the registry modaliser:start! populates) reports.
        try engine.evaluate("""
          (define term-fg #f)
          (define tmix-fg #f)
          (define (test-host-backend sym bundle)
            (make-terminal-backend sym "TestHost" 'host bundle #f
              (lambda () term-fg) (lambda () "p0")
              #f #f #f #f #f #f #f #f #f #f #f #f
              #f #f
              (lambda () #t)))
          (define (test-mux-backend sym exe)
            (make-terminal-backend sym "TestMux" 'mux exe #f
              (lambda () tmix-fg) (lambda () "m0")
              #f #f #f #f #f #f #f #f #f #f #f #f
              #f #f
              (lambda () #t)))
          (define (live-triggers)
            (map (lambda (e) (cdr (assoc 'trigger e))) (fsm-live-edges)))
        """)
        // The toy configuration: both leaders, a non-default overlay
        // delay, a terminal-like host screen, a mux-backed context entry
        // (tmix) and a tree-only one (edit), and a global tree whose "x"
        // key cross-edges into tmix-tree (for the leaderless-past-the-
        // baseline check).
        try engine.evaluate("""
          (define cfg
            (configuration
              (leaders (leader 'global F18)
                       (leader 'local F17))
              (overlay-delay 0.25)
              (tree 'global (group "" "Global"
                              (key "g" "G" (lambda () 'g))
                              (key "x" "X" (lambda () 'x) 'next 'tmix-tree)))
              (tree "com.test.term" (group "" "Term" (key "t" "T" (lambda () 't))))
              (tree 'tmix-tree (group "" "Tmix" (key "m" "M" (lambda () 'm))))
              (tree 'edit-tree (group "" "Edit" (key "e" "E" (lambda () 'e))))
              (backend 'term (test-host-backend 'term "com.test.term"))
              (backend 'tmix (test-mux-backend 'tmix "tmix"))
              (terminal-contexts
                (context "tmix" 'tree 'tmix-tree 'backend 'tmix)
                (context "edit" 'tree 'edit-tree))))
        """)
        return engine
    }

    // MARK: - Install: graph, settings, backends, leaders

    @Test func handoffInstallsGraphSettingsBackendsAndArmsLeaders() throws {
        let engine = try loaded()
        try engine.evaluate("(define installed (modaliser:start! cfg))")
        // Returns the value it installed; the accessor reads it back.
        #expect(try engine.evaluate("(eq? installed cfg)") == .true)
        #expect(try engine.evaluate("(eq? (modaliser:configuration) cfg)") == .true)
        // The value's trees are now the engine's installed graph.
        #expect(try engine.evaluate("(and (fsm-state-ref \"global\") #t)") == .true)
        #expect(try engine.evaluate("(and (fsm-state-ref \"edit-tree\") #t)") == .true)
        // Settings applied from the value.
        #expect(try engine.evaluate("(= modal-overlay-delay 0.25)") == .true)
        // Both leaders armed, into the Swift hotkey registry.
        let kbLib = try engine.context.libraries.lookup(KeyboardLibrary.self)!
        #expect(kbLib.handlerRegistry.hotkeyHandlers[HotkeyKey(keyCode: KeyCode.f18, modifiers: [])] != nil)
        #expect(kbLib.handlerRegistry.hotkeyHandlers[HotkeyKey(keyCode: KeyCode.f17, modifiers: [])] != nil)
        // The value's backend records reached the terminal façade's
        // registry: the REAL chain walk resolves them.
        try engine.evaluate("(set! term-fg \"tmix\") (set! tmix-fg \"edit\")")
        #expect(try engine.evaluate("""
          (parameterize ((current-frontmost-bundle-id (lambda () "com.test.term")))
            (equal? (focused-terminal-path)
                    (list (cons 'term (vector 'pane "p0" 'fg "tmix"))
                          (cons 'tmix (vector 'pane "m0" 'fg "edit")))))
        """) == .true)
    }

    // MARK: - The configured leader path, end to end

    @Test func configuredGlobalLeaderTogglesTheModal() throws {
        let engine = try loaded()
        try engine.evaluate("(modaliser:start! cfg)")
        try engine.evaluate("(define global-press (make-configured-leader-handler F18 'global))")
        try engine.evaluate("(global-press)")
        #expect(try engine.evaluate("modal-active?") == .true)
        #expect(try engine.evaluate("(equal? (fsm-current-state) \"global\")") == .true)
        #expect(try engine.evaluate("(= modal-leader-keycode F18)") == .true)
        // A second press toggles the modal off.
        try engine.evaluate("(global-press)")
        #expect(try engine.evaluate("(fsm-active?)") == .false)
        #expect(try engine.evaluate("modal-active?") == .false)
    }

    @Test func configuredLocalLeaderLandsInnermostWithSeededStack() throws {
        let engine = try loaded()
        try engine.evaluate("(modaliser:start! cfg)")
        try engine.evaluate("(set! term-fg \"tmix\") (set! tmix-fg \"edit\")")
        try engine.evaluate("""
          (parameterize ((current-frontmost-bundle-id (lambda () "com.test.term")))
            ((make-configured-leader-handler F17 'local)))
        """)
        #expect(try engine.evaluate("modal-active?") == .true)
        #expect(try engine.evaluate("(equal? (fsm-current-state) \"edit-tree\")") == .true)
        #expect(try engine.evaluate("(equal? (fsm-return-stack) '(\"tmix-tree\" \"com.test.term\"))") == .true)
        // The leader still toggles at the chain-seeded landing depth —
        // through the real catch-all keycode path.
        #expect(try engine.evaluate("(= modal-leader-keycode F17)") == .true)
        try engine.evaluate("(modal-key-handler F17 0)")
        #expect(try engine.evaluate("(fsm-active?)") == .false)
    }

    @Test func seededLandingBackspacesOutwardAndKeepsTheLeaderThroughTheBaseline() throws {
        let engine = try loaded()
        try engine.evaluate("(modaliser:start! cfg)")
        try engine.evaluate("(set! term-fg \"tmix\") (set! tmix-fg \"edit\")")
        // Each step runs in its own parameterize extent (the per-snapshot
        // chain probes must see the same frontmost app a real session
        // would), with every modal-leader-keycode read at top level in a
        // SEPARATE evaluate — a bare-variable read compiled in the same
        // top-level form as the mutation sees a stale snapshot (the
        // fsm.sld thunk-pattern caveat).
        try engine.evaluate("""
          (parameterize ((current-frontmost-bundle-id (lambda () "com.test.term")))
            ((make-configured-leader-handler F17 'local)))
        """)
        #expect(try engine.evaluate("(equal? (fsm-current-state) \"edit-tree\")") == .true)
        #expect(try engine.evaluate("(= modal-leader-keycode F17)") == .true)
        try engine.evaluate("""
          (parameterize ((current-frontmost-bundle-id (lambda () "com.test.term")))
            (modal-step-back))
        """)
        #expect(try engine.evaluate("(equal? (fsm-current-state) \"tmix-tree\")") == .true)
        try engine.evaluate("""
          (parameterize ((current-frontmost-bundle-id (lambda () "com.test.term")))
            (modal-step-back))
        """)
        #expect(try engine.evaluate("(equal? (fsm-current-state) \"com.test.term\")") == .true)
        #expect(try engine.evaluate("(null? (fsm-return-stack))") == .true)
        // Backing out below the baseline never went leaderless, and the
        // modal is still active at the host screen.
        #expect(try engine.evaluate("(= modal-leader-keycode F17)") == .true)
        #expect(try engine.evaluate("modal-active?") == .true)
    }

    @Test func stepInDerivesThroughTheInstalledChainSource() throws {
        let engine = try loaded()
        try engine.evaluate("(modaliser:start! cfg)")
        // The host pane runs "edit" directly; landing seeds one frame,
        // and stepping back to the host screen must derive the "." edge
        // from the SAME live chain the handoff wired as chain source.
        try engine.evaluate("(set! term-fg \"edit\")")
        try engine.evaluate("""
          (define step-in-live?
            (parameterize ((current-frontmost-bundle-id (lambda () "com.test.term")))
              ((make-configured-leader-handler F17 'local))
              (modal-step-back)
              (and (equal? (fsm-current-state) "com.test.term")
                   (member "." (live-triggers))
                   #t)))
        """)
        #expect(try engine.evaluate("step-in-live?") == .true)
    }

    @Test func crossEdgePastTheSeededBaselineGoesLeaderless() throws {
        let engine = try loaded()
        try engine.evaluate("(modaliser:start! cfg)")
        try engine.evaluate("((make-configured-leader-handler F18 'global))")
        #expect(try engine.evaluate("(= modal-leader-keycode F18)") == .true)
        // "x" cross-edges into tmix-tree: one call frame past the (zero)
        // baseline — leaderless, exactly the pre-handoff rule.
        try engine.evaluate("(modal-handle-key \"x\")")
        #expect(try engine.evaluate("(equal? (fsm-current-state) \"tmix-tree\")") == .true)
        #expect(try engine.evaluate("(eq? modal-leader-keycode #f)") == .true)
        // Popping back to the baseline restores it.
        try engine.evaluate("(modal-step-back)")
        #expect(try engine.evaluate("(= modal-leader-keycode F18)") == .true)
    }

    // MARK: - One-shot

    @Test func secondHandoffErrors() throws {
        let engine = try loaded()
        try engine.evaluate("(modaliser:start! cfg)")
        #expect(try engine.evaluate("""
          (equal? (catch-irritants (lambda () (modaliser:start! cfg)))
                  '(already-started))
        """) == .true)
    }

    // MARK: - Config-error emptiness

    @Test func failingHandoffLeavesTheEngineEmptyAndRetryable() throws {
        let engine = try loaded()
        // A dangling context reference fails the pure phase.
        try engine.evaluate("""
          (define bad-cfg
            (configuration
              (leaders (leader 'global F18))
              (tree 'global (group "" "Global" (key "g" "G" (lambda () 'g))))
              (context "ghost" 'tree 'no-such-tree)))
          (define irritants
            (catch-irritants (lambda () (modaliser:start! bad-cfg))))
        """)
        #expect(try engine.evaluate("""
          (equal? irritants '(dangling-context-tree "ghost" no-such-tree))
        """) == .true)
        // Cleanly empty: nothing was ever installed.
        #expect(try engine.evaluate("(null? (fsm-state-ids))") == .true)
        #expect(try engine.evaluate("(fsm-active?)") == .false)
        #expect(try engine.evaluate("(modaliser:configuration)") == .false)
        #expect(try engine.evaluate("(= modal-overlay-delay 1.0)") == .true)
        let kbLib = try engine.context.libraries.lookup(KeyboardLibrary.self)!
        #expect(kbLib.handlerRegistry.hotkeyHandlers.isEmpty)
        // The one-shot latch never set — a corrected retry succeeds.
        try engine.evaluate("(modaliser:start! cfg)")
        #expect(try engine.evaluate("(eq? (modaliser:configuration) cfg)") == .true)
        #expect(try engine.evaluate("(and (fsm-state-ref \"global\") #t)") == .true)
    }

    @Test func invalidBackendRecordFailsBeforeAnyEffect() throws {
        let engine = try loaded()
        // The graph lowers fine; the backend check fails — and because
        // every check runs before the first effect, the graph must NOT
        // have been installed and no leader armed.
        try engine.evaluate("""
          (define bad-cfg
            (configuration
              (leaders (leader 'global F18))
              (tree 'global (group "" "Global" (key "g" "G" (lambda () 'g))))
              (backend 'junk 42)))
          (define irritants
            (catch-irritants (lambda () (modaliser:start! bad-cfg))))
        """)
        #expect(try engine.evaluate("(equal? irritants '(invalid-backend-record junk))") == .true)
        #expect(try engine.evaluate("(null? (fsm-state-ids))") == .true)
        #expect(try engine.evaluate("(modaliser:configuration)") == .false)
        let kbLib = try engine.context.libraries.lookup(KeyboardLibrary.self)!
        #expect(kbLib.handlerRegistry.hotkeyHandlers.isEmpty)
    }

    @Test func outOfRangeLeaderKeycodeFailsBeforeAnyEffect() throws {
        let engine = try loaded()
        // A keycode beyond the host CGKeyCode range passes the `leader`
        // constructor (unbounded there) but must fail the handoff's
        // pre-effect validation — arming is an effect, and an error
        // surfacing only in the native layer would fire mid-effect-phase.
        try engine.evaluate("""
          (define bad-cfg
            (configuration
              (leaders (leader 'global 70000))
              (tree 'global (group "" "Global" (key "g" "G" (lambda () 'g))))))
          (define irritants
            (catch-irritants (lambda () (modaliser:start! bad-cfg))))
        """)
        #expect(try engine.evaluate("(equal? (car irritants) 'invalid-leader-spec)") == .true)
        #expect(try engine.evaluate("(null? (fsm-state-ids))") == .true)
        #expect(try engine.evaluate("(modaliser:configuration)") == .false)
        let kbLib = try engine.context.libraries.lookup(KeyboardLibrary.self)!
        #expect(kbLib.handlerRegistry.hotkeyHandlers.isEmpty)
    }

    @Test func malformedLeaderSpecFailsBeforeAnyEffect() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (define bad-cfg
            (configuration
              (setting 'leaders (list (list (cons 'mode 'sideways) (cons 'keycode 64))))
              (tree 'global (group "" "Global" (key "g" "G" (lambda () 'g))))))
          (define irritants
            (catch-irritants (lambda () (modaliser:start! bad-cfg))))
        """)
        #expect(try engine.evaluate("(equal? (car irritants) 'invalid-leader-spec)") == .true)
        #expect(try engine.evaluate("(null? (fsm-state-ids))") == .true)
        #expect(try engine.evaluate("(modaliser:configuration)") == .false)
    }
}
