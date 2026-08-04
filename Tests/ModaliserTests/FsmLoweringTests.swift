import Foundation
import Testing
import LispKit
@testable import Modaliser

// Lowering tests: the pure lower (lower-configuration, fsm.sld) turns a
// Configuration value's trees — tree-root / screen / walk built — into
// states + edges (graph-model-k8 / closed-graph-lowering-k7), and that
// graph is what dispatch runs on (docs/specs/fsm-graph.md "Lowering and
// the façade"; ADR-0015, ADR-0018). These assert the shape of the
// lowered graph; LayoutDslTests/ConfigDslTests cover that user-visible
// dispatch behaviour is unchanged through the modal façade.
@Suite("FSM lowering (lower-configuration: value → closed graph)")
struct FsmLoweringTests {

    private func loadFsmLowering() throws -> SchemeEngine {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser util)
                  (modaliser keymap)
                  (modaliser configuration)
                  (modaliser fsm))
        """)
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")
        // Shared shorthand: lower the given contributions as ONE value and
        // install the resulting graph (build-value-then-install).
        try engine.evaluate("""
          (define (install-config! . contribs)
            (fsm-install-graph! (lower-configuration (apply configuration contribs))))
        """)
        return engine
    }

    // MARK: - Groups → resting states with implicit up edges

    @Test func groupBecomesRestingStateWithUpEdgeToItsLoweringParent() throws {
        let engine = try loadFsmLowering()
        try engine.evaluate("""
          (install-config! (tree 'grp-test (tree-root 'grp-test
            (group "f" "Find"
              (key "a" "A" (lambda () 'ok))))))
        """)
        #expect(try engine.evaluate("(eq? (fsm-state-class \"grp-test\") 'resting)") == .true)
        #expect(try engine.evaluate("(eq? (fsm-state-class \"grp-test/f\") 'resting)") == .true)
        #expect(try engine.evaluate("""
          (equal? (cdr (assoc 'target (fsm-up-edge "grp-test/f"))) "grp-test")
        """) == .true)
        // The root itself carries no up edge — backspace at depth 0 is the
        // return-stack / walk-root rule, not a graph edge.
        #expect(try engine.evaluate("(fsm-up-edge \"grp-test\")") == .false)
    }

    // MARK: - Command / range leaves → transient / terminal states

    @Test func terminalCommandHasNoEdgesAndItsActionBecomesEntry() throws {
        let engine = try loadFsmLowering()
        try engine.evaluate("""
          (define fired #f)
          (install-config! (tree 'term-test (tree-root 'term-test
            (key "a" "A" (lambda () (set! fired #t))))))
        """)
        #expect(try engine.evaluate("(eq? (fsm-state-class \"term-test/a\") 'terminal)") == .true)
        try engine.evaluate("((fsm-behavior-proc (fsm-state-entry \"term-test/a\")))")
        #expect(try engine.evaluate("fired") == .true)
    }

    @Test func nonTerminalCommandBecomesTransientWithACyclicSelfAutoEdge() throws {
        let engine = try loadFsmLowering()
        try engine.evaluate("""
          (install-config! (tree 'walk-test (tree-root 'walk-test
            (key "h" "Left" (lambda () 'ok) 'next 'self))))
        """)
        #expect(try engine.evaluate("(eq? (fsm-state-class \"walk-test/h\") 'transient)") == .true)
        #expect(try engine.evaluate("""
          (equal? (cdr (assoc 'target (car (fsm-state-edges "walk-test/h")))) "walk-test")
        """) == .true)
        #expect(try engine.evaluate("""
          (cdr (assoc 'call (car (fsm-state-edges "walk-test/h"))))
        """) == .false)
    }

    @Test func crossEdgeNextTargetsTheNamedTreeAsACallEdge() throws {
        let engine = try loadFsmLowering()
        try engine.evaluate("""
          (install-config!
            (tree 'cross-target (tree-root 'cross-target (key "z" "Z" (lambda () 'ok))))
            (tree 'cross-source (tree-root 'cross-source
              (key "h" "Focus" (lambda () 'ok) 'next 'cross-target))))
        """)
        #expect(try engine.evaluate("(eq? (fsm-state-class \"cross-source/h\") 'transient)") == .true)
        #expect(try engine.evaluate("""
          (equal? (cdr (assoc 'target (car (fsm-state-edges "cross-source/h")))) "cross-target")
        """) == .true)
        #expect(try engine.evaluate("""
          (cdr (assoc 'call (car (fsm-state-edges "cross-source/h"))))
        """) == .true)
    }

    @Test func dynamicResolverNextBecomesAProcedureValuedAutoEdge() throws {
        // dispatch-cutover-k11 reconciles the façade-audit concern flagged at
        // lower-and-shadow-k10: a dynamic resolver may itself return a bare
        // mode-id SYMBOL (the real terminal façade's "whichever backend is
        // frontmost" does — see terminal.sld's focus-pane-by-digit), but
        // (modaliser fsm)'s state ids are strings, so the target the auto
        // edge carries wraps the resolver to normalize a symbol result to
        // its string form at fire time — no longer eq? to the bare resolver,
        // but still a procedure, and still resolves through to the same
        // destination.
        let engine = try loadFsmLowering()
        try engine.evaluate("""
          (define (resolver) 'somewhere)
          (install-config! (tree 'dyn-test (tree-root 'dyn-test
            (key "h" "Focus" (lambda () 'ok) 'next resolver))))
        """)
        #expect(try engine.evaluate("""
          (let ((target (cdr (assoc 'target (car (fsm-state-edges "dyn-test/h"))))))
            (and (procedure? target) (equal? (target) "somewhere")))
        """) == .true)
    }

    // MARK: - Selectors → terminal states opening the chooser

    @Test func selectorLowersToATerminalStateThatOpensTheChooser() throws {
        let engine = try loadFsmLowering()
        try engine.evaluate("""
          (define chooser-arg #f)
          (set-open-chooser! (lambda (node) (set! chooser-arg node)))
          (install-config! (tree 'sel-test (tree-root 'sel-test
            (key "f" "Find" (selector 'prompt "Find…")))))
        """)
        #expect(try engine.evaluate("(eq? (fsm-state-class \"sel-test/f\") 'terminal)") == .true)
        try engine.evaluate("((fsm-behavior-proc (fsm-state-entry \"sel-test/f\")))")
        #expect(try engine.evaluate("(selector? chooser-arg)") == .true)
    }

    // MARK: - Panels stay transparent

    @Test func panelChildrenAttachDirectlyToTheEnclosingGroupWithNoStateOfItsOwn() throws {
        let engine = try loadFsmLowering()
        try engine.evaluate("""
          (install-config! (screen 'panel-test
            (panel "Windows" (key "c" "Center" (lambda () 'ok)))))
        """)
        // The panel itself never became a state...
        #expect(try engine.evaluate("(fsm-state-ref \"panel-test/Windows\")") == .false)
        // ...its child's key edge attaches straight to the screen root.
        #expect(try engine.evaluate("""
          (equal? (cdr (assoc 'target (find (lambda (e) (equal? (cdr (assoc 'trigger e)) "c"))
                                             (fsm-state-edges "panel-test"))))
                  "panel-test/c")
        """) == .true)
    }

    // MARK: - Literal shadows range in the explicit per-key edge set

    @Test func literalKeyShadowsARangeCoveringTheSameKeyInTheEdgeSet() throws {
        let engine = try loadFsmLowering()
        try engine.evaluate("""
          (install-config! (tree 'shadow-test (tree-root 'shadow-test
            (keys '("1" ..) "Space <n>" (lambda (k i ks) 'ranged))
            (key "1" "Special" (lambda () 'special)))))
        """)
        // Trigger "1" resolves to the LITERAL command, not the range.
        #expect(try engine.evaluate("""
          (equal? (cdr (assoc 'target (find (lambda (e) (equal? (cdr (assoc 'trigger e)) "1"))
                                             (fsm-state-edges "shadow-test"))))
                  "shadow-test/1")
        """) == .true)
        // "2" is uncontested — still resolves to the range's own state.
        #expect(try engine.evaluate("""
          (equal? (cdr (assoc 'target (find (lambda (e) (equal? (cdr (assoc 'trigger e)) "2"))
                                             (fsm-state-edges "shadow-test"))))
                  "shadow-test/1..")
        """) == .true)
        #expect(try engine.evaluate("(eq? (fsm-state-class \"shadow-test/1\") 'terminal)") == .true)
    }

    // MARK: - Stamped unknown-key policy (inherited at lowering, not walked live)

    @Test func exitOnUnknownIsInheritedAndStampedOnEveryDescendantState() throws {
        let engine = try loadFsmLowering()
        try engine.evaluate("""
          (install-config! (tree 'unk-test (tree-root 'unk-test 'exit-on-unknown #t
            (group "f" "Find" (key "a" "A" (lambda () 'ok))))))
        """)
        #expect(try engine.evaluate("(fsm-state-exit-on-unknown? \"unk-test\")") == .true)
        #expect(try engine.evaluate("(fsm-state-exit-on-unknown? \"unk-test/f\")") == .true)
    }

    @Test func exitOnUnknownDefaultsToForgivingWhenUndeclared() throws {
        let engine = try loadFsmLowering()
        try engine.evaluate("""
          (install-config! (tree 'forgiving-test
            (tree-root 'forgiving-test (key "a" "A" (lambda () 'ok)))))
        """)
        #expect(try engine.evaluate("(fsm-state-exit-on-unknown? \"forgiving-test\")") == .false)
    }

    // MARK: - on-enter/on-leave land in show/hide (presentation-gated), not entry/exit

    @Test func onEnterOnLeaveLowerToShowHideNotEntryExit() throws {
        let engine = try loadFsmLowering()
        try engine.evaluate("""
          (define entered #f)
          (define left #f)
          (install-config! (tree 'hook-test (tree-root 'hook-test
            'on-enter (lambda () (set! entered #t))
            'on-leave (lambda () (set! left #t))
            (key "a" "A" (lambda () 'ok)))))
        """)
        #expect(try engine.evaluate("(fsm-state-entry \"hook-test\")") == .false)
        #expect(try engine.evaluate("(fsm-state-exit \"hook-test\")") == .false)
        try engine.evaluate("((fsm-behavior-proc (fsm-state-show \"hook-test\")))")
        #expect(try engine.evaluate("entered") == .true)
        try engine.evaluate("((fsm-behavior-proc (fsm-state-hide \"hook-test\")))")
        #expect(try engine.evaluate("left") == .true)
    }

    // MARK: - Unconditional entry/exit hooks (entry-exit-slot-wiring-k47):
    // `group`/`tree-root`'s optional 'entry/'exit keyword pair lowers
    // straight onto the state's own entry/exit slots — distinct from
    // 'on-enter/'on-leave, which lower onto the presentation-gated show/
    // hide pair (see onEnterOnLeaveLowerToShowHideNotEntryExit above). No
    // engine change: fsm.sld already fires entry/exit unconditionally at
    // come-to-rest / visit-end (move-to!/end-old-visit!) — this just proves
    // the new authoring surface reaches those existing slots correctly.

    @Test func entryExitLowerOntoTheirOwnSlotsNotShowHide() throws {
        let engine = try loadFsmLowering()
        try engine.evaluate("""
          (define entered #f)
          (define left #f)
          (install-config! (tree 'entry-exit-lower-test (tree-root 'entry-exit-lower-test
            'entry (lambda () (set! entered #t))
            'exit (lambda () (set! left #t))
            (key "a" "A" (lambda () 'ok)))))
        """)
        #expect(try engine.evaluate("(fsm-state-show \"entry-exit-lower-test\")") == .false)
        #expect(try engine.evaluate("(fsm-state-hide \"entry-exit-lower-test\")") == .false)
        try engine.evaluate("((fsm-behavior-proc (fsm-state-entry \"entry-exit-lower-test\")))")
        #expect(try engine.evaluate("entered") == .true)
        try engine.evaluate("((fsm-behavior-proc (fsm-state-exit \"entry-exit-lower-test\")))")
        #expect(try engine.evaluate("left") == .true)
    }

    @Test func entryFiresSynchronouslyInModalEnterWithoutWaitingOutTheOverlayDelay() throws {
        let engine = try loadFsmLowering()
        try engine.evaluate("""
          (define entered #f)
          (define shown #f)
          (install-config! (tree 'entry-timing-test (tree-root 'entry-timing-test
            'entry (lambda () (set! entered #t))
            'on-enter (lambda () (set! shown #t))
            (key "a" "A" (lambda () 'ok)))))
        """)
        // Default modal-overlay-delay (1.0s) never gets a chance to elapse in
        // this synchronous test — the delayed after-delay callback simply
        // never runs — so 'shown staying #f also proves 'on-enter's gated
        // behaviour is unaffected by 'entry existing alongside it.
        try engine.evaluate("(modal-activate! \"entry-timing-test\" '() F18)")
        #expect(try engine.evaluate("entered") == .true)
        #expect(try engine.evaluate("shown") == .false)
        try engine.evaluate("(modal-exit)")
    }

    @Test func exitFiresOnNavigateAwayAndOnModalExit() throws {
        let engine = try loadFsmLowering()
        try engine.evaluate("""
          (define root-exited #f)
          (define child-exited #f)
          (install-config! (tree 'exit-timing-test (tree-root 'exit-timing-test
            'exit (lambda () (set! root-exited #t))
            (group "g" "G" 'exit (lambda () (set! child-exited #t))
              (key "a" "A" (lambda () 'ok))))))
        """)
        try engine.evaluate("(modal-activate! \"exit-timing-test\" '() F18)")
        #expect(try engine.evaluate("root-exited") == .false)
        // Descending into the child group ends the root's Visit — 'exit
        // fires unconditionally (navigate-away), even though the overlay
        // never displayed (the delay never elapsed).
        try engine.evaluate("(modal-handle-key \"g\")")
        #expect(try engine.evaluate("root-exited") == .true)
        #expect(try engine.evaluate("child-exited") == .false)
        // modal-exit ends the child's Visit too.
        try engine.evaluate("(modal-exit)")
        #expect(try engine.evaluate("child-exited") == .true)
    }

    // MARK: - display-name / renderer payloads ride the state's presentation payload

    @Test func payloadCarriesTheOriginalNodeIncludingItsDisplayValue() throws {
        let engine = try loadFsmLowering()
        try engine.evaluate("""
          (install-config! (screen 'payload-test 'display-name "Title"
            (panel "P" (key "c" "C" (lambda () 'ok)))))
        """)
        #expect(try engine.evaluate("""
          (equal? (node-display-name (fsm-state-payload "payload-test")) "Title")
        """) == .true)
        #expect(try engine.evaluate("""
          (pair? (node-display-ref (fsm-state-payload "payload-test") 'panels))
        """) == .true)
    }

    // MARK: - The gated step-in edge (an authored cross-tree key edge)

    @Test func stepInLowersToAGatedKeyEdgeWithNoStateOfItsOwn() throws {
        let engine = try loadFsmLowering()
        try engine.evaluate("""
          (install-config!
            (screen 'step-in-target-test (key "a" "A" (lambda () 'ok)))
            (screen 'step-in-source-test
              (step-in "." "In" 'step-in-target-test (lambda () #t))))
        """)
        // No intermediate state was created for the "." child...
        #expect(try engine.evaluate("(fsm-state-ref \"step-in-source-test/.\")") == .false)
        // ...the parent instead carries a plain key edge straight to the
        // target — not a call, unlike a (key … 'next TARGET) cross edge.
        #expect(try engine.evaluate("""
          (let ((e (find (lambda (e) (equal? (cdr (assoc 'trigger e)) "."))
                          (fsm-state-edges "step-in-source-test"))))
            (and (equal? (cdr (assoc 'target e)) "step-in-target-test")
                 (not (cdr (assoc 'call e)))))
        """) == .true)
    }

    @Test func stepInEdgeIsLiveOnlyWhileItsGatePasses() throws {
        let engine = try loadFsmLowering()
        try engine.evaluate("""
          (define gate-open #f)
          (define cfg (configuration
            (screen 'gate-target-test (key "a" "A" (lambda () 'ok)))
            (screen 'gate-source-test
              ;; An always-live sibling key, exactly like the real iTerm
              ;; screen: with ONLY the gated step-in, gating it off would
              ;; leave zero live key edges and the root would classify as
              ;; terminal (halting on activation) rather than resting.
              (key "x" "X" (lambda () 'ok))
              (step-in "." "In" 'gate-target-test (lambda () gate-open)))))
          (fsm-install-graph! (lower-configuration cfg))
        """)
        // Gate closed at visit start: "." is not a live edge — falls to the
        // ordinary unknown-key policy (forgiving default — swallowed).
        try engine.evaluate("(modal-activate! \"gate-source-test\" '() F18)")
        try engine.evaluate("(modal-handle-key \".\")")
        #expect(try engine.evaluate("(eq? modal-root-node (configuration-tree-ref cfg \"gate-source-test\"))") == .true)
        #expect(try engine.evaluate("modal-active?") == .true)
        try engine.evaluate("(modal-exit)")

        // Gate open at visit start: the same key moves straight to the
        // target, immediately — a plain group descent, not a delayed
        // cross-tree call.
        try engine.evaluate("(set! gate-open #t)")
        try engine.evaluate("(modal-activate! \"gate-source-test\" '() F18)")
        try engine.evaluate("(modal-handle-key \".\")")
        #expect(try engine.evaluate("(eq? modal-root-node (configuration-tree-ref cfg \"gate-target-test\"))") == .true)
        #expect(try engine.evaluate("(null? modal-stack)") == .true)
    }

    // MARK: - Walk members' cyclic edges (both copies `walk` builds)

    @Test func walkRegisteredModeMembersCarryCyclicAutoEdgesBackToTheModeRoot() throws {
        let engine = try loadFsmLowering()
        try engine.evaluate("""
          (install-config! (screen 'cyclic-walk-host
            (walk 'cyclic-walk-test "Walk" (key "h" "Left" (lambda () 'ok)))))
        """)
        #expect(try engine.evaluate("(eq? (fsm-state-class \"cyclic-walk-test/h\") 'transient)") == .true)
        #expect(try engine.evaluate("""
          (equal? (cdr (assoc 'target (car (fsm-state-edges "cyclic-walk-test/h"))))
                  "cyclic-walk-test")
        """) == .true)
    }

    @Test func walkSpliceEntryCopyCarriesACallEdgeIntoTheModeAtItsOwnSpliceSite() throws {
        let engine = try loadFsmLowering()
        try engine.evaluate("""
          (install-config! (screen 'walk-entry-site-test
            (walk 'cyclic-walk-entry-test "Walk" (key "h" "Left" (lambda () 'ok)))))
        """)
        #expect(try engine.evaluate("(eq? (fsm-state-class \"walk-entry-site-test/h\") 'transient)") == .true)
        #expect(try engine.evaluate("""
          (equal? (cdr (assoc 'target (car (fsm-state-edges "walk-entry-site-test/h"))))
                  "cyclic-walk-entry-test")
        """) == .true)
        #expect(try engine.evaluate("""
          (cdr (assoc 'call (car (fsm-state-edges "walk-entry-site-test/h"))))
        """) == .true)
    }

    // MARK: - DSL provider wiring (dsl-provider-wiring-k24): `group` /
    // `tree-root` thread an optional 'provider onto the lowered FSM
    // state, mirroring on-enter/on-leave — but straight onto the state's
    // 'provider slot rather than show/hide, since a provider's live edges/
    // synthetic states are what dispatch itself consults. Toy case only —
    // no herdr involvement (that's jump-dispatch-wiring, the next child).

    @Test func groupProviderFiresAtVisitStartAndItsEdgesAndStatesAreLiveAndDispatchable() throws {
        let engine = try loadFsmLowering()
        try engine.evaluate("""
          (define fired #f)
          (install-config! (tree 'provider-wiring-test (tree-root 'provider-wiring-test
            (group "g" "G" 'provider
              (lambda (owner-id)
                (list (cons 'edges (list (edge "j" 'provided-target)))
                      (cons 'states (list (provided-state 'provided-target
                                            'entry (lambda () (set! fired #t)))))))
              (key "a" "A" (lambda () 'ok))))))
        """)
        try engine.evaluate("(modal-activate! \"provider-wiring-test\" '() F18)")
        try engine.evaluate("(modal-handle-key \"g\")")
        // "j" was never declared on the group directly — only the provider,
        // run at come-to-rest, contributes it for this Visit.
        try engine.evaluate("(modal-handle-key \"j\")")
        #expect(try engine.evaluate("fired") == .true)
        try engine.evaluate("(modal-exit)")
    }

    // MARK: - The provider calling convention (provider-state-id-k9): a
    // provider is invoked with ONE argument, the id of the state it was
    // lowered onto. Not decoration — a provider minting a provided RESTING
    // state must id it `<owner-id>/<key>` and point its 'up edge at
    // `<owner-id>`, and %fsm-visit-owner is no substitute: it still holds
    // the PREVIOUS owner when the provider runs.

    @Test func providerIsCalledWithTheIdOfTheStateItIsLoweredOnto() throws {
        let engine = try loadFsmLowering()
        try engine.evaluate("""
          (define root-saw #f)
          (define group-saw #f)
          (install-config! (tree 'owner-id-test (tree-root 'owner-id-test
            'provider (lambda (owner-id) (set! root-saw owner-id) '())
            (group "g" "G" 'provider
              (lambda (owner-id) (set! group-saw owner-id) '())
              (key "a" "A" (lambda () 'ok))))))
        """)
        try engine.evaluate("(modal-activate! \"owner-id-test\" '() F18)")
        #expect(try engine.evaluate("(equal? root-saw \"owner-id-test\")") == .true)
        // Not yet visited — the group's provider runs at ITS come-to-rest.
        #expect(try engine.evaluate("group-saw") == .false)
        try engine.evaluate("(modal-handle-key \"g\")")
        #expect(try engine.evaluate("(equal? group-saw \"owner-id-test/g\")") == .true)
        try engine.evaluate("(modal-exit)")
    }

    // MARK: - `open` threads 'provider (provider-state-id-k9)

    @Test func openThreadsProviderOntoItsGroupsStateAndTheProvidedEdgesDispatch() throws {
        let engine = try loadFsmLowering()
        try engine.evaluate("""
          (define fired #f)
          (define seen #f)
          (install-config! (screen 'open-provider-test
            (panel "P"
              (open "w" "Windows" 'provider
                (lambda (owner-id)
                  (set! seen owner-id)
                  (list (cons 'edges (list (edge "j" 'open-provided-target)))
                        (cons 'states (list (provided-state 'open-provided-target
                                              'entry (lambda () (set! fired #t)))))))
                (panel "Q" (key "a" "A" (lambda () 'ok)))))))
        """)
        try engine.evaluate("(modal-activate! \"open-provider-test\" '() F18)")
        try engine.evaluate("(modal-handle-key \"w\")")
        #expect(try engine.evaluate("(equal? seen \"open-provider-test/w\")") == .true)
        // "j" exists only for this Visit, contributed by the provider `open`
        // now threads through — before provider-state-id-k9 it was dropped.
        try engine.evaluate("(modal-handle-key \"j\")")
        #expect(try engine.evaluate("fired") == .true)
        try engine.evaluate("(modal-exit)")
    }

    // The motivating shape (docs/specs/paneru-window-management.md decision
    // 4): a two-key jump label needs a narrowing PREFIX state, whose id and
    // 'up edge are both derived from the owner id the provider is handed.
    // Nothing else in the graph can supply them. Mirrors herdr.sld's
    // jump-prefix-state, including its own 'provider re-minting the terminal
    // targets — landing on a provided RESTING state begins a new Visit,
    // which discards whatever the previous visit owner installed.
    @Test func providerMintsANarrowingPrefixStateFromItsOwnerId() throws {
        let engine = try loadFsmLowering()
        try engine.evaluate("""
          (define landed #f)
          (define (target-state prefix)
            (provided-state (string-append prefix "/d")
              'entry (lambda () (set! landed #t))))
          (install-config! (screen 'narrow-test
            (panel "P"
              (open "w" "Windows" 'provider
                (lambda (owner-id)
                  (let ((prefix (string-append owner-id "/a")))
                    (list (cons 'edges (list (edge "a" prefix)))
                          (cons 'states
                                (list (provided-state prefix 'payload '()
                                        'provider (lambda (own-id)
                                                    (list (cons 'states (list (target-state own-id)))))
                                        (edge 'up owner-id)
                                        (edge "d" (string-append prefix "/d"))))))))
                (panel "Q" (key "z" "Z" (lambda () 'ok)))))))
        """)
        try engine.evaluate("(modal-activate! \"narrow-test\" '() F18)")
        try engine.evaluate("(modal-handle-key \"w\")")
        try engine.evaluate("(modal-handle-key \"a\")")
        // The prefix state's id is the owner's, extended by the leader key —
        // so it reads as a child of the node it narrowed, not a stray root.
        #expect(try engine.evaluate("(equal? (fsm-current-state) \"narrow-test/w/a\")") == .true)
        // Its 'up edge climbs back to the owner rather than dead-ending.
        try engine.evaluate("(modal-step-back)")
        #expect(try engine.evaluate("(equal? (fsm-current-state) \"narrow-test/w\")") == .true)
        // Narrow again and complete the two-key label.
        try engine.evaluate("(modal-handle-key \"a\")")
        try engine.evaluate("(modal-handle-key \"d\")")
        #expect(try engine.evaluate("landed") == .true)
        try engine.evaluate("(modal-exit)")
    }

    // MARK: - The whole bundled config hands off to a well-formed, live graph

    @Test func defaultConfigHandsOffAndResolvesActivationThroughTheContextMap() throws {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("Scheme directory not found")
            throw SchemeTestError.noSchemeDir
        }
        // Stub WebView primitives, mirroring ConfigDslTests.loadAllModules.
        try engine.evaluate("""
            (define (webview-create id opts) id)
            (define (webview-close id) #f)
            (define (webview-set-html! id html) #f)
            (define (webview-on-message id handler) #t)
            (define (webview-eval id js) #t)
            """)
        try engine.evaluate("""
          (import (modaliser util)
                  (modaliser keymap)
                  (modaliser fsm))
        """)
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")
        try engine.evaluate("(import (modaliser terminal))")
        try engine.evaluate("(import (modaliser ax-hints))")
        try engine.evaluate("(import (modaliser dom))")
        try engine.evaluate("(import (modaliser web-search))")
        for file in ["ui/css.scm", "ui/overlay.scm", "ui/chooser.scm"] {
            try engine.evaluateFile(schemePath + "/" + file)
        }
        try engine.evaluate("(set-chooser-push! chooser-push-results)")

        try engine.evaluateFile(schemePath + "/default-config.scm")

        // The config's own (modaliser:start! …) ran: the value is
        // installed, and its graph is the engine's live graph.
        try engine.evaluate("""
          (import (modaliser configuration)
                  (modaliser activation)
                  (modaliser handoff))
        """)
        #expect(try engine.evaluate("(configuration? (modaliser:configuration))") == .true)
        for scope in ["global", "com.googlecode.iterm2", "herdr", "nvim", "zellij"] {
            #expect(try engine.evaluate("(and (fsm-state-ref \"\(scope)\") #t)") == .true,
                    "missing installed state \(scope)")
        }

        // Activation resolves through the installed value's context map
        // (the entry table's replacement): iTerm alone lands on the
        // iTerm screen; an iTerm→herdr chain lands on herdr with the
        // host screen seeded for the outward backspace.
        try engine.evaluate("""
          (define (frame sym fg) (cons sym (vector 'pane "p" 'fg fg)))
          (define installed (modaliser:configuration))
        """)
        #expect(try engine.evaluate("""
          (equal? (resolve-activation 'local "com.googlecode.iterm2"
                    (list (frame 'iterm "zsh")) installed)
                  '((root . "com.googlecode.iterm2") (stack)))
        """) == .true)
        #expect(try engine.evaluate("""
          (equal? (resolve-activation 'local "com.googlecode.iterm2"
                    (list (frame 'iterm "herdr") (frame 'herdr "zsh")) installed)
                  '((root . "herdr") (stack "com.googlecode.iterm2")))
        """) == .true)

        // The global root's "b" (Browser, per ConfigDslTests) key resolves
        // to a reachable, registered fsm state.
        #expect(try engine.evaluate("""
          (equal? (cdr (assoc 'target (find (lambda (e) (equal? (cdr (assoc 'trigger e)) "b"))
                                             (fsm-state-edges "global"))))
                  "global/b")
        """) == .true)
        #expect(try engine.evaluate("(fsm-state-ref \"global/b\")") != .false)
    }
}
