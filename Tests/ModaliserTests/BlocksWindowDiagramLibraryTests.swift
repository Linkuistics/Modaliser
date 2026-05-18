import Foundation
import Testing
@testable import Modaliser

@Suite("(modaliser blocks window-diagram) library")
struct BlocksWindowDiagramLibraryTests {

    @Test func makeWindowDiagramBlockReturnsSpec() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser blocks window-diagram))")
        try engine.evaluate("""
          (define spec
            (list (list (cons 'type 'grid) (cons 'cols 1) (cons 'rows 1)
                        (cons 'cells (list (list (cons 'key "d") (cons 'col 1) (cons 'row 1)
                                                 (cons 'colSpan 1) (cons 'rowSpan 1)))))))
          (define b (make-window-diagram-block spec))
        """)
        #expect(try engine.evaluate("(eq? (cdr (assoc 'type b)) 'window-diagram)") == .true)
        // 'panels carries the original list
        #expect(try engine.evaluate("(equal? (cdr (assoc 'panels b)) spec)") == .true)
        // 'consumed-keys lists the keys painted on the panel(s)
        #expect(try engine.evaluate("(member \"d\" (cdr (assoc 'consumed-keys b)))") != .false)
    }

    @Test func consumedKeysCoversGridCenterAndFill() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser blocks window-diagram))")
        try engine.evaluate("""
          (define grid (list (cons 'type 'grid) (cons 'cols 1) (cons 'rows 1)
                             (cons 'cells (list (list (cons 'key "d") (cons 'col 1) (cons 'row 1)
                                                      (cons 'colSpan 1) (cons 'rowSpan 1))))))
          (define cen  (list (cons 'type 'center) (cons 'key "c")))
          (define fil  (list (cons 'type 'fill)   (cons 'key "m")))
          (define b (make-window-diagram-block (list grid cen fil)))
          (define ck (cdr (assoc 'consumed-keys b)))
        """)
        #expect(try engine.evaluate("(member \"d\" ck)") != .false)
        #expect(try engine.evaluate("(member \"c\" ck)") != .false)
        #expect(try engine.evaluate("(member \"m\" ck)") != .false)
    }

    @Test func blockRendersViaBlockListInOverlay() throws {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("Scheme directory not found"); return
        }
        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser state-machine))")
        try engine.evaluate("(import (modaliser event-dispatch) (modaliser dsl) (modaliser dom))")
        try engine.evaluateFile(schemePath + "/ui/css.scm")
        try engine.evaluateFile(schemePath + "/ui/overlay.scm")
        try engine.evaluate("(import (modaliser blocks window-diagram))")
        try engine.evaluate("""
          (define panel (list (cons 'type 'grid) (cons 'cols 1) (cons 'rows 1)
                              (cons 'cells (list (list (cons 'key "d") (cons 'col 1) (cons 'row 1)
                                                       (cons 'colSpan 1) (cons 'rowSpan 1))))))
          (define b (make-window-diagram-block (list panel)))
          (define grp (group "w" "Win" 'renderer 'blocks 'blocks (list b)))
          (define html (render-overlay-html grp '("Root") '()))
        """)
        let html = try engine.evaluate("html").asString()
        // Block JS + CSS registered → strings present in rendered HTML
        #expect(html.contains("window.overlayBlockRenderers"))
        #expect(html.contains(".block-window-diagram"))
        // Block payload type is window-diagram
        #expect(html.contains("\"type\":\"window-diagram\""))
        // Panel cell key flows through
        #expect(html.contains("\"key\":\"d\""))
    }
}
