import Foundation
import Testing
import LispKit
@testable import Modaliser

// Lowering tests for fsm-core: the layout lowering (register-tree! /
// screen in state-machine.sld / dsl.sld) builds the operational tree
// straight into (modaliser fsm) states + edges (graph-model-k8 /
// lower-and-shadow-k10), and since dispatch-cutover-k11 that graph is
// what dispatch actually runs on (docs/specs/fsm-graph.md "Lowering and
// the façade"; ADR-0015). These assert the shape of the lowered graph;
// LayoutDslTests/ConfigDslTests cover that user-visible dispatch
// behaviour is unchanged through the façade.
@Suite("FSM shadow lowering (register-tree! / screen mirror into (modaliser fsm))")
struct FsmLoweringTests {

    private func loadFsmLowering() throws -> SchemeEngine {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser util)
                  (modaliser keymap)
                  (modaliser state-machine)
                  (modaliser fsm))
        """)
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")
        return engine
    }

    // MARK: - Groups → resting states with implicit up edges

    @Test func groupBecomesRestingStateWithUpEdgeToItsLoweringParent() throws {
        let engine = try loadFsmLowering()
        try engine.evaluate("""
          (register-tree! 'grp-test
            (group "f" "Find"
              (key "a" "A" (lambda () 'ok))))
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
          (register-tree! 'term-test
            (key "a" "A" (lambda () (set! fired #t))))
        """)
        #expect(try engine.evaluate("(eq? (fsm-state-class \"term-test/a\") 'terminal)") == .true)
        try engine.evaluate("((fsm-behavior-proc (fsm-state-entry \"term-test/a\")))")
        #expect(try engine.evaluate("fired") == .true)
    }

    @Test func nonTerminalCommandBecomesTransientWithACyclicSelfAutoEdge() throws {
        let engine = try loadFsmLowering()
        try engine.evaluate("""
          (register-tree! 'walk-test
            (key "h" "Left" (lambda () 'ok) 'next 'self))
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
          (register-tree! 'cross-target (key "z" "Z" (lambda () 'ok)))
          (register-tree! 'cross-source
            (key "h" "Focus" (lambda () 'ok) 'next 'cross-target))
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
          (register-tree! 'dyn-test
            (key "h" "Focus" (lambda () 'ok) 'next resolver))
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
          (register-tree! 'sel-test
            (key "f" "Find" (selector 'prompt "Find…")))
        """)
        #expect(try engine.evaluate("(eq? (fsm-state-class \"sel-test/f\") 'terminal)") == .true)
        try engine.evaluate("((fsm-behavior-proc (fsm-state-entry \"sel-test/f\")))")
        #expect(try engine.evaluate("(selector? chooser-arg)") == .true)
    }

    // MARK: - Panels stay transparent

    @Test func panelChildrenAttachDirectlyToTheEnclosingGroupWithNoStateOfItsOwn() throws {
        let engine = try loadFsmLowering()
        try engine.evaluate("""
          (screen 'panel-test
            (panel "Windows" (key "c" "Center" (lambda () 'ok))))
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
          (register-tree! 'shadow-test
            (keys '("1" ..) "Space <n>" (lambda (k i ks) 'ranged))
            (key "1" "Special" (lambda () 'special)))
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
          (register-tree! 'unk-test 'exit-on-unknown #t
            (group "f" "Find" (key "a" "A" (lambda () 'ok))))
        """)
        #expect(try engine.evaluate("(fsm-state-exit-on-unknown? \"unk-test\")") == .true)
        #expect(try engine.evaluate("(fsm-state-exit-on-unknown? \"unk-test/f\")") == .true)
    }

    @Test func exitOnUnknownDefaultsToForgivingWhenUndeclared() throws {
        let engine = try loadFsmLowering()
        try engine.evaluate("""
          (register-tree! 'forgiving-test (key "a" "A" (lambda () 'ok)))
        """)
        #expect(try engine.evaluate("(fsm-state-exit-on-unknown? \"forgiving-test\")") == .false)
    }

    // MARK: - on-enter/on-leave land in show/hide (presentation-gated), not entry/exit

    @Test func onEnterOnLeaveLowerToShowHideNotEntryExit() throws {
        let engine = try loadFsmLowering()
        try engine.evaluate("""
          (define entered #f)
          (define left #f)
          (register-tree! 'hook-test
            'on-enter (lambda () (set! entered #t))
            'on-leave (lambda () (set! left #t))
            (key "a" "A" (lambda () 'ok)))
        """)
        #expect(try engine.evaluate("(fsm-state-entry \"hook-test\")") == .false)
        #expect(try engine.evaluate("(fsm-state-exit \"hook-test\")") == .false)
        try engine.evaluate("((fsm-behavior-proc (fsm-state-show \"hook-test\")))")
        #expect(try engine.evaluate("entered") == .true)
        try engine.evaluate("((fsm-behavior-proc (fsm-state-hide \"hook-test\")))")
        #expect(try engine.evaluate("left") == .true)
    }

    // MARK: - Unconditional entry/exit hooks (entry-exit-slot-wiring-k47):
    // `group`/`register-tree!`'s optional 'entry/'exit keyword pair lowers
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
          (register-tree! 'entry-exit-lower-test
            'entry (lambda () (set! entered #t))
            'exit (lambda () (set! left #t))
            (key "a" "A" (lambda () 'ok)))
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
          (register-tree! 'entry-timing-test
            'entry (lambda () (set! entered #t))
            'on-enter (lambda () (set! shown #t))
            (key "a" "A" (lambda () 'ok)))
        """)
        // Default modal-overlay-delay (1.0s) never gets a chance to elapse in
        // this synchronous test — the delayed after-delay callback simply
        // never runs — so 'shown staying #f also proves 'on-enter's gated
        // behaviour is unaffected by 'entry existing alongside it.
        try engine.evaluate("(modal-enter (lookup-tree \"entry-timing-test\") F18)")
        #expect(try engine.evaluate("entered") == .true)
        #expect(try engine.evaluate("shown") == .false)
        try engine.evaluate("(modal-exit)")
    }

    @Test func exitFiresOnNavigateAwayAndOnModalExit() throws {
        let engine = try loadFsmLowering()
        try engine.evaluate("""
          (define root-exited #f)
          (define child-exited #f)
          (register-tree! 'exit-timing-test
            'exit (lambda () (set! root-exited #t))
            (group "g" "G" 'exit (lambda () (set! child-exited #t))
              (key "a" "A" (lambda () 'ok))))
        """)
        try engine.evaluate("(modal-enter (lookup-tree \"exit-timing-test\") F18)")
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

    @Test func payloadCarriesTheOriginalNodeIncludingDisplayNameAndRendererMarkers() throws {
        let engine = try loadFsmLowering()
        try engine.evaluate("""
          (screen 'payload-test 'display-name "Title"
            (panel "P" (key "c" "C" (lambda () 'ok))))
        """)
        #expect(try engine.evaluate("""
          (equal? (cdr (assoc 'display-name (fsm-state-payload "payload-test"))) "Title")
        """) == .true)
        #expect(try engine.evaluate("""
          (eq? (cdr (assoc 'renderer (fsm-state-payload "payload-test"))) 'panel-grid)
        """) == .true)
    }

    // MARK: - Entry rows: `screen` adds one; `walk`'s internal mode-id doesn't

    @Test func screenAddsAnUngatedEntryRowForItsScope() throws {
        let engine = try loadFsmLowering()
        try engine.evaluate("(screen 'entry-base-test (key \"a\" \"A\" (lambda () 'ok)))")
        #expect(try engine.evaluate("(fsm-entry-ref \"entry-base-test\")") != .false)
        #expect(try engine.evaluate("""
          (equal? (cdr (assoc 'target (fsm-entry-ref "entry-base-test"))) "entry-base-test")
        """) == .true)
    }

    @Test func walkModeIdRegistrationGetsNoEntryRow() throws {
        let engine = try loadFsmLowering()
        try engine.evaluate("""
          (walk 'entry-walk-test "Walk" (key "h" "Left" (lambda () 'ok)))
        """)
        #expect(try engine.evaluate("(fsm-entry-ref \"entry-walk-test\")") == .false)
    }

    @Test func suffixVariantEntryRefinesItsBaseOutrankingItInSpecificity() throws {
        let engine = try loadFsmLowering()
        try engine.evaluate("""
          (screen 'com.example.variant-test (key "a" "A" (lambda () 'ok)))
          (screen "com.example.variant-test/herdr" (key "a" "A" (lambda () 'ok)))
        """)
        #expect(try engine.evaluate("""
          (fsm-entry-more-specific? "com.example.variant-test/herdr" "com.example.variant-test")
        """) == .true)
        #expect(try engine.evaluate("""
          (equal? (cdr (assoc 'refines (fsm-entry-ref "com.example.variant-test/herdr")))
                  "com.example.variant-test")
        """) == .true)
    }

    @Test func suffixVariantRegisteredBeforeItsBaseOmitsRefinesInsteadOfErroring() throws {
        // Ordering isn't guaranteed for a hand-written config — the base
        // entry simply doesn't exist yet, so `refines` is omitted instead
        // of raising fsm-entry!'s "unknown entry" error.
        let engine = try loadFsmLowering()
        #expect(throws: Never.self) {
            try engine.evaluate("""
              (screen "com.example.out-of-order/herdr" (key "a" "A" (lambda () 'ok)))
              (screen 'com.example.out-of-order (key "a" "A" (lambda () 'ok)))
            """)
        }
        #expect(try engine.evaluate("""
          (cdr (assoc 'refines (fsm-entry-ref "com.example.out-of-order/herdr")))
        """) == .false)
    }

    // MARK: - Nested-context entry points (ADR-0013): outward up edges
    // crossing tree boundaries, and the gated step-in edge that enters them.

    @Test func registerTreeUpEdgeMakesTheNestedEntryOutrankItsContainer() throws {
        let engine = try loadFsmLowering()
        try engine.evaluate("""
          (screen 'outer-nest-test (key "a" "A" (lambda () 'ok)))
          (screen 'inner-nest-test 'auto-entry #f (key "b" "B" (lambda () 'ok)))
          (register-tree-up-edge! 'inner-nest-test 'outer-nest-test)
          (register-tree-entry-gated! 'inner-nest-test (lambda () #t))
        """)
        // Ranked by structural nesting (the up edge), not a 'refines stamp.
        #expect(try engine.evaluate("""
          (fsm-entry-more-specific? "inner-nest-test" "outer-nest-test")
        """) == .true)
        #expect(try engine.evaluate("""
          (cdr (assoc 'refines (fsm-entry-ref "inner-nest-test")))
        """) == .false)
        #expect(try engine.evaluate("""
          (equal? (cdr (assoc 'target (fsm-up-edge "inner-nest-test"))) "outer-nest-test")
        """) == .true)
    }

    @Test func registerTreeUpEdgeAndEntryGatedAreIdempotent() throws {
        // A second wiring call (config reload, a mux's register! called
        // twice) must not raise fsm-edge!'s "state already has an up edge"
        // or fsm-entry!'s "duplicate entry name" — mirrors register-tree!'s
        // own safe-to-call-more-than-once contract.
        let engine = try loadFsmLowering()
        try engine.evaluate("""
          (screen 'outer-idem-test (key "a" "A" (lambda () 'ok)))
          (screen 'inner-idem-test 'auto-entry #f (key "b" "B" (lambda () 'ok)))
        """)
        #expect(throws: Never.self) {
            try engine.evaluate("""
              (register-tree-up-edge! 'inner-idem-test 'outer-idem-test)
              (register-tree-up-edge! 'inner-idem-test 'outer-idem-test)
              (register-tree-entry-gated! 'inner-idem-test (lambda () #t))
              (register-tree-entry-gated! 'inner-idem-test (lambda () #f))
            """)
        }
    }

    @Test func stepInLowersToAGatedKeyEdgeWithNoStateOfItsOwn() throws {
        let engine = try loadFsmLowering()
        try engine.evaluate("""
          (screen 'step-in-target-test (key "a" "A" (lambda () 'ok)))
          (screen 'step-in-source-test
            (step-in "." "In" 'step-in-target-test (lambda () #t)))
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
          (screen 'gate-target-test (key "a" "A" (lambda () 'ok)))
          (screen 'gate-source-test
            ;; An always-live sibling key, exactly like the real iTerm
            ;; screen: with ONLY the gated step-in, gating it off would
            ;; leave zero live key edges and the root would classify as
            ;; terminal (halting on activation) rather than resting.
            (key "x" "X" (lambda () 'ok))
            (step-in "." "In" 'gate-target-test (lambda () gate-open)))
        """)
        // Gate closed at visit start: "." is not a live edge — falls to the
        // ordinary unknown-key policy (forgiving default — swallowed).
        try engine.evaluate("(modal-enter (lookup-tree \"gate-source-test\") F18)")
        try engine.evaluate("(modal-handle-key \".\")")
        #expect(try engine.evaluate("(eq? modal-root-node (lookup-tree \"gate-source-test\"))") == .true)
        #expect(try engine.evaluate("modal-active?") == .true)
        try engine.evaluate("(modal-exit)")

        // Gate open at visit start: the same key moves straight to the
        // target, immediately — a plain group descent, not a delayed
        // cross-tree call.
        try engine.evaluate("(set! gate-open #t)")
        try engine.evaluate("(modal-enter (lookup-tree \"gate-source-test\") F18)")
        try engine.evaluate("(modal-handle-key \".\")")
        #expect(try engine.evaluate("(eq? modal-root-node (lookup-tree \"gate-target-test\"))") == .true)
        #expect(try engine.evaluate("(null? modal-stack)") == .true)
    }

    @Test func breadcrumbAndPathStayScopedToTheNestedTreeUntilBackspacingOut() throws {
        // Regression coverage for the invariant dispatch-cutover-k11 baked
        // into fsm-tree-root/derive-current-path — "a registered tree's
        // root carries no up edge, so the ancestor chain never crosses a
        // tree boundary" — which ADR-0013's outward up edge deliberately
        // breaks. fsm-tree-root/derive-current-path must stop the climb at
        // the nested tree's OWN root, not the container's.
        let engine = try loadFsmLowering()
        try engine.evaluate("""
          (screen 'crumb-outer-test (key "a" "A" (lambda () 'ok)))
          (screen 'crumb-inner-test 'auto-entry #f
            (group "g" "Group" (key "b" "B" (lambda () 'ok))))
          (register-tree-up-edge! 'crumb-inner-test 'crumb-outer-test)
        """)
        try engine.evaluate("(modal-enter (lookup-tree \"crumb-inner-test\") F18)")
        // At the nested root: path empty, root is the nested tree's OWN
        // root — the up edge must not make the root resolve outward.
        #expect(try engine.evaluate("(eq? modal-root-node (lookup-tree \"crumb-inner-test\"))") == .true)
        #expect(try engine.evaluate("(null? modal-current-path)") == .true)

        // A level deeper: the path is relative to the nested root, not the
        // container — exactly where an unbounded ancestor walk would have
        // produced a corrupted (too-long, wrongly-rooted) path.
        try engine.evaluate("(modal-handle-key \"g\")")
        #expect(try engine.evaluate("(eq? modal-root-node (lookup-tree \"crumb-inner-test\"))") == .true)
        #expect(try engine.evaluate("(equal? modal-current-path '(\"g\"))") == .true)
        #expect(try engine.evaluate("(null? modal-stack)") == .true)

        // Backspace out: two ordinary up-edge moves (structural, then the
        // declared cross-tree one) — never a return-stack pop.
        try engine.evaluate("(modal-step-back)") // g -> crumb-inner-test root
        try engine.evaluate("(modal-step-back)") // crumb-inner-test -> crumb-outer-test
        #expect(try engine.evaluate("(eq? modal-root-node (lookup-tree \"crumb-outer-test\"))") == .true)
        #expect(try engine.evaluate("(null? modal-current-path)") == .true)
        #expect(try engine.evaluate("(null? modal-stack)") == .true)
    }

    // MARK: - Walk members' cyclic edges (both copies `walk` builds)

    @Test func walkRegisteredModeMembersCarryCyclicAutoEdgesBackToTheModeRoot() throws {
        let engine = try loadFsmLowering()
        try engine.evaluate("""
          (walk 'cyclic-walk-test "Walk" (key "h" "Left" (lambda () 'ok)))
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
          (screen 'walk-entry-site-test
            (walk 'cyclic-walk-entry-test "Walk" (key "h" "Left" (lambda () 'ok))))
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
    // `register-tree!` thread an optional 'provider onto the lowered FSM
    // state, mirroring on-enter/on-leave — but straight onto the state's
    // 'provider slot rather than show/hide, since a provider's live edges/
    // synthetic states are what dispatch itself consults. Toy case only —
    // no herdr involvement (that's jump-dispatch-wiring, the next child).

    @Test func groupProviderFiresAtVisitStartAndItsEdgesAndStatesAreLiveAndDispatchable() throws {
        let engine = try loadFsmLowering()
        try engine.evaluate("""
          (define fired #f)
          (register-tree! 'provider-wiring-test
            (group "g" "G" 'provider
              (lambda ()
                (list (cons 'edges (list (edge "j" 'provided-target)))
                      (cons 'states (list (provided-state 'provided-target
                                            'entry (lambda () (set! fired #t)))))))
              (key "a" "A" (lambda () 'ok))))
        """)
        try engine.evaluate("(modal-enter (lookup-tree \"provider-wiring-test\") F18)")
        try engine.evaluate("(modal-handle-key \"g\")")
        // "j" was never declared on the group directly — only the provider,
        // run at come-to-rest, contributes it for this Visit.
        try engine.evaluate("(modal-handle-key \"j\")")
        #expect(try engine.evaluate("fired") == .true)
        try engine.evaluate("(modal-exit)")
    }

    // MARK: - Re-registration (rebuild-tree!) doesn't raise a duplicate-id error

    @Test func reRegisteringTheSameScopeDoesNotRaiseADuplicateStateIdError() throws {
        // rebuild-tree! / mux register! call register-tree! more than once
        // for the SAME scope by design; (modaliser fsm) has no delete
        // primitive, so only the first registration is mirrored.
        let engine = try loadFsmLowering()
        #expect(throws: Never.self) {
            try engine.evaluate("""
              (register-tree! 'rebuild-test (key "a" "A" (lambda () 'ok)))
              (register-tree! 'rebuild-test (key "a" "A" (lambda () 'ok)))
            """)
        }
        #expect(try engine.evaluate("(fsm-state-ref \"rebuild-test\")") != .false)
    }

    // MARK: - The whole bundled config lowers to a well-formed, live graph

    @Test func defaultConfigLowersEveryScreenToAResolvableEntryRow() throws {
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
                  (modaliser state-machine)
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

        #expect(try engine.evaluate("(fsm-entry-ref \"global\")") != .false)
        #expect(try engine.evaluate("(fsm-entry-ref \"com.googlecode.iterm2\")") != .false)
        #expect(try engine.evaluate("""
          (fsm-entry-more-specific? "com.googlecode.iterm2/herdr" "com.googlecode.iterm2")
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
