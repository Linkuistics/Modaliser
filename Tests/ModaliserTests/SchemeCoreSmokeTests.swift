import Foundation
import Testing
import LispKit
@testable import Modaliser

private func joinPath(_ base: String, _ component: String) -> String {
    base.hasSuffix("/") ? base + component : base + "/" + component
}

@Suite("Scheme Core Smoke Tests")
struct SchemeCoreSmokeTests {

    // MARK: - Module loading

    @Test func stateMachineModuleLoads() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser fsm))")

        #expect(try engine.evaluate("(procedure? lower-configuration)") == .true)
        #expect(try engine.evaluate("(procedure? modal-activate!)") == .true)
        #expect(try engine.evaluate("(procedure? modal-exit)") == .true)
        #expect(try engine.evaluate("(procedure? modal-handle-key)") == .true)
        #expect(try engine.evaluate("(procedure? modal-step-back)") == .true)
    }

    @Test func dslModuleLoads() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser fsm) (modaliser configuration))")
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")

        // `key` is now a syntactic keyword (macro), not a procedure.
        // Smoke-check that it expands to a command node.
        try engine.evaluate("(define cmd (key \"x\" \"X\" (lambda () #t)))")
        #expect(try engine.evaluate("(eq? (cdr (assoc 'kind cmd)) 'command)") == .true)
        #expect(try engine.evaluate("(procedure? group)") == .true)
        #expect(try engine.evaluate("(procedure? screen)") == .true)
        #expect(try engine.evaluate("(procedure? tree-root)") == .true)
    }

    // MARK: - Tree contribution and lookup

    @Test func registerAndLookupTree() throws {
        let engine = try SchemeEngine()
        guard engine.schemeDirectoryPath != nil else { return }
        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser fsm) (modaliser configuration))")
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")

        try engine.evaluate("""
            (define cfg (configuration
              (tree 'global (tree-root 'global
                (key "s" "Safari" (lambda () 'launched-safari))))))
            (fsm-install-graph! (lower-configuration cfg))
            """)

        let result = try engine.evaluate("(configuration-tree-ref cfg \"global\")")
        #expect(result != .false)
        #expect(try engine.evaluate("(group? (configuration-tree-ref cfg \"global\"))") == .true)
    }

    @Test func registerAppSpecificTree() throws {
        let engine = try SchemeEngine()
        guard engine.schemeDirectoryPath != nil else { return }
        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser fsm) (modaliser configuration))")
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")

        try engine.evaluate("""
            (define cfg (configuration
              (tree 'com.apple.Safari (tree-root 'com.apple.Safari
                (key "t" "New Tab" (lambda () 'new-tab))))))
            (fsm-install-graph! (lower-configuration cfg))
            """)

        #expect(try engine.evaluate("(configuration-tree-ref cfg \"com.apple.Safari\")") != .false)
        #expect(try engine.evaluate("(configuration-tree-ref cfg \"nonexistent\")") == .false)
    }

    // MARK: - Modal navigation

    @Test func modalEnterAndExit() throws {
        let engine = try SchemeEngine()
        guard engine.schemeDirectoryPath != nil else { return }
        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser fsm) (modaliser configuration))")
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")

        try engine.evaluate("""
            (fsm-install-graph! (lower-configuration (configuration
              (tree 'global (tree-root 'global
                (key "s" "Safari" (lambda () 'ok)))))))
            """)

        #expect(try engine.evaluate("modal-active?") == .false)

        try engine.evaluate("(modal-activate! \"global\" '() F18)")
        #expect(try engine.evaluate("modal-active?") == .true)

        // modal-activate! registers a catch-all, so unregister it for test cleanup
        try engine.evaluate("(modal-exit)")
        #expect(try engine.evaluate("modal-active?") == .false)
    }

    @Test func modalHandleKeyExecutesCommand() throws {
        let engine = try SchemeEngine()
        guard engine.schemeDirectoryPath != nil else { return }
        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser fsm) (modaliser configuration))")
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")

        try engine.evaluate("""
            (define action-called #f)
            (fsm-install-graph! (lower-configuration (configuration
              (tree 'global (tree-root 'global
                (key "s" "Safari" (lambda () (set! action-called #t))))))))
            """)

        try engine.evaluate("(modal-activate! \"global\" '() F18)")
        try engine.evaluate("(modal-handle-key \"s\")")

        #expect(try engine.evaluate("action-called") == .true)
        #expect(try engine.evaluate("modal-active?") == .false)
    }

    @Test func modalHandleKeyNavigatesGroup() throws {
        let engine = try SchemeEngine()
        guard engine.schemeDirectoryPath != nil else { return }
        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser fsm) (modaliser configuration))")
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")

        try engine.evaluate("""
            (fsm-install-graph! (lower-configuration (configuration
              (tree 'global (tree-root 'global
                (group "w" "Windows"
                  (key "c" "Center" (lambda () 'centered))))))))
            """)

        try engine.evaluate("(modal-activate! \"global\" '() F18)")
        try engine.evaluate("(modal-handle-key \"w\")")

        #expect(try engine.evaluate("modal-active?") == .true)
        #expect(try engine.evaluate("(equal? modal-current-path '(\"w\"))") == .true)

        try engine.evaluate("(modal-exit)")
    }

    @Test func modalStepBackWorks() throws {
        let engine = try SchemeEngine()
        guard engine.schemeDirectoryPath != nil else { return }
        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser fsm) (modaliser configuration))")
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")

        try engine.evaluate("""
            (fsm-install-graph! (lower-configuration (configuration
              (tree 'global (tree-root 'global
                (group "w" "Windows"
                  (key "c" "Center" (lambda () 'centered))))))))
            """)

        try engine.evaluate("(modal-activate! \"global\" '() F18)")
        try engine.evaluate("(modal-handle-key \"w\")")
        try engine.evaluate("(modal-step-back)")

        #expect(try engine.evaluate("modal-active?") == .true)
        #expect(try engine.evaluate("(null? modal-current-path)") == .true)

        try engine.evaluate("(modal-exit)")
    }

    @Test func modalStepBackAtRootIsNoOp() throws {
        // Backspace is purely navigational: at the root there's no parent
        // to retreat to, so it's a stand-still. Exit is owned by Escape
        // and 'exit-on-unknown; backspace never drops a modal.
        let engine = try SchemeEngine()
        guard engine.schemeDirectoryPath != nil else { return }
        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser fsm) (modaliser configuration))")
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")

        try engine.evaluate("""
            (fsm-install-graph! (lower-configuration (configuration
              (tree 'global (tree-root 'global
                (key "s" "Safari" (lambda () 'ok)))))))
            """)

        try engine.evaluate("(modal-activate! \"global\" '() F18)")
        try engine.evaluate("(modal-step-back)")

        #expect(try engine.evaluate("modal-active?") == .true)

        try engine.evaluate("(modal-exit)")
    }

    // MARK: - DSL integration

    @Test func setLeaderRegistersHotkey() throws {
        let engine = try SchemeEngine()
        guard engine.schemeDirectoryPath != nil else { return }
        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser fsm) (modaliser configuration))")
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")
        try engine.evaluate("(import (modaliser handoff))")

        // The real handoff arms the leaders from the configuration value.
        try engine.evaluate("""
            (modaliser:start! (configuration
              (leaders (leader 'global F18))
              (screen 'global
                (key "s" "Safari" (lambda () 'ok)))))
            """)

        // Verify the hotkey was registered in the keyboard library
        let keyboardLib = try engine.context.libraries.lookup(KeyboardLibrary.self)
        #expect(keyboardLib?.handlerRegistry.hotkeyHandlers[HotkeyKey(keyCode: KeyCode.f18, modifiers: [])] != nil)
    }

    @Test func fullLifecycleViaSchemeModules() throws {
        let engine = try SchemeEngine()
        guard engine.schemeDirectoryPath != nil else { return }
        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser fsm) (modaliser configuration))")
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")

        try engine.evaluate("""
            (define test-action-log '())
            (fsm-install-graph! (lower-configuration (configuration
              (tree 'global (tree-root 'global
                (key "s" "Safari" (lambda () (set! test-action-log (cons 'safari test-action-log))))
                (group "w" "Windows"
                  (key "c" "Center" (lambda () (set! test-action-log (cons 'center test-action-log))))))))))
            """)

        // Simulate full flow: enter → navigate group → execute command
        try engine.evaluate("(modal-activate! \"global\" '() F18)")
        #expect(try engine.evaluate("modal-active?") == .true)

        try engine.evaluate("(modal-handle-key \"w\")")
        #expect(try engine.evaluate("modal-active?") == .true)

        try engine.evaluate("(modal-handle-key \"c\")")
        #expect(try engine.evaluate("modal-active?") == .false)
        #expect(try engine.evaluate("(car test-action-log)") == .symbol(engine.context.symbols.intern("center")))
    }

    @Test func appSpecificTreeOverridesGlobal() throws {
        let engine = try SchemeEngine()
        guard engine.schemeDirectoryPath != nil else { return }
        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser fsm) (modaliser configuration))")
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")

        try engine.evaluate("""
            (define which-tree #f)
            (define cfg (configuration
              (tree 'global (tree-root 'global
                (key "s" "Safari" (lambda () (set! which-tree 'global)))))
              (tree 'com.apple.Safari (tree-root 'com.apple.Safari
                (key "t" "Tab" (lambda () (set! which-tree 'safari)))))))
            (fsm-install-graph! (lower-configuration cfg))
            """)

        // App-specific tree should be found for Safari
        let safariTree = try engine.evaluate("(configuration-tree-ref cfg \"com.apple.Safari\")")
        #expect(safariTree != .false)

        // Global should still exist
        let globalTree = try engine.evaluate("(configuration-tree-ref cfg \"global\")")
        #expect(globalTree != .false)

        // The old make-leader-handler's (or app-tree global-tree) fallback now
        // lives in resolve-activation; activating the app scope directly must
        // dispatch the app-specific tree.
        try engine.evaluate("(modal-activate! \"com.apple.Safari\" '() F18)")
        try engine.evaluate("(modal-handle-key \"t\")")
        #expect(try engine.evaluate("which-tree") == .symbol(engine.context.symbols.intern("safari")))
    }

    @Test func modalNoBindingIsNoOp() throws {
        // Unknown keys are swallowed — never dismiss the modal. Escape
        // is the sole exit; this applies to Terminal and Walk trees alike.
        let engine = try SchemeEngine()
        guard engine.schemeDirectoryPath != nil else { return }
        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser fsm) (modaliser configuration))")
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")

        try engine.evaluate("""
            (fsm-install-graph! (lower-configuration (configuration
              (tree 'global (tree-root 'global
                (key "s" "Safari" (lambda () 'ok)))))))
            """)

        try engine.evaluate("(modal-activate! \"global\" '() F18)")
        try engine.evaluate("(modal-handle-key \"x\")")

        #expect(try engine.evaluate("modal-active?") == .true)

        try engine.evaluate("(modal-exit)")
    }

    // MARK: - Walks and Terminal dispatch (ADR-0015)
    //
    // Each test loads the core layer fresh because the installed graph
    // and modal-* state survive across evaluates within a single engine,
    // and we want isolated trees per scenario.

    private func loadCore(_ engine: SchemeEngine, _ schemePath: String) throws {
        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser fsm) (modaliser configuration))")
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")
    }

    @Test func walkReArmsAfterCommand() throws {
        // A leaf declaring 'next 'self is a cyclic edge: firing it re-arms
        // in place rather than exiting.
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else { return }
        try loadCore(engine, schemePath)

        try engine.evaluate("""
            (define fire-count 0)
            (fsm-install-graph! (lower-configuration (configuration
              (tree 'panes (tree-root 'panes
                (key "h" "Left" (lambda () (set! fire-count (+ fire-count 1))) 'next 'self))))))
            """)

        try engine.evaluate("(modal-activate! \"panes\" '() F18)")
        try engine.evaluate("(modal-handle-key \"h\")")
        try engine.evaluate("(modal-handle-key \"h\")")
        try engine.evaluate("(modal-handle-key \"h\")")

        #expect(try engine.evaluate("fire-count") == .fixnum(3))
        #expect(try engine.evaluate("modal-active?") == .true)
        #expect(try engine.evaluate("(null? modal-current-path)") == .true)

        try engine.evaluate("(modal-exit)")
    }

    @Test func unknownKeyIsSwallowedRegardlessOfNext() throws {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else { return }
        try loadCore(engine, schemePath)

        try engine.evaluate("""
            (fsm-install-graph! (lower-configuration (configuration
              (tree 'panes (tree-root 'panes
                (key "h" "Left" (lambda () 'ok) 'next 'self))))))
            """)

        try engine.evaluate("(modal-activate! \"panes\" '() F18)")
        try engine.evaluate("(modal-handle-key \"z\")") // unknown
        #expect(try engine.evaluate("modal-active?") == .true)

        try engine.evaluate("(modal-exit)")
    }

    @Test func terminalLeafReleasesBeforeAction() throws {
        // A leaf with no 'next is Terminal: dispatch calls (modal-exit)
        // BEFORE running the action. Proven behaviourally: under the old
        // action-then-cleanup order, the unconditional post-action
        // modal-exit would tear down whatever fresh modal state the
        // action itself set up; under the new order there's nothing left
        // to tear down, so a fresh context the action enters survives.
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else { return }
        try loadCore(engine, schemePath)

        try engine.evaluate("""
            (define cfg (configuration
              (tree 'fresh (tree-root 'fresh
                (key "z" "Z" (lambda () 'ok))))
              (tree 'global (tree-root 'global
                (key "s" "Safari" (lambda () (modal-activate! "fresh" '() F19)))))))
            (fsm-install-graph! (lower-configuration cfg))
            """)

        try engine.evaluate("(modal-activate! \"global\" '() F18)")
        try engine.evaluate("(modal-handle-key \"s\")")

        #expect(try engine.evaluate("modal-active?") == .true)
        #expect(try engine.evaluate("(eq? modal-root-node (configuration-tree-ref cfg \"fresh\"))") == .true)
        #expect(try engine.evaluate("(eq? modal-leader-keycode F19)") == .true)

        try engine.evaluate("(modal-exit)")
    }

    @Test func cyclicSelfEdgeNeverPushesStack() throws {
        // ADR-0015's "suspected per-press push wart": a cyclic ('next
        // 'self) edge re-arms in place without touching modal-stack,
        // however many times it fires — only a cross edge pushes.
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else { return }
        try loadCore(engine, schemePath)

        try engine.evaluate("""
            (fsm-install-graph! (lower-configuration (configuration
              (tree 'panes (tree-root 'panes
                (key "h" "Left" (lambda () 'ok) 'next 'self))))))
            """)

        try engine.evaluate("(modal-activate! \"panes\" '() F18)")
        #expect(try engine.evaluate("(null? modal-stack)") == .true)

        try engine.evaluate("(modal-handle-key \"h\")")
        try engine.evaluate("(modal-handle-key \"h\")")
        try engine.evaluate("(modal-handle-key \"h\")")

        #expect(try engine.evaluate("(null? modal-stack)") == .true)
        #expect(try engine.evaluate("modal-active?") == .true)

        try engine.evaluate("(modal-exit)")
    }

    @Test func crossEdgePushesCallerAndSwitchesRoot() throws {
        // A 'next edge naming a DIFFERENT tree in the configuration is a
        // cross edge: push the caller context and switch into the target —
        // what the old enter-mode! primitive did imperatively, now declared
        // on the leaf and followed by the engine itself after the action.
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else { return }
        try loadCore(engine, schemePath)

        try engine.evaluate("""
            (define cfg (configuration
              (tree 'panes (tree-root 'panes
                (key "h" "Left" (lambda () 'ok) 'next 'self)))
              (tree 'launcher (tree-root 'launcher
                (key "p" "Pane Mode" (lambda () 'ok) 'next 'panes)))))
            (fsm-install-graph! (lower-configuration cfg))
            """)

        try engine.evaluate("(modal-activate! \"launcher\" '() F18)")
        try engine.evaluate("(modal-handle-key \"p\")")

        #expect(try engine.evaluate("(eq? modal-root-node (configuration-tree-ref cfg \"panes\"))") == .true)
        #expect(try engine.evaluate("(length modal-stack)") == .fixnum(1))

        try engine.evaluate("(modal-step-back)")
        #expect(try engine.evaluate("(eq? modal-root-node (configuration-tree-ref cfg \"launcher\"))") == .true)
        #expect(try engine.evaluate("(null? modal-stack)") == .true)

        try engine.evaluate("(modal-exit)")
    }

    @Test func dynamicNextResolvingToFalseFallsBackToExit() throws {
        // A procedure-valued 'next that resolves to #f at fire time is
        // the dynamic-edge fail-safe (ADR-0015): the node was never
        // Terminal (the edge existed statically), so capture stays
        // through the action, then normal cleanup (modal-exit) runs
        // since there's nothing to follow.
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else { return }
        try loadCore(engine, schemePath)

        try engine.evaluate("""
            (define fired #f)
            (fsm-install-graph! (lower-configuration (configuration
              (tree 'global (tree-root 'global
                (key "g" "Goto" (lambda () (set! fired #t)) 'next (lambda () #f)))))))
            """)

        try engine.evaluate("(modal-activate! \"global\" '() F18)")
        try engine.evaluate("(modal-handle-key \"g\")")

        #expect(try engine.evaluate("fired") == .true)
        #expect(try engine.evaluate("modal-active?") == .false)
    }

    @Test func dynamicNextResolvingToSymbolCrossesIntoIt() throws {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else { return }
        try loadCore(engine, schemePath)

        try engine.evaluate("""
            (define cfg (configuration
              (tree 'panes (tree-root 'panes
                (key "h" "Left" (lambda () 'ok) 'next 'self)))
              (tree 'global (tree-root 'global
                (key "g" "Goto" (lambda () 'ok) 'next (lambda () 'panes))))))
            (fsm-install-graph! (lower-configuration cfg))
            """)

        try engine.evaluate("(modal-activate! \"global\" '() F18)")
        try engine.evaluate("(modal-handle-key \"g\")")

        #expect(try engine.evaluate("(eq? modal-root-node (configuration-tree-ref cfg \"panes\"))") == .true)
        #expect(try engine.evaluate("(length modal-stack)") == .fixnum(1))

        try engine.evaluate("(modal-exit)")
    }

    @Test func walkBackspaceAtRootExits() throws {
        // A Walk entered directly (no caller pushed) still has an
        // "outside" conceptually — backspace at its root exits the
        // modal, distinct from a transient launcher's root no-op.
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else { return }
        try loadCore(engine, schemePath)

        try engine.evaluate("""
            (fsm-install-graph! (lower-configuration (configuration
              (tree 'panes (tree-root 'panes
                (key "h" "Left" (lambda () 'ok) 'next 'self))))))
            """)

        try engine.evaluate("(modal-activate! \"panes\" '() F18)")
        try engine.evaluate("(modal-step-back)")
        #expect(try engine.evaluate("modal-active?") == .false)
    }

    @Test func nestedWalkBackspaceUnwindsThenExits() throws {
        // Backspace from a nested Walk subgroup steps up one level first
        // (today's existing behaviour); only the FOLLOWING backspace, now
        // at the true root with an empty modal-stack, exits — gradual
        // unwind.
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else { return }
        try loadCore(engine, schemePath)

        try engine.evaluate("""
            (fsm-install-graph! (lower-configuration (configuration
              (tree 'panes (tree-root 'panes
                (key "p" "Panes" (lambda () 'ok) 'next 'self)
                (group "x" "Split"
                  (key "h" "Split Left" (lambda () 'ok) 'next 'self)))))))
            """)

        try engine.evaluate("(modal-activate! \"panes\" '() F18)")
        try engine.evaluate("(modal-handle-key \"x\")")
        #expect(try engine.evaluate("(equal? modal-current-path '(\"x\"))") == .true)

        try engine.evaluate("(modal-step-back)")
        #expect(try engine.evaluate("modal-active?") == .true)
        #expect(try engine.evaluate("(null? modal-current-path)") == .true)

        try engine.evaluate("(modal-step-back)")
        #expect(try engine.evaluate("modal-active?") == .false)
    }

    @Test func nestedWalkStaysAtOwnLevel() throws {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else { return }
        try loadCore(engine, schemePath)

        try engine.evaluate("""
            (define split-count 0)
            (fsm-install-graph! (lower-configuration (configuration
              (tree 'panes (tree-root 'panes
                (group "x" "Split"
                  (key "h" "Split Left"
                    (lambda () (set! split-count (+ split-count 1))) 'next 'self)))))))
            """)

        try engine.evaluate("(modal-activate! \"panes\" '() F18)")
        try engine.evaluate("(modal-handle-key \"x\")")
        #expect(try engine.evaluate("(equal? modal-current-path '(\"x\"))") == .true)

        try engine.evaluate("(modal-handle-key \"h\")")
        try engine.evaluate("(modal-handle-key \"h\")")
        #expect(try engine.evaluate("split-count") == .fixnum(2))
        // Cyclic 'next 'self: after firing, we're still inside "x", not at root.
        #expect(try engine.evaluate("(equal? modal-current-path '(\"x\"))") == .true)
        #expect(try engine.evaluate("modal-active?") == .true)

        try engine.evaluate("(modal-exit)")
    }

    @Test func nestedWalkBackspaceStepsToParent() throws {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else { return }
        try loadCore(engine, schemePath)

        try engine.evaluate("""
            (fsm-install-graph! (lower-configuration (configuration
              (tree 'panes (tree-root 'panes
                (group "x" "Split"
                  (key "h" "Split Left" (lambda () 'ok) 'next 'self)))))))
            """)

        try engine.evaluate("(modal-activate! \"panes\" '() F18)")
        try engine.evaluate("(modal-handle-key \"x\")")
        try engine.evaluate("(modal-step-back)")

        // From the Walk subgroup, backspace steps to the parent (mode root).
        #expect(try engine.evaluate("(null? modal-current-path)") == .true)
        #expect(try engine.evaluate("modal-active?") == .true)

        try engine.evaluate("(modal-exit)")
    }

    @Test func transientTreeStillExitsAfterCommand() throws {
        // Regression: a leaf must declare 'next to re-arm; a plain leaf
        // (Terminal) keeps today's one-shot launcher behavior.
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else { return }
        try loadCore(engine, schemePath)

        try engine.evaluate("""
            (fsm-install-graph! (lower-configuration (configuration
              (tree 'global (tree-root 'global
                (key "s" "Safari" (lambda () 'ok)))))))
            """)

        try engine.evaluate("(modal-activate! \"global\" '() F18)")
        try engine.evaluate("(modal-handle-key \"s\")")

        #expect(try engine.evaluate("modal-active?") == .false)
    }

    // enter-mode! is no longer exported (ADR-0015 / digit-jump-facade-async-k7):
    // the cross-edge mechanics — pushing a return frame, switching state —
    // now live inside (modaliser fsm)'s move-to! (dispatch-cutover-k11),
    // driven by fsm-step! after a leaf's 'next auto edge, never something
    // these tests — or a leaf's action — call directly. Every test below
    // drives it the same way production does: a leaf declaring 'next TARGET,
    // fired via modal-handle-key from an already-active modal (modal-key-
    // handler, enter-mode!'s only route in historically, is itself only
    // installed while a modal is active, so a "no modal active" entry is not
    // a reachable production path and isn't tested here).

    @Test func enterModeByIdEntersRegisteredTree() throws {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else { return }
        try loadCore(engine, schemePath)

        try engine.evaluate("""
            (fsm-install-graph! (lower-configuration (configuration
              (tree 'panes (tree-root 'panes
                'display-name "Pane Mode"
                (key "h" "Left" (lambda () 'ok))))
              (tree 'launcher (tree-root 'launcher
                (key "p" "Pane Mode" (lambda () 'ok) 'next 'panes))))))
            """)

        try engine.evaluate("(modal-activate! \"launcher\" '() F18)")
        try engine.evaluate("(modal-handle-key \"p\")")
        #expect(try engine.evaluate("modal-active?") == .true)
        #expect(try engine.evaluate("(member \"Pane Mode\" (modal-root-segments))") != .false)

        try engine.evaluate("(modal-exit)")
    }

    @Test func enterModeExitsExistingModalFirst() throws {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else { return }
        try loadCore(engine, schemePath)

        try engine.evaluate("""
            (define cfg (configuration
              (tree 'panes (tree-root 'panes
                (key "h" "Left" (lambda () 'ok))))
              (tree 'global (tree-root 'global
                (key "s" "Safari" (lambda () 'ok) 'next 'panes)))))
            (fsm-install-graph! (lower-configuration cfg))
            """)

        // Enter the global modal first.
        try engine.evaluate("(modal-activate! \"global\" '() F18)")
        #expect(try engine.evaluate("modal-active?") == .true)

        // The cross edge should switch us cleanly into the panes mode.
        try engine.evaluate("(modal-handle-key \"s\")")
        #expect(try engine.evaluate("modal-active?") == .true)
        #expect(try engine.evaluate(
            "(eq? modal-root-node (configuration-tree-ref cfg \"panes\"))") == .true)

        try engine.evaluate("(modal-exit)")
    }

    @Test func enterModePreservesCallerContextInBreadcrumb() throws {
        // Switching into a mode from an active modal must keep the
        // caller's breadcrumb root (e.g. the app/global segment) and append
        // the mode's segment — so the title reads "Global > Splits" rather
        // than collapsing to the bare mode name "Splits".
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else { return }
        try loadCore(engine, schemePath)

        try engine.evaluate("""
            (fsm-install-graph! (lower-configuration (configuration
              (tree 'walk-mode (tree-root 'walk-mode
                'display-name "Splits"
                (key "h" "Left" (lambda () 'ok))))
              (tree 'global (tree-root 'global
                (key "s" "Splits" (lambda () 'ok) 'next 'walk-mode))))))
            """)

        // Enter the parent (global → root segment "Global"), then cross in.
        try engine.evaluate("(modal-activate! \"global\" '() F18)")
        try engine.evaluate("(modal-handle-key \"s\")")

        // Both the caller's segment and the mode's segment are present.
        #expect(try engine.evaluate(
            "(member \"Global\" (modal-root-segments))") != .false)
        #expect(try engine.evaluate(
            "(member \"Splits\" (modal-root-segments))") != .false)

        try engine.evaluate("(modal-exit)")
    }

    @Test func walkRegistersModeAndSplicesEntries() throws {
        // (walk …) defines an "act + latch" set once: it builds a splice
        // node carrying its mode tree, whose own members cycle ('next
        // 'self), AND whose entry keys carry a 'next cross edge back to
        // that mode. Splicing it into a parent tree hoists the mode tree
        // into the configuration's tree set at the merge (walk hoisting)
        // and expands the entry keys in place (DRY — one definition, two
        // uses).
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else { return }
        try loadCore(engine, schemePath)

        try engine.evaluate("""
            (define nav
              (walk 'walk-mode "Walk"
                (key "h" "Left"  (lambda () 'l))
                (key "l" "Right" (lambda () 'r))))
            (define cfg (configuration
              (tree 'global (tree-root 'global
                (key "x" "X" (lambda () 'x))
                nav))))
            (fsm-install-graph! (lower-configuration cfg))
            (define global-root (configuration-tree-ref cfg "global"))
            (define walk-mode-root (configuration-tree-ref cfg "walk-mode"))
            """)

        // The mode tree was hoisted into the tree set and its own members cycle.
        #expect(try engine.evaluate("(node-walk? walk-mode-root)") == .true)

        // The splice expanded into the parent: the spliced key dispatches
        // and carries a 'next cross edge back to the mode.
        #expect(try engine.evaluate(
            "(find-child global-root \"h\")") != .false)
        #expect(try engine.evaluate(
            "(eq? (node-next (find-child global-root \"h\")) 'walk-mode)")
            == .true)
        // The non-spliced sibling is untouched.
        #expect(try engine.evaluate(
            "(find-child global-root \"x\")") != .false)
        // The mode's own copy of the key carries 'next 'self (it cycles via
        // its own edge, not a cross edge back to itself).
        #expect(try engine.evaluate(
            "(eq? (node-next (find-child walk-mode-root \"h\")) 'self)") == .true)
    }

    @Test func exitOnUnknownDismissesAtRoot() throws {
        // 'exit-on-unknown #t on the tree root means typing a non-binding
        // key dismisses the modal — the opposite of the default forgiving
        // behaviour. Targets cyclic focus-movement modes (a Walk, e.g.
        // iTerm pane mode) where the next non-pane keypress should reach
        // the app.
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else { return }
        try loadCore(engine, schemePath)

        try engine.evaluate("""
            (fsm-install-graph! (lower-configuration (configuration
              (tree 'panes (tree-root 'panes
                'exit-on-unknown #t
                (key "h" "Left" (lambda () 'ok) 'next 'self))))))
            """)

        try engine.evaluate("(modal-activate! \"panes\" '() F18)")
        try engine.evaluate("(modal-handle-key \"z\")")  // unknown
        #expect(try engine.evaluate("modal-active?") == .false)
    }

    @Test func exitOnUnknownIsInheritedByDescendants() throws {
        // The flag set on the root applies inside any subgroup on the
        // current path — typing a non-binding key in the Split subgroup
        // of an exit-on-unknown root still dismisses.
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else { return }
        try loadCore(engine, schemePath)

        try engine.evaluate("""
            (fsm-install-graph! (lower-configuration (configuration
              (tree 'panes (tree-root 'panes
                'exit-on-unknown #t
                (group "x" "Split"
                  (key "h" "Split Left" (lambda () 'ok))))))))
            """)

        try engine.evaluate("(modal-activate! \"panes\" '() F18)")
        try engine.evaluate("(modal-handle-key \"x\")")
        #expect(try engine.evaluate("modal-active?") == .true)

        try engine.evaluate("(modal-handle-key \"z\")")  // unknown inside Split
        #expect(try engine.evaluate("modal-active?") == .false)
    }

    @Test func exitOnUnknownOnSubgroupOnly() throws {
        // The flag on a subgroup only activates once the user is at or
        // below that subgroup — at the root (where the parent doesn't
        // have the flag), unknown keys are still swallowed.
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else { return }
        try loadCore(engine, schemePath)

        try engine.evaluate("""
            (fsm-install-graph! (lower-configuration (configuration
              (tree 'panes (tree-root 'panes
                (key "h" "Root H" (lambda () 'ok))
                (group "x" "Strict"
                  'exit-on-unknown #t
                  (key "h" "Strict H" (lambda () 'ok))))))))
            """)

        try engine.evaluate("(modal-activate! \"panes\" '() F18)")
        // Unknown at root: tree default is forgiving → swallowed.
        try engine.evaluate("(modal-handle-key \"z\")")
        #expect(try engine.evaluate("modal-active?") == .true)

        // Descend into Strict; unknown there dismisses.
        try engine.evaluate("(modal-handle-key \"x\")")
        try engine.evaluate("(modal-handle-key \"z\")")
        #expect(try engine.evaluate("modal-active?") == .false)
    }

    // MARK: - Modal stack via cross edges (fired through 'next + modal-handle-key)

    @Test func enterModeFromTransientLeafPushesCaller() throws {
        // A cross edge fired from an active modal (the launcher) pushes
        // the caller context. Backspace at the new mode's root pops back
        // to the launcher rather than exiting entirely.
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else { return }
        try loadCore(engine, schemePath)

        try engine.evaluate("""
            (define cfg (configuration
              (tree 'panes (tree-root 'panes
                (key "h" "Left" (lambda () 'ok))))
              (tree 'launcher (tree-root 'launcher
                (key "p" "Pane Mode" (lambda () 'ok) 'next 'panes)))))
            (fsm-install-graph! (lower-configuration cfg))
            """)

        try engine.evaluate("(modal-activate! \"launcher\" '() F18)")
        try engine.evaluate("(modal-handle-key \"p\")")
        #expect(try engine.evaluate(
            "(eq? modal-root-node (configuration-tree-ref cfg \"panes\"))") == .true)
        #expect(try engine.evaluate("(length modal-stack)") == .fixnum(1))

        // Backspace at the panes root pops back to the launcher — a
        // non-empty stack always has a caller to return to, regardless of
        // whether this root is a Walk.
        try engine.evaluate("(modal-step-back)")
        #expect(try engine.evaluate("modal-active?") == .true)
        #expect(try engine.evaluate(
            "(eq? modal-root-node (configuration-tree-ref cfg \"launcher\"))") == .true)
        #expect(try engine.evaluate("(null? modal-stack)") == .true)

        try engine.evaluate("(modal-exit)")
    }

    @Test func escapeClearsTheEntireStack() throws {
        // Escape (= modal-exit) tears down everything, even with pushed
        // callers — the user can never be stuck in a half-exited stack.
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else { return }
        try loadCore(engine, schemePath)

        try engine.evaluate("""
            (fsm-install-graph! (lower-configuration (configuration
              (tree 'panes (tree-root 'panes
                (key "h" "Left" (lambda () 'ok))))
              (tree 'launcher (tree-root 'launcher
                (key "p" "Pane Mode" (lambda () 'ok) 'next 'panes))))))
            """)

        try engine.evaluate("(modal-activate! \"launcher\" '() F18)")
        try engine.evaluate("(modal-handle-key \"p\")")
        #expect(try engine.evaluate("(length modal-stack)") == .fixnum(1))

        try engine.evaluate("(modal-exit)")
        #expect(try engine.evaluate("modal-active?") == .false)
        #expect(try engine.evaluate("(null? modal-stack)") == .true)
    }

    @Test func nestedEnterModeBuildsStack() throws {
        // A cross edge fired from an already-stacked mode pushes again.
        // Backspace then unwinds one level at a time.
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else { return }
        try loadCore(engine, schemePath)

        try engine.evaluate("""
            (define cfg (configuration
              (tree 'b (tree-root 'b
                (key "x" "Noop" (lambda () 'ok))))
              (tree 'a (tree-root 'a
                (key "n" "Next" (lambda () 'ok) 'next 'b)))
              (tree 'launcher (tree-root 'launcher
                (key "p" "Mode A" (lambda () 'ok) 'next 'a)))))
            (fsm-install-graph! (lower-configuration cfg))
            """)

        try engine.evaluate("(modal-activate! \"launcher\" '() F18)")
        try engine.evaluate("(modal-handle-key \"p\")")  // launcher → a
        try engine.evaluate("(modal-handle-key \"n\")")  // a → b
        #expect(try engine.evaluate("(length modal-stack)") == .fixnum(2))
        #expect(try engine.evaluate(
            "(eq? modal-root-node (configuration-tree-ref cfg \"b\"))") == .true)

        try engine.evaluate("(modal-step-back)")  // b → a
        #expect(try engine.evaluate(
            "(eq? modal-root-node (configuration-tree-ref cfg \"a\"))") == .true)
        #expect(try engine.evaluate("(length modal-stack)") == .fixnum(1))

        try engine.evaluate("(modal-step-back)")  // a → launcher
        #expect(try engine.evaluate(
            "(eq? modal-root-node (configuration-tree-ref cfg \"launcher\"))") == .true)
        #expect(try engine.evaluate("(null? modal-stack)") == .true)

        try engine.evaluate("(modal-exit)")
    }
}
