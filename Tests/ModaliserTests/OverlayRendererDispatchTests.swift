import Foundation
import Testing
import LispKit
@testable import Modaliser

private func joinPath(_ base: String, _ component: String) -> String {
    base.hasSuffix("/") ? base + component : base + "/" + component
}

@Suite("Overlay renderer dispatch (display-shape derived)")
struct OverlayRendererDispatchTests {

    private func loadOverlay() throws -> SchemeEngine {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("Scheme directory not found"); throw SchemeTestError.noSchemeDir
        }
        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser fsm))")
        try engine.evaluate("(import (modaliser event-dispatch) (modaliser dsl) (modaliser dom))")
        for file in ["ui/css.scm", "ui/overlay.scm"] {
            try engine.evaluateFile(joinPath(schemePath, file))
        }
        return engine
    }

    @Test func groupWithoutDisplayStillRendersAsListEntries() throws {
        let engine = try loadOverlay()
        try engine.evaluate("""
          (define grp (group "w" "Win" (key "a" "Apple" (lambda () #t))))
          (define html (render-overlay-html grp '("Root") '()))
        """)
        let html = try engine.evaluate("html").asString()
        #expect(html.contains("overlay-entry"))    // default list renderer markup
    }

    @Test func structuredDisplaySelectsThePanelGridPath() throws {
        let engine = try loadOverlay()
        // The render path is DERIVED from the display value's shape
        // (ADR-0011 — the former 'renderer 'panel-grid marker is gone):
        // a node whose display carries panels renders through the
        // panel-grid custom body; a display holding only row-order data
        // keeps the list renderer.
        try engine.evaluate("""
          (define o (open "s" "Sub" (panel "P" (key "a" "Apple" (lambda () #t)))))
          (define grid-html (render-overlay-html o '("Root") '()))
          (define ordered (group "w" "Win" 'order 'declared
                            (key "a" "Apple" (lambda () #t))))
          (define list-html (render-overlay-html ordered '("Root") '()))
        """)
        // The custom-body DIV (not the inlined overlay.js source, which
        // also mentions data-renderer) is the discriminator.
        let bodyDiv = "<div class=\"overlay-custom-body\" data-renderer=\"panel-grid\""
        let gridHtml = try engine.evaluate("grid-html").asString()
        let listHtml = try engine.evaluate("list-html").asString()
        #expect(gridHtml.contains(bodyDiv))
        #expect(!listHtml.contains(bodyDiv))
        #expect(listHtml.contains("overlay-entry"))
    }

    @Test func updateOverlayJsExposesRendererRegistry() throws {
        let engine = try loadOverlay()
        // Read the bundled overlay.js source and check the dispatch hook is present.
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("scheme path"); throw SchemeTestError.noSchemeDir
        }
        let js = try String(contentsOfFile: joinPath(schemePath, "ui/overlay.js"), encoding: .utf8)
        #expect(js.contains("window.overlayRenderers"))
        #expect(js.contains("overlayRenderers[payload.type]"))
    }
}
