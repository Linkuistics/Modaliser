import Foundation
import Testing
import LispKit
@testable import Modaliser

private func joinPath(_ base: String, _ component: String) -> String {
    base.hasSuffix("/") ? base + component : base + "/" + component
}

// Tests for the panel-grid overlay renderer (panel-grid-renderer-k4): the
// Scheme `panel-grid-payload-json` that serializes a `screen`/`open` group
// (lowered by the layout DSL, ADR-0011) into the JSON the JS renderer reads,
// plus the dispatch wiring and the JS registry hook. The payload shape is the
// co-designed contract with the lowering (LayoutDslTests covers the alist
// side); here we pin the JSON it produces.
@Suite("Panel-grid overlay renderer")
struct PanelGridRendererTests {

    private func loadPanelGrid() throws -> SchemeEngine {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("Scheme directory not found"); throw SchemeTestError.noSchemeDir
        }
        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser state-machine))")
        try engine.evaluate("(import (modaliser event-dispatch) (modaliser dsl) (modaliser dom))")
        for file in ["ui/css.scm", "ui/overlay.scm"] {
            try engine.evaluateFile(joinPath(schemePath, file))
        }
        // A minimal live-list block-spec shaped like the real window:list /
        // iterm:pane blocks: a 'type entry, an on-render-fn that snapshots
        // live rows (return-and-merge), an on-leave-fn (chip clear), and a
        // 'hidden 1.. digit range under 'block-children (the panel lifts it
        // into dispatch — it must NOT surface as a key row).
        try engine.evaluate("""
          (define render-fires 0)
          (define (fake-list-block)
            (list (cons 'type 'window-list)
                  (cons 'on-render-fn
                        (lambda ()
                          (set! render-fires (+ render-fires 1))
                          (list (cons 'windows
                                  (list (list (cons 'label "1")
                                              (cons 'app "Safari")
                                              (cons 'title "Home")
                                              (cons 'visible #t)))))))
                  (cons 'on-leave-fn (lambda () 'left))
                  (cons 'block-children
                        (list (cons (cons 'hidden #t)
                                    (key-range "1.." "Win <n>" (list "1" "2")
                                      (lambda (k) k)))))))
        """)
        return engine
    }

    // MARK: - payload shape

    @Test func payloadCarriesTypeAndPanelsArray() throws {
        let engine = try loadPanelGrid()
        try engine.evaluate("""
          (screen 'pg-shape
            (panel "Windows" (key "c" "Center" (lambda () 'ok))))
          (define p (panel-grid-payload-json (lookup-tree "pg-shape")))
        """)
        let payload = try engine.evaluate("p").asString()
        #expect(payload.contains("\"type\":\"panel-grid\""))
        #expect(payload.contains("\"panels\":["))
        #expect(payload.contains("\"label\":\"Windows\""))
    }

    @Test func authoredColsAppearInPayload() throws {
        let engine = try loadPanelGrid()
        try engine.evaluate("""
          (screen 'pg-cols 'cols 3
            (panel "Windows" (key "c" "Center" (lambda () 'ok))))
          (define p (panel-grid-payload-json (lookup-tree "pg-cols")))
        """)
        #expect(try engine.evaluate("p").asString().contains("\"cols\":3"))
    }

    @Test func absentColsOmittedFromPayload() throws {
        let engine = try loadPanelGrid()
        try engine.evaluate("""
          (screen 'pg-nocols
            (panel "Windows" (key "c" "Center" (lambda () 'ok))))
          (define p (panel-grid-payload-json (lookup-tree "pg-nocols")))
        """)
        #expect(!(try engine.evaluate("p").asString().contains("\"cols\"")))
    }

    @Test func authoredGridLayoutAppearsInPayload() throws {
        let engine = try loadPanelGrid()
        try engine.evaluate("""
          (screen 'pg-grid 'layout 'grid
            (panel "Windows" (key "c" "Center" (lambda () 'ok))))
          (define p (panel-grid-payload-json (lookup-tree "pg-grid")))
        """)
        #expect(try engine.evaluate("p").asString().contains("\"layout\":\"grid\""))
    }

    @Test func absentLayoutOmittedFromPayload() throws {
        let engine = try loadPanelGrid()
        // Omitted layout → no key in the payload; JS sets no data-layout and the
        // base .panel-grid masonry default renders.
        try engine.evaluate("""
          (screen 'pg-nolayout
            (panel "Windows" (key "c" "Center" (lambda () 'ok))))
          (define p (panel-grid-payload-json (lookup-tree "pg-nolayout")))
        """)
        #expect(!(try engine.evaluate("p").asString().contains("\"layout\"")))
    }

    @Test func colsAndSpanHonouredUnderGridLayout() throws {
        let engine = try loadPanelGrid()
        // 'layout 'grid composes with 'cols and a panel 'span — all three ride
        // the one payload, so the deterministic grid keeps the width hints.
        try engine.evaluate("""
          (screen 'pg-grid-mix 'layout 'grid 'cols 3
            (panel "Windows" 'span 'wide (key "c" "Center" (lambda () 'ok))))
          (define p (panel-grid-payload-json (lookup-tree "pg-grid-mix")))
        """)
        let payload = try engine.evaluate("p").asString()
        #expect(payload.contains("\"layout\":\"grid\""))
        #expect(payload.contains("\"cols\":3"))
        #expect(payload.contains("\"span\":\"wide\""))
    }

    @Test func panelCarriesLabelSpanAndKeyRows() throws {
        let engine = try loadPanelGrid()
        try engine.evaluate("""
          (screen 'pg-panel
            (panel "Windows" 'span 'wide
              (key "c" "Center"   (lambda () 'ok))
              (key "m" "Maximise" (lambda () 'ok))))
          (define p (panel-grid-payload-json (lookup-tree "pg-panel")))
        """)
        let payload = try engine.evaluate("p").asString()
        #expect(payload.contains("\"label\":\"Windows\""))
        #expect(payload.contains("\"span\":\"wide\""))
        // Both key rows present (entry->row-json shape: key/label/isGroup/isSticky).
        #expect(payload.contains("\"label\":\"Center\""))
        #expect(payload.contains("\"label\":\"Maximise\""))
        #expect(payload.contains("\"isGroup\":false"))
    }

    @Test func looseKeysFormLeadingGeneralPanel() throws {
        let engine = try loadPanelGrid()
        try engine.evaluate("""
          (screen 'pg-general
            (key "z" "Loose Z" (lambda () 'ok))
            (panel "Windows" (key "c" "Center" (lambda () 'ok))))
          (define p (panel-grid-payload-json (lookup-tree "pg-general")))
        """)
        let payload = try engine.evaluate("p").asString()
        // A "General" panel exists, holding the loose key, and is placed FIRST.
        #expect(payload.contains("\"label\":\"General\""))
        #expect(payload.contains("\"label\":\"Loose Z\""))
        guard let generalIdx = payload.range(of: "\"label\":\"General\""),
              let windowsIdx = payload.range(of: "\"label\":\"Windows\"") else {
            Issue.record("panels missing in payload: \(payload)"); return
        }
        #expect(generalIdx.lowerBound < windowsIdx.lowerBound)
    }

    // MARK: - embedded live list

    @Test func listPanelEmbedsBlockAutoWidesAndHidesLiftedRange() throws {
        let engine = try loadPanelGrid()
        try engine.evaluate("""
          (screen 'pg-list
            (panel "Live" (fake-list-block)))
          (define p (panel-grid-payload-json (lookup-tree "pg-list")))
        """)
        let payload = try engine.evaluate("p").asString()
        // Embedded list is serialized through block-json (same path the blocks
        // renderer uses) and rides under the panel's "list" key.
        #expect(payload.contains("\"list\":{"))
        #expect(payload.contains("\"type\":\"window-list\""))
        // The on-render-fn fired and its live snapshot merged in.
        #expect(payload.contains("\"app\":\"Safari\""))
        #expect(try engine.evaluate("(= render-fires 1)") == .true)
        // A list-bearing panel auto-promotes to span wide.
        #expect(payload.contains("\"span\":\"wide\""))
        // The lifted 'hidden 1.. digit range is NOT surfaced as a key row.
        #expect(!payload.contains("\"label\":\"Win <n>\""))
    }

    // MARK: - opens

    @Test func nestedOpenRendersAsGroupRowInsidePanel() throws {
        let engine = try loadPanelGrid()
        try engine.evaluate("""
          (screen 'pg-nested
            (panel "Splits"
              (key "c" "Center" (lambda () 'ok))
              (open "f" "Full Toolkit"
                (panel "More" (key "x" "X" (lambda () 'ok))))))
          (define p (panel-grid-payload-json (lookup-tree "pg-nested")))
        """)
        let payload = try engine.evaluate("p").asString()
        // The nested open is an accent group-row inside the Splits panel, not
        // its own grid cell.
        #expect(payload.contains("\"label\":\"Full Toolkit\""))
        #expect(payload.contains("\"isGroup\":true"))
    }

    @Test func topLevelOpenRendersAsSingleRowPanel() throws {
        let engine = try loadPanelGrid()
        try engine.evaluate("""
          (screen 'pg-toplevel-open
            (open "s" "Splits"
              (panel "P" (key "x" "X" (lambda () 'ok)))))
          (define p (panel-grid-payload-json (lookup-tree "pg-toplevel-open")))
        """)
        let payload = try engine.evaluate("p").asString()
        // A top-level open becomes a panel (header = its label) with a single
        // drill-in group row.
        #expect(payload.contains("\"label\":\"Splits\""))
        #expect(payload.contains("\"isGroup\":true"))
    }

    // MARK: - dispatch + JS wiring

    @Test func bootstrapHtmlCarriesPanelGridRenderer() throws {
        let engine = try loadPanelGrid()
        try engine.evaluate("""
          (screen 'pg-html
            (panel "Windows" (key "c" "Center" (lambda () 'ok))))
          (define html (render-overlay-html (lookup-tree "pg-html") '("Root") '()))
        """)
        let html = try engine.evaluate("html").asString()
        // The custom-body div dispatches to overlayRenderers['panel-grid'] on load.
        #expect(html.contains("data-renderer=\"panel-grid\""))
        #expect(html.contains("data-payload='"))
        #expect(html.contains("\"type\":\"panel-grid\""))
    }

    @Test func overlayJsRegistersPanelGridRenderer() throws {
        let engine = try loadPanelGrid()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("scheme path"); throw SchemeTestError.noSchemeDir
        }
        let js = try String(contentsOfFile: joinPath(schemePath, "ui/overlay.js"), encoding: .utf8)
        #expect(js.contains("overlayRenderers['panel-grid']"))
        #expect(js.contains("renderPanel"))
        // The canonical key-row renderer now lives in overlay.js itself
        // (relocated from the removed which-key block); the panel grid draws its
        // key rows with it.
        #expect(js.contains("renderPanelRow"))
    }

    @Test func overlayJsAppliesDataLayoutAttribute() throws {
        let engine = try loadPanelGrid()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("scheme path"); throw SchemeTestError.noSchemeDir
        }
        let js = try String(contentsOfFile: joinPath(schemePath, "ui/overlay.js"), encoding: .utf8)
        // The renderer reflects the payload's `layout` onto the grid element as
        // data-layout; base.css keys the deterministic-grid override off it.
        #expect(js.contains("data-layout"))
    }
}
