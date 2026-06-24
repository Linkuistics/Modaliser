import Foundation
import Testing
import LispKit
@testable import Modaliser

// Lowering tests for the presentation-first layout DSL (ADR-0011/0012):
// the `screen` / `panel` / `open` container forms in (modaliser dsl) and the
// construction-time lowering that emits operational alist nodes carrying the
// presentation metadata the panel-grid renderer (panel-grid-renderer-k4)
// reads. The state machine is untouched, so these exercise the alist shape
// and that find-child / flatten-categories still dispatch transparently.
@Suite("Layout DSL (screen / panel / open lowering)")
struct LayoutDslTests {

    // Imports just enough for lowering + dispatch: dsl, state-machine,
    // and the helpers below. No ui/*.scm — find-child / navigate-to-path
    // are pure state-machine, and modal show/hide hooks default to no-ops.
    private func loadLayout() throws -> SchemeEngine {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser util)
                  (modaliser keymap)
                  (modaliser state-machine))
        """)
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")
        // A minimal live-list block-spec, shaped like the real
        // window:list-block / iterm:pane-list-block output: a 'type entry,
        // a hidden digit (key-range …) under 'block-children, and an
        // on-leave-fn (the chip-clear hook). No window system needed.
        try engine.evaluate("""
          (define (fake-list-block)
            (list (cons 'type 'window-list)
                  (cons 'on-leave-fn (lambda () 'left))
                  (cons 'block-children
                        (list (key-range "1.." "Win <n>" (list "1" "2")
                                (lambda (k) k))))))
          ;; Find a direct child category (panel) of ROOT by its label.
          (define (find-panel root label)
            (let loop ((cs (node-children root)))
              (cond ((null? cs) #f)
                    ((and (eq? (cdr (assoc 'kind (car cs))) 'category)
                          (equal? (node-label (car cs)) label))
                     (car cs))
                    (else (loop (cdr cs))))))
        """)
        return engine
    }

    // MARK: - panel

    @Test func panelLowersToCategoryWithDefaultNarrowSpan() throws {
        let engine = try loadLayout()
        try engine.evaluate("""
            (define p (panel "Windows" (key "c" "Center" (lambda () 'ok))))
            """)
        #expect(try engine.evaluate("(category? p)") == .true)
        #expect(try engine.evaluate("(node-label p)").asString() == "Windows")
        #expect(try engine.evaluate("(eq? (cdr (assoc 'span p)) 'narrow)") == .true)
        // The key descends transparently.
        #expect(try engine.evaluate("(command? (find-child p \"c\"))") == .true)
    }

    @Test func panelAcceptsExplicitSpan() throws {
        let engine = try loadLayout()
        try engine.evaluate("(define p (panel \"X\" 'span 'full (key \"c\" \"C\" (lambda () 'ok))))")
        #expect(try engine.evaluate("(eq? (cdr (assoc 'span p)) 'full)") == .true)
    }

    @Test func panelRejectsUnknownSpan() throws {
        let engine = try loadLayout()
        #expect(throws: (any Error).self) {
            try engine.evaluate("(panel \"X\" 'span 'huge (key \"c\" \"C\" (lambda () 'ok)))")
        }
    }

    @Test func panelRejectsUnknownKeyword() throws {
        let engine = try loadLayout()
        #expect(throws: (any Error).self) {
            try engine.evaluate("(panel \"X\" 'frob 1 (key \"c\" \"C\" (lambda () 'ok)))")
        }
    }

    @Test func panelAutoWidesWithEmbeddedListBlock() throws {
        let engine = try loadLayout()
        try engine.evaluate("(define p (panel \"Windows\" (fake-list-block)))")
        #expect(try engine.evaluate("(eq? (cdr (assoc 'span p)) 'wide)") == .true)
    }

    @Test func explicitSpanOverridesAutoWide() throws {
        let engine = try loadLayout()
        try engine.evaluate("(define p (panel \"Windows\" 'span 'narrow (fake-list-block)))")
        #expect(try engine.evaluate("(eq? (cdr (assoc 'span p)) 'narrow)") == .true)
    }

    @Test func panelCarriesListBlockUnderListKey() throws {
        let engine = try loadLayout()
        try engine.evaluate("(define p (panel \"Windows\" (fake-list-block)))")
        // The block-spec rides under 'list for the renderer to read.
        #expect(try engine.evaluate("(eq? (cdr (assoc 'type (node-renderer-payload p 'list))) 'window-list)") == .true)
    }

    @Test func panelLiftsListBlockChildrenIntoDispatch() throws {
        let engine = try loadLayout()
        try engine.evaluate("(define p (panel \"Windows\" (fake-list-block)))")
        // The block's hidden digit range was lifted into the panel's
        // dispatch children, so pressing "1" resolves to it.
        #expect(try engine.evaluate("(range-command? (find-child p \"1\"))") == .true)
    }

    @Test func panelRejectsTwoListBlocks() throws {
        let engine = try loadLayout()
        #expect(throws: (any Error).self) {
            try engine.evaluate("(panel \"Windows\" (fake-list-block) (fake-list-block))")
        }
    }

    @Test func panelExpandsSplicesAmongChildren() throws {
        let engine = try loadLayout()
        // sticky-set returns a splice; its keys must hoist into the panel.
        try engine.evaluate("""
            (define sp (sticky-set 'panel-walk-test "Walk"
              (key "h" "Left" (lambda () 'ok))
              (key "l" "Right" (lambda () 'ok))))
            (define p (panel "Nav" sp))
            """)
        #expect(try engine.evaluate("(command? (find-child p \"h\"))") == .true)
        #expect(try engine.evaluate("(command? (find-child p \"l\"))") == .true)
    }

    // MARK: - screen

    @Test func screenRegistersTreeWithPanelGridRenderer() throws {
        let engine = try loadLayout()
        try engine.evaluate("""
            (screen 'scr-test
              (panel "P" (key "c" "C" (lambda () 'ok))))
            """)
        #expect(try engine.evaluate("(lookup-tree \"scr-test\")") != .false)
        #expect(try engine.evaluate("(eq? (node-renderer (lookup-tree \"scr-test\")) 'panel-grid)") == .true)
    }

    @Test func screenCarriesColsWhenGiven() throws {
        let engine = try loadLayout()
        try engine.evaluate("(screen 'scr-cols 'cols 3 (panel \"P\" (key \"c\" \"C\" (lambda () 'ok))))")
        #expect(try engine.evaluate("(= (node-renderer-payload (lookup-tree \"scr-cols\") 'cols) 3)") == .true)
    }

    @Test func screenCarriesLayoutWhenGiven() throws {
        let engine = try loadLayout()
        try engine.evaluate("(screen 'scr-layout 'layout 'grid (panel \"P\" (key \"c\" \"C\" (lambda () 'ok))))")
        #expect(try engine.evaluate("(eq? (node-renderer-payload (lookup-tree \"scr-layout\") 'layout) 'grid)") == .true)
    }

    @Test func screenDefaultsToMasonryWhenLayoutOmitted() throws {
        let engine = try loadLayout()
        // No 'layout keyword → no layout marker on the node; the renderer omits
        // it and the CSS default (.panel-grid masonry) applies.
        try engine.evaluate("(screen 'scr-nolayout (panel \"P\" (key \"c\" \"C\" (lambda () 'ok))))")
        #expect(try engine.evaluate("(node-renderer-payload (lookup-tree \"scr-nolayout\") 'layout)") == .false)
    }

    @Test func screenRejectsUnknownLayout() throws {
        let engine = try loadLayout()
        #expect(throws: (any Error).self) {
            try engine.evaluate("(screen 'scr-badlayout 'layout 'wat (panel \"P\" (key \"c\" \"C\" (lambda () 'ok))))")
        }
    }

    @Test func screenPacksLooseKeysIntoGeneralPanel() throws {
        let engine = try loadLayout()
        try engine.evaluate("""
            (screen 'scr-general
              (key "a" "Loose A" (lambda () 'ok))
              (panel "P" (key "b" "B" (lambda () 'ok))))
            """)
        let root = "(lookup-tree \"scr-general\")"
        // A "General" panel exists holding the loose key.
        #expect(try engine.evaluate("(category? (find-panel \(root) \"General\"))") == .true)
        #expect(try engine.evaluate("(command? (find-child (find-panel \(root) \"General\") \"a\"))") == .true)
        // The explicit panel passed through, and dispatch is transparent.
        #expect(try engine.evaluate("(category? (find-panel \(root) \"P\"))") == .true)
        #expect(try engine.evaluate("(command? (find-child \(root) \"a\"))") == .true)
        #expect(try engine.evaluate("(command? (find-child \(root) \"b\"))") == .true)
    }

    @Test func screenWithoutLooseKeysHasNoGeneralPanel() throws {
        let engine = try loadLayout()
        try engine.evaluate("(screen 'scr-nogeneral (panel \"P\" (key \"b\" \"B\" (lambda () 'ok))))")
        #expect(try engine.evaluate("(find-panel (lookup-tree \"scr-nogeneral\") \"General\")") == .false)
    }

    @Test func screenAcceptsLifecycleKeywords() throws {
        let engine = try loadLayout()
        try engine.evaluate("""
            (screen 'scr-life 'sticky #t 'display-name "Title" 'exit-on-unknown #t
              (panel "P" (key "c" "C" (lambda () 'ok))))
            """)
        let root = "(lookup-tree \"scr-life\")"
        #expect(try engine.evaluate("(node-sticky? \(root))") == .true)
        #expect(try engine.evaluate("(equal? (node-display-name \(root)) \"Title\")") == .true)
        #expect(try engine.evaluate("(node-exit-on-unknown? \(root))") == .true)
    }

    @Test func screenComposesEmbeddedListOnLeaveHook() throws {
        let engine = try loadLayout()
        // The embedded list's on-leave-fn (chip clear) must be composed
        // onto the screen group's on-leave (via panel-grid-head's hook merge).
        try engine.evaluate("(screen 'scr-hooks (panel \"Windows\" (fake-list-block)))")
        #expect(try engine.evaluate("(procedure? (node-on-leave (lookup-tree \"scr-hooks\")))") == .true)
    }

    @Test func screenExpandsTopLevelSplices() throws {
        let engine = try loadLayout()
        try engine.evaluate("""
            (define sp2 (sticky-set 'screen-walk-test "Walk"
              (key "h" "Left" (lambda () 'ok))))
            (screen 'scr-splice sp2 (panel "P" (key "c" "C" (lambda () 'ok))))
            """)
        // The spliced key lands in General and dispatches from the root.
        #expect(try engine.evaluate("(command? (find-child (lookup-tree \"scr-splice\") \"h\"))") == .true)
    }

    // MARK: - open

    @Test func openLowersToNavigableGroupWithPanelGrid() throws {
        let engine = try loadLayout()
        try engine.evaluate("""
            (define o (open "s" "Splits"
              (panel "P" (key "x" "X" (lambda () 'ok)))))
            """)
        #expect(try engine.evaluate("(group? o)") == .true)
        #expect(try engine.evaluate("(equal? (node-key o) \"s\")") == .true)
        #expect(try engine.evaluate("(equal? (node-label o) \"Splits\")") == .true)
        #expect(try engine.evaluate("(eq? (node-renderer o) 'panel-grid)") == .true)
    }

    @Test func openDispatchDescendsThroughItsPanels() throws {
        let engine = try loadLayout()
        try engine.evaluate("""
            (screen 'scr-open
              (open "s" "Splits"
                (panel "P" (key "x" "X" (lambda () 'ok)))))
            """)
        let root = "(lookup-tree \"scr-open\")"
        // Pressing "s" descends into the open group (navigable, not flattened).
        #expect(try engine.evaluate("(group? (find-child \(root) \"s\"))") == .true)
        // Inside the open, the panel's key dispatches transparently.
        #expect(try engine.evaluate("(command? (find-child (navigate-to-path \(root) (list \"s\")) \"x\"))") == .true)
    }

    @Test func openCarriesColsWhenGiven() throws {
        let engine = try loadLayout()
        try engine.evaluate("""
            (define o (open "s" "Splits" 'cols 2
              (panel "P" (key "x" "X" (lambda () 'ok)))))
            """)
        #expect(try engine.evaluate("(= (node-renderer-payload o 'cols) 2)") == .true)
    }

    @Test func openCarriesLayoutWhenGiven() throws {
        let engine = try loadLayout()
        try engine.evaluate("""
            (define o (open "s" "Splits" 'layout 'grid
              (panel "P" (key "x" "X" (lambda () 'ok)))))
            """)
        #expect(try engine.evaluate("(eq? (node-renderer-payload o 'layout) 'grid)") == .true)
    }

    // MARK: - fragment

    @Test func fragmentProducesTransparentSpliceNode() throws {
        let engine = try loadLayout()
        try engine.evaluate("(define frag (fragment (key \"c\" \"Center\" (lambda () 'ok))))")
        // A 'kind 'splice node — expand-splices hoists its children, so
        // nothing downstream ever sees the fragment.
        #expect(try engine.evaluate("(eq? (cdr (assoc 'kind frag)) 'splice)") == .true)
    }

    @Test func fragmentSplicesIdenticallyToInlineInPanel() throws {
        let engine = try loadLayout()
        // Sharing the same action object + key nodes makes node-tree equality
        // exact (lambdas compare by identity), so this is a true "splices
        // identically to inline content" assertion.
        try engine.evaluate("""
            (define act (lambda () 'ok))
            (define kc (key "c" "Center"   act))
            (define km (key "m" "Maximise" act))
            (define window-ops (fragment kc km))
            (define p-frag   (panel "Windows" window-ops))
            (define p-inline (panel "Windows" kc km))
            """)
        #expect(try engine.evaluate("(equal? p-frag p-inline)") == .true)
    }

    @Test func fragmentSplicesIdenticallyToInlineInScreen() throws {
        let engine = try loadLayout()
        try engine.evaluate("""
            (define act (lambda () 'ok))
            (define pa (panel "A" (key "a" "A" act)))
            (define pb (panel "B" (key "b" "B" act)))
            (define panels-frag (fragment pa pb))
            (screen 'scr-frag-eq   panels-frag)
            (screen 'scr-inline-eq pa pb)
            """)
        #expect(try engine.evaluate("""
            (equal? (node-children (lookup-tree "scr-frag-eq"))
                    (node-children (lookup-tree "scr-inline-eq")))
            """) == .true)
    }

    @Test func fragmentDefinedOnceSplicedIntoTwoSitesDispatches() throws {
        let engine = try loadLayout()
        // A genuinely shared window-ops set, defined once and spliced into two
        // separate screens (DRY) — the leaf's proof, not a contrived example.
        try engine.evaluate("""
            (define act (lambda () 'ok))
            (define window-ops
              (fragment
                (key "c" "Center"   act)
                (key "m" "Maximise" act)))
            (screen 'scr-global (panel "Windows" window-ops))
            (screen 'scr-finder (panel "Layout"  window-ops))
            """)
        // The shared keys dispatch transparently from BOTH sites.
        #expect(try engine.evaluate("(command? (find-child (lookup-tree \"scr-global\") \"c\"))") == .true)
        #expect(try engine.evaluate("(command? (find-child (lookup-tree \"scr-global\") \"m\"))") == .true)
        #expect(try engine.evaluate("(command? (find-child (lookup-tree \"scr-finder\") \"c\"))") == .true)
        #expect(try engine.evaluate("(command? (find-child (lookup-tree \"scr-finder\") \"m\"))") == .true)
    }

    @Test func fragmentOfPanelsDispatchesAtScreenLevel() throws {
        let engine = try loadLayout()
        // A fragment may carry panels (screen-level reuse); they splice in as
        // real panels alongside inline ones.
        try engine.evaluate("""
            (define act (lambda () 'ok))
            (define shared-panels
              (fragment
                (panel "A" (key "a" "A" act))
                (panel "B" (key "b" "B" act))))
            (screen 'scr-panels shared-panels (panel "C" (key "c" "C" act)))
            """)
        let root = "(lookup-tree \"scr-panels\")"
        #expect(try engine.evaluate("(command? (find-child \(root) \"a\"))") == .true)
        #expect(try engine.evaluate("(command? (find-child \(root) \"b\"))") == .true)
        #expect(try engine.evaluate("(command? (find-child \(root) \"c\"))") == .true)
        // The spliced panels survive as real panels (categories).
        #expect(try engine.evaluate("(category? (find-panel \(root) \"A\"))") == .true)
        #expect(try engine.evaluate("(category? (find-panel \(root) \"B\"))") == .true)
    }

    @Test func fragmentComposesWithStickySetInPanel() throws {
        let engine = try loadLayout()
        // A fragment whose contents include a sticky-set — both are
        // 'kind 'splice, so the nested splice hoists via expand-splices'
        // recursion. Proves splices compose inside a panel body.
        try engine.evaluate("""
            (define act (lambda () 'ok))
            (define sset (sticky-set 'frag-compose-walk "Walk"
                           (key "h" "Left" act)))
            (define frag2 (fragment (key "c" "Center" act) sset))
            (define p (panel "Nav" frag2))
            """)
        #expect(try engine.evaluate("(command? (find-child p \"c\"))") == .true)  // from fragment
        #expect(try engine.evaluate("(command? (find-child p \"h\"))") == .true)  // from nested sticky-set
        // The sticky entry keeps its 'sticky-target, latching as before.
        #expect(try engine.evaluate("(eq? (cdr (assoc 'sticky-target (find-child p \"h\"))) 'frag-compose-walk)") == .true)
    }

    @Test func fragmentComposesWithStickySetInScreen() throws {
        let engine = try loadLayout()
        // Same composition at screen level: a fragment + a sticky-set both
        // spliced into the screen body, their loose keys landing in General.
        try engine.evaluate("""
            (define act (lambda () 'ok))
            (define ops (fragment (key "c" "Center" act)))
            (define sset (sticky-set 'frag-screen-walk "Walk" (key "h" "Left" act)))
            (screen 'scr-compose ops sset (panel "P" (key "p" "P" act)))
            """)
        let root = "(lookup-tree \"scr-compose\")"
        #expect(try engine.evaluate("(command? (find-child \(root) \"c\"))") == .true)  // fragment
        #expect(try engine.evaluate("(command? (find-child \(root) \"h\"))") == .true)  // sticky-set
        #expect(try engine.evaluate("(command? (find-child \(root) \"p\"))") == .true)  // inline panel
    }

    @Test func fragmentSplicesInsideOpenBody() throws {
        let engine = try loadLayout()
        // The third container body — open — runs expand-splices too, so a
        // fragment hoists inside a drill-down sub-grid.
        try engine.evaluate("""
            (define act (lambda () 'ok))
            (define ops (fragment (key "c" "Center" act)))
            (define o (open "s" "Splits" ops (panel "P" (key "x" "X" act))))
            """)
        #expect(try engine.evaluate("(command? (find-child o \"c\"))") == .true)  // from fragment
        #expect(try engine.evaluate("(command? (find-child o \"x\"))") == .true)  // inline panel
    }
}
