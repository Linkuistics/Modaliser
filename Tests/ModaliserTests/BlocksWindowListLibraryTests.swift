import Foundation
import Testing
@testable import Modaliser

@Suite("(modaliser blocks window-list) library")
struct BlocksWindowListLibraryTests {

    @Test func makeWindowListBlockDefaultShowChipsIsFalse() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser blocks window-list))")
        try engine.evaluate("(define b (make-window-list-block))")
        #expect(try engine.evaluate("(eq? (cdr (assoc 'type b)) 'window-list)") == .true)
        // No on-render-fn when show-chips defaulted to #f
        #expect(try engine.evaluate("(not (assoc 'on-render-fn b))") == .true)
    }

    @Test func makeWindowListBlockWithShowChipsAttachesOnRenderFn() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser blocks window-list))")
        try engine.evaluate("(define b (make-window-list-block 'show-chips #t))")
        #expect(try engine.evaluate("(procedure? (cdr (assoc 'on-render-fn b)))") == .true)
    }

    @Test func windowListPayloadCarriesEmptyWindowsByDefault() throws {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else { Issue.record("scheme path"); return }
        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser state-machine))")
        try engine.evaluate("(import (modaliser event-dispatch) (modaliser dsl) (modaliser dom))")
        try engine.evaluateFile(schemePath + "/ui/css.scm")
        try engine.evaluateFile(schemePath + "/ui/overlay.scm")
        try engine.evaluate("(import (modaliser blocks window-list))")
        try engine.evaluate("""
          (define grp (group "w" "Win" 'renderer 'blocks
                        'blocks (list (make-window-list-block))))
          (define html (render-overlay-html grp '("Root") '()))
        """)
        let html = try engine.evaluate("html").asString()
        #expect(html.contains("\"type\":\"window-list\""))
        #expect(html.contains("\"windows\":[]"))
    }

    @Test func windowListRegistersJsAndCss() throws {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else { Issue.record("scheme path"); return }
        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser state-machine))")
        try engine.evaluate("(import (modaliser event-dispatch) (modaliser dsl) (modaliser dom))")
        try engine.evaluateFile(schemePath + "/ui/css.scm")
        try engine.evaluateFile(schemePath + "/ui/overlay.scm")
        try engine.evaluate("(import (modaliser blocks window-list))")
        try engine.evaluate("""
          (define grp (group "w" "Win" 'renderer 'blocks
                        'blocks (list (make-window-list-block))))
          (define html (render-overlay-html grp '("Root") '()))
        """)
        let html = try engine.evaluate("html").asString()
        #expect(html.contains("overlayBlockRenderers['window-list']"))
        #expect(html.contains(".block-window-list"))
    }
}
