import Foundation
import Testing
import LispKit
@testable import Modaliser

private func joinPath(_ base: String, _ component: String) -> String {
    base.hasSuffix("/") ? base + component : base + "/" + component
}

@Suite("Diagram panel rendering")
struct DiagramPanelRenderTests {

    private func loadOverlayAndDiagram() throws -> SchemeEngine {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("Scheme directory not found"); throw SchemeTestError.noSchemeDir
        }
        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser state-machine))")
        try engine.evaluate("(import (modaliser event-dispatch) (modaliser dsl) (modaliser dom))")
        for file in ["ui/css.scm", "ui/overlay.scm"] {
            try engine.evaluateFile(joinPath(schemePath, file))
        }
        try engine.evaluate("(import (modaliser diagram-panel))")
        return engine
    }

    @Test func libraryImportRegistersCssAndJs() throws {
        let engine = try loadOverlayAndDiagram()
        try engine.evaluate("""
          (define grp (group "w" "Win" 'renderer 'diagram 'panels '()
                        (key "r" "Restore" (lambda () #t))))
          (define html (render-overlay-html grp '("Root") '()))
        """)
        let html = try engine.evaluate("html").asString()
        #expect(html.contains("window.overlayRenderers.diagram"))   // from diagram-panel.js
        #expect(html.contains(".diagram-panel"))                    // from diagram-panel.css
    }

    @Test func customRendererBodyContainsDataPayload() throws {
        let engine = try loadOverlayAndDiagram()
        try engine.evaluate("""
          (define spec (make-grid-panel-spec 3 1
                        (list (list (cons 'key "d") (cons 'col 1) (cons 'row 1) (cons 'col-span 1) (cons 'row-span 1)))))
          (define grp (group "w" "Win" 'renderer 'diagram 'panels (list spec)
                        (key "r" "Restore" (lambda () #t))))
          (define html (render-overlay-html grp '("Root") '()))
        """)
        let html = try engine.evaluate("html").asString()
        #expect(html.contains("data-renderer=\"diagram\""))
        #expect(html.contains("data-payload="))
        #expect(html.contains("\"type\":\"diagram\""))
        #expect(html.contains("\"cells\":"))
    }
}
