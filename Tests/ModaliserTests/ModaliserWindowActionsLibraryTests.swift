import Foundation
import Testing
@testable import Modaliser

@Suite("(modaliser window-actions) library")
struct ModaliserWindowActionsLibraryTests {

    @Test func overlayReturnsGroupNode() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine) (modaliser window-actions))")
        try engine.evaluate("""
          (define g (overlay 'key "w" 'label "Windows"
                      (default-layout-block)
                      (list-block 'show-chips #t)))
        """)
        #expect(try engine.evaluate("(group? g)") == .true)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'key g)) \"w\")") == .true)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'label g)) \"Windows\")") == .true)
        #expect(try engine.evaluate("(eq? (node-renderer g) 'blocks)") == .true)
    }

    @Test func overlayDefaultsKeyAndLabel() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser window-actions))")
        try engine.evaluate("(define g (overlay (default-layout-block)))")
        #expect(try engine.evaluate("(equal? (cdr (assoc 'key g)) \"w\")") == .true)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'label g)) \"Windows\")") == .true)
    }

    @Test func divisionsBuilderGeneratesKeysForMatrix() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (prefix (modaliser window-actions) window:))")
        try engine.evaluate("(define result (window:divisions '((\"d\" \"f\" \"g\"))))")
        try engine.evaluate("(define spec (car result))")
        try engine.evaluate("(define keys (cadr result))")
        #expect(try engine.evaluate("(eq? (cdr (assoc 'type spec)) 'grid)") == .true)
        #expect(try engine.evaluate("(= (length keys) 3)") == .true)
        try engine.evaluate("(define k1 (car keys))")
        #expect(try engine.evaluate("(equal? (cdr (assoc 'key k1)) \"d\")") == .true)
    }

    @Test func defaultLayoutBlockHasSixPanels() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser window-actions))")
        try engine.evaluate("(define b (default-layout-block))")
        #expect(try engine.evaluate("(eq? (cdr (assoc 'type b)) 'window-diagram)") == .true)
        try engine.evaluate("(define panels (cdr (assoc 'panels b)))")
        #expect(try engine.evaluate("(= (length panels) 6)") == .true)
        try engine.evaluate("(define p1 (car panels))")
        #expect(try engine.evaluate("(eq? (cdr (assoc 'type p1)) 'grid)") == .true)
        #expect(try engine.evaluate("(= (cdr (assoc 'cols p1)) 3)") == .true)
    }

    @Test func layoutBlockExposesPanelKeysAsBlockChildren() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser window-actions))")
        try engine.evaluate("""
          (define b (layout-block (divisions '(("d" "f" "g")))))
          (define bc (cdr (assoc 'block-children b)))
        """)
        // Three keys for the three thirds.
        #expect(try engine.evaluate("(= (length bc) 3)") == .true)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'key (car bc))) \"d\")") == .true)
    }

    @Test func listBlockExposesWindowRangeAsBlockChild() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine) (modaliser window-actions))")
        try engine.evaluate("""
          (define b (list-block 'show-chips #t))
          (define bc (cdr (assoc 'block-children b)))
        """)
        #expect(try engine.evaluate("(= (length bc) 1)") == .true)
        // The single block-child is the 1.. window-range, marked hidden.
        try engine.evaluate("(define rng (car bc))")
        #expect(try engine.evaluate("(range-command? rng)") == .true)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'key rng)) \"1..\")") == .true)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'hidden rng)) #t)") == .true)
    }

    @Test func overlayLiftsBlockChildrenToGroupChildren() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine) (modaliser window-actions))")
        try engine.evaluate("""
          (define g (overlay 'key "w" 'label "Windows"
                      (layout-block (divisions '(("d" "f" "g"))))
                      (list-block 'show-chips #t)))
          (define ch (cdr (assoc 'children g)))
        """)
        // 3 panel keys + 1 window-range = 4 children
        #expect(try engine.evaluate("(= (length ch) 4)") == .true)
        // find-child sees "d" through the lifted block-children
        #expect(try engine.evaluate("(and (find-child g \"d\") #t)") == .true)
        // and resolves a digit via the window-range
        #expect(try engine.evaluate("(and (find-child g \"5\") #t)") == .true)
    }

    @Test func overlayAppliesOnLeaveHintsHide() throws {
        // Replaces the now-removed on-enter (chip-painting moved to
        // the window-list block's on-render-fn). on-leave clears chips
        // when the overlay closes.
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine) (modaliser window-actions))")
        try engine.evaluate("""
          (define g (overlay 'key "w" 'label "Windows"
                      (default-layout-block)
                      (list-block 'show-chips #t)))
        """)
        #expect(try engine.evaluate("(procedure? (node-on-leave g))") == .true)
    }

    @Test func overlayEndToEndRendersFullPayload() throws {
        // End-to-end render-path coverage. Exercises block-list-payload-
        // json -> each block's on-render-fn (including the window-list
        // chip-painting effect) -> serialization. Guards against the
        // (now-fixed) set-cdr! issue and any future regression in the
        // serialization path.
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("Scheme directory not found"); throw SchemeTestError.noSchemeDir
        }
        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser state-machine))")
        try engine.evaluate("(import (modaliser event-dispatch) (modaliser dsl) (modaliser dom))")
        try engine.evaluateFile(schemePath + "/ui/css.scm")
        try engine.evaluateFile(schemePath + "/ui/overlay.scm")
        try engine.evaluate("(import (modaliser blocks which-key) (modaliser window-actions))")
        try engine.evaluate("""
          (define g (overlay 'key "w" 'label "Windows"
                      (default-layout-block)
                      (make-which-key-block
                        (key "r" "Restore" (lambda () #t)))
                      (list-block 'show-chips #t)))
          (define payload (block-list-payload-json g))
        """)
        let p = try engine.evaluate("payload").asString()
        #expect(p.contains("\"type\":\"blocks\""))
        #expect(p.contains("\"type\":\"window-diagram\""))
        #expect(p.contains("\"type\":\"which-key\""))
        #expect(p.contains("\"type\":\"window-list\""))
        // which-key carries the user-declared "r" (Restore)
        #expect(p.contains("\"label\":\"Restore\""))
        // Panel keys are owned by window-diagram, NOT which-key
        guard let wkStart = p.range(of: "\"type\":\"which-key\"") else {
            Issue.record("which-key block missing"); return
        }
        let afterWk = p[wkStart.lowerBound...]
        let wkSlice = String(afterWk.prefix(while: { $0 != "]" }))
        #expect(!wkSlice.contains("\"key\":\"d\""),
                "panel key 'd' leaked into which-key (block-children leak?)")
        // block-children should NOT appear as a JSON field
        #expect(!p.contains("block-children"))
    }
}
