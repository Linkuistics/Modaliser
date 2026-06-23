import Foundation
import Testing
@testable import Modaliser

@Suite("(modaliser window-actions) library")
struct ModaliserWindowActionsLibraryTests {

    // A live (chips) window list-block carries a 'cursor-targets-fn accessor so
    // the selection cursor (list-cursor-k6) moves over the same label→window
    // targets the digit dispatch uses, alongside its hidden digit range.
    @Test func liveListBlockCarriesCursorTargets() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (prefix (modaliser window-actions) window:))")
        try engine.evaluate("(define b (window:list-block 'chips? #t))")
        #expect(try engine.evaluate("(procedure? (cdr (assoc 'cursor-targets-fn b)))") == .true)
        // The digit range still rides under 'block-children, unchanged.
        #expect(try engine.evaluate("(pair? (assoc 'block-children b))") == .true)
    }

    // A no-chips window list-block has no on-render-fn, so it never refreshes its
    // targets snapshot — the cursor must NOT attach to it (it would show nav
    // chrome over stale/empty data). The cursor follows live data only.
    @Test func staticListBlockOmitsCursorTargets() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (prefix (modaliser window-actions) window:))")
        try engine.evaluate("(define b (window:list-block))")
        #expect(try engine.evaluate("(assoc 'cursor-targets-fn b)") == .false)
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

    @Test func layoutBlockMacroAcceptsBareMatrixForm() throws {
        // layout-block is a macro that quasiquotes each form, so the
        // matrix can be written directly without explicit (divisions …).
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser window-actions))")
        try engine.evaluate("""
          (define b (layout-block (("d" "f" "g"))))
          (define bc (cdr (assoc 'block-children b)))
        """)
        // Three keys for the three thirds.
        #expect(try engine.evaluate("(= (length bc) 3)") == .true)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'key (car bc))) \"d\")") == .true)
    }

    @Test func layoutBlockMacroAcceptsCenterForm() throws {
        // (center K) dispatches to (center-panel K) inside the macro.
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser window-actions))")
        try engine.evaluate("""
          (define b (layout-block (center "c")))
          (define panels (cdr (assoc 'panels b)))
          (define p1 (car panels))
        """)
        #expect(try engine.evaluate("(eq? (cdr (assoc 'type p1)) 'center)") == .true)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'key p1)) \"c\")") == .true)
    }

    @Test func layoutBlockMacroMixesMatrixAndCenter() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser window-actions))")
        try engine.evaluate("""
          (define b (layout-block
                      (("d" "f" "g"))
                      (center "c")))
          (define panels (cdr (assoc 'panels b)))
        """)
        // Two panels: a 1x3 grid + a center
        #expect(try engine.evaluate("(= (length panels) 2)") == .true)
        #expect(try engine.evaluate("(eq? (cdr (assoc 'type (car panels))) 'grid)") == .true)
        #expect(try engine.evaluate("(eq? (cdr (assoc 'type (cadr panels))) 'center)") == .true)
    }

    @Test func listBlockExposesWindowRangeAsBlockChild() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine) (modaliser window-actions))")
        try engine.evaluate("""
          (define b (list-block 'chips? #t))
          (define bc (cdr (assoc 'block-children b)))
        """)
        #expect(try engine.evaluate("(= (length bc) 1)") == .true)
        // The single block-child is the 1.. window-range, marked hidden.
        try engine.evaluate("(define rng (car bc))")
        #expect(try engine.evaluate("(range-command? rng)") == .true)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'key rng)) \"1..\")") == .true)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'hidden rng)) #t)") == .true)
    }

}
