import Foundation
import Testing
@testable import Modaliser

@Suite("(modaliser fsm) library")
struct ModaliserFsmLibraryTests {

    private func loadFsm() throws -> SchemeEngine {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser fsm))")
        return engine
    }

    // MARK: - Both edge-declaration surfaces build identical graphs

    @Test func inlineAndStandaloneEdgesProduceIdenticalGraphs() throws {
        // One engine, two distinctly-named states built via the two
        // surfaces; compare their edge sets with targets normalized away
        // (the targets are deliberately different symbols — only the
        // trigger structure need match) so the same graph shape check
        // doesn't depend on cross-state symbol identity.
        let engine = try loadFsm()
        try engine.evaluate("""
          (fsm-state! 'a-inline 'label "A" (edge "x" 'b-inline) (edge 'up 'c-inline))
          (fsm-state! 'b-inline 'label "B")
          (fsm-state! 'c-inline 'label "C")

          (fsm-state! 'a-standalone 'label "A")
          (fsm-edge! 'a-standalone "x" 'b-standalone)
          (fsm-edge! 'a-standalone 'up 'c-standalone)
          (fsm-state! 'b-standalone 'label "B")
          (fsm-state! 'c-standalone 'label "C")

          (define (edge-triggers id)
            (map (lambda (e) (cdr (assoc 'trigger e))) (fsm-state-edges id)))
        """)
        #expect(try engine.evaluate("""
          (equal? (edge-triggers 'a-inline) (edge-triggers 'a-standalone))
        """) == .true)
        #expect(try engine.evaluate("(eq? (fsm-state-class 'a-inline) (fsm-state-class 'a-standalone))") == .true)
    }

    @Test func upEdgeDeclaredInlineOrStandaloneAgree() throws {
        let engine = try loadFsm()
        try engine.evaluate("""
          (fsm-state! 'root 'label "Root")
          (fsm-state! 'child 'label "Child" (edge 'up 'root))
        """)
        // fsm-up-edge returns the raw edge alist; read its target directly.
        #expect(try engine.evaluate("(cdr (assoc 'target (fsm-up-edge 'child)))") == engine.evaluate("'root"))
    }

    // MARK: - State classes are derived, never declared

    @Test func stateClassDerivesFromEdges() throws {
        let engine = try loadFsm()
        try engine.evaluate("""
          (fsm-state! 'resting 'label "R" (edge "a" 'x))
          (fsm-state! 'transient 'label "T" (edge 'auto 'x))
          (fsm-state! 'terminal 'label "Term")
        """)
        #expect(try engine.evaluate("(eq? (fsm-state-class 'resting) 'resting)") == .true)
        #expect(try engine.evaluate("(eq? (fsm-state-class 'transient) 'transient)") == .true)
        #expect(try engine.evaluate("(eq? (fsm-state-class 'terminal) 'terminal)") == .true)
    }

    // Regression for narrowing-live-dispatch-anomaly-k35: fsm-state-class
    // only reads the PERMANENT graph's edge table, so a PROVIDED (visit-
    // scoped) resting state — its edges live only in %fsm-visit-provided,
    // never fsm-edges — reads back as zero-edges 'terminal even though it
    // genuinely has key edges of its own (e.g. a jump-label narrowing
    // prefix state's second-key edges). fsm-resolved-state-class is the
    // fix: it must classify a provided resting state as 'resting, exactly
    // as classify-and-snapshot (the step engine's own live classification)
    // would once actually landed on it.
    @Test func resolvedStateClassSeesAProvidedRestingStatesOwnEdges() throws {
        let engine = try loadFsm()
        try engine.evaluate("""
          (fsm-state! 'root 'label "Root"
            'provider (lambda ()
                        (list (cons 'edges (list (edge "a" 'prefix)))
                              (cons 'states (list (provided-state 'prefix
                                                     (edge "d" 'landed)))))))
          (fsm-state! 'landed 'label "Landed")
          (fsm-activate! 'root)
        """)
        // The permanent-graph-only query is blind to 'prefix's own edges —
        // this documents the pre-existing (correct, narrower-purpose)
        // behaviour, not a bug in fsm-state-class itself.
        #expect(try engine.evaluate("(eq? (fsm-state-class 'prefix) 'terminal)") == .true)
        // The resolved query must see through to the provided state's own
        // edges and correctly report 'resting.
        #expect(try engine.evaluate("(eq? (fsm-resolved-state-class 'prefix) 'resting)") == .true)
    }

    @Test func upEdgeAloneDoesNotAffectStateClass() throws {
        // A state with only an up edge (no key/auto edges) is still
        // terminal — backspace is orthogonal to resting/transient/terminal.
        let engine = try loadFsm()
        try engine.evaluate("""
          (fsm-state! 'root 'label "Root")
          (fsm-state! 'leaf 'label "Leaf" (edge 'up 'root))
        """)
        #expect(try engine.evaluate("(eq? (fsm-state-class 'leaf) 'terminal)") == .true)
    }

    // MARK: - Validation failures

    @Test func duplicateStateIdRaises() throws {
        let engine = try loadFsm()
        try engine.evaluate("(fsm-state! 'dup 'label \"First\")")
        #expect(throws: (any Error).self) {
            try engine.evaluate("(fsm-state! 'dup 'label \"Second\")")
        }
    }

    @Test func keyEdgeThenAutoEdgeOnSameStateRaises() throws {
        let engine = try loadFsm()
        try engine.evaluate("(fsm-state! 's 'label \"S\")")
        try engine.evaluate("(fsm-edge! 's \"a\" 'x)")
        #expect(throws: (any Error).self) {
            try engine.evaluate("(fsm-edge! 's 'auto 'y)")
        }
    }

    @Test func autoEdgeThenKeyEdgeOnSameStateRaises() throws {
        let engine = try loadFsm()
        try engine.evaluate("(fsm-state! 's 'label \"S\")")
        try engine.evaluate("(fsm-edge! 's 'auto 'y)")
        #expect(throws: (any Error).self) {
            try engine.evaluate("(fsm-edge! 's \"a\" 'x)")
        }
    }

    @Test func secondAutoEdgeOnSameStateRaises() throws {
        let engine = try loadFsm()
        try engine.evaluate("(fsm-state! 's 'label \"S\")")
        try engine.evaluate("(fsm-edge! 's 'auto 'y)")
        #expect(throws: (any Error).self) {
            try engine.evaluate("(fsm-edge! 's 'auto 'z)")
        }
    }

    @Test func secondUpEdgeOnSameStateRaises() throws {
        let engine = try loadFsm()
        try engine.evaluate("(fsm-state! 's 'label \"S\")")
        try engine.evaluate("(fsm-edge! 's 'up 'y)")
        #expect(throws: (any Error).self) {
            try engine.evaluate("(fsm-edge! 's 'up 'z)")
        }
    }

    @Test func duplicateKeyTriggerOnSameStateRaises() throws {
        let engine = try loadFsm()
        try engine.evaluate("(fsm-state! 's 'label \"S\")")
        try engine.evaluate("(fsm-edge! 's \"a\" 'x)")
        #expect(throws: (any Error).self) {
            try engine.evaluate("(fsm-edge! 's \"a\" 'y)")
        }
    }

    @Test func entryReferencingUnknownStateRaises() throws {
        let engine = try loadFsm()
        #expect(throws: (any Error).self) {
            try engine.evaluate("(fsm-entry! 'e 'no-such-state)")
        }
    }

    @Test func duplicateEntryNameRaises() throws {
        let engine = try loadFsm()
        try engine.evaluate("(fsm-state! 's 'label \"S\")")
        try engine.evaluate("(fsm-entry! 'e 's)")
        #expect(throws: (any Error).self) {
            try engine.evaluate("(fsm-entry! 'e 's)")
        }
    }

    @Test func danglingEdgeTargetIsAllowedAtConstructionTime() throws {
        // The graph is open — an edge may point at a state that doesn't
        // exist yet. Only entry rows are checked eagerly.
        let engine = try loadFsm()
        #expect(throws: Never.self) {
            try engine.evaluate("(fsm-state! 's 'label \"S\" (edge \"a\" 'not-yet-registered))")
        }
    }

    @Test func stateKeywordUnknownRaises() throws {
        let engine = try loadFsm()
        #expect(throws: (any Error).self) {
            try engine.evaluate("(fsm-state! 's 'frob 1)")
        }
    }

    @Test func edgeInvalidTriggerRaises() throws {
        let engine = try loadFsm()
        #expect(throws: (any Error).self) {
            try engine.evaluate("(edge 'not-a-trigger 'x)")
        }
    }

    // MARK: - The `named` behaviour wrapper

    @Test func namedWrapsAProcedureAndPrintsItsName() throws {
        let engine = try loadFsm()
        try engine.evaluate("""
          (fsm-state! 'leaf 'label "Leaf" 'entry (named 'my-action (lambda () 'ok)))
        """)
        #expect(try engine.evaluate("(fsm-named? (fsm-state-entry 'leaf))") == .true)
        #expect(try engine.evaluate("(eq? (fsm-behavior-name (fsm-state-entry 'leaf)) 'my-action)") == .true)
        #expect(try engine.evaluate("((fsm-behavior-proc (fsm-state-entry 'leaf)))") == engine.evaluate("'ok"))
    }

    @Test func anonymousProcedureBehaviorHasNoName() throws {
        let engine = try loadFsm()
        try engine.evaluate("""
          (fsm-state! 'leaf 'label "Leaf" 'entry (lambda () 'ok))
        """)
        #expect(try engine.evaluate("(fsm-behavior-name (fsm-state-entry 'leaf))") == .false)
        #expect(try engine.evaluate("((fsm-behavior-proc (fsm-state-entry 'leaf)))") == engine.evaluate("'ok"))
    }

    @Test func namedRejectsNonProcedure() throws {
        let engine = try loadFsm()
        #expect(throws: (any Error).self) {
            try engine.evaluate("(named 'x 42)")
        }
    }

    // MARK: - Printing shows structure and given names; only closures are opaque

    @Test func graphAlistShowsNamedBehaviorAndAnonymousMarker() throws {
        let engine = try loadFsm()
        try engine.evaluate("""
          (fsm-state! 'leaf 'label "Leaf"
            'entry (named 'my-entry (lambda () 'ok))
            'exit (lambda () 'bye))
        """)
        // fsm-graph->alist's 'states entry is (list state-alist ...); one
        // state is registered here, so its alist is the sole element.
        try engine.evaluate("(define leaf-info (car (cdr (assoc 'states (fsm-graph->alist)))))")
        #expect(try engine.evaluate("(eq? (cdr (assoc 'entry leaf-info)) 'my-entry)") == .true)
        #expect(try engine.evaluate("(eq? (cdr (assoc 'exit leaf-info)) 'anonymous-proc)") == .true)
        #expect(try engine.evaluate("(eq? (cdr (assoc 'label leaf-info)) 'anonymous-proc)") == .false)
        #expect(try engine.evaluate("(cdr (assoc 'label leaf-info))").asString() == "Leaf")
    }

    @Test func printDoesNotThrow() throws {
        let engine = try loadFsm()
        try engine.evaluate("(fsm-state! 's 'label \"S\")")
        #expect(throws: Never.self) {
            try engine.evaluate("(fsm-print)")
        }
    }

    // MARK: - Queries a renderer would make

    @Test func stateIdsPreserveDeclarationOrder() throws {
        let engine = try loadFsm()
        try engine.evaluate("""
          (fsm-state! 'first 'label "1")
          (fsm-state! 'second 'label "2")
          (fsm-state! 'third 'label "3")
        """)
        #expect(try engine.evaluate("(equal? (fsm-state-ids) '(first second third))") == .true)
    }

    @Test func stateRefReturnsFalseForUnknownId() throws {
        let engine = try loadFsm()
        #expect(try engine.evaluate("(fsm-state-ref 'nope)") == .false)
    }

    @Test func edgesOutEnumeratesInDeclarationOrder() throws {
        let engine = try loadFsm()
        try engine.evaluate("""
          (fsm-state! 's 'label "S" (edge "a" 'x) (edge "b" 'y) (edge 'up 'z))
        """)
        #expect(try engine.evaluate("""
          (equal? (map (lambda (e) (cdr (assoc 'trigger e))) (fsm-state-edges 's))
                  (list "a" "b" 'up))
        """) == .true)
    }

    @Test func ancestorsWalkUpEdgesOutward() throws {
        let engine = try loadFsm()
        try engine.evaluate("""
          (fsm-state! 'grandparent 'label "GP")
          (fsm-state! 'parent 'label "P" (edge 'up 'grandparent))
          (fsm-state! 'child 'label "C" (edge 'up 'parent))
        """)
        #expect(try engine.evaluate("(equal? (fsm-ancestors 'child) '(parent grandparent))") == .true)
        #expect(try engine.evaluate("(equal? (fsm-ancestors 'grandparent) '())") == .true)
    }

    @Test func ancestorsStopsAtDanglingUpEdgeTarget() throws {
        let engine = try loadFsm()
        try engine.evaluate("(fsm-state! 's 'label \"S\" (edge 'up 'never-registered))")
        #expect(try engine.evaluate("(equal? (fsm-ancestors 's) '())") == .true)
    }

    @Test func entryRowsEnumerateInDeclarationOrder() throws {
        let engine = try loadFsm()
        try engine.evaluate("""
          (fsm-state! 'a 'label "A")
          (fsm-state! 'b 'label "B")
          (fsm-entry! 'entry-a 'a)
          (fsm-entry! 'entry-b 'b)
        """)
        #expect(try engine.evaluate("""
          (equal? (map (lambda (r) (cdr (assoc 'name r))) (fsm-entry-rows))
                  '(entry-a entry-b))
        """) == .true)
    }

    @Test func entryMoreSpecificByUpEdgeContainment() throws {
        // A nested context's entry outranks its container's — the herdr
        // entry node beats the iTerm node it lives inside.
        let engine = try loadFsm()
        try engine.evaluate("""
          (fsm-state! 'outer-root 'label "Outer")
          (fsm-state! 'inner-root 'label "Inner" (edge 'up 'outer-root))
          (fsm-entry! 'outer 'outer-root)
          (fsm-entry! 'inner 'inner-root)
        """)
        #expect(try engine.evaluate("(fsm-entry-more-specific? 'inner 'outer)") == .true)
        #expect(try engine.evaluate("(fsm-entry-more-specific? 'outer 'inner)") == .false)
    }

    @Test func entryMoreSpecificByExplicitRefinesStamp() throws {
        // Non-nested siblings (today's suffix-hook disambiguation) use an
        // explicit scope-refinement stamp instead of structural nesting.
        let engine = try loadFsm()
        try engine.evaluate("""
          (fsm-state! 'base-state 'label "Base")
          (fsm-state! 'variant-state 'label "Variant")
          (fsm-entry! 'base 'base-state)
          (fsm-entry! 'variant 'variant-state 'refines 'base)
        """)
        #expect(try engine.evaluate("(fsm-entry-more-specific? 'variant 'base)") == .true)
        #expect(try engine.evaluate("(fsm-entry-more-specific? 'base 'variant)") == .false)
    }

    @Test func entryMoreSpecificTiesFallToDeclarationOrder() throws {
        let engine = try loadFsm()
        try engine.evaluate("""
          (fsm-state! 'a 'label "A")
          (fsm-state! 'b 'label "B")
          (fsm-entry! 'declared-first 'a)
          (fsm-entry! 'declared-second 'b)
        """)
        #expect(try engine.evaluate("(fsm-entry-more-specific? 'declared-first 'declared-second)") == .true)
        #expect(try engine.evaluate("(fsm-entry-more-specific? 'declared-second 'declared-first)") == .false)
    }

    @Test func entryMoreSpecificRejectsUnknownEntry() throws {
        let engine = try loadFsm()
        try engine.evaluate("""
          (fsm-state! 'a 'label "A")
          (fsm-entry! 'known 'a)
        """)
        #expect(throws: (any Error).self) {
            try engine.evaluate("(fsm-entry-more-specific? 'known 'unknown)")
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // Step engine (step-engine-k9) — toy graphs, no lowering, no overlay.
    // ═══════════════════════════════════════════════════════════════

    // MARK: - State classes, dynamically (via activation)

    @Test func activatingARestingStateStaysActive() throws {
        let engine = try loadFsm()
        try engine.evaluate("""
          (fsm-state! 'root 'label "Root" (edge "a" 'leaf))
          (fsm-state! 'leaf 'label "Leaf")
          (fsm-activate! 'root)
        """)
        #expect(try engine.evaluate("(fsm-active?)") == .true)
        #expect(try engine.evaluate("(eq? (fsm-current-state) 'root)") == .true)
    }

    @Test func activatingATerminalStateHaltsImmediately() throws {
        let engine = try loadFsm()
        try engine.evaluate("""
          (fsm-state! 'lone 'label "Lone")
          (fsm-activate! 'lone)
        """)
        #expect(try engine.evaluate("(fsm-active?)") == .false)
    }

    @Test func activatingATransientStateFollowsItsAutoEdgeToAConcreteTarget() throws {
        let engine = try loadFsm()
        try engine.evaluate("""
          (fsm-state! 'command 'label "Command" (edge 'auto 'landing))
          (fsm-state! 'landing 'label "Landing" (edge "x" 'somewhere))
          (fsm-state! 'somewhere 'label "Somewhere")
          (fsm-activate! 'command)
        """)
        #expect(try engine.evaluate("(fsm-active?)") == .true)
        #expect(try engine.evaluate("(eq? (fsm-current-state) 'landing)") == .true)
    }

    // MARK: - Halt-before-entry (terminal) vs halt-after-#f (dynamic auto edge)

    @Test func terminalHaltsBeforeItsEntryActionRuns() throws {
        let engine = try loadFsm()
        try engine.evaluate("""
          (define active-when-entry-ran 'unset)
          (fsm-state! 'lone 'label "Lone"
            'entry (lambda () (set! active-when-entry-ran (fsm-active?))))
          (fsm-activate! 'lone)
        """)
        #expect(try engine.evaluate("active-when-entry-ran") == .false)
    }

    @Test func dynamicAutoEdgeResolvingToFalseHaltsAfterTheActionRuns() throws {
        let engine = try loadFsm()
        try engine.evaluate("""
          (define entry-ran? #f)
          (fsm-state! 'declines 'label "Declines"
            'entry (lambda () (set! entry-ran? #t))
            (edge 'auto (lambda () #f)))
          (fsm-activate! 'declines)
        """)
        #expect(try engine.evaluate("entry-ran?") == .true)
        #expect(try engine.evaluate("(fsm-active?)") == .false)
    }

    // MARK: - Visit continuity: cyclic re-arm doesn't refire, but refreshes

    @Test func cyclicAutoEdgeReturnDoesNotRefireEntryOrShow() throws {
        let engine = try loadFsm()
        try engine.evaluate("""
          (define entry-count 0)
          (define show-count 0)
          (fsm-state! 'walk 'label "Walk"
            'entry (lambda () (set! entry-count (+ entry-count 1)))
            'show (lambda () (set! show-count (+ show-count 1)))
            (edge "x" 'leaf))
          (fsm-state! 'leaf 'label "Leaf" (edge 'auto 'walk))
          (fsm-activate! 'walk)
          (fsm-mark-displayed! (fsm-visit-generation))
          (fsm-step! "x")
          (fsm-step! "x")
          (fsm-step! "x")
        """)
        #expect(try engine.evaluate("(= entry-count 1)") == .true)
        #expect(try engine.evaluate("(= show-count 1)") == .true)
        #expect(try engine.evaluate("(eq? (fsm-current-state) 'walk)") == .true)
    }

    @Test func providerRerunsOnEachComeToRestIncludingCyclicRearm() throws {
        let engine = try loadFsm()
        try engine.evaluate("""
          (define provider-calls 0)
          (fsm-state! 'walk 'label "Walk"
            'provider (lambda ()
                        (set! provider-calls (+ provider-calls 1))
                        (list (cons 'edges (list (edge "x" 'leaf))))))
          (fsm-state! 'leaf 'label "Leaf" (edge 'auto 'walk))
          (fsm-activate! 'walk)
        """)
        #expect(try engine.evaluate("(= provider-calls 1)") == .true)
        try engine.evaluate("(fsm-step! \"x\")")
        #expect(try engine.evaluate("(= provider-calls 2)") == .true)
        try engine.evaluate("(fsm-step! \"x\")")
        #expect(try engine.evaluate("(= provider-calls 3)") == .true)
    }

    // MARK: - Call edges / return stack, multi-caller return-to-caller

    @Test func callEdgePushesAReturnFrameAndBackspacePopsBackToTheCaller() throws {
        let engine = try loadFsm()
        try engine.evaluate("""
          (fsm-state! 'caller 'label "Caller" (edge "w" 'walk-root 'call #t))
          (fsm-state! 'walk-root 'label "WalkRoot" (edge "y" 'walk-leaf))
          (fsm-state! 'walk-leaf 'label "WalkLeaf" (edge 'auto 'walk-root))
          (fsm-activate! 'caller)
          (fsm-step! "w")
        """)
        #expect(try engine.evaluate("(eq? (fsm-current-state) 'walk-root)") == .true)
        #expect(try engine.evaluate("(equal? (fsm-return-stack) '(caller))") == .true)
        try engine.evaluate("(fsm-step-back!)")
        #expect(try engine.evaluate("(eq? (fsm-current-state) 'caller)") == .true)
        #expect(try engine.evaluate("(null? (fsm-return-stack))") == .true)
    }

    @Test func multipleCallersEachReturnToTheirOwnCaller() throws {
        let engine = try loadFsm()
        try engine.evaluate("""
          (fsm-state! 'caller-a 'label "A" (edge "w" 'walk-root 'call #t))
          (fsm-state! 'caller-b 'label "B" (edge "w" 'walk-root 'call #t))
          (fsm-state! 'walk-root 'label "WalkRoot" (edge "y" 'walk-leaf))
          (fsm-state! 'walk-leaf 'label "WalkLeaf" (edge 'auto 'walk-root))
        """)
        try engine.evaluate("(fsm-activate! 'caller-a) (fsm-step! \"w\") (fsm-step-back!)")
        #expect(try engine.evaluate("(eq? (fsm-current-state) 'caller-a)") == .true)
        try engine.evaluate("(fsm-activate! 'caller-b) (fsm-step! \"w\") (fsm-step-back!)")
        #expect(try engine.evaluate("(eq? (fsm-current-state) 'caller-b)") == .true)
    }

    // MARK: - Backspace at every position

    @Test func backspaceFollowsTheUpEdgeAtDepth() throws {
        let engine = try loadFsm()
        try engine.evaluate("""
          (define parent-entry-count 0)
          (fsm-state! 'parent 'label "Parent"
            'entry (lambda () (set! parent-entry-count (+ parent-entry-count 1)))
            (edge "c" 'child))
          (fsm-state! 'child 'label "Child" (edge 'up 'parent) (edge "q" 'elsewhere))
          (fsm-state! 'elsewhere 'label "Elsewhere")
          (fsm-activate! 'parent)
          (fsm-step! "c")
        """)
        #expect(try engine.evaluate("(eq? (fsm-current-state) 'child)") == .true)
        #expect(try engine.evaluate("(= parent-entry-count 1)") == .true)
        try engine.evaluate("(fsm-step-back!)")
        #expect(try engine.evaluate("(eq? (fsm-current-state) 'parent)") == .true)
        #expect(try engine.evaluate("(= parent-entry-count 2)") == .true)
    }

    @Test func backspaceAtAWalkRootWithNoCallerHalts() throws {
        let engine = try loadFsm()
        try engine.evaluate("""
          (fsm-state! 'walk-root 'label "WalkRoot" (edge "y" 'walk-leaf))
          (fsm-state! 'walk-leaf 'label "WalkLeaf" (edge 'auto 'walk-root))
          (fsm-activate! 'walk-root)
          (fsm-step-back!)
        """)
        #expect(try engine.evaluate("(fsm-active?)") == .false)
    }

    @Test func backspaceAtANonWalkRootWithNoCallerIsANoOp() throws {
        let engine = try loadFsm()
        try engine.evaluate("""
          (fsm-state! 'plain 'label "Plain" (edge "z" 'leaf))
          (fsm-state! 'leaf 'label "Leaf")
          (fsm-activate! 'plain)
          (fsm-step-back!)
        """)
        #expect(try engine.evaluate("(fsm-active?)") == .true)
        #expect(try engine.evaluate("(eq? (fsm-current-state) 'plain)") == .true)
    }

    // MARK: - Escape (fsm-halt!) clears the stack, is idempotent

    @Test func haltClearsTheReturnStackAndFullyDeactivates() throws {
        let engine = try loadFsm()
        try engine.evaluate("""
          (fsm-state! 'caller 'label "Caller" (edge "w" 'walk-root 'call #t))
          (fsm-state! 'walk-root 'label "WalkRoot" (edge "y" 'walk-leaf))
          (fsm-state! 'walk-leaf 'label "WalkLeaf" (edge 'auto 'walk-root))
          (fsm-activate! 'caller)
          (fsm-step! "w")
        """)
        #expect(try engine.evaluate("(equal? (fsm-return-stack) '(caller))") == .true)
        try engine.evaluate("(fsm-halt!)")
        #expect(try engine.evaluate("(fsm-active?)") == .false)
        #expect(try engine.evaluate("(null? (fsm-return-stack))") == .true)
    }

    @Test func haltIsIdempotentWhenAlreadyInactive() throws {
        let engine = try loadFsm()
        #expect(throws: Never.self) {
            try engine.evaluate("(fsm-halt!)")
        }
        #expect(try engine.evaluate("(fsm-active?)") == .false)
    }

    // MARK: - Snapshot timing: providers once per come-to-rest; provided states expire

    @Test func providerRunsExactlyOnceAtActivation() throws {
        let engine = try loadFsm()
        try engine.evaluate("""
          (define provider-calls 0)
          (fsm-state! 'jump 'label "Jump"
            'provider (lambda ()
                        (set! provider-calls (+ provider-calls 1))
                        (list (cons 'edges (list (edge "j" 'landed))))))
          (fsm-state! 'landed 'label "Landed")
          (fsm-activate! 'jump)
        """)
        #expect(try engine.evaluate("(= provider-calls 1)") == .true)
    }

    @Test func providedEdgesAreDispatchableWithinTheVisitAndExpireAfterward() throws {
        let engine = try loadFsm()
        try engine.evaluate("""
          (fsm-state! 'jump 'label "Jump"
            'provider (lambda () (list (cons 'edges (list (edge "j" 'landed))))))
          (fsm-state! 'landed 'label "Landed" (edge "z" 'elsewhere))
          (fsm-state! 'elsewhere 'label "Elsewhere" (edge "j" 'not-landed))
          (fsm-state! 'not-landed 'label "NotLanded" (edge "q" 'nowhere))
          (fsm-state! 'nowhere 'label "Nowhere")
          (fsm-activate! 'jump)
          (fsm-step! "j")
        """)
        // "j" was jump's provided edge, live only for jump's visit.
        #expect(try engine.evaluate("(eq? (fsm-current-state) 'landed)") == .true)
        try engine.evaluate("(fsm-step! \"z\")")
        #expect(try engine.evaluate("(eq? (fsm-current-state) 'elsewhere)") == .true)
        // "j" now dispatches through elsewhere's own static edge instead —
        // jump's provided edge/target expired with jump's visit.
        try engine.evaluate("(fsm-step! \"j\")")
        #expect(try engine.evaluate("(eq? (fsm-current-state) 'not-landed)") == .true)
    }

    @Test func gatesAreEvaluatedFreshAtEachComeToRest() throws {
        let engine = try loadFsm()
        try engine.evaluate("""
          (define gate-open? #f)
          (fsm-state! 'gated 'label "Gated"
            (edge "g" 'through 'gate (lambda () gate-open?))
            (edge "n" 'noop))
          (fsm-state! 'through 'label "Through" (edge "q" 'nowhere))
          (fsm-state! 'nowhere 'label "Nowhere")
          (fsm-state! 'noop 'label "Noop" (edge "b" 'gated))
          (fsm-activate! 'gated)
          (fsm-step! "g")
        """)
        // Gate closed: "g" has no live edge, swallowed (forgiving default).
        #expect(try engine.evaluate("(fsm-active?)") == .true)
        #expect(try engine.evaluate("(eq? (fsm-current-state) 'gated)") == .true)
        try engine.evaluate("""
          (set! gate-open? #t)
          (fsm-step! "n")
          (fsm-step! "b")
          (fsm-step! "g")
        """)
        // Coming back to rest on 'gated' re-evaluates its gate fresh.
        #expect(try engine.evaluate("(eq? (fsm-current-state) 'through)") == .true)
    }

    // MARK: - Entry-table specificity, end-to-end through activation

    @Test func activateViaEntryTableChoosesTheRefinesVariantOverItsBaseWithNoContainment() throws {
        let engine = try loadFsm()
        try engine.evaluate("""
          (fsm-state! 'base-state 'label "Base" (edge "z" 'somewhere))
          (fsm-state! 'variant-state 'label "Variant" (edge "z" 'somewhere))
          (fsm-state! 'somewhere 'label "Somewhere")
          (fsm-entry! 'base 'base-state)
          (fsm-entry! 'variant 'variant-state 'refines 'base)
        """)
        #expect(try engine.evaluate("(eq? (fsm-activate-via-entry-table!) 'variant)") == .true)
        #expect(try engine.evaluate("(eq? (fsm-current-state) 'variant-state)") == .true)
    }

    @Test func activateViaEntryTableSkipsAFailingGate() throws {
        let engine = try loadFsm()
        try engine.evaluate("""
          (fsm-state! 'blocked-state 'label "Blocked" (edge "z" 'somewhere))
          (fsm-state! 'fallback-state 'label "Fallback" (edge "z" 'somewhere))
          (fsm-state! 'somewhere 'label "Somewhere")
          (fsm-entry! 'blocked 'blocked-state 'gate (lambda () #f))
          (fsm-entry! 'fallback 'fallback-state)
        """)
        #expect(try engine.evaluate("(eq? (fsm-activate-via-entry-table!) 'fallback)") == .true)
        #expect(try engine.evaluate("(eq? (fsm-current-state) 'fallback-state)") == .true)
    }

    @Test func activateViaEntryTableReturnsFalseWhenNothingPasses() throws {
        let engine = try loadFsm()
        try engine.evaluate("""
          (fsm-state! 'blocked-state 'label "Blocked" (edge "z" 'somewhere))
          (fsm-state! 'somewhere 'label "Somewhere")
          (fsm-entry! 'blocked 'blocked-state 'gate (lambda () #f))
        """)
        #expect(try engine.evaluate("(fsm-activate-via-entry-table!)") == .false)
        #expect(try engine.evaluate("(fsm-active?)") == .false)
    }

    // MARK: - Entry actions and the arriving key (shared provided targets)

    @Test func entryActionsDefaultToBeingCalledWithNoArgs() throws {
        let engine = try loadFsm()
        try engine.evaluate("""
          (define called-with-zero-args? #f)
          (fsm-state! 'target 'label "Target" 'entry (lambda () (set! called-with-zero-args? #t)))
          (fsm-state! 'source 'label "Source" (edge "1" 'target))
          (fsm-activate! 'source)
          (fsm-step! "1")
        """)
        #expect(try engine.evaluate("called-with-zero-args?") == .true)
    }

    // entry's key-vs-no-key dispatch is gated by a host-injected arity
    // predicate (set-fsm-accepts-arg!), same pattern as (modaliser
    // state-machine)'s set-on-leave-accepts-reason! — a shared provided
    // target's entry action distinguishes which of several edges arrived.
    @Test func entryReceivesTheArrivingKeyOnceTheHostInstallsTheArityPredicate() throws {
        let engine = try loadFsm()
        try engine.evaluate(
          "(set-fsm-accepts-arg! (lambda (p) (procedure-arity-includes? p 1)))")
        try engine.evaluate("""
          (define last-key #f)
          (fsm-state! 'jump 'label "Jump"
            'provider (lambda ()
                        (list (cons 'edges (list (edge "1" 'shared) (edge "2" 'shared)))
                              (cons 'states (list (provided-state 'shared
                                                    'entry (lambda (k) (set! last-key k))))))))
        """)
        try engine.evaluate("(fsm-activate! 'jump) (fsm-step! \"1\")")
        #expect(try engine.evaluate("last-key").asString() == "1")
        try engine.evaluate("(fsm-activate! 'jump) (fsm-step! \"2\")")
        #expect(try engine.evaluate("last-key").asString() == "2")
    }

    // MARK: - show/hide fire iff the host signals the visit was displayed

    @Test func showDoesNotFireWithoutTheHostMarkingTheVisitDisplayed() throws {
        let engine = try loadFsm()
        try engine.evaluate("""
          (define show-count 0)
          (define hide-count 0)
          (fsm-state! 'shown 'label "Shown"
            'show (lambda () (set! show-count (+ show-count 1)))
            'hide (lambda () (set! hide-count (+ hide-count 1)))
            (edge "z" 'elsewhere))
          (fsm-state! 'elsewhere 'label "Elsewhere")
          (fsm-activate! 'shown)
          (fsm-step! "z")
        """)
        #expect(try engine.evaluate("(= show-count 0)") == .true)
        #expect(try engine.evaluate("(= hide-count 0)") == .true)
    }

    @Test func markDisplayedFiresShowAndTheSubsequentTransitionFiresHide() throws {
        let engine = try loadFsm()
        try engine.evaluate("""
          (define show-count 0)
          (define hide-count 0)
          (fsm-state! 'shown 'label "Shown"
            'show (lambda () (set! show-count (+ show-count 1)))
            'hide (lambda () (set! hide-count (+ hide-count 1)))
            (edge "z" 'elsewhere))
          (fsm-state! 'elsewhere 'label "Elsewhere")
          (fsm-activate! 'shown)
          (fsm-mark-displayed! (fsm-visit-generation))
        """)
        #expect(try engine.evaluate("(= show-count 1)") == .true)
        try engine.evaluate("(fsm-step! \"z\")")
        #expect(try engine.evaluate("(= hide-count 1)") == .true)
    }

    @Test func markDisplayedIsIdempotentWithinTheSameVisit() throws {
        let engine = try loadFsm()
        try engine.evaluate("""
          (define show-count 0)
          (fsm-state! 'shown 'label "Shown"
            'show (lambda () (set! show-count (+ show-count 1))) (edge "z" 'elsewhere))
          (fsm-state! 'elsewhere 'label "Elsewhere")
          (fsm-activate! 'shown)
          (fsm-mark-displayed! (fsm-visit-generation))
          (fsm-mark-displayed! (fsm-visit-generation))
        """)
        #expect(try engine.evaluate("(= show-count 1)") == .true)
    }

    @Test func markDisplayedWithAStaleGenerationIsANoOp() throws {
        let engine = try loadFsm()
        try engine.evaluate("""
          (define show-count 0)
          (fsm-state! 'shown 'label "Shown"
            'show (lambda () (set! show-count (+ show-count 1))) (edge "z" 'elsewhere))
          (fsm-state! 'elsewhere 'label "Elsewhere" (edge "q" 'noop))
          (fsm-state! 'noop 'label "Noop")
          (fsm-activate! 'shown)
          (define stale-gen (fsm-visit-generation))
          (fsm-step! "z")
        """)
        #expect(try engine.evaluate("(fsm-mark-displayed! stale-gen)") == .false)
        #expect(try engine.evaluate("(= show-count 0)") == .true)
    }

    @Test func markDisplayedWhileInactiveIsANoOp() throws {
        let engine = try loadFsm()
        #expect(try engine.evaluate("(fsm-mark-displayed! 0)") == .false)
    }

    // MARK: - Per-state unknown-key policy

    @Test func unknownKeyIsSwallowedByDefault() throws {
        let engine = try loadFsm()
        try engine.evaluate("""
          (fsm-state! 'forgiving 'label "Forgiving" (edge "a" 'somewhere))
          (fsm-state! 'somewhere 'label "Somewhere")
          (fsm-activate! 'forgiving)
          (fsm-step! "unbound-key")
        """)
        #expect(try engine.evaluate("(fsm-active?)") == .true)
        #expect(try engine.evaluate("(eq? (fsm-current-state) 'forgiving)") == .true)
    }

    @Test func unknownKeyHaltsWhenExitOnUnknownIsSet() throws {
        let engine = try loadFsm()
        try engine.evaluate("""
          (fsm-state! 'strict 'label "Strict" 'exit-on-unknown #t (edge "a" 'somewhere))
          (fsm-state! 'somewhere 'label "Somewhere")
          (fsm-activate! 'strict)
          (fsm-step! "unbound-key")
        """)
        #expect(try engine.evaluate("(fsm-active?)") == .false)
    }

    // MARK: - Exit reasons flow like today's on-leave reasons

    @Test func exitReceivesTheReasonPassedToHalt() throws {
        let engine = try loadFsm()
        try engine.evaluate(
          "(set-fsm-accepts-arg! (lambda (p) (procedure-arity-includes? p 1)))")
        try engine.evaluate("""
          (define seen-reason 'unset)
          (fsm-state! 'root 'label "Root" 'exit (lambda (r) (set! seen-reason r)) (edge "a" 'x))
          (fsm-state! 'x 'label "X")
          (fsm-activate! 'root)
          (fsm-halt! 'cancel)
        """)
        #expect(try engine.evaluate("(eq? seen-reason 'cancel)") == .true)
    }

    @Test func movingToADifferentRestingStateExitsWithNavigateReason() throws {
        let engine = try loadFsm()
        try engine.evaluate(
          "(set-fsm-accepts-arg! (lambda (p) (procedure-arity-includes? p 1)))")
        try engine.evaluate("""
          (define seen-reason 'unset)
          (fsm-state! 'a 'label "A" 'exit (lambda (r) (set! seen-reason r)) (edge "b" 'b))
          (fsm-state! 'b 'label "B" (edge "q" 'nowhere))
          (fsm-state! 'nowhere 'label "Nowhere")
          (fsm-activate! 'a)
          (fsm-step! "b")
        """)
        #expect(try engine.evaluate("(eq? seen-reason 'navigate)") == .true)
    }

    // MARK: - The auto-edge step-limit guard (file Notes)

    @Test func autoEdgeCycleRaisesInsteadOfLoopingForever() throws {
        let engine = try loadFsm()
        try engine.evaluate("""
          (fsm-state! 'a 'label "A" (edge 'auto 'b))
          (fsm-state! 'b 'label "B" (edge 'auto 'a))
        """)
        #expect(throws: (any Error).self) {
            try engine.evaluate("(fsm-activate! 'a)")
        }
    }

    // MARK: - Dispatch guards when inactive

    @Test func stepRaisesWhenTheEngineIsNotActive() throws {
        let engine = try loadFsm()
        #expect(throws: (any Error).self) {
            try engine.evaluate("(fsm-step! \"x\")")
        }
    }

    @Test func stepBackRaisesWhenTheEngineIsNotActive() throws {
        let engine = try loadFsm()
        #expect(throws: (any Error).self) {
            try engine.evaluate("(fsm-step-back!)")
        }
    }
}
