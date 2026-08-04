import Foundation
import Testing
import LispKit
@testable import Modaliser

// The pure lower function on the configuration-pipeline seam
// (closed-graph-lowering-k7, ADR-0018, docs/specs/configuration-value.md
// "Lowering and validation"): lower-configuration takes a Configuration
// value (the pure merge's output) and returns a FRESH, CLOSED fsm graph
// value — the installed graph is untouched, every authored reference
// must resolve as a load-time error, and the two runtime carve-outs
// (providers, dynamic 'next resolvers) stay outside static closure.
// FsmLoweringTests covers the per-tree lowering shapes; these tests
// cover the seam itself: purity, closure validation, and the
// engine's graph-install point.
@Suite("Pure lowering (configuration value → closed FSM graph)")
struct ConfigurationLoweringTests {

    private func loaded() throws -> SchemeEngine {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser util)
                  (modaliser keymap)
                  (modaliser configuration)
                  (modaliser fsm))
        """)
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")
        // Decodable-error helper: run THUNK, returning its error's
        // irritants — (code detail …) — or 'no-error when it succeeds.
        try engine.evaluate("""
          (define (catch-irritants thunk)
            (guard (e (#t (error-object-irritants e)))
              (thunk)
              'no-error))
        """)
        return engine
    }

    // MARK: - Purity at the seam

    @Test func lowerReturnsAFreshGraphValueWithoutTouchingTheInstalledGraph() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (define cfg (configuration
            (tree 'pure-test
              (group "" "Root"
                (key "x" "X" (lambda () 'x))))))
          (define g (lower-configuration cfg))
        """)
        #expect(try engine.evaluate("(fsm-graph? g)") == .true)
        // The lowered graph carries the tree's states…
        #expect(try engine.evaluate("""
          (let ((states (cdr (assoc 'states (fsm-graph->alist g)))))
            (equal? (map (lambda (s) (cdr (assoc 'id s))) states)
                    '("pure-test" "pure-test/x")))
        """) == .true)
        // …and its tree roots are recorded (the breadcrumb boundary set).
        #expect(try engine.evaluate("(equal? (cdr (assoc 'roots (fsm-graph->alist g))) '(\"pure-test\"))") == .true)
        // The installed graph never saw any of it.
        #expect(try engine.evaluate("(fsm-state-ref \"pure-test\")") == .false)
        // The input value is still a valid configuration (nothing consumed it).
        #expect(try engine.evaluate("(configuration? cfg)") == .true)
    }

    // MARK: - The lowering is deterministic over the same value

    @Test func lowerConfigurationIsDeterministicOverTheSameValue() throws {
        let engine = try loaded()
        // Lower the SAME value twice and compare the printable views:
        // ids, labels, classes, edge triggers/targets/call flags,
        // behaviour-slot names — everything fsm-graph->alist carries.
        // Payloads are the same node objects; wrapped entry slots print
        // as 'anonymous-proc on both sides.
        try engine.evaluate("""
          (define both-cfg
            (configuration (tree 'both-test (tree-root 'both-test
              (key "a" "A" (lambda () 'a))
              (key-range "1-3" "Digits" '("1" "2" "3") (lambda (k) k))
              (group "g" "Group"
                (key "b" "B" (lambda () 'b) 'next 'self)
                (key "c" "C" (lambda () 'c)))))))
          (define graph-a (lower-configuration both-cfg))
          (define graph-b (lower-configuration both-cfg))
          (define (states-with-prefix view prefix)
            (filter
              (lambda (s)
                (let ((id (cdr (assoc 'id s))))
                  (and (string? id)
                       (>= (string-length id) (string-length prefix))
                       (string=? (substring id 0 (string-length prefix)) prefix))))
              (cdr (assoc 'states view))))
        """)
        #expect(try engine.evaluate("""
          (equal? (states-with-prefix (fsm-graph->alist graph-a) "both-test")
                  (states-with-prefix (fsm-graph->alist graph-b) "both-test"))
        """) == .true)
        // Sanity: the comparison wasn't vacuous — the walk member, the
        // range keys, and the nested group all lowered.
        #expect(try engine.evaluate("""
          (equal? (map (lambda (s) (cdr (assoc 'id s)))
                       (states-with-prefix (fsm-graph->alist graph-b) "both-test"))
                  '("both-test" "both-test/a" "both-test/1-3"
                    "both-test/g" "both-test/g/b" "both-test/g/c"))
        """) == .true)
    }

    // MARK: - Closure validation (load-time, naming the offender)

    @Test func danglingNextCrossIdErrorsNamingTheOffendingIds() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (define irritants
            (catch-irritants
              (lambda ()
                (lower-configuration
                  (configuration
                    (tree 'dangle-test
                      (group "" "Root"
                        (key "x" "X" (lambda () 'x) 'next 'no-such-mode))))))))
        """)
        #expect(try engine.evaluate("""
          (equal? irritants '(dangling-edge-target "dangle-test/x" auto "no-such-mode"))
        """) == .true)
    }

    @Test func crossTreeNextResolvesWhenBothTreesAreInTheValue() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (define g (lower-configuration
            (configuration
              (tree 'cross-a
                (group "" "A"
                  (key "x" "X" (lambda () 'x) 'next 'cross-b)))
              (tree 'cross-b
                (group "" "B"
                  (key "y" "Y" (lambda () 'y)))))))
          (define x-state
            (find (lambda (s) (equal? (cdr (assoc 'id s)) "cross-a/x"))
                  (cdr (assoc 'states (fsm-graph->alist g)))))
          (define x-auto
            (find (lambda (e) (eq? (cdr (assoc 'trigger e)) 'auto))
                  (cdr (assoc 'edges x-state))))
        """)
        #expect(try engine.evaluate("(eq? (cdr (assoc 'class x-state)) 'transient)") == .true)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'target x-auto)) \"cross-b\")") == .true)
        #expect(try engine.evaluate("(cdr (assoc 'call x-auto))") == .true)
    }

    // MARK: - The two runtime carve-outs stay outside static closure

    @Test func dynamicNextResolverIsExemptFromClosureValidation() throws {
        let engine = try loaded()
        // A procedure-valued 'next resolves at fire time; the lowering
        // must accept it even though nothing it could return is checkable.
        try engine.evaluate("""
          (define g (lower-configuration
            (configuration
              (tree 'dyn-test
                (group "" "Root"
                  (key "x" "X" (lambda () 'x)
                       'next (lambda () "resolved-at-fire-time")))))))
        """)
        #expect(try engine.evaluate("(fsm-graph? g)") == .true)
    }

    @Test func providerIsNeverInvokedAtLowerTime() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (define provider-ran? #f)
          (define g (lower-configuration
            (configuration
              (tree 'prov-test
                (group "" "Root"
                  'provider (lambda (owner-id)
                              (set! provider-ran? #t)
                              (list (cons 'edges (list (edge "z" 'synthetic)))
                                    (cons 'states (list (provided-state 'synthetic)))))
                  (key "x" "X" (lambda () 'x)))))))
        """)
        // Lowering succeeded despite the provider's synthetic states not
        // existing in the graph — visit-scoped states are outside static
        // closure — and the provider itself never ran.
        #expect(try engine.evaluate("(fsm-graph? g)") == .true)
        #expect(try engine.evaluate("provider-ran?") == .false)
    }

    // MARK: - The engine consumes the installed graph

    @Test func installGraphSwapsWhatTheEngineConsumes() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (fsm-install-graph! (lower-configuration
            (configuration (tree 'old-tree
              (tree-root 'old-tree (key "o" "Old" (lambda () 'old)))))))
          (define fired #f)
          (define g (lower-configuration
            (configuration
              (tree 'swap-test
                (group "" "Root"
                  (key "x" "X" (lambda () (set! fired #t))))))))
          (fsm-install-graph! g)
        """)
        // The previously-installed tree's states are gone with its graph…
        #expect(try engine.evaluate("(fsm-state-ref \"old-tree\")") == .false)
        // …the lowered graph's states are what the engine now resolves…
        #expect(try engine.evaluate("(eq? (fsm-state-class \"swap-test\") 'resting)") == .true)
        #expect(try engine.evaluate("(eq? (fsm-installed-graph) g)") == .true)
        // …and the step engine runs it end-to-end: activate, dispatch a
        // key, the terminal leaf's action fires.
        try engine.evaluate("""
          (fsm-activate! "swap-test")
          (fsm-step! "x")
        """)
        #expect(try engine.evaluate("fired") == .true)
        #expect(try engine.evaluate("(fsm-active?)") == .false)
    }
}
