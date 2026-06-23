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
        // onto the screen group's on-leave, exactly as define-tree does.
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
}
