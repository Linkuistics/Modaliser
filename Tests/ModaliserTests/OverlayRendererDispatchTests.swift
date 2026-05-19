import Foundation
import Testing
import LispKit
@testable import Modaliser

private func joinPath(_ base: String, _ component: String) -> String {
    base.hasSuffix("/") ? base + component : base + "/" + component
}

@Suite("Overlay renderer dispatch (group 'renderer)")
struct OverlayRendererDispatchTests {

    private func loadOverlay() throws -> SchemeEngine {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("Scheme directory not found"); throw SchemeTestError.noSchemeDir
        }
        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser state-machine))")
        try engine.evaluate("(import (modaliser event-dispatch) (modaliser dsl) (modaliser dom))")
        for file in ["ui/css.scm", "ui/overlay.scm"] {
            try engine.evaluateFile(joinPath(schemePath, file))
        }
        return engine
    }

    @Test func groupWithoutRendererStillRendersAsListEntries() throws {
        let engine = try loadOverlay()
        try engine.evaluate("""
          (define grp (group "w" "Win" (key "a" "Apple" (lambda () #t))))
          (define html (render-overlay-html grp '("Root") '()))
        """)
        let html = try engine.evaluate("html").asString()
        #expect(html.contains("overlay-entry"))    // default list renderer markup
    }

    @Test func rendererPropertyOnGroupNodeIsAccessible() throws {
        let engine = try loadOverlay()
        try engine.evaluate("""
          (define grp (group "w" "Win" 'renderer 'blocks 'blocks '()
                        (key "a" "Apple" (lambda () #t))))
        """)
        #expect(try engine.evaluate("(eq? (node-renderer grp) 'blocks)") == .true)
        #expect(try engine.evaluate("(equal? (node-renderer-payload grp 'blocks) '())") == .true)
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
