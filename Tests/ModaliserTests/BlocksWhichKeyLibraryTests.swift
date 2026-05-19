import Foundation
import Testing
import LispKit
@testable import Modaliser
@testable import Modaliser

@Suite("(modaliser blocks which-key) + category DSL")
struct BlocksWhichKeyLibraryTests {

    @Test func categoryConstructorReturnsCategoryNode() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl))")
        try engine.evaluate("""
          (define c (category "Move"
                      (key "h" "Left"  (lambda () #t))
                      (key "j" "Down"  (lambda () #t))))
        """)
        #expect(try engine.evaluate("(eq? (cdr (assoc 'kind c)) 'category)") == .true)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'label c)) \"Move\")") == .true)
        #expect(try engine.evaluate("(= (length (cdr (assoc 'children c))) 2)") == .true)
    }

    @Test func findChildResolvesThroughCategoryTransparently() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine))")
        try engine.evaluate("""
          (define grp
            (group "w" "Win"
              (category "Move"
                (key "h" "Left" (lambda () 'left))
                (key "j" "Down" (lambda () 'down)))
              (key "q" "Quit" (lambda () 'quit))))
          ;; "h" lives under a category; find-child must still resolve it.
          (define h-node (find-child grp "h"))
          (define q-node (find-child grp "q"))
        """)
        #expect(try engine.evaluate("(and h-node #t)") == .true)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'key h-node)) \"h\")") == .true)
        #expect(try engine.evaluate("(and q-node #t)") == .true)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'key q-node)) \"q\")") == .true)
    }

    @Test func makeWhichKeyBlockEmptyHasNoChildren() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser blocks which-key))")
        try engine.evaluate("(define b (which-key-block))")
        #expect(try engine.evaluate("(eq? (cdr (assoc 'type b)) 'which-key)") == .true)
        #expect(try engine.evaluate("(null? (cdr (assoc 'block-children b)))") == .true)
    }

    @Test func makeWhichKeyBlockCarriesInlineChildren() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser blocks which-key))")
        try engine.evaluate("""
          (define b (which-key-block
                      (key "a" "Apple" (lambda () #t))
                      (key "z" "Zebra" (lambda () #t))))
          (define bc (cdr (assoc 'block-children b)))
        """)
        #expect(try engine.evaluate("(= (length bc) 2)") == .true)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'key (car bc))) \"a\")") == .true)
    }

    @Test func explicitWhichKeyBlockPreservesAuthorialOrder() throws {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("scheme path"); throw SchemeTestError.noSchemeDir
        }
        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser state-machine))")
        try engine.evaluate("(import (modaliser event-dispatch) (modaliser dsl) (modaliser dom))")
        try engine.evaluateFile(schemePath + "/ui/css.scm")
        try engine.evaluateFile(schemePath + "/ui/overlay.scm")
        try engine.evaluate("(import (modaliser blocks which-key))")
        // Explicit (which-key-block …) wrapping — author mixed miscs and
        // a category in source order. We don't re-shuffle inside an
        // explicit block, so payload segments follow declaration order:
        // misc[a] → category[Move] → misc[z]. (Within each, sort applies.)
        try engine.evaluate("""
          (define grp
            (group "w" "Win"
              'renderer 'blocks
              'blocks (list (which-key-block
                              (key "a" "Apple" (lambda () #t))
                              (category "Move"
                                (key "j" "Down" (lambda () #t))
                                (key "h" "Left" (lambda () #t)))
                              (key "z" "Zebra" (lambda () #t))))))
          (define html (render-overlay-html grp '("Root") '()))
        """)
        let html = try engine.evaluate("html").asString()
        guard let s = html.range(of: "data-payload='") else { Issue.record("no payload"); return }
        let after = html[s.upperBound...]
        guard let e = after.firstIndex(of: "'") else { Issue.record("unterminated"); return }
        let payload = String(after[..<e])
        let aIdx    = payload.range(of: "\"label\":\"Apple\"")!.lowerBound
        let moveIdx = payload.range(of: "\"label\":\"Move\"")!.lowerBound
        let zIdx    = payload.range(of: "\"label\":\"Zebra\"")!.lowerBound
        #expect(aIdx < moveIdx)
        #expect(moveIdx < zIdx)
        // Two misc segments (a and z) flank the category.
        let miscMatches = payload.components(separatedBy: "\"kind\":\"misc\"").count - 1
        #expect(miscMatches == 2)
        // Category rows sorted (h before j).
        let hIdx = payload.range(of: "\"key\":\"h\"")!.lowerBound
        let jIdx = payload.range(of: "\"key\":\"j\"")!.lowerBound
        #expect(hIdx < jIdx)
    }

    @Test func autoPackSplitsMixedRunIntoTwoWhichKeyBlocks() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine))")
        // Auto-pack at top level: interleaved miscs and categories should
        // collect into TWO which-key blocks — uncategorised first, then
        // categorised. Categories preserve declaration order across the
        // split; miscs cluster regardless of where they appear.
        try engine.evaluate("""
          (define-tree 'global
            (key "a" "Apple"  (lambda () #t))
            (category "X" (key "x" "X1" (lambda () #t)))
            (key "z" "Zebra"  (lambda () #t))
            (category "Y" (key "y" "Y1" (lambda () #t))))
        """)
        let root = "(lookup-tree \"global\")"
        let blocks = "(cdr (assoc 'blocks \(root)))"
        // Two blocks, both which-key.
        #expect(try engine.evaluate("(length \(blocks))").asInt64() == 2)
        let kindSym = Expr.symbol(engine.context.symbols.intern("which-key"))
        #expect(try engine.evaluate("(cdr (assoc 'type (car \(blocks))))") == kindSym)
        #expect(try engine.evaluate("(cdr (assoc 'type (cadr \(blocks))))") == kindSym)
        // First (misc) block contains the two loose keys.
        let firstChildren = "(cdr (assoc 'block-children (car \(blocks))))"
        #expect(try engine.evaluate("(length \(firstChildren))").asInt64() == 2)
        #expect(try engine.evaluate("(node-key (car \(firstChildren)))").asString() == "a")
        // Second (category) block contains the two categories.
        let secondChildren = "(cdr (assoc 'block-children (cadr \(blocks))))"
        #expect(try engine.evaluate("(length \(secondChildren))").asInt64() == 2)
        #expect(try engine.evaluate("(node-label (car \(secondChildren)))").asString() == "X")
        #expect(try engine.evaluate("(node-label (cadr \(secondChildren)))").asString() == "Y")
    }

    @Test func autoPackHomogeneousRunsProduceSingleBlock() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine))")
        try engine.evaluate("""
          (define-tree 'global
            (key "a" "Apple"  (lambda () #t))
            (key "b" "Banana" (lambda () #t)))
        """)
        // All-misc → one block.
        let root = "(lookup-tree \"global\")"
        #expect(try engine.evaluate("(length (cdr (assoc 'blocks \(root))))").asInt64() == 1)

        try engine.evaluate("""
          (define-tree 'safari
            (category "Tabs" (key "n" "New" (lambda () #t)))
            (category "Win"  (key "w" "Close" (lambda () #t))))
        """)
        // All-category → also one block.
        let safari = "(lookup-tree \"safari\")"
        #expect(try engine.evaluate("(length (cdr (assoc 'blocks \(safari))))").asInt64() == 1)
    }

    @Test func whichKeyConsecutiveMiscsCoalesceIntoOneSegment() throws {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("scheme path"); throw SchemeTestError.noSchemeDir
        }
        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser state-machine))")
        try engine.evaluate("(import (modaliser event-dispatch) (modaliser dsl) (modaliser dom))")
        try engine.evaluateFile(schemePath + "/ui/css.scm")
        try engine.evaluateFile(schemePath + "/ui/overlay.scm")
        try engine.evaluate("(import (modaliser blocks which-key))")
        try engine.evaluate("""
          (define grp
            (group "w" "Win"
              'renderer 'blocks
              'blocks (list (which-key-block
                              (key "z" "Zebra" (lambda () #t))
                              (key "a" "Apple" (lambda () #t))
                              (key "m" "Mango" (lambda () #t))))))
          (define html (render-overlay-html grp '("Root") '()))
        """)
        let html = try engine.evaluate("html").asString()
        guard let s = html.range(of: "data-payload='") else { Issue.record("no payload"); return }
        let after = html[s.upperBound...]
        guard let e = after.firstIndex(of: "'") else { Issue.record("unterminated"); return }
        let payload = String(after[..<e])
        // Three misc entries in a row → exactly one "misc" segment.
        let miscMatches = payload.components(separatedBy: "\"kind\":\"misc\"").count - 1
        #expect(miscMatches == 1)
        // Internal sort: a, m, z.
        let aIdx = payload.range(of: "\"label\":\"Apple\"")!.lowerBound
        let mIdx = payload.range(of: "\"label\":\"Mango\"")!.lowerBound
        let zIdx = payload.range(of: "\"label\":\"Zebra\"")!.lowerBound
        #expect(aIdx < mIdx)
        #expect(mIdx < zIdx)
    }
}
