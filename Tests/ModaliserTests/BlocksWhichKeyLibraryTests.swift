import Foundation
import Testing
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

    @Test func whichKeyPayloadPartitionsCategoriesAndMiscSorted() throws {
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
                              (key "a" "Apple" (lambda () #t))
                              (category "Move"
                                (key "h" "Left" (lambda () #t))
                                (key "j" "Down" (lambda () #t)))
                              (key "z" "Zebra" (lambda () #t))))))
          (define html (render-overlay-html grp '("Root") '()))
        """)
        let html = try engine.evaluate("html").asString()
        guard let s = html.range(of: "data-payload='") else { Issue.record("no payload"); return }
        let after = html[s.upperBound...]
        guard let e = after.firstIndex(of: "'") else { Issue.record("unterminated"); return }
        let payload = String(after[..<e])
        // Children are sorted by key. Category "Move" has no key — empty
        // strings sort before any letter, so the order is: Move → a → z.
        let aIdx = payload.range(of: "\"label\":\"Apple\"")!.lowerBound
        let moveIdx = payload.range(of: "\"label\":\"Move\"")!.lowerBound
        let zIdx = payload.range(of: "\"label\":\"Zebra\"")!.lowerBound
        #expect(moveIdx < aIdx)
        #expect(aIdx < zIdx)
        // Category contains its rows (h, j) — also sorted within the category.
        #expect(payload.contains("\"key\":\"h\""))
        #expect(payload.contains("\"key\":\"j\""))
        // kind tags exist
        #expect(payload.contains("\"kind\":\"misc\""))
        #expect(payload.contains("\"kind\":\"category\""))
    }
}
