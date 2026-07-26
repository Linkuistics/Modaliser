import Foundation
import Testing
import LispKit
@testable import Modaliser

// Unit tests for (modaliser display-dsl) resolve-display — the pure
// resolution seam of the two-layer node model (ADR-0011; docs/specs/
// configuration-value.md "Test seams"): (children, display value) →
// render plan. Children are a node's flat dispatch rows plus block-spec
// atoms — exactly what the sugar emits and the overlay resolves — and
// the suite ends with the invariant the factoring exists for:
// substituting a display value cannot change the live key set.
@Suite("Display DSL (resolve-display)")
struct DisplayDslTests {

    private func loadDisplay() throws -> SchemeEngine {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser util)
                  (modaliser fsm))
        """)
        try engine.evaluate("(import (modaliser dsl))")
        // The sugar's `panel` and the bare clause constructor `panel`
        // share a name by design (ADR-0011); configs and tests import
        // the bare surface prefixed. resolve-display is collision-free,
        // so the resolution tests keep it bare.
        try engine.evaluate("(import (only (modaliser display-dsl) resolve-display))")
        try engine.evaluate("(import (prefix (modaliser display-dsl) d:))")
        try engine.evaluate("(import (modaliser configuration))")
        try engine.evaluate("""
          (define act (lambda () 'ok))
          ;; A minimal live-list block-spec (cf. window:list-block): 'type,
          ;; an optional explicit 'id reference override, and the hidden
          ;; digit key-range under 'block-children.
          (define (fake-block . id)
            (let ((base (list (cons 'type 'window-list)
                              (cons 'on-leave-fn (lambda () 'left))
                              (cons 'block-children
                                    (list (key-range "1.." "Win <n>" (list "1" "2")
                                            (lambda (k) k)))))))
              (if (pair? id) (cons (cons 'id (car id)) base) base)))
          (define (plan-ref plan k) (cdr (assoc k plan)))
          (define (panel0 plan) (car (plan-ref plan 'panels)))
          (define (row-keys p) (map node-key (cdr (assoc 'rows p))))
        """)
        return engine
    }

    // MARK: - the no-display default

    @Test func emptyDisplayRendersAllChildrenLooseInDeclarationOrder() throws {
        let engine = try loadDisplay()
        // '() is both "no display" and "empty display" (fsm.sld
        // node-display): everything flows loose, declaration order,
        // blocks included — ADR-0011's no-display rendering.
        try engine.evaluate("""
            (define blk (fake-block))
            (define kids (list (key "b" "B" act) blk (key "a" "A" act)))
            (define plan (resolve-display kids '()))
            (define loose (plan-ref plan 'loose))
            """)
        #expect(try engine.evaluate("(= (length loose) 3)") == .true)
        #expect(try engine.evaluate("(eq? (car loose) (car kids))") == .true)
        #expect(try engine.evaluate("(eq? (cadr loose) blk)") == .true)
        #expect(try engine.evaluate("(eq? (caddr loose) (caddr kids))") == .true)
        #expect(try engine.evaluate("(null? (plan-ref plan 'panels))") == .true)
        #expect(try engine.evaluate("(null? (plan-ref plan 'sections))") == .true)
        #expect(try engine.evaluate("(not (plan-ref plan 'cols))") == .true)
        #expect(try engine.evaluate("(not (plan-ref plan 'layout))") == .true)
        #expect(try engine.evaluate("(not (plan-ref plan 'display-name))") == .true)
    }

    @Test func displayOptionsPassThroughToThePlan() throws {
        let engine = try loadDisplay()
        try engine.evaluate("""
            (define plan (resolve-display '()
              '((display-name . "T") (cols . 3) (layout . grid))))
            """)
        #expect(try engine.evaluate("(equal? (plan-ref plan 'display-name) \"T\")") == .true)
        #expect(try engine.evaluate("(= (plan-ref plan 'cols) 3)") == .true)
        #expect(try engine.evaluate("(eq? (plan-ref plan 'layout) 'grid)") == .true)
    }

    // MARK: - panels

    @Test func panelRowsResolveByKeyAndKeySortByDefault() throws {
        let engine = try loadDisplay()
        // Refs resolve to the node's own row objects; default 'keys
        // order applies the overlay's sort: case-insensitive, lowercase
        // before its own uppercase — "a A B c".
        try engine.evaluate("""
            (define ka (key "a" "A" act))
            (define kids (list (key "c" "C" act) (key "B" "Big" act)
                               ka (key "A" "BigA" act)))
            (define plan (resolve-display kids
              '((panels . (((label . "P") (span . narrow)
                            (rows . ((key . "c") (key . "B")
                                     (key . "a") (key . "A")))))))))
            (define p0 (panel0 plan))
            """)
        #expect(try engine.evaluate("(equal? (row-keys p0) '(\"a\" \"A\" \"B\" \"c\"))") == .true)
        #expect(try engine.evaluate("(eq? (car (cdr (assoc 'rows p0))) ka)") == .true)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'label p0)) \"P\")") == .true)
        #expect(try engine.evaluate("(eq? (cdr (assoc 'span p0)) 'narrow)") == .true)
        #expect(try engine.evaluate("(not (cdr (assoc 'list p0)))") == .true)
    }

    @Test func rowOrderResolvesPanelExplicitOverGridDefault() throws {
        let engine = try loadDisplay()
        try engine.evaluate("""
            (define kids (list (key "c" "C" act) (key "B" "Big" act) (key "a" "A" act)))
            (define refs '((key . "c") (key . "B") (key . "a")))
            ;; Grid-wide 'declared: the panel with no own 'order inherits it.
            (define plan-inherit (resolve-display kids
              (list (cons 'order 'declared)
                    (cons 'panels (list (list (cons 'label "P") (cons 'span 'narrow)
                                              (cons 'rows refs)))))))
            ;; Panel-explicit 'keys overrides the grid's 'declared.
            (define plan-override (resolve-display kids
              (list (cons 'order 'declared)
                    (cons 'panels (list (list (cons 'label "P") (cons 'span 'narrow)
                                              (cons 'order 'keys)
                                              (cons 'rows refs)))))))
            """)
        #expect(try engine.evaluate("(equal? (row-keys (panel0 plan-inherit)) '(\"c\" \"B\" \"a\"))") == .true)
        #expect(try engine.evaluate("(equal? (row-keys (panel0 plan-override)) '(\"a\" \"B\" \"c\"))") == .true)
    }

    @Test func panelBlockRefPartitionsIntoTheListSlot() throws {
        let engine = try loadDisplay()
        // A (block . id) ref among a panel's rows resolves to the block
        // atom and lands in the plan's 'list slot — rows stay rows, the
        // rendered structure (rows, then list) whatever the ref order.
        try engine.evaluate("""
            (define blk (fake-block))
            (define kids (list (key "a" "A" act) blk))
            (define plan (resolve-display kids
              '((panels . (((label . "W") (span . wide)
                            (rows . ((block . window-list) (key . "a")))))))))
            (define p0 (panel0 plan))
            """)
        #expect(try engine.evaluate("(equal? (row-keys p0) '(\"a\"))") == .true)
        #expect(try engine.evaluate("(eq? (cdr (assoc 'list p0)) blk)") == .true)
        #expect(try engine.evaluate("(eq? (cdr (assoc 'span p0)) 'wide)") == .true)
    }

    @Test func headerlessPanelKeepsItsFalseLabel() throws {
        let engine = try loadDisplay()
        // (label . #f) is HEADERLESS — distinct from "" — and survives
        // into the plan for the renderer to decide (no .panel-head).
        try engine.evaluate("""
            (define kids (list (key "a" "A" act)))
            (define plan (resolve-display kids
              '((panels . (((label . #f) (span . narrow) (rows . ((key . "a")))))))))
            """)
        #expect(try engine.evaluate("(not (cdr (assoc 'label (panel0 plan))))") == .true)
    }

    // MARK: - the loose region

    @Test func explicitLooseRefsResolveInRefOrder() throws {
        let engine = try loadDisplay()
        // An explicit 'loose entry states the region exactly — its ref
        // order IS the render order, rows and blocks interleaved.
        try engine.evaluate("""
            (define blk (fake-block))
            (define ka (key "a" "A" act))
            (define kb (key "b" "B" act))
            (define kids (list ka blk kb))
            (define plan (resolve-display kids
              '((loose . ((key . "b") (block . window-list) (key . "a"))))))
            (define loose (plan-ref plan 'loose))
            """)
        #expect(try engine.evaluate("(eq? (car loose) kb)") == .true)
        #expect(try engine.evaluate("(eq? (cadr loose) blk)") == .true)
        #expect(try engine.evaluate("(eq? (caddr loose) ka)") == .true)
    }

    @Test func absentLooseFallsBackToUnreferencedChildren() throws {
        let engine = try loadDisplay()
        // No 'loose entry: every child no panel references flows loose
        // in declaration order — a panels-only display cannot silently
        // drop an unreferenced live key.
        try engine.evaluate("""
            (define blk (fake-block))
            (define kb (key "b" "B" act))
            (define kids (list (key "a" "A" act) kb blk))
            (define plan (resolve-display kids
              '((panels . (((label . "P") (span . narrow)
                            (rows . ((key . "a") (block . window-list)))))))))
            (define loose (plan-ref plan 'loose))
            """)
        #expect(try engine.evaluate("(= (length loose) 1)") == .true)
        #expect(try engine.evaluate("(eq? (car loose) kb)") == .true)
    }

    // MARK: - embeds

    @Test func embedResolvesSectionsAndDropsTheDrillRows() throws {
        let engine = try loadDisplay()
        // Each embed key resolves to its group target, in embed-list
        // order; the embedded key's row leaves the loose region and the
        // panel rows — the section replaces the drill row.
        try engine.evaluate("""
            (define sub (group "s" "Sub" (key "x" "X" act)))
            (define ka (key "a" "A" act))
            (define kids (list ka sub))
            (define plan (resolve-display kids
              '((embed . ("s")) (loose . ((key . "a") (key . "s"))))))
            (define plan2 (resolve-display kids
              '((embed . ("s"))
                (panels . (((label . "P") (span . narrow)
                            (rows . ((key . "a") (key . "s")))))))))
            """)
        #expect(try engine.evaluate("(equal? (map car (plan-ref plan 'sections)) '(\"s\"))") == .true)
        #expect(try engine.evaluate("(eq? (cdr (car (plan-ref plan 'sections))) sub)") == .true)
        #expect(try engine.evaluate("(equal? (map node-key (plan-ref plan 'loose)) '(\"a\"))") == .true)
        #expect(try engine.evaluate("(equal? (row-keys (panel0 plan2)) '(\"a\"))") == .true)
    }

    @Test func embedKeyMustNameAGroupChild() throws {
        let engine = try loadDisplay()
        try engine.evaluate("(define kids (list (key \"a\" \"A\" act)))")
        // A command target rejects — a section is an intra-tree drill
        // target rendered in place, same contract lower-node! enforces.
        #expect(throws: (any Error).self) {
            try engine.evaluate("(resolve-display kids '((embed . (\"a\"))))")
        }
        #expect(throws: (any Error).self) {
            try engine.evaluate("(resolve-display kids '((embed . (\"missing\"))))")
        }
    }

    // MARK: - reference strictness

    @Test func danglingRefsError() throws {
        let engine = try loadDisplay()
        try engine.evaluate("(define kids (list (key \"a\" \"A\" act)))")
        #expect(throws: (any Error).self) {
            try engine.evaluate("(resolve-display kids '((loose . ((key . \"z\")))))")
        }
        #expect(throws: (any Error).self) {
            try engine.evaluate("""
                (resolve-display kids
                  '((panels . (((label . "P") (span . narrow)
                                (rows . ((block . ghost))))))))
                """)
        }
    }

    @Test func ambiguousBlockIdsErrorAndExplicitIdResolves() throws {
        let engine = try loadDisplay()
        // Two same-type blocks: the shared default id ('type) is
        // ambiguous; an explicit 'id disambiguates and resolves to that
        // very block.
        try engine.evaluate("""
            (define blk1 (fake-block))
            (define blk2 (fake-block 'second))
            (define kids-dup (list (fake-block) (fake-block)))
            (define kids-ids (list blk1 blk2))
            """)
        #expect(throws: (any Error).self) {
            try engine.evaluate("(resolve-display kids-dup '((loose . ((block . window-list)))))")
        }
        try engine.evaluate("""
            (define plan (resolve-display kids-ids '((loose . ((block . second))))))
            """)
        #expect(try engine.evaluate("(eq? (car (plan-ref plan 'loose)) blk2)") == .true)
    }

    // MARK: - sugar parity

    @Test func sugarBuiltNodeResolvesToItsAuthoredRenderStructure() throws {
        let engine = try loadDisplay()
        // A representative screen — loose row, loose block, embedded
        // open, panel with rows + block — resolved exactly as the
        // overlay does: from the node's own flat children and single
        // 'display entry. The plan must hand the overlay the very row
        // and block objects the sugar was given.
        try engine.evaluate("""
            (define blk-loose (fake-block))
            (define blk-panel (fake-block 'panes))
            (define cfg (configuration
              (screen 'scr-par 'embed '("s")
                (key "z" "Z" act)
                blk-loose
                (open "s" "Sub" (panel "Q" (key "x" "X" act)))
                (panel "W" blk-panel (key "c" "C" act) (key "B" "Big" act)))))
            (define root (configuration-tree-ref cfg "scr-par"))
            (define plan (resolve-display (node-children root) (node-display root)))
            (define loose (plan-ref plan 'loose))
            (define p0 (panel0 plan))
            """)
        // Loose: the authored row and the loose block, in declaration
        // order, with the embedded open's drill row dropped (the section
        // replaces it).
        #expect(try engine.evaluate("(= (length loose) 2)") == .true)
        #expect(try engine.evaluate("(eq? (car loose) (find-child root \"z\"))") == .true)
        #expect(try engine.evaluate("(eq? (cadr loose) blk-loose)") == .true)
        // The panel: key-sorted rows (the very child objects), the block
        // in the list slot, auto-'wide span.
        #expect(try engine.evaluate("(equal? (cdr (assoc 'label p0)) \"W\")") == .true)
        #expect(try engine.evaluate("(eq? (cdr (assoc 'span p0)) 'wide)") == .true)
        #expect(try engine.evaluate("(equal? (row-keys p0) '(\"B\" \"c\"))") == .true)
        #expect(try engine.evaluate("(eq? (car (cdr (assoc 'rows p0))) (find-child root \"B\"))") == .true)
        #expect(try engine.evaluate("(eq? (cdr (assoc 'list p0)) blk-panel)") == .true)
        // The embedded section resolves to the drilled group itself.
        #expect(try engine.evaluate("(equal? (map car (plan-ref plan 'sections)) '(\"s\"))") == .true)
        #expect(try engine.evaluate("(eq? (cdr (car (plan-ref plan 'sections))) (find-child root \"s\"))") == .true)
    }

    // MARK: - the structural invariant (ADR-0011)

    @Test func substitutingADisplayValueCannotChangeTheLiveKeySet() throws {
        let engine = try loadDisplay()
        // The invariant the two-layer factoring makes STRUCTURAL rather
        // than promised: dispatch reads (find-child, the FSM lowering)
        // never consult 'display, so replacing a node's display value
        // wholesale — here with a hostile one referencing a single key —
        // changes nothing about which keys are live.
        try engine.evaluate("""
            (define blk (fake-block))
            (define cfg (configuration
              (screen 'scr-inv
                (key "z" "Z" act)
                blk
                (panel "W" (key "c" "C" act) (key "B" "Big" act)))))
            (define root (configuration-tree-ref cfg "scr-inv"))
            (define swapped
              (node-with-display root
                '((panels . (((label . "Only C") (span . narrow)
                              (rows . ((key . "c")))))))))
            (define (live-keys n)
              (map node-key (dispatch-children n)))
            """)
        // Same live keys, the very same child objects — including the
        // block's hidden digit range ("1" "2"), which dispatch expands
        // from the block atom regardless of display placement.
        #expect(try engine.evaluate("(equal? (live-keys swapped) (live-keys root))") == .true)
        #expect(try engine.evaluate("""
            (equal? (live-keys root) '("z" "1.." "c" "B"))
            """) == .true)
        #expect(try engine.evaluate("(eq? (find-child swapped \"B\") (find-child root \"B\"))") == .true)
        #expect(try engine.evaluate("(eq? (find-child swapped \"1\") (find-child root \"1\"))") == .true)
        // And the swap really took: the new display renders only "c".
        #expect(try engine.evaluate("""
            (equal? (row-keys (panel0 (resolve-display (node-children swapped)
                                                       (node-display swapped))))
                    '("c"))
            """) == .true)
    }

    // MARK: - the bare clause constructors (display-dsl-surface-k23)

    @Test func withDisplayAssemblesClausesInCanonicalOrder() throws {
        let engine = try loadDisplay()
        // Clause order in the call is free; the assembled value is always
        // canonical (display-name, cols, layout, order, embed, loose,
        // panels), so a bare and a sugar spelling can never differ by
        // entry order. Dispatch entries ride through untouched.
        try engine.evaluate("""
            (define sub (group "s" "Sub" (key "x" "X" act)))
            (define node (tree-root 'bare1 (key "c" "C" act) (key "B" "Big" act) sub))
            (define shown
              (d:with-display node
                (d:panel "P" (d:span 'wide) "c" "B")
                (d:loose "s")
                (d:embed "s")
                (d:order 'declared)
                (d:layout 'grid)
                (d:cols 2)
                (d:display-name "Bare")))
            """)
        #expect(try engine.evaluate("""
            (equal? (node-display shown)
                    '((display-name . "Bare") (cols . 2) (layout . grid)
                      (order . declared) (embed . ("s"))
                      (loose . ((key . "s")))
                      (panels . (((label . "P") (span . wide)
                                  (rows . ((key . "c") (key . "B"))))))))
            """) == .true)
        #expect(try engine.evaluate("(eq? (node-children shown) (node-children node))") == .true)
    }

    @Test func withDisplayWithNoClausesReturnsTheNodeUnchanged() throws {
        let engine = try loadDisplay()
        // Zero clauses build the empty display value, and '() ≡ absent
        // (fsm.sld node-display) — so nothing is attached at all.
        try engine.evaluate("(define node (tree-root 'bare2 (key \"a\" \"A\" act)))")
        #expect(try engine.evaluate("(eq? (d:with-display node) node)") == .true)
    }

    @Test func barePanelDefaultsSpanNarrowAndAutoWidensOnABlockRef() throws {
        let engine = try loadDisplay()
        // The span default is the bare constructor's own rule (the sugar
        // resolves its span at panel-spec construction and passes it
        // through explicitly): 'narrow, auto-'wide when a block ref is
        // present, explicit span always winning.
        #expect(try engine.evaluate("(eq? (cdr (assoc 'span (d:panel \"P\" \"c\"))) 'narrow)") == .true)
        #expect(try engine.evaluate("(eq? (cdr (assoc 'span (d:panel \"L\" (d:block 'window-list)))) 'wide)") == .true)
        #expect(try engine.evaluate("""
            (eq? (cdr (assoc 'span (d:panel "L" (d:span 'narrow) (d:block 'window-list))))
                 'narrow)
            """) == .true)
        // A headerless panel keeps #f distinct from "".
        #expect(try engine.evaluate("(not (cdr (assoc 'label (d:panel #f \"c\"))))") == .true)
        // An explicit 'order is stored; absence inherits the grid default.
        #expect(try engine.evaluate("""
            (eq? (cdr (assoc 'order (d:panel "P" (d:order 'declared) "c"))) 'declared)
            """) == .true)
        #expect(try engine.evaluate("(not (assoc 'order (d:panel \"P\" \"c\")))") == .true)
    }

    @Test func bareClauseConstructorsValidateTheirValues() throws {
        let engine = try loadDisplay()
        for bad in [
            "(d:cols 0)", "(d:cols \"3\")",
            "(d:layout 'diagonal)",
            "(d:order 'random)",
            "(d:span 'huge)",
            "(d:embed \"a\" 'b)",
            "(d:block \"window-list\")",
            "(d:display-name 42)",
        ] {
            #expect(throws: (any Error).self, "\(bad) should reject") {
                try engine.evaluate(bad)
            }
        }
    }

    @Test func barePanelRejectsBadArgs() throws {
        let engine = try loadDisplay()
        // Two block refs, misplaced top-level clauses, duplicate span/
        // order clauses, and a non-string label all reject at
        // construction.
        for bad in [
            "(d:panel \"P\" (d:block 'a) (d:block 'b))",
            "(d:panel \"P\" (d:cols 3))",
            "(d:panel \"P\" (d:span 'wide) (d:span 'full))",
            "(d:panel \"P\" (d:order 'keys) (d:order 'declared))",
            "(d:panel 42 \"c\")",
        ] {
            #expect(throws: (any Error).self, "\(bad) should reject") {
                try engine.evaluate(bad)
            }
        }
    }

    @Test func withDisplayRejectsUnknownDuplicateAndMisplacedClauses() throws {
        let engine = try loadDisplay()
        try engine.evaluate("(define node (tree-root 'bare3 (key \"a\" \"A\" act)))")
        // 'span is a panel clause, duplicates of a top-level clause are
        // ambiguous, and an unrecognised clause shape is an error.
        for bad in [
            "(d:with-display node (d:span 'wide))",
            "(d:with-display node (d:cols 2) (d:cols 3))",
            "(d:with-display node '(bogus . 1))",
        ] {
            #expect(throws: (any Error).self, "\(bad) should reject") {
                try engine.evaluate(bad)
            }
        }
        // Attaching is one explicit step: a node that already carries a
        // display value rejects a second attach.
        #expect(throws: (any Error).self) {
            try engine.evaluate("(d:with-display (d:with-display node (d:cols 2)) (d:cols 3))")
        }
    }

    @Test func withDisplayValidatesReferencesAgainstTheNodesChildren() throws {
        let engine = try loadDisplay()
        // Display references are load-time errors (docs/specs/
        // configuration-value.md "Lowering and validation") — with-display
        // has the node in hand, so a bare author's dangling ref fails at
        // the attach, not at first render.
        try engine.evaluate("""
            (define node (tree-root 'bare4 (key "a" "A" act)))
            (define two-blocks (tree-root 'bare5 (key "a" "A" act) (fake-block) (fake-block)))
            """)
        #expect(throws: (any Error).self) {
            try engine.evaluate("(d:with-display node (d:panel \"P\" \"z\"))")
        }
        #expect(throws: (any Error).self) {
            try engine.evaluate("(d:with-display node (d:embed \"a\"))")
        }
        #expect(throws: (any Error).self) {
            try engine.evaluate("""
                (d:with-display two-blocks (d:loose "a")
                  (d:panel "L" (d:block 'window-list)))
                """)
        }
    }

    @Test func withDisplayExplicitLooseMustPlaceEveryChild() throws {
        let engine = try loadDisplay()
        // An explicit 'loose states the region exactly — but a display
        // may never silently drop a live row (active rows ≡ live keys):
        // every child must be placed loose, in a panel, or embedded.
        // Blocks count too — an unplaced block's hidden digit keys would
        // stay live with no rows shown.
        try engine.evaluate("""
            (define node (tree-root 'bare6 (key "a" "A" act) (key "b" "B" act)))
            (define with-blk (tree-root 'bare7 (key "a" "A" act) (fake-block)))
            (define sub (group "s" "Sub" (key "x" "X" act)))
            (define with-sub (tree-root 'bare8 (key "a" "A" act) sub))
            """)
        #expect(throws: (any Error).self) {
            try engine.evaluate("(d:with-display node (d:loose \"a\"))")
        }
        #expect(throws: (any Error).self) {
            try engine.evaluate("(d:with-display with-blk (d:loose \"a\"))")
        }
        // Placed elsewhere is fine: a panel row, a block ref, an embed.
        try engine.evaluate("(d:with-display node (d:loose \"a\") (d:panel \"P\" \"b\"))")
        try engine.evaluate("""
            (d:with-display with-blk (d:loose "a" (d:block 'window-list)))
            """)
        try engine.evaluate("(d:with-display with-sub (d:loose \"a\") (d:embed \"s\"))")
    }

    // MARK: - sugar ≡ bare (the veneer contract, ADR-0012)

    @Test func sugarScreenWithPanelsAndLooseEqualsItsBareSpelling() throws {
        let engine = try loadDisplay()
        // The same child objects authored both ways must produce
        // IDENTICAL node output — the equivalence that pins the sugar as
        // a veneer with no lowering logic of its own.
        try engine.evaluate("""
            (define kz (key "z" "Z" act))
            (define kc (key "c" "C" act))
            (define kB (key "B" "Big" act))
            (define sugar-cfg (configuration
              (screen 'eqv1 'cols 2 kz (panel "W" 'span 'wide kc kB))))
            (define bare-cfg (configuration
              (tree 'eqv1
                (d:with-display (tree-root 'eqv1 kz kc kB)
                  (d:cols 2)
                  (d:loose "z")
                  (d:panel "W" (d:span 'wide) "c" "B")))))
            """)
        #expect(try engine.evaluate("""
            (equal? (configuration-tree-ref sugar-cfg "eqv1")
                    (configuration-tree-ref bare-cfg "eqv1"))
            """) == .true)
    }

    @Test func sugarScreenWithBlocksEqualsItsBareSpelling() throws {
        let engine = try loadDisplay()
        // Blocks are dispatch atoms placed by reference: the loose block
        // interleaves in declaration order, the panel block auto-widens
        // its panel and its ref lands after the row refs. The resolved
        // render plans agree object-for-object.
        try engine.evaluate("""
            (define kz (key "z" "Z" act))
            (define kc (key "c" "C" act))
            (define blkL (fake-block))
            (define blkP (fake-block 'panes))
            (define sugar-cfg (configuration
              (screen 'eqv2 kz blkL (panel "W" blkP kc))))
            (define bare-cfg (configuration
              (tree 'eqv2
                (d:with-display (tree-root 'eqv2 kz blkL blkP kc)
                  (d:loose "z" (d:block 'window-list))
                  (d:panel "W" "c" (d:block 'panes))))))
            (define s-root (configuration-tree-ref sugar-cfg "eqv2"))
            (define b-root (configuration-tree-ref bare-cfg "eqv2"))
            """)
        #expect(try engine.evaluate("(equal? s-root b-root)") == .true)
        #expect(try engine.evaluate("""
            (equal? (resolve-display (node-children s-root) (node-display s-root))
                    (resolve-display (node-children b-root) (node-display b-root)))
            """) == .true)
    }

    @Test func sugarScreenWithEmbeddedOpenEqualsItsBareSpelling() throws {
        let engine = try loadDisplay()
        // `open` is the drill+display sugar: a group whose own display
        // carries the sub-grid's panel clauses. The embedding parent
        // lists the drill key both loose and embedded, exactly as the
        // sugar emits it.
        try engine.evaluate("""
            (define ka (key "a" "A" act))
            (define kx (key "x" "X" act))
            (define sugar-cfg (configuration
              (screen 'eqv3 'embed '("s")
                ka
                (open "s" "Sub" (panel "Q" kx)))))
            (define bare-cfg (configuration
              (tree 'eqv3
                (d:with-display
                  (tree-root 'eqv3 ka
                    (d:with-display (group "s" "Sub" kx) (d:panel "Q" "x")))
                  (d:embed "s")
                  (d:loose "a" "s")))))
            """)
        #expect(try engine.evaluate("""
            (equal? (configuration-tree-ref sugar-cfg "eqv3")
                    (configuration-tree-ref bare-cfg "eqv3"))
            """) == .true)
    }

    @Test func sugarScreenWithAWalkEqualsItsBareSpelling() throws {
        let engine = try loadDisplay()
        // A walk splice survives as a child in both spellings; its entry
        // keys land in the loose region by key ref, and the SAME hoisted
        // mode tree reaches the configuration from either one.
        try engine.evaluate("""
            (define kc (key "c" "C" act))
            (define w (walk 'eqv4-mode "Walk" (key "h" "Left" act)))
            (define sugar-cfg (configuration
              (screen 'eqv4 w (panel "P" kc))))
            (define bare-cfg (configuration
              (tree 'eqv4
                (d:with-display (tree-root 'eqv4 w kc)
                  (d:loose "h")
                  (d:panel "P" "c")))))
            """)
        #expect(try engine.evaluate("""
            (equal? (configuration-tree-ref sugar-cfg "eqv4")
                    (configuration-tree-ref bare-cfg "eqv4"))
            """) == .true)
        #expect(try engine.evaluate("""
            (eq? (configuration-tree-ref sugar-cfg "eqv4-mode")
                 (configuration-tree-ref bare-cfg "eqv4-mode"))
            """) == .true)
    }

    @Test func theDocumentedSugarAndBareSpellingsAgree() throws {
        let engine = try loadDisplay()
        // The worked example carried by docs/reference/dsl.md
        // ("Sugar ≡ bare") and by default-config.scm's header comment,
        // pinned verbatim so the documentation can't drift off the
        // surface it teaches (display-docs-ground-truth-k24).
        try engine.evaluate("""
            (define kz (key "z" "Z" act))
            (define kc (key "c" "C" act))
            (define kB (key "B" "Big" act))

            (define sugar-cfg (configuration
              (screen 'demo 'cols 2
                kz
                (panel "W" 'span 'wide kc kB))))

            (define bare-cfg (configuration
              (tree 'demo
                (d:with-display (tree-root 'demo kz kc kB)
                  (d:cols 2)
                  (d:loose "z")
                  (d:panel "W" (d:span 'wide) "c" "B")))))
            """)
        #expect(try engine.evaluate("""
            (equal? (configuration-tree-ref sugar-cfg "demo")
                    (configuration-tree-ref bare-cfg "demo"))
            """) == .true)
        // default-config.scm's comment shows the same pair without the
        // 'cols clause — the shortest honest spelling of the equivalence.
        try engine.evaluate("""
            (define sugar-plain (configuration
              (screen 'demo2 kz (panel "W" 'span 'wide kc kB))))
            (define bare-plain (configuration
              (tree 'demo2
                (d:with-display (tree-root 'demo2 kz kc kB)
                  (d:loose "z")
                  (d:panel "W" (d:span 'wide) "c" "B")))))
            """)
        #expect(try engine.evaluate("""
            (equal? (configuration-tree-ref sugar-plain "demo2")
                    (configuration-tree-ref bare-plain "demo2"))
            """) == .true)
    }
}
