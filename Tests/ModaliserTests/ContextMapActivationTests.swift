import Foundation
import Testing
import LispKit
@testable import Modaliser

// The Terminal context map and activation on the pure configuration-
// pipeline seam (context-map-activation-k8, ADR-0013, docs/specs/
// configuration-value.md "The Terminal context map"): resolve-activation
// (leader kind × bundle-id × detection chain × value → landing state +
// seeded stack) as a pure function with the chain as an ARGUMENT,
// resolve-direct-activation (programmatic entry through the same
// resolution), the chain-seeded return stack driven through the fsm
// engine, and the derived one-inward `.` step-in edge on terminal-like
// screens. The entry-table leader path is untouched — nothing here is
// wired live until cutover-contract-k13.
@Suite("Terminal context map activation (resolve-activation / seeded stack / step-in)")
struct ContextMapActivationTests {

    private func loaded() throws -> SchemeEngine {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser util)
                  (modaliser fsm)
                  (modaliser configuration)
                  (modaliser terminal)
                  (modaliser activation)
                  (modaliser fsm))
        """)
        try engine.evaluate("(import (modaliser dsl))")
        // Decodable-error helper (same shape as ConfigurationLoweringTests).
        try engine.evaluate("""
          (define (catch-irritants thunk)
            (guard (e (#t (error-object-irritants e)))
              (thunk)
              'no-error))
        """)
        // Toy backends: the minimal records that make a scope terminal-like
        // (kind + match-key + the two chain probes) — every op slot #f.
        try engine.evaluate("""
          (define (test-host-backend sym bundle)
            (make-terminal-backend sym "TestHost" 'host bundle #f
              (lambda () #f) (lambda () "p0")
              #f #f #f #f #f #f #f #f #f #f #f #f
              #f #f
              (lambda () #t)))
          (define (test-mux-backend sym exe)
            (make-terminal-backend sym "TestMux" 'mux exe #f
              (lambda () #f) (lambda () "m0")
              #f #f #f #f #f #f #f #f #f #f #f #f
              #f #f
              (lambda () #t)))
          (define (frame sym fg) (cons sym (vector 'pane "p" 'fg fg)))
          (define (live-triggers)
            (map (lambda (e) (cdr (assoc 'trigger e))) (fsm-live-edges)))
        """)
        // The toy configuration: one host screen (terminal-like), one plain
        // app screen (not), a global screen, and a context map with a
        // mux-backed entry (tmix — a tmux stand-in) and a tree-only entry
        // (edit — an nvim stand-in).
        try engine.evaluate("""
          (define cfg
            (configuration
              (tree 'global (group "" "Global" (key "g" "G" (lambda () 'g))))
              (tree "com.test.term" (group "" "Term" (key "t" "T" (lambda () 't))))
              (tree "com.test.plain" (group "" "Plain" (key "p" "P" (lambda () 'p))))
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

    // MARK: - resolve-activation: the five chain shapes

    @Test func hostOnlyChainWithMappedFgLandsOnThatContext() throws {
        let engine = try loaded()
        // The host's focused pane runs "edit" directly (nvim-in-iTerm):
        // land on the mapped tree, one outward frame — the host screen.
        #expect(try engine.evaluate("""
          (equal? (resolve-activation 'local "com.test.term"
                    (list (frame 'term "edit")) cfg)
                  '((root . "edit-tree") (stack "com.test.term")))
        """) == .true)
    }

    @Test func hostMuxChainLandsOnTheMuxTree() throws {
        let engine = try loaded()
        #expect(try engine.evaluate("""
          (equal? (resolve-activation 'local "com.test.term"
                    (list (frame 'term "tmix") (frame 'tmix "zsh")) cfg)
                  '((root . "tmix-tree") (stack "com.test.term")))
        """) == .true)
    }

    @Test func hostMuxInnerChainLandsInnermostSeedingOneFramePerOuterContext() throws {
        let engine = try loaded()
        // Stack is in POP ORDER: backspace pops tmix-tree first, the host
        // screen last.
        #expect(try engine.evaluate("""
          (equal? (resolve-activation 'local "com.test.term"
                    (list (frame 'term "tmix") (frame 'tmix "edit")) cfg)
                  '((root . "edit-tree") (stack "tmix-tree" "com.test.term")))
        """) == .true)
    }

    @Test func unmappedChainLandsOnTheHostScreenWithNoSeeds() throws {
        let engine = try loaded()
        #expect(try engine.evaluate("""
          (equal? (resolve-activation 'local "com.test.term"
                    (list (frame 'term "zsh")) cfg)
                  '((root . "com.test.term") (stack)))
        """) == .true)
    }

    @Test func emptyChainLandsOnTheHostScreenWithNoSeeds() throws {
        let engine = try loaded()
        #expect(try engine.evaluate("""
          (equal? (resolve-activation 'local "com.test.term" '() cfg)
                  '((root . "com.test.term") (stack)))
        """) == .true)
    }

    // MARK: - resolve-activation: scope resolution

    @Test func globalLeaderNeverWalksTheChain() throws {
        let engine = try loaded()
        // The global screen is never terminal-like, so even a fully mapped
        // chain is ignored.
        #expect(try engine.evaluate("""
          (equal? (resolve-activation 'global "com.test.term"
                    (list (frame 'term "tmix") (frame 'tmix "edit")) cfg)
                  '((root . "global") (stack)))
        """) == .true)
    }

    @Test func unknownBundleFallsBackToTheGlobalScreen() throws {
        let engine = try loaded()
        #expect(try engine.evaluate("""
          (equal? (resolve-activation 'local "com.test.unknown"
                    (list (frame 'term "tmix")) cfg)
                  '((root . "global") (stack)))
        """) == .true)
    }

    @Test func nonTerminalLikeScreenIgnoresTheChain() throws {
        let engine = try loaded()
        // com.test.plain has a screen but no host backend — terminal-
        // likeness is capability, so the chain never engages.
        #expect(try engine.evaluate("""
          (equal? (resolve-activation 'local "com.test.plain"
                    (list (frame 'term "tmix") (frame 'tmix "edit")) cfg)
                  '((root . "com.test.plain") (stack)))
        """) == .true)
    }

    @Test func noScreenAnywhereResolvesToFalse() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (define no-global-cfg
            (configuration
              (tree "com.other.app" (group "" "Other" (key "o" "O" (lambda () 'o))))))
        """)
        #expect(try engine.evaluate("""
          (resolve-activation 'local "com.test.unknown" '() no-global-cfg)
        """) == .false)
    }

    // MARK: - resolve-direct-activation (programmatic entry, same resolution)

    @Test func directActivationSeedsWhenTheChainContainsTheContext() throws {
        let engine = try loaded()
        #expect(try engine.evaluate("""
          (equal? (resolve-direct-activation 'tmix-tree
                    (list (frame 'term "tmix") (frame 'tmix "zsh")) cfg)
                  '((root . "tmix-tree") (stack "com.test.term")))
        """) == .true)
        #expect(try engine.evaluate("""
          (equal? (resolve-direct-activation 'edit-tree
                    (list (frame 'term "tmix") (frame 'tmix "edit")) cfg)
                  '((root . "edit-tree") (stack "tmix-tree" "com.test.term")))
        """) == .true)
    }

    @Test func directActivationOutsideTheChainSeedsNothing() throws {
        let engine = try loaded()
        // Context tree, chain doesn't contain it: backspace at the root is
        // honestly a no-op — there is no outer context.
        #expect(try engine.evaluate("""
          (equal? (resolve-direct-activation 'tmix-tree '() cfg)
                  '((root . "tmix-tree") (stack)))
        """) == .true)
        // A non-context tree entered directly never seeds.
        #expect(try engine.evaluate("""
          (equal? (resolve-direct-activation "com.test.term"
                    (list (frame 'term "tmix")) cfg)
                  '((root . "com.test.term") (stack)))
        """) == .true)
        // An unknown scope resolves to #f.
        #expect(try engine.evaluate("""
          (resolve-direct-activation 'no-such-tree '() cfg)
        """) == .false)
    }

    // MARK: - terminal-contexts (the named grouping fragment)

    @Test func terminalContextsGroupsEntriesAsOneFragment() throws {
        let engine = try loaded()
        #expect(try engine.evaluate("""
          (equal? (cdr (assoc 'tree (configuration-context-ref cfg "tmix"))) 'tmix-tree)
        """) == .true)
        #expect(try engine.evaluate("""
          (equal? (cdr (assoc 'backend (configuration-context-ref cfg "tmix"))) 'tmix)
        """) == .true)
        #expect(try engine.evaluate("""
          (equal? (configuration-context-ref cfg "edit") '((tree . edit-tree)))
        """) == .true)
    }

    // MARK: - Context-reference closure at lowering

    @Test func danglingContextTreeReferenceErrorsAtLowering() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (define irritants
            (catch-irritants
              (lambda ()
                (lower-with-activation
                  (configuration
                    (tree 'global (group "" "Global" (key "g" "G" (lambda () 'g))))
                    (context "ghost" 'tree 'no-such-tree))
                  (lambda () '())))))
        """)
        #expect(try engine.evaluate("""
          (equal? irritants '(dangling-context-tree "ghost" no-such-tree))
        """) == .true)
    }

    @Test func danglingContextBackendReferenceErrorsAtLowering() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (define irritants
            (catch-irritants
              (lambda ()
                (lower-with-activation
                  (configuration
                    (tree 'ghost-tree (group "" "Ghost" (key "x" "X" (lambda () 'x))))
                    (context "ghost" 'tree 'ghost-tree 'backend 'no-such-backend))
                  (lambda () '())))))
        """)
        #expect(try engine.evaluate("""
          (equal? irritants '(dangling-context-backend "ghost" no-such-backend))
        """) == .true)
    }

    // MARK: - The chain-seeded return stack, through the engine

    @Test func seededStackPopsOutwardOneBoundaryPerBackspace() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (define chain-now '())
          (fsm-install-graph! (lower-with-activation cfg (lambda () chain-now)))
          (fsm-activate! "edit-tree" '("tmix-tree" "com.test.term"))
        """)
        #expect(try engine.evaluate("(equal? (fsm-current-state) \"edit-tree\")") == .true)
        #expect(try engine.evaluate("(equal? (fsm-return-stack) '(\"tmix-tree\" \"com.test.term\"))") == .true)
        // One boundary per backspace, exactly the seeded frames.
        try engine.evaluate("(fsm-step-back!)")
        #expect(try engine.evaluate("(equal? (fsm-current-state) \"tmix-tree\")") == .true)
        try engine.evaluate("(fsm-step-back!)")
        #expect(try engine.evaluate("(equal? (fsm-current-state) \"com.test.term\")") == .true)
        #expect(try engine.evaluate("(null? (fsm-return-stack))") == .true)
        // At the host root with nothing left: not a walk root — a no-op,
        // still active.
        try engine.evaluate("(fsm-step-back!)")
        #expect(try engine.evaluate("(fsm-active?)") == .true)
        #expect(try engine.evaluate("(equal? (fsm-current-state) \"com.test.term\")") == .true)
        // Escape's halt clears everything from any depth.
        try engine.evaluate("(fsm-halt!)")
        #expect(try engine.evaluate("(fsm-active?)") == .false)
        #expect(try engine.evaluate("(null? (fsm-return-stack))") == .true)
    }

    // MARK: - The derived `.` step-in edge

    @Test func stepInWalksInwardOneMappedContextAtATime() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (define chain-now (list (frame 'term "tmix") (frame 'tmix "edit")))
          (fsm-install-graph! (lower-with-activation cfg (lambda () chain-now)))
          (fsm-activate! "com.test.term")
        """)
        // The host screen derives "." to the first mapped context inward.
        #expect(try engine.evaluate("(and (member \".\" (live-triggers)) #t)") == .true)
        try engine.evaluate("(fsm-step! \".\")")
        #expect(try engine.evaluate("(equal? (fsm-current-state) \"tmix-tree\")") == .true)
        // Firing pushed exactly one return frame (the host screen).
        #expect(try engine.evaluate("(equal? (fsm-return-stack) '(\"com.test.term\"))") == .true)
        // The mux-backed context tree is itself terminal-like: one more
        // mapped context inward.
        #expect(try engine.evaluate("(and (member \".\" (live-triggers)) #t)") == .true)
        try engine.evaluate("(fsm-step! \".\")")
        #expect(try engine.evaluate("(equal? (fsm-current-state) \"edit-tree\")") == .true)
        #expect(try engine.evaluate("(equal? (fsm-return-stack) '(\"tmix-tree\" \"com.test.term\"))") == .true)
        // A tree-only context (edit) is not terminal-like: no "." here.
        #expect(try engine.evaluate("(member \".\" (live-triggers))") == .false)
        // Step-in and backspace are symmetric — pop back out one boundary.
        try engine.evaluate("(fsm-step-back!)")
        #expect(try engine.evaluate("(equal? (fsm-current-state) \"tmix-tree\")") == .true)
    }

    @Test func stepInIsAbsentWhenNoMappedContextExistsInward() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (define chain-now (list (frame 'term "zsh")))
          (fsm-install-graph! (lower-with-activation cfg (lambda () chain-now)))
          (fsm-activate! "com.test.term")
        """)
        #expect(try engine.evaluate("(member \".\" (live-triggers))") == .false)
        // The gate re-evaluates per visit snapshot: a chain that now offers
        // a mapped context inward derives the edge on the next landing.
        try engine.evaluate("""
          (fsm-halt!)
          (set! chain-now (list (frame 'term "edit")))
          (fsm-activate! "com.test.term")
        """)
        #expect(try engine.evaluate("(and (member \".\" (live-triggers)) #t)") == .true)
    }

    @Test func stepInIsAbsentWhenTheChainBelongsToAnotherHost() throws {
        let engine = try loaded()
        // The chain's host frame is some other backend — this screen has no
        // position in it, so no step-in derives.
        try engine.evaluate("""
          (fsm-install-graph!
            (lower-with-activation cfg
              (lambda () (list (frame 'other "tmix")))))
          (fsm-activate! "com.test.term")
        """)
        #expect(try engine.evaluate("(member \".\" (live-triggers))") == .false)
    }

    @Test func authoredProviderComposesWithTheDerivedStepIn() throws {
        let engine = try loaded()
        // The host screen root carries its own authored provider (the
        // herdr-jump-provider shape); the derived step-in must ride along,
        // not replace it.
        try engine.evaluate("""
          (define prov-cfg
            (configuration
              (tree "com.test.term"
                (group "" "Term"
                  'provider (lambda ()
                              (list (cons 'edges (list (edge "z" "com.test.term/t")))))
                  (key "t" "T" (lambda () 't))))
              (tree 'tmix-tree (group "" "Tmix" (key "m" "M" (lambda () 'm))))
              (backend 'term (test-host-backend 'term "com.test.term"))
              (backend 'tmix (test-mux-backend 'tmix "tmix"))
              (terminal-contexts
                (context "tmix" 'tree 'tmix-tree 'backend 'tmix))))
          (fsm-install-graph!
            (lower-with-activation prov-cfg
              (lambda () (list (frame 'term "tmix")))))
          (fsm-activate! "com.test.term")
        """)
        #expect(try engine.evaluate("(and (member \"z\" (live-triggers)) #t)") == .true)
        #expect(try engine.evaluate("(and (member \".\" (live-triggers)) #t)") == .true)
        try engine.evaluate("(fsm-step! \".\")")
        #expect(try engine.evaluate("(equal? (fsm-current-state) \"tmix-tree\")") == .true)
    }
}
