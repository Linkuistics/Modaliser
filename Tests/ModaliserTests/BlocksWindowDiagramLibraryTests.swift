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
        // 'panels carries the original list verbatim
        #expect(try engine.evaluate("(equal? (cdr (assoc 'panels b)) spec)") == .true)
    }

    @Test func blockRendersEmbeddedInPanel() throws {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("Scheme directory not found"); throw SchemeTestError.noSchemeDir
        }
        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser state-machine))")
        try engine.evaluate("(import (modaliser event-dispatch) (modaliser dsl) (modaliser dom))")
        try engine.evaluateFile(schemePath + "/ui/css.scm")
        try engine.evaluateFile(schemePath + "/ui/overlay.scm")
        try engine.evaluate("(import (modaliser blocks window-diagram))")
        // Embed the window-diagram block in a panel (the live path now that the
        // whole-overlay block-list renderer is gone). `dpanel` avoids shadowing
        // the `panel` DSL constructor.
        try engine.evaluate("""
          (define dpanel (list (cons 'type 'grid) (cons 'cols 1) (cons 'rows 1)
                               (cons 'cells (list (list (cons 'key "d") (cons 'col 1) (cons 'row 1)
                                                        (cons 'colSpan 1) (cons 'rowSpan 1))))))
          (define b (make-window-diagram-block (list dpanel)))
          (screen 'wd (panel "Win" b))
          (define html (render-overlay-html (lookup-tree "wd") '("Root") '()))
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
