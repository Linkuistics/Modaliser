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
          (define grp (group "w" "Win" 'renderer 'diagram 'panels '(("p1"))
                        (key "a" "Apple" (lambda () #t))))
        """)
        #expect(try engine.evaluate("(eq? (node-renderer grp) 'diagram)") == .true)
        #expect(try engine.evaluate("(equal? (node-renderer-payload grp 'panels) '((\"p1\")))") == .true)
    }

    @Test func updateOverlayJsExposesRendererRegistry() throws {
        let engine = try loadOverlay()
        // Read the bundled overlay.js source and check the dispatch hook is present.
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("scheme path"); return
        }
        let js = try String(contentsOfFile: joinPath(schemePath, "ui/overlay.js"), encoding: .utf8)
        #expect(js.contains("window.overlayRenderers"))
        #expect(js.contains("overlayRenderers[payload.type]"))
    }

    @Test func diagramRendererEntriesExcludePanelBoundKeys() throws {
        let engine = try loadOverlay()
        try engine.evaluate("""
          ;; Group with a panel containing key "d" plus a text-only child key "r".
          ;; The custom-renderer payload's entries list should contain "r" but
          ;; NOT "d" — "d" is painted on the panel, not in the text strip.
          (define spec (list (cons 'type 'grid)
                             (cons 'cols 1) (cons 'rows 1)
                             (cons 'cells
                               (list (list (cons 'key "d") (cons 'col 1) (cons 'row 1)
                                           (cons 'colSpan 1) (cons 'rowSpan 1))))))
          (define grp (group "w" "Win" 'renderer 'diagram 'panels (list spec)
                        (key "d" "First Third" (lambda () #t))
                        (key "r" "Restore"     (lambda () #t))))
          (define html (render-overlay-html grp '("Root") '()))
        """)
        let html = try engine.evaluate("html").asString()
        // Pull out the data-payload value — it's a JSON object string between
        // single quotes after data-payload=.
        guard let payloadRange = html.range(of: "data-payload='") else {
            Issue.record("data-payload attribute not present")
            return
        }
        let after = html[payloadRange.upperBound...]
        guard let endQuote = after.firstIndex(of: "'") else {
            Issue.record("data-payload not terminated")
            return
        }
        let payload = String(after[..<endQuote])
        // Isolate the "entries" array slice — "d" appears legitimately in the
        // panels cell object, so we must scope the check to entries only.
        guard let entriesRange = payload.range(of: "\"entries\":[") else {
            Issue.record("entries field not present in payload: \(payload)")
            return
        }
        let entries = String(payload[entriesRange.lowerBound...])
        // "r" must appear in entries; "d" must NOT (it's painted on the panel).
        #expect(entries.contains("\"key\":\"r\""))
        #expect(!entries.contains("\"key\":\"d\""),
                "panel-bound key \"d\" should not appear in custom renderer entries; entries was: \(entries)")
    }
}
