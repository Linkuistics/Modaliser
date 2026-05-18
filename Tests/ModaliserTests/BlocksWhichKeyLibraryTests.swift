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

    @Test func makeWhichKeyBlockReturnsTypeSpec() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser blocks which-key))")
        try engine.evaluate("(define b (make-which-key-block))")
        #expect(try engine.evaluate("(eq? (cdr (assoc 'type b)) 'which-key)") == .true)
    }

    @Test func whichKeyPayloadPartitionsCategoriesAndMiscInSourceOrder() throws {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("scheme path"); return
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
              'blocks (list (make-which-key-block))
              (key "a" "Apple" (lambda () #t))
              (category "Move"
                (key "h" "Left" (lambda () #t))
                (key "j" "Down" (lambda () #t)))
              (key "z" "Zebra" (lambda () #t))))
          (define html (render-overlay-html grp '("Root") '()))
        """)
        let html = try engine.evaluate("html").asString()
        // Pull out data-payload
        guard let s = html.range(of: "data-payload='") else { Issue.record("no payload"); return }
        let after = html[s.upperBound...]
        guard let e = after.firstIndex(of: "'") else { Issue.record("unterminated"); return }
        let payload = String(after[..<e])
        // Verify source order: a → Move → z
        let aIdx = payload.range(of: "\"label\":\"Apple\"")!.lowerBound
        let moveIdx = payload.range(of: "\"label\":\"Move\"")!.lowerBound
        let zIdx = payload.range(of: "\"label\":\"Zebra\"")!.lowerBound
        #expect(aIdx < moveIdx)
        #expect(moveIdx < zIdx)
        // Category contains its rows (h, j)
        #expect(payload.contains("\"key\":\"h\""))
        #expect(payload.contains("\"key\":\"j\""))
        // kind tags exist
        #expect(payload.contains("\"kind\":\"misc\""))
        #expect(payload.contains("\"kind\":\"category\""))
    }

    @Test func whichKeySkipsConsumedKeys() throws {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("scheme path"); return
        }
        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser state-machine))")
        try engine.evaluate("(import (modaliser event-dispatch) (modaliser dsl) (modaliser dom))")
        try engine.evaluateFile(schemePath + "/ui/css.scm")
        try engine.evaluateFile(schemePath + "/ui/overlay.scm")
        try engine.evaluate("(import (modaliser blocks which-key) (modaliser blocks window-diagram))")
        try engine.evaluate("""
          (define panel (list (cons 'type 'grid) (cons 'cols 1) (cons 'rows 1)
                              (cons 'cells (list (list (cons 'key "d") (cons 'col 1) (cons 'row 1)
                                                       (cons 'colSpan 1) (cons 'rowSpan 1))))))
          (define grp (group "w" "Win"
                        'renderer 'blocks
                        'blocks (list (make-window-diagram-block (list panel))
                                      (make-which-key-block))
                        (key "d" "First Third" (lambda () #t))
                        (key "r" "Restore" (lambda () #t))))
          (define html (render-overlay-html grp '("Root") '()))
        """)
        let html = try engine.evaluate("html").asString()
        // Extract the which-key segments substring
        guard let wkRange = html.range(of: "\"type\":\"which-key\"") else {
            Issue.record("no which-key payload"); return
        }
        let tail = html[wkRange.lowerBound...]
        // "r" must appear in which-key segments (it's a misc row).
        #expect(tail.contains("\"label\":\"Restore\""))
        // "d" must NOT appear in which-key segments — it's painted on the panel.
        // Look only at the which-key portion. Find the closing of "blocks":[…]
        // by trimming at the next "}]}" sequence.
        let wkSlice = String(tail.prefix(while: { $0 != "]" }))
        #expect(!wkSlice.contains("\"key\":\"d\""))
    }
}
