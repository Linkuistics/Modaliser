import Foundation
import Testing
import LispKit
@testable import Modaliser

// Lowering tests for the presentation-first layout DSL (ADR-0011/0012):
// the `screen` / `panel` / `open` container forms in (modaliser dsl) and the
// construction-time lowering onto the two-layer node model — flat dispatch
// children plus one 'display entry holding the complete Display value the
// renderer resolves (resolve-display). These exercise the lowered shape
// and that find-child / dispatch-children still dispatch transparently.
@Suite("Layout DSL (screen / panel / open lowering)")
struct LayoutDslTests {

    // Imports just enough for lowering + dispatch: dsl, state-machine,
    // configuration (the pure merge the value-built trees go through),
    // and the helpers below. No ui/*.scm — find-child / navigate-to-path
    // are pure state-machine, and modal show/hide hooks default to no-ops.
    private func loadLayout() throws -> SchemeEngine {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser util)
                  (modaliser keymap)
                  (modaliser fsm))
        """)
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")
        try engine.evaluate("(import (modaliser configuration))")
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
          ;; Find a panel CLAUSE of ROOT's display value by its label —
          ;; panels live only in the display value now (ADR-0011), never
          ;; among a node's children.
          (define (find-panel root label)
            (let loop ((ps (or (node-display-ref root 'panels) '())))
              (cond ((null? ps) #f)
                    ((equal? (cdr (assoc 'label (car ps))) label) (car ps))
                    (else (loop (cdr ps))))))
        """)
        return engine
    }

    // MARK: - panel

    @Test func panelBuildsAConstructionSpecWithDefaultNarrowSpan() throws {
        let engine = try loadLayout()
        // panel returns a construction-time panel-spec the enclosing
        // screen/open consumes — never an IR node kind.
        try engine.evaluate("""
            (define p (panel "Windows" (key "c" "Center" (lambda () 'ok))))
            """)
        #expect(try engine.evaluate("(eq? (cdr (assoc 'kind p)) 'panel-spec)") == .true)
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
        // The block-spec rides under 'list (hook composition + the
        // display clause's block reference).
        #expect(try engine.evaluate("(eq? (cdr (assoc 'type (cdr (assoc 'list p)))) 'window-list)") == .true)
    }

    @Test func panelBlockDigitRangeResolvesInDispatch() throws {
        let engine = try loadLayout()
        try engine.evaluate("(define p (panel \"Windows\" (fake-list-block)))")
        // The block stays a dispatch atom among the children; its hidden
        // digit range expands at read time (dispatch-children), so
        // pressing "1" resolves to it.
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
        // walk returns a splice; its keys must hoist into the panel.
        try engine.evaluate("""
            (define sp (walk 'panel-walk-test "Walk"
              (key "h" "Left" (lambda () 'ok))
              (key "l" "Right" (lambda () 'ok))))
            (define p (panel "Nav" sp))
            """)
        #expect(try engine.evaluate("(command? (find-child p \"h\"))") == .true)
        #expect(try engine.evaluate("(command? (find-child p \"l\"))") == .true)
    }

    @Test func walkForwardsOrderToModeTree() throws {
        let engine = try loadLayout()
        // 'order 'declared on walk rides through to the walk's carried mode
        // tree (hoisted into the configuration's tree set by the merge) so
        // the crossed-into Walk renders in declaration order rather than
        // key-sorted (iterm-nav-declared-order-k38).
        try engine.evaluate("""
            (define cfg (configuration
              (tree 'sset-order-host (tree-root 'sset-order-host
                (walk 'sset-order-declared "Walk" 'order 'declared
                  (key "h" "Left"  (lambda () 'ok))
                  (key "l" "Right" (lambda () 'ok)))))))
            """)
        #expect(try engine.evaluate(
          "(eq? (node-display-ref (configuration-tree-ref cfg \"sset-order-declared\") 'order) 'declared)") == .true)
    }

    @Test func walkOmitsOrderByDefault() throws {
        let engine = try loadLayout()
        // No 'order keyword → the hoisted mode carries no 'order entry, so
        // it keeps the renderer's key-sort default.
        try engine.evaluate("""
            (define cfg (configuration
              (tree 'sset-order-host (tree-root 'sset-order-host
                (walk 'sset-order-default "Walk"
                  (key "h" "Left"  (lambda () 'ok))
                  (key "l" "Right" (lambda () 'ok)))))))
            """)
        #expect(try engine.evaluate(
          "(node-display-ref (configuration-tree-ref cfg \"sset-order-default\") 'order)") == .false)
    }

    @Test func walkOrderKeywordDoesNotLeakIntoSplice() throws {
        let engine = try loadLayout()
        // The 'order keyword configures the registered mode only; the splice it
        // returns must carry exactly the two key nodes (so they hoist cleanly),
        // not the keyword pair.
        try engine.evaluate("""
            (define sp (walk 'sset-order-splice "Walk" 'order 'declared
              (key "h" "Left"  (lambda () 'ok))
              (key "l" "Right" (lambda () 'ok))))
            """)
        #expect(try engine.evaluate("(= (length (node-children sp)) 2)") == .true)
    }

    // MARK: - screen

    @Test func screenContributesTreeWithStructuredDisplay() throws {
        let engine = try loadLayout()
        try engine.evaluate("""
            (define cfg (configuration (screen 'scr-test
              (panel "P" (key "c" "C" (lambda () 'ok))))))
            (define scr-root (configuration-tree-ref cfg "scr-test"))
            """)
        #expect(try engine.evaluate("scr-root") != .false)
        // The panel grid lives in the display value — the shape the
        // overlay derives the panel-grid render path from.
        #expect(try engine.evaluate("(pair? (node-display-ref scr-root 'panels))") == .true)
    }

    @Test func screenCarriesColsWhenGiven() throws {
        let engine = try loadLayout()
        try engine.evaluate("(define cfg (configuration (screen 'scr-cols 'cols 3 (panel \"P\" (key \"c\" \"C\" (lambda () 'ok))))))")
        #expect(try engine.evaluate("(= (node-display-ref (configuration-tree-ref cfg \"scr-cols\") 'cols) 3)") == .true)
    }

    @Test func screenCarriesLayoutWhenGiven() throws {
        let engine = try loadLayout()
        try engine.evaluate("(define cfg (configuration (screen 'scr-layout 'layout 'grid (panel \"P\" (key \"c\" \"C\" (lambda () 'ok))))))")
        #expect(try engine.evaluate("(eq? (node-display-ref (configuration-tree-ref cfg \"scr-layout\") 'layout) 'grid)") == .true)
    }

    @Test func screenDefaultsToMasonryWhenLayoutOmitted() throws {
        let engine = try loadLayout()
        // No 'layout keyword → no layout entry in the display value; the
        // renderer omits it and the CSS default (.panel-grid masonry) applies.
        try engine.evaluate("(define cfg (configuration (screen 'scr-nolayout (panel \"P\" (key \"c\" \"C\" (lambda () 'ok))))))")
        #expect(try engine.evaluate("(node-display-ref (configuration-tree-ref cfg \"scr-nolayout\") 'layout)") == .false)
    }

    @Test func screenRejectsUnknownLayout() throws {
        let engine = try loadLayout()
        #expect(throws: (any Error).self) {
            try engine.evaluate("(screen 'scr-badlayout 'layout 'wat (panel \"P\" (key \"c\" \"C\" (lambda () 'ok))))")
        }
    }

    @Test func screenRendersLooseKeysWithoutGeneralPanel() throws {
        let engine = try loadLayout()
        try engine.evaluate("""
            (define cfg (configuration (screen 'scr-general
              (key "a" "Loose A" (lambda () 'ok))
              (panel "P" (key "b" "B" (lambda () 'ok))))))
            """)
        let root = "(configuration-tree-ref cfg \"scr-general\")"
        // No "General" panel is created — loose atoms no longer bucket into one.
        #expect(try engine.evaluate("(find-panel \(root) \"General\")") == .false)
        // The loose key rides the display value's 'loose refs (the renderer
        // draws them as a bare, header-less row block above the panel grid).
        #expect(try engine.evaluate("(pair? (node-display-ref \(root) 'loose))") == .true)
        // The explicit panel passed through, and dispatch stays transparent for
        // both the loose key and the panel key.
        #expect(try engine.evaluate("(pair? (find-panel \(root) \"P\"))") == .true)
        #expect(try engine.evaluate("(command? (find-child \(root) \"a\"))") == .true)
        #expect(try engine.evaluate("(command? (find-child \(root) \"b\"))") == .true)
    }

    @Test func screenWithoutLooseAtomsHasNoLooseRegion() throws {
        let engine = try loadLayout()
        try engine.evaluate("(define cfg (configuration (screen 'scr-nogeneral (panel \"P\" (key \"b\" \"B\" (lambda () 'ok))))))")
        let root = "(configuration-tree-ref cfg \"scr-nogeneral\")"
        // No General panel, and no 'loose entry when every child is a panel.
        #expect(try engine.evaluate("(find-panel \(root) \"General\")") == .false)
        #expect(try engine.evaluate("(node-display-ref \(root) 'loose)") == .false)
    }

    @Test func looseBlockDigitRangeResolvesInDispatch() throws {
        let engine = try loadLayout()
        // A live-list block placed LOOSE at the screen top level (not wrapped
        // in a panel) stays a dispatch atom among the children — its hidden
        // digit range expands at read time (dispatch-children) so the digits
        // resolve transparently, while the display's loose refs place the
        // block for the renderer to draw bare.
        try engine.evaluate("""
            (define cfg (configuration (screen 'scr-loose-block
              (key "a" "Loose A" (lambda () 'ok))
              (fake-list-block))))
            """)
        let root = "(configuration-tree-ref cfg \"scr-loose-block\")"
        #expect(try engine.evaluate("(range-command? (find-child \(root) \"1\"))") == .true)
        #expect(try engine.evaluate("(command? (find-child \(root) \"a\"))") == .true)
        #expect(try engine.evaluate("(find-panel \(root) \"General\")") == .false)
    }

    @Test func screenLeavesBlockHooksOnTheBlockAtom() throws {
        let engine = try loadLayout()
        // Block hooks are NOT composed into the node's own on-leave (the
        // sugar is a veneer — display-dsl-surface-k23): they stay on the
        // block atom, and run-on-leave fires them structurally from the
        // children. The node's 'on-leave is the user's raw hook or #f.
        try engine.evaluate("(define cfg (configuration (screen 'scr-loose-hooks (fake-list-block))))")
        #expect(try engine.evaluate("(not (node-on-leave (configuration-tree-ref cfg \"scr-loose-hooks\")))") == .true)
    }

    @Test func runOnLeaveFiresUserHookThenBlockHooksStructurally() throws {
        let engine = try loadLayout()
        // The firing contract: the node's own hook first, then each block
        // child's hook fn in declaration order — loose and panel-embedded
        // alike, since both are flat children under ADR-0011.
        try engine.evaluate("""
            (define fired '())
            (define (mk-block id)
              (list (cons 'type 'window-list)
                    (cons 'id id)
                    (cons 'on-leave-fn (lambda () (set! fired (cons id fired))))))
            (define cfg (configuration
              (screen 'scr-fire 'on-leave (lambda () (set! fired (cons 'user fired)))
                (mk-block 'loose-blk)
                (panel "W" (mk-block 'panel-blk)))))
            (define root (configuration-tree-ref cfg "scr-fire"))
            (run-on-leave root)
            """)
        #expect(try engine.evaluate("(equal? (reverse fired) '(user loose-blk panel-blk))") == .true)
        // The node's own on-leave is the user's raw hook — no composed
        // wrapper closure.
        #expect(try engine.evaluate("(procedure? (node-on-leave root))") == .true)
    }

    @Test func runOnEnterFiresBlockHooksOnBareGroupsToo() throws {
        let engine = try loadLayout()
        // The bare surface gets the same firing for free: a block child
        // of a plain tree-root/group fires its hooks with no sugar
        // involved — hook wiring derives from structure, not authoring
        // surface.
        try engine.evaluate("""
            (define entered '())
            (define blk
              (list (cons 'type 'window-list)
                    (cons 'on-enter-fn (lambda () (set! entered (cons 'blk entered))))))
            (define broot (tree-root 'bare-fire blk))
            (run-on-enter broot)
            """)
        #expect(try engine.evaluate("(equal? entered '(blk))") == .true)
    }

    @Test func screenAcceptsLifecycleKeywords() throws {
        let engine = try loadLayout()
        try engine.evaluate("""
            (define cfg (configuration (screen 'scr-life 'display-name "Title" 'exit-on-unknown #t
              (panel "P" (key "c" "C" (lambda () 'ok))))))
            """)
        let root = "(configuration-tree-ref cfg \"scr-life\")"
        #expect(try engine.evaluate("(equal? (node-display-name \(root)) \"Title\")") == .true)
        #expect(try engine.evaluate("(node-exit-on-unknown? \(root))") == .true)
    }

    // entry-exit-slot-wiring-k47: 'entry/'exit ride through `screen` onto
    // the node alongside 'on-enter/'on-leave.
    @Test func screenAcceptsEntryExitKeywords() throws {
        let engine = try loadLayout()
        try engine.evaluate("""
            (define cfg (configuration (screen 'scr-entry-exit 'entry (lambda () 'e) 'exit (lambda () 'x)
              (panel "P" (key "c" "C" (lambda () 'ok))))))
            """)
        let root = "(configuration-tree-ref cfg \"scr-entry-exit\")"
        #expect(try engine.evaluate("(procedure? (node-entry \(root)))") == .true)
        #expect(try engine.evaluate("(procedure? (node-exit \(root)))") == .true)
    }

    @Test func screenLeavesPanelBlockHooksOnTheBlockAtomToo() throws {
        let engine = try loadLayout()
        // Same contract for a panel-embedded list: the hook stays on the
        // block atom (fired structurally by run-on-leave), never composed
        // onto the screen group's own on-leave.
        try engine.evaluate("(define cfg (configuration (screen 'scr-hooks (panel \"Windows\" (fake-list-block)))))")
        #expect(try engine.evaluate("(not (node-on-leave (configuration-tree-ref cfg \"scr-hooks\")))") == .true)
    }

    @Test func screenExpandsTopLevelSplices() throws {
        let engine = try loadLayout()
        try engine.evaluate("""
            (define sp2 (walk 'screen-walk-test "Walk"
              (key "h" "Left" (lambda () 'ok))))
            (define cfg (configuration (screen 'scr-splice sp2 (panel "P" (key "c" "C" (lambda () 'ok))))))
            """)
        // The spliced key lands in the loose region and dispatches from the root.
        #expect(try engine.evaluate("(command? (find-child (configuration-tree-ref cfg \"scr-splice\") \"h\"))") == .true)
    }

    // MARK: - open

    @Test func openLowersToNavigableGroupWithStructuredDisplay() throws {
        let engine = try loadLayout()
        try engine.evaluate("""
            (define o (open "s" "Splits"
              (panel "P" (key "x" "X" (lambda () 'ok)))))
            """)
        #expect(try engine.evaluate("(group? o)") == .true)
        #expect(try engine.evaluate("(equal? (node-key o) \"s\")") == .true)
        #expect(try engine.evaluate("(equal? (node-label o) \"Splits\")") == .true)
        #expect(try engine.evaluate("(pair? (node-display-ref o 'panels))") == .true)
    }

    @Test func openDispatchDescendsThroughItsPanels() throws {
        let engine = try loadLayout()
        try engine.evaluate("""
            (define cfg (configuration
              (screen 'scr-open
                (open "s" "Splits"
                  (panel "P" (key "x" "X" (lambda () 'ok)))))))
            """)
        let root = "(configuration-tree-ref cfg \"scr-open\")"
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
        #expect(try engine.evaluate("(= (node-display-ref o 'cols) 2)") == .true)
    }

    @Test func openAcceptsEntryExitKeywords() throws {
        let engine = try loadLayout()
        try engine.evaluate("""
            (define o (open "s" "Splits" 'entry (lambda () 'e) 'exit (lambda () 'x)
              (panel "P" (key "x" "X" (lambda () 'ok)))))
            """)
        #expect(try engine.evaluate("(procedure? (node-entry o))") == .true)
        #expect(try engine.evaluate("(procedure? (node-exit o))") == .true)
    }

    @Test func openCarriesLayoutWhenGiven() throws {
        let engine = try loadLayout()
        try engine.evaluate("""
            (define o (open "s" "Splits" 'layout 'grid
              (panel "P" (key "x" "X" (lambda () 'ok)))))
            """)
        #expect(try engine.evaluate("(eq? (node-display-ref o 'layout) 'grid)") == .true)
    }

    // MARK: - order (manual-panel-order-k24)

    // 'order ('keys | 'declared) rides the display value; stored only when
    // authored so absence means "inherit" (panel-explicit > screen/open
    // default > 'keys — resolved by resolve-display).

    @Test func panelCarriesOrderWhenDeclared() throws {
        let engine = try loadLayout()
        try engine.evaluate("(define p (panel \"X\" 'order 'declared (key \"c\" \"C\" (lambda () 'ok))))")
        #expect(try engine.evaluate("(eq? (cdr (assoc 'order p)) 'declared)") == .true)
    }

    @Test func panelCarriesOrderWhenKeys() throws {
        let engine = try loadLayout()
        try engine.evaluate("(define p (panel \"X\" 'order 'keys (key \"c\" \"C\" (lambda () 'ok))))")
        #expect(try engine.evaluate("(eq? (cdr (assoc 'order p)) 'keys)") == .true)
    }

    @Test func panelAbsentOrderHasNoKey() throws {
        let engine = try loadLayout()
        // No 'order keyword → no 'order entry at all, so the renderer falls
        // through to the screen/open default (and ultimately 'keys).
        try engine.evaluate("(define p (panel \"X\" (key \"c\" \"C\" (lambda () 'ok))))")
        #expect(try engine.evaluate("(assoc 'order p)") == .false)
    }

    @Test func panelRejectsUnknownOrder() throws {
        let engine = try loadLayout()
        #expect(throws: (any Error).self) {
            try engine.evaluate("(panel \"X\" 'order 'random (key \"c\" \"C\" (lambda () 'ok)))")
        }
    }

    @Test func screenCarriesOrderWhenGiven() throws {
        let engine = try loadLayout()
        try engine.evaluate("(define cfg (configuration (screen 'scr-order 'order 'declared (panel \"P\" (key \"c\" \"C\" (lambda () 'ok))))))")
        #expect(try engine.evaluate("(eq? (node-display-ref (configuration-tree-ref cfg \"scr-order\") 'order) 'declared)") == .true)
    }

    @Test func screenAbsentOrderHasNoPayload() throws {
        let engine = try loadLayout()
        try engine.evaluate("(define cfg (configuration (screen 'scr-noorder (panel \"P\" (key \"c\" \"C\" (lambda () 'ok))))))")
        #expect(try engine.evaluate("(node-display-ref (configuration-tree-ref cfg \"scr-noorder\") 'order)") == .false)
    }

    @Test func screenRejectsUnknownOrder() throws {
        let engine = try loadLayout()
        #expect(throws: (any Error).self) {
            try engine.evaluate("(screen 'scr-badorder 'order 'wat (panel \"P\" (key \"c\" \"C\" (lambda () 'ok))))")
        }
    }

    @Test func openCarriesOrderWhenGiven() throws {
        let engine = try loadLayout()
        try engine.evaluate("""
            (define o (open "s" "Splits" 'order 'declared
              (panel "P" (key "x" "X" (lambda () 'ok)))))
            """)
        #expect(try engine.evaluate("(eq? (node-display-ref o 'order) 'declared)") == .true)
    }

    // MARK: - splice

    @Test func spliceProducesTransparentSpliceNode() throws {
        let engine = try loadLayout()
        try engine.evaluate("(define frag (splice (key \"c\" \"Center\" (lambda () 'ok))))")
        // A 'kind 'splice node — expand-splices hoists its children, so
        // nothing downstream ever sees the splice.
        #expect(try engine.evaluate("(eq? (cdr (assoc 'kind frag)) 'splice)") == .true)
    }

    @Test func spliceExpandsIdenticallyToInlineInPanel() throws {
        let engine = try loadLayout()
        // Splices SURVIVE construction now (dsl-purification-k9) — the
        // authored splice node stays in the panel's children so the merge can
        // hoist any carried tree — and expansion happens downstream. Sharing
        // the same action object + key nodes makes the expanded-view equality
        // exact (lambdas compare by identity).
        try engine.evaluate("""
            (define act (lambda () 'ok))
            (define kc (key "c" "Center"   act))
            (define km (key "m" "Maximise" act))
            (define window-ops (splice kc km))
            (define p-spliced (panel "Windows" window-ops))
            (define p-inline  (panel "Windows" kc km))
            """)
        // The splice node itself is preserved in the children …
        #expect(try engine.evaluate("(pair? (filter splice? (node-children p-spliced)))") == .true)
        // … and the expanded view is identical to inline authoring.
        #expect(try engine.evaluate("""
            (equal? (expand-splices (node-children p-spliced))
                    (node-children p-inline))
            """) == .true)
    }

    @Test func spliceExpandsIdenticallyToInlineInScreen() throws {
        let engine = try loadLayout()
        try engine.evaluate("""
            (define act (lambda () 'ok))
            (define pa (panel "A" (key "a" "A" act)))
            (define pb (panel "B" (key "b" "B" act)))
            (define shared (splice pa pb))
            (define cfg (configuration
              (screen 'scr-splice-eq   shared)
              (screen 'scr-inline-eq pa pb)))
            """)
        #expect(try engine.evaluate("""
            (equal? (expand-splices (node-children (configuration-tree-ref cfg "scr-splice-eq")))
                    (node-children (configuration-tree-ref cfg "scr-inline-eq")))
            """) == .true)
    }

    @Test func spliceDefinedOnceSplicedIntoTwoSitesDispatches() throws {
        let engine = try loadLayout()
        // A genuinely shared window-ops set, defined once and spliced into two
        // separate screens (DRY) — the leaf's proof, not a contrived example.
        try engine.evaluate("""
            (define act (lambda () 'ok))
            (define window-ops
              (splice
                (key "c" "Center"   act)
                (key "m" "Maximise" act)))
            (define cfg (configuration
              (screen 'scr-global (panel "Windows" window-ops))
              (screen 'scr-finder (panel "Layout"  window-ops))))
            (define scr-global-root (configuration-tree-ref cfg "scr-global"))
            (define scr-finder-root (configuration-tree-ref cfg "scr-finder"))
            """)
        // The shared keys dispatch transparently from BOTH sites.
        #expect(try engine.evaluate("(command? (find-child scr-global-root \"c\"))") == .true)
        #expect(try engine.evaluate("(command? (find-child scr-global-root \"m\"))") == .true)
        #expect(try engine.evaluate("(command? (find-child scr-finder-root \"c\"))") == .true)
        #expect(try engine.evaluate("(command? (find-child scr-finder-root \"m\"))") == .true)
    }

    @Test func spliceOfPanelsDispatchesAtScreenLevel() throws {
        let engine = try loadLayout()
        // A splice may carry panels (screen-level reuse); they splice in as
        // real panels alongside inline ones.
        try engine.evaluate("""
            (define act (lambda () 'ok))
            (define shared-panels
              (splice
                (panel "A" (key "a" "A" act))
                (panel "B" (key "b" "B" act))))
            (define cfg (configuration
              (screen 'scr-panels shared-panels (panel "C" (key "c" "C" act)))))
            """)
        let root = "(configuration-tree-ref cfg \"scr-panels\")"
        #expect(try engine.evaluate("(command? (find-child \(root) \"a\"))") == .true)
        #expect(try engine.evaluate("(command? (find-child \(root) \"b\"))") == .true)
        #expect(try engine.evaluate("(command? (find-child \(root) \"c\"))") == .true)
        // The spliced panels land in the display value's panel clauses,
        // exactly as inline ones do.
        #expect(try engine.evaluate("(pair? (find-panel \(root) \"A\"))") == .true)
        #expect(try engine.evaluate("(pair? (find-panel \(root) \"B\"))") == .true)
    }

    @Test func spliceComposesWithWalkInPanel() throws {
        let engine = try loadLayout()
        // A splice whose contents include a walk — both are 'kind
        // 'splice, so the nested splice hoists via expand-splices'
        // recursion. Proves splices compose inside a panel body.
        try engine.evaluate("""
            (define act (lambda () 'ok))
            (define sset (walk 'frag-compose-walk "Walk"
                           (key "h" "Left" act)))
            (define frag2 (splice (key "c" "Center" act) sset))
            (define p (panel "Nav" frag2))
            """)
        #expect(try engine.evaluate("(command? (find-child p \"c\"))") == .true)  // from splice
        #expect(try engine.evaluate("(command? (find-child p \"h\"))") == .true)  // from nested walk
        // The entry keeps its 'next cross edge, crossing in as before.
        #expect(try engine.evaluate("(eq? (cdr (assoc 'next (find-child p \"h\"))) 'frag-compose-walk)") == .true)
    }

    @Test func spliceComposesWithWalkInScreen() throws {
        let engine = try loadLayout()
        // Same composition at screen level: a splice + a walk both
        // spliced into the screen body, their loose keys landing in the loose region.
        try engine.evaluate("""
            (define act (lambda () 'ok))
            (define ops (splice (key "c" "Center" act)))
            (define sset (walk 'frag-screen-walk "Walk" (key "h" "Left" act)))
            (define cfg (configuration
              (screen 'scr-compose ops sset (panel "P" (key "p" "P" act)))))
            """)
        let root = "(configuration-tree-ref cfg \"scr-compose\")"
        #expect(try engine.evaluate("(command? (find-child \(root) \"c\"))") == .true)  // splice
        #expect(try engine.evaluate("(command? (find-child \(root) \"h\"))") == .true)  // walk
        #expect(try engine.evaluate("(command? (find-child \(root) \"p\"))") == .true)  // inline panel
    }

    @Test func spliceSplicesInsideOpenBody() throws {
        let engine = try loadLayout()
        // The third container body — open — is splice-transparent too, so a
        // splice dispatches inside a drill-down sub-grid.
        try engine.evaluate("""
            (define act (lambda () 'ok))
            (define ops (splice (key "c" "Center" act)))
            (define o (open "s" "Splits" ops (panel "P" (key "x" "X" act))))
            """)
        #expect(try engine.evaluate("(command? (find-child o \"c\"))") == .true)  // from splice
        #expect(try engine.evaluate("(command? (find-child o \"x\"))") == .true)  // inline panel
    }

    // MARK: - pure value-builders (dsl-purification-k9)

    @Test func walkSpliceCarriesItsModeTree() throws {
        let engine = try loadLayout()
        // The walk's splice carries (mode-id . root-node) under 'tree for the
        // pure merge to hoist (configuration.sld "WALK HOISTING") …
        try engine.evaluate("""
            (define sp (walk 'walk-carried-tree "Walk"
              (key "h" "Left" (lambda () 'ok))))
            (define carried (cdr (assoc 'tree sp)))
            """)
        #expect(try engine.evaluate("(eq? (car carried) 'walk-carried-tree)") == .true)
        #expect(try engine.evaluate("(group? (cdr carried))") == .true)
        // … and the carried root IS the tree the merge hoists into the
        // configuration's tree set — one shared tree object, no copy.
        try engine.evaluate("""
            (define cfg (configuration (tree 'walk-host (tree-root 'walk-host sp))))
            """)
        #expect(try engine.evaluate("(eq? (cdr carried) (configuration-tree-ref cfg \"walk-carried-tree\"))") == .true)
    }

    @Test func screenReturnsTreeContribution() throws {
        let engine = try loadLayout()
        // screen is pure: it returns the (tree scope node) contribution the
        // configuration merge consumes — nothing installs until the handoff.
        try engine.evaluate("""
            (define c (screen 'scr-contrib (panel "P" (key "c" "C" (lambda () 'ok)))))
            """)
        #expect(try engine.evaluate("(eq? (car c) 'tree)") == .true)
        #expect(try engine.evaluate("(eq? (cadr c) 'scr-contrib)") == .true)
        // The contribution's node is exactly what the merged configuration
        // holds under that scope.
        #expect(try engine.evaluate("(eq? (caddr c) (configuration-tree-ref (configuration c) \"scr-contrib\"))") == .true)
    }

    @Test func screenPreservesSpliceNodesInChildren() throws {
        let engine = try loadLayout()
        // The authored splice survives in the dispatch children — expansion
        // moved to lowering/read time — so the merge can hoist its carried
        // tree; dispatch stays transparent through it.
        try engine.evaluate("""
            (define sp (walk 'scr-preserve-walk "Walk" (key "h" "Left" (lambda () 'ok))))
            (define cfg (configuration
              (screen 'scr-preserve sp (panel "P" (key "c" "C" (lambda () 'ok))))))
            """)
        let root = "(configuration-tree-ref cfg \"scr-preserve\")"
        #expect(try engine.evaluate("(pair? (filter splice? (node-children \(root))))") == .true)
        #expect(try engine.evaluate("(command? (find-child \(root) \"h\"))") == .true)
    }

    // MARK: - two-layer display factoring (ADR-0011)
    //
    // Every screen/open carries its COMPLETE Display value under one
    // 'display entry — rows referenced BY KEY, blocks BY ID, never node
    // copies — and node-display / node-with-display extract / replace
    // that single entry wholesale. Since the readers cutover this is the
    // ONLY place display data lives (the scattered legacy keys and the
    // category node kind are gone).

    @Test func nodeDisplayExtractsTheSingleDisplayEntry() throws {
        let engine = try loadLayout()
        try engine.evaluate("""
            (define cfg (configuration
              (screen 'scr-disp 'cols 2 'layout 'grid 'order 'declared
                (key "a" "Loose" (lambda () 'ok))
                (panel "P" (key "b" "B" (lambda () 'ok))))))
            (define d (node-display (configuration-tree-ref cfg "scr-disp")))
            """)
        #expect(try engine.evaluate("(= (cdr (assoc 'cols d)) 2)") == .true)
        #expect(try engine.evaluate("(eq? (cdr (assoc 'layout d)) 'grid)") == .true)
        #expect(try engine.evaluate("(eq? (cdr (assoc 'order d)) 'declared)") == .true)
        // The loose region is key REFS, not node copies.
        #expect(try engine.evaluate("(equal? (cdr (assoc 'loose d)) '((key . \"a\")))") == .true)
        // The panel clause: label / span / rows-as-refs.
        try engine.evaluate("(define p0 (car (cdr (assoc 'panels d))))")
        #expect(try engine.evaluate("(equal? (cdr (assoc 'label p0)) \"P\")") == .true)
        #expect(try engine.evaluate("(eq? (cdr (assoc 'span p0)) 'narrow)") == .true)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'rows p0)) '((key . \"b\")))") == .true)
        // Dispatch structure never leaks into the display value.
        #expect(try engine.evaluate("(assoc 'children d)") == .false)
        #expect(try engine.evaluate("(assoc 'kind d)") == .false)
        // And no scattered display key rides the node itself any more —
        // the 'display entry is the display's only home.
        try engine.evaluate("(define root (configuration-tree-ref cfg \"scr-disp\"))")
        #expect(try engine.evaluate("(assoc 'renderer root)") == .false)
        #expect(try engine.evaluate("(assoc 'cols root)") == .false)
        #expect(try engine.evaluate("(assoc 'loose root)") == .false)
        #expect(try engine.evaluate("(assoc 'order root)") == .false)
    }

    @Test func nodeWithDisplayReplacesDisplayWithoutTouchingDispatch() throws {
        let engine = try loadLayout()
        try engine.evaluate("""
            (define cfg (configuration
              (screen 'scr-redisp 'cols 2
                (panel "P" (key "b" "B" (lambda () 'ok))))))
            (define before (configuration-tree-ref cfg "scr-redisp"))
            (define after (node-with-display before '((cols . 3))))
            """)
        // The substituted display is what node-display now reads, whole.
        #expect(try engine.evaluate("(equal? (node-display after) '((cols . 3)))") == .true)
        // … and the live key set is untouched (ADR-0011's invariant).
        #expect(try engine.evaluate("(eq? (find-child after \"b\") (find-child before \"b\"))") == .true)
    }

    @Test func panelClauseCarriesSpanAndBlockRef() throws {
        let engine = try loadLayout()
        // A paneled live-list block: the panel clause auto-promotes to
        // 'wide and places the block BY REFERENCE (id defaulting to its
        // 'type), after the row refs; the lifted hidden digit range never
        // appears among the refs.
        try engine.evaluate("""
            (define cfg (configuration
              (screen 'scr-blk
                (panel "Windows" (fake-list-block) (key "c" "C" (lambda () 'ok))))))
            (define d (node-display (configuration-tree-ref cfg "scr-blk")))
            (define p0 (car (cdr (assoc 'panels d))))
            """)
        #expect(try engine.evaluate("(eq? (cdr (assoc 'span p0)) 'wide)") == .true)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'rows p0)) '((key . \"c\") (block . window-list)))") == .true)
    }

    @Test func looseDisplayRefsPreserveAuthoredInterleaving() throws {
        let engine = try loadLayout()
        // Loose rows and loose blocks interleave in the display value's
        // refs exactly as authored (rows + blocks, declaration order).
        try engine.evaluate("""
            (define cfg (configuration
              (screen 'scr-inter
                (key "a" "A" (lambda () 'ok))
                (fake-list-block)
                (key "b" "B" (lambda () 'ok)))))
            (define d (node-display (configuration-tree-ref cfg "scr-inter")))
            """)
        #expect(try engine.evaluate("""
            (equal? (cdr (assoc 'loose d))
                    '((key . "a") (block . window-list) (key . "b")))
            """) == .true)
    }

    @Test func nestedOpenCarriesItsOwnDisplayValue() throws {
        let engine = try loadLayout()
        // An open is its own display root: it dual-writes its own
        // 'display entry, disjoint from the enclosing screen's.
        try engine.evaluate("""
            (define cfg (configuration
              (screen 'scr-nest
                (open "s" "Sub" (panel "P" (key "x" "X" (lambda () 'ok)))))))
            (define sub (find-child (configuration-tree-ref cfg "scr-nest") "s"))
            (define d (node-display sub))
            """)
        #expect(try engine.evaluate("(pair? (assoc 'panels d))") == .true)
        #expect(try engine.evaluate("""
            (equal? (cdr (assoc 'rows (car (cdr (assoc 'panels d)))))
                    '((key . "x")))
            """) == .true)
    }

    @Test func duplicateBlockReferenceIdsErrorAtConstruction() throws {
        let engine = try loadLayout()
        // Two same-type blocks in one screen collide on the default
        // reference id ('type) — a construction-time error naming the
        // 'id override …
        #expect(throws: (any Error).self) {
            try engine.evaluate("""
                (screen 'scr-dup (fake-list-block) (fake-list-block))
                """)
        }
        // … and an explicit 'id disambiguates: refs use the override.
        try engine.evaluate("""
            (define cfg (configuration
              (screen 'scr-ids
                (fake-list-block)
                (cons (cons 'id 'second-list) (fake-list-block)))))
            (define d (node-display (configuration-tree-ref cfg "scr-ids")))
            """)
        #expect(try engine.evaluate("""
            (equal? (cdr (assoc 'loose d))
                    '((block . window-list) (block . second-list)))
            """) == .true)
    }

    @Test func screenCarriesEmbedChoiceAsDisplayData() throws {
        let engine = try loadLayout()
        // Embed is representable as data from this leaf on (spec "Staging");
        // rendering in place is embed-rendering-k14's business — until then
        // the marked edge renders as a drill row, so dispatch is unchanged.
        try engine.evaluate("""
            (define cfg (configuration
              (screen 'scr-embed 'embed '("s")
                (open "s" "Splits" (panel "P" (key "x" "X" (lambda () 'ok)))))))
            (define scr-embed-root (configuration-tree-ref cfg "scr-embed"))
            (define d (node-display scr-embed-root))
            """)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'embed d)) '(\"s\"))") == .true)
        #expect(try engine.evaluate("(group? (find-child scr-embed-root \"s\"))") == .true)
    }
}
