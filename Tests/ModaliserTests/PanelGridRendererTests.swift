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
        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser fsm))")
        try engine.evaluate("(import (modaliser event-dispatch) (modaliser dsl) (modaliser dom))")
        try engine.evaluate("(import (modaliser configuration))")
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
          (define cfg (configuration (screen 'pg-shape
            (panel "Windows" (key "c" "Center" (lambda () 'ok))))))
          (define p (panel-grid-payload-json (configuration-tree-ref cfg "pg-shape")))
        """)
        let payload = try engine.evaluate("p").asString()
        #expect(payload.contains("\"type\":\"panel-grid\""))
        #expect(payload.contains("\"panels\":["))
        #expect(payload.contains("\"label\":\"Windows\""))
    }

    @Test func authoredColsAppearInPayload() throws {
        let engine = try loadPanelGrid()
        try engine.evaluate("""
          (define cfg (configuration (screen 'pg-cols 'cols 3
            (panel "Windows" (key "c" "Center" (lambda () 'ok))))))
          (define p (panel-grid-payload-json (configuration-tree-ref cfg "pg-cols")))
        """)
        #expect(try engine.evaluate("p").asString().contains("\"cols\":3"))
    }

    @Test func absentColsOmittedFromPayload() throws {
        let engine = try loadPanelGrid()
        try engine.evaluate("""
          (define cfg (configuration (screen 'pg-nocols
            (panel "Windows" (key "c" "Center" (lambda () 'ok))))))
          (define p (panel-grid-payload-json (configuration-tree-ref cfg "pg-nocols")))
        """)
        #expect(!(try engine.evaluate("p").asString().contains("\"cols\"")))
    }

    @Test func authoredGridLayoutAppearsInPayload() throws {
        let engine = try loadPanelGrid()
        try engine.evaluate("""
          (define cfg (configuration (screen 'pg-grid 'layout 'grid
            (panel "Windows" (key "c" "Center" (lambda () 'ok))))))
          (define p (panel-grid-payload-json (configuration-tree-ref cfg "pg-grid")))
        """)
        #expect(try engine.evaluate("p").asString().contains("\"layout\":\"grid\""))
    }

    @Test func absentLayoutOmittedFromPayload() throws {
        let engine = try loadPanelGrid()
        // Omitted layout → no key in the payload; JS sets no data-layout and the
        // base .panel-grid masonry default renders.
        try engine.evaluate("""
          (define cfg (configuration (screen 'pg-nolayout
            (panel "Windows" (key "c" "Center" (lambda () 'ok))))))
          (define p (panel-grid-payload-json (configuration-tree-ref cfg "pg-nolayout")))
        """)
        #expect(!(try engine.evaluate("p").asString().contains("\"layout\"")))
    }

    @Test func colsAndSpanHonouredUnderGridLayout() throws {
        let engine = try loadPanelGrid()
        // 'layout 'grid composes with 'cols and a panel 'span — all three ride
        // the one payload, so the deterministic grid keeps the width hints.
        try engine.evaluate("""
          (define cfg (configuration (screen 'pg-grid-mix 'layout 'grid 'cols 3
            (panel "Windows" 'span 'wide (key "c" "Center" (lambda () 'ok))))))
          (define p (panel-grid-payload-json (configuration-tree-ref cfg "pg-grid-mix")))
        """)
        let payload = try engine.evaluate("p").asString()
        #expect(payload.contains("\"layout\":\"grid\""))
        #expect(payload.contains("\"cols\":3"))
        #expect(payload.contains("\"span\":\"wide\""))
    }

    @Test func panelCarriesLabelSpanAndKeyRows() throws {
        let engine = try loadPanelGrid()
        try engine.evaluate("""
          (define cfg (configuration (screen 'pg-panel
            (panel "Windows" 'span 'wide
              (key "c" "Center"   (lambda () 'ok))
              (key "m" "Maximise" (lambda () 'ok))))))
          (define p (panel-grid-payload-json (configuration-tree-ref cfg "pg-panel")))
        """)
        let payload = try engine.evaluate("p").asString()
        #expect(payload.contains("\"label\":\"Windows\""))
        #expect(payload.contains("\"span\":\"wide\""))
        // Both key rows present (entry->row-json shape: key/label/isGroup/isSticky).
        #expect(payload.contains("\"label\":\"Center\""))
        #expect(payload.contains("\"label\":\"Maximise\""))
        #expect(payload.contains("\"isGroup\":false"))
    }

    @Test func looseKeysRenderInLooseRegionNotGeneralPanel() throws {
        let engine = try loadPanelGrid()
        try engine.evaluate("""
          (define cfg (configuration (screen 'pg-general
            (key "z" "Loose Z" (lambda () 'ok))
            (panel "Windows" (key "c" "Center" (lambda () 'ok))))))
          (define p (panel-grid-payload-json (configuration-tree-ref cfg "pg-general")))
        """)
        let payload = try engine.evaluate("p").asString()
        // The loose key rides a "loose" array (a bare header-less row block) —
        // NOT a "General" panel card.
        #expect(payload.contains("\"loose\":["))
        #expect(payload.contains("\"label\":\"Loose Z\""))
        #expect(!payload.contains("\"label\":\"General\""))
        // The real panel still packs in the panel grid.
        #expect(payload.contains("\"label\":\"Windows\""))
    }

    @Test func panelOnlyScreenHasEmptyLooseRegion() throws {
        let engine = try loadPanelGrid()
        // No loose atoms → the loose array is empty (the JS renders no
        // .panel-loose block), and the panel still renders.
        try engine.evaluate("""
          (define cfg (configuration (screen 'pg-panelonly
            (panel "Windows" (key "c" "Center" (lambda () 'ok))))))
          (define p (panel-grid-payload-json (configuration-tree-ref cfg "pg-panelonly")))
        """)
        let payload = try engine.evaluate("p").asString()
        #expect(payload.contains("\"loose\":[]"))
        #expect(payload.contains("\"label\":\"Windows\""))
    }

    @Test func looseOnlyScreenHasEmptyPanelsArray() throws {
        let engine = try loadPanelGrid()
        // Loose atoms with no real panels → the panels array is empty (the JS
        // renders no .panel-grid), and the loose rows are present.
        try engine.evaluate("""
          (define cfg (configuration (screen 'pg-looseonly
            (key "a" "Alpha" (lambda () 'ok))
            (key "b" "Beta"  (lambda () 'ok)))))
          (define p (panel-grid-payload-json (configuration-tree-ref cfg "pg-looseonly")))
        """)
        let payload = try engine.evaluate("p").asString()
        #expect(payload.contains("\"panels\":[]"))
        #expect(payload.contains("\"label\":\"Alpha\""))
        #expect(payload.contains("\"label\":\"Beta\""))
    }

    // MARK: - embedded live list

    @Test func listPanelEmbedsBlockAutoWidesAndHidesLiftedRange() throws {
        let engine = try loadPanelGrid()
        try engine.evaluate("""
          (define cfg (configuration (screen 'pg-list
            (panel "Live" (fake-list-block)))))
          (define p (panel-grid-payload-json (configuration-tree-ref cfg "pg-list")))
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

    // MARK: - bare diagram host (diagram-bare-panel-k22)

    @Test func diagramPanelMarkedBare() throws {
        let engine = try loadPanelGrid()
        // A panel whose embedded block is a window-diagram hosts it BARE: the
        // payload carries "bare":true so the JS renderer drops the card chrome
        // and the diagram's transparent empty cells reveal the body tint.
        // Keyed on the block 'type — no config opt-in.
        try engine.evaluate("""
          (define (fake-diagram-block)
            (list (cons 'type 'window-diagram)
                  (cons 'panels '())))
          (define cfg (configuration (screen 'pg-diagram
            (panel "Layout" (fake-diagram-block)))))
          (define p (panel-grid-payload-json (configuration-tree-ref cfg "pg-diagram")))
        """)
        let payload = try engine.evaluate("p").asString()
        #expect(payload.contains("\"bare\":true"))
        #expect(payload.contains("\"type\":\"window-diagram\""))
    }

    @Test func nonDiagramListPanelNotBare() throws {
        let engine = try loadPanelGrid()
        // A panel embedding a non-diagram live list (window-list) keeps its
        // white card: no "bare" flag in the payload.
        try engine.evaluate("""
          (define cfg (configuration (screen 'pg-notbare
            (panel "Live" (fake-list-block)))))
          (define p (panel-grid-payload-json (configuration-tree-ref cfg "pg-notbare")))
        """)
        #expect(!(try engine.evaluate("p").asString().contains("\"bare\"")))
    }

    @Test func keyOnlyPanelNotBare() throws {
        let engine = try loadPanelGrid()
        // A plain key-row panel (no embedded block) is never bare.
        try engine.evaluate("""
          (define cfg (configuration (screen 'pg-keysonly
            (panel "Windows" (key "c" "Center" (lambda () 'ok))))))
          (define p (panel-grid-payload-json (configuration-tree-ref cfg "pg-keysonly")))
        """)
        #expect(!(try engine.evaluate("p").asString().contains("\"bare\"")))
    }

    @Test func overlayJsAddsBareClassForBarePanels() throws {
        let engine = try loadPanelGrid()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("scheme path"); throw SchemeTestError.noSchemeDir
        }
        let js = try String(contentsOfFile: joinPath(schemePath, "ui/overlay.js"), encoding: .utf8)
        // renderPanel adds the .panel--bare modifier when the payload marks the
        // panel bare, so base.css can drop the card chrome for diagram hosts.
        #expect(js.contains("panel.bare"))
        #expect(js.contains("panel--bare"))
    }

    @Test func baseCssDefinesBarePanelVariant() throws {
        let engine = try loadPanelGrid()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("scheme path"); throw SchemeTestError.noSchemeDir
        }
        let css = try String(contentsOfFile: joinPath(schemePath, "base.css"), encoding: .utf8)
        #expect(css.contains(".panel--bare"))
    }

    @Test func barePanelDropsOverflowClip() throws {
        let engine = try loadPanelGrid()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("scheme path"); throw SchemeTestError.noSchemeDir
        }
        let css = try String(contentsOfFile: joinPath(schemePath, "base.css"), encoding: .utf8)
        // A bare panel must drop the .panel base rule's rounded clip (overflow:
        // hidden + border-radius) — otherwise the flush, start-aligned diagram
        // grid gets its bottom-left cell border nibbled (window-diagram-polish-
        // k31). Scope the assertion to the .panel--bare block.
        guard let bareStart = css.range(of: ".panel--bare {"),
              let bareEnd = css.range(of: "}", range: bareStart.upperBound..<css.endIndex) else {
            Issue.record("no .panel--bare {} rule"); return
        }
        let bareBody = css[bareStart.lowerBound..<bareEnd.upperBound]
        #expect(bareBody.contains("overflow: visible"))
    }

    // MARK: - headerless panel (window-diagram-polish-k31)

    @Test func headerlessPanelEmitsEmptyLabel() throws {
        let engine = try loadPanelGrid()
        // (panel #f …) is headerless: node-label hands back #f, which panel->json
        // normalises to an empty label so js-escape-overlay doesn't choke and the
        // JS draws no .panel-head. The title stays config-controlled.
        try engine.evaluate("""
          (define cfg (configuration (screen 'pg-headerless
            (panel #f (key "c" "Center" (lambda () 'ok))))))
          (define p (panel-grid-payload-json (configuration-tree-ref cfg "pg-headerless")))
        """)
        let payload = try engine.evaluate("p").asString()
        #expect(payload.contains("\"label\":\"\""))
        // The row still renders — only the header is dropped.
        #expect(payload.contains("\"label\":\"Center\""))
    }

    @Test func overlayJsSkipsHeadForEmptyLabel() throws {
        let engine = try loadPanelGrid()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("scheme path"); throw SchemeTestError.noSchemeDir
        }
        let js = try String(contentsOfFile: joinPath(schemePath, "ui/overlay.js"), encoding: .utf8)
        // renderPanel guards .panel-head creation on a truthy label, so an empty
        // label draws no header band at all (not just an empty one).
        #expect(js.contains("if (panel.label) {"))
    }

    // MARK: - loose region rendering (bare-loose-rows-k23)

    @Test func overlayJsRendersLooseRegion() throws {
        let engine = try loadPanelGrid()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("scheme path"); throw SchemeTestError.noSchemeDir
        }
        let js = try String(contentsOfFile: joinPath(schemePath, "ui/overlay.js"), encoding: .utf8)
        // The panel-grid renderer reads data.loose and draws a header-less
        // .panel-loose block (rows + bare blocks) above the .panel-grid.
        #expect(js.contains("data.loose"))
        #expect(js.contains("panel-loose"))
    }

    @Test func baseCssDefinesLooseRegion() throws {
        let engine = try loadPanelGrid()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("scheme path"); throw SchemeTestError.noSchemeDir
        }
        let css = try String(contentsOfFile: joinPath(schemePath, "base.css"), encoding: .utf8)
        #expect(css.contains(".panel-loose"))
    }

    @Test func overlayJsColumnizesLooseRows() throws {
        let engine = try loadPanelGrid()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("scheme path"); throw SchemeTestError.noSchemeDir
        }
        let js = try String(contentsOfFile: joinPath(schemePath, "ui/overlay.js"), encoding: .utf8)
        let css = try String(contentsOfFile: joinPath(schemePath, "base.css"), encoding: .utf8)
        // renderLoose groups consecutive rows into .panel-loose-rows runs, and
        // layoutLooseColumns fills each run with its own column count to span the
        // width the panel grid / loose blocks established (loose-row-columns-k33).
        // Like the panel balance, the pure-JS measurement can't run in this suite
        // (no browser layout engine) — these structural anchors assert the path
        // exists; live verification is the behavioural gate.
        #expect(js.contains("panel-loose-rows"))
        #expect(js.contains("layoutLooseColumns"))
        #expect(css.contains(".panel-loose-rows"))
        #expect(css.contains("--loose-row-cols"))
    }

    // MARK: - opens

    @Test func nestedOpenRendersAsGroupRowInsidePanel() throws {
        let engine = try loadPanelGrid()
        try engine.evaluate("""
          (define cfg (configuration (screen 'pg-nested
            (panel "Splits"
              (key "c" "Center" (lambda () 'ok))
              (open "f" "Full Toolkit"
                (panel "More" (key "x" "X" (lambda () 'ok))))))))
          (define p (panel-grid-payload-json (configuration-tree-ref cfg "pg-nested")))
        """)
        let payload = try engine.evaluate("p").asString()
        // The nested open is an accent group-row inside the Splits panel, not
        // its own grid cell.
        #expect(payload.contains("\"label\":\"Full Toolkit\""))
        #expect(payload.contains("\"isGroup\":true"))
    }

    @Test func topLevelOpenFoldsIntoLooseRegionAsDrillRow() throws {
        let engine = try loadPanelGrid()
        try engine.evaluate("""
          (define cfg (configuration (screen 'pg-toplevel-open
            (open "s" "Splits"
              (panel "P" (key "x" "X" (lambda () 'ok)))))))
          (define p (panel-grid-payload-json (configuration-tree-ref cfg "pg-toplevel-open")))
        """)
        let payload = try engine.evaluate("p").asString()
        // A top-level open folds into the loose region as a single drill row
        // (isGroup true → accent + arrow), NOT its own panel card. With no real
        // panels, the panels array is empty.
        #expect(payload.contains("\"loose\":["))
        #expect(payload.contains("\"label\":\"Splits\""))
        #expect(payload.contains("\"isGroup\":true"))
        #expect(payload.contains("\"panels\":[]"))
        // It stays navigable — dispatch is unchanged.
        let root = "(configuration-tree-ref cfg \"pg-toplevel-open\")"
        #expect(try engine.evaluate("(group? (find-child \(root) \"s\"))") == .true)
    }

    // MARK: - loose top-level blocks (bare-loose-rows-k23)

    @Test func looseDiagramBlockRidesLooseRegionBare() throws {
        let engine = try loadPanelGrid()
        // A window-diagram placed LOOSE at the screen top level (not in a panel)
        // serializes into the loose region through the SAME block-json path, and
        // its hidden dispatch keys lift into the screen's children. With no
        // real panels the grid is empty; the JS draws the block bare.
        try engine.evaluate("""
          (define (fake-diagram-block)
            (list (cons 'type 'window-diagram)
                  (cons 'panels '())
                  (cons 'block-children
                        (list (cons (cons 'hidden #t)
                                    (key-range "x.." "Move" (list "x")
                                      (lambda (k) k)))))))
          (define cfg (configuration (screen 'pg-loose-diagram
            (key "s" "Select" (lambda () 'ok))
            (fake-diagram-block))))
          (define p (panel-grid-payload-json (configuration-tree-ref cfg "pg-loose-diagram")))
        """)
        let payload = try engine.evaluate("p").asString()
        #expect(payload.contains("\"loose\":["))
        #expect(payload.contains("\"type\":\"window-diagram\""))
        #expect(payload.contains("\"panels\":[]"))
        let root = "(configuration-tree-ref cfg \"pg-loose-diagram\")"
        #expect(try engine.evaluate("(range-command? (find-child \(root) \"x\"))") == .true)
    }

    @Test func looseListBlockMergesLiveRowsInLooseRegion() throws {
        let engine = try loadPanelGrid()
        // A live window-list placed loose at the top level runs its on-render-fn
        // and merges the live rows, exactly as a panel-embedded list does — but
        // rides the loose region, not a panel.
        try engine.evaluate("""
          (define cfg (configuration (screen 'pg-loose-list
            (fake-list-block))))
          (define p (panel-grid-payload-json (configuration-tree-ref cfg "pg-loose-list")))
        """)
        let payload = try engine.evaluate("p").asString()
        #expect(payload.contains("\"loose\":["))
        #expect(payload.contains("\"type\":\"window-list\""))
        #expect(payload.contains("\"app\":\"Safari\""))
        #expect(try engine.evaluate("(= render-fires 1)") == .true)
        #expect(payload.contains("\"panels\":[]"))
        // The lifted hidden 1.. range is NOT surfaced as a loose row.
        #expect(!payload.contains("\"label\":\"Win <n>\""))
    }

    // MARK: - dispatch + JS wiring

    @Test func bootstrapHtmlCarriesPanelGridRenderer() throws {
        let engine = try loadPanelGrid()
        try engine.evaluate("""
          (define cfg (configuration (screen 'pg-html
            (panel "Windows" (key "c" "Center" (lambda () 'ok))))))
          (define html (render-overlay-html (configuration-tree-ref cfg "pg-html") '("Root") '()))
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

    @Test func overlayJsBalancesPanelColumnsByDefault() throws {
        let engine = try loadPanelGrid()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("scheme path"); throw SchemeTestError.noSchemeDir
        }
        let js = try String(contentsOfFile: joinPath(schemePath, "ui/overlay.js"), encoding: .utf8)
        // When the payload omits `cols`, the renderer measures the laid-out grid
        // and picks the column count whose shape is closest to the target ratio
        // (responsive-columns-k30 / panel-aspect-balance-k32). The pure-JS
        // balance can't be exercised in this suite (no browser layout engine);
        // these structural anchors assert the default path exists, and live
        // verification is the behavioural gate. Authored `cols` still hard-pins.
        #expect(js.contains("balancePanelGridColumns"))
        #expect(js.contains("PANEL_GRID_TARGET_RATIO"))
    }

    // MARK: - embedded sections (embed-rendering-k14; ADR-0011)

    @Test func embedTargetRidesSectionsArrayAndLosesDrillRow() throws {
        let engine = try loadPanelGrid()
        // 'embed '("a") → the open's target serializes as a section of THIS
        // display root (key/keyHtml/label/rows), and its drill row disappears
        // from the loose region — the section replaces the row.
        try engine.evaluate("""
          (define cfg (configuration (screen 'pg-embed 'embed '("a")
            (key "x" "Xylophone" (lambda () 'ok))
            (open "a" "Agents"
              (key "j" "Jump" (lambda () 'ok))))))
          (define p (panel-grid-payload-json (configuration-tree-ref cfg "pg-embed")))
        """)
        let payload = try engine.evaluate("p").asString()
        #expect(payload.contains("\"sections\":["))
        #expect(payload.contains("\"key\":\"a\""))
        #expect(payload.contains("\"label\":\"Agents\""))
        #expect(payload.contains("\"label\":\"Jump\""))
        // No drill row for the embedded open (a loose drill row would carry
        // "isGroup":true right after the Agents label).
        #expect(!payload.contains("\"label\":\"Agents\",\"isGroup\":true"))
        // The non-embedded loose key still renders as a loose row.
        #expect(payload.contains("\"label\":\"Xylophone\""))
        // At the anchor no section is active.
        #expect(!payload.contains("\"activeSection\""))
        // Dispatch is untouched: the embedded key still navigates.
        let root = "(configuration-tree-ref cfg \"pg-embed\")"
        #expect(try engine.evaluate("(group? (find-child \(root) \"a\"))") == .true)
    }

    @Test func embedKeyInsidePanelLosesAccentGroupRow() throws {
        let engine = try loadPanelGrid()
        // An embedded open declared INSIDE a panel loses its accent group-row
        // there too — the section replaces it wherever the drill row lived.
        try engine.evaluate("""
          (define cfg (configuration (screen 'pg-embed-panel 'embed '("a")
            (panel "Tools"
              (key "c" "Center" (lambda () 'ok))
              (open "a" "Agents"
                (key "j" "Jump" (lambda () 'ok)))))))
          (define p (panel-grid-payload-json (configuration-tree-ref cfg "pg-embed-panel")))
        """)
        let payload = try engine.evaluate("p").asString()
        #expect(payload.contains("\"sections\":["))
        #expect(!payload.contains("\"label\":\"Agents\",\"isGroup\":true"))
        #expect(payload.contains("\"label\":\"Center\""))
    }

    @Test func inactiveSectionRendersStaticSkeletonWithoutBlockRender() throws {
        let engine = try loadPanelGrid()
        // The binding contract (spec "The two-layer node model"): an unvisited
        // embedded section renders its STATIC rows only — its live-list block
        // does not serialize, so on-render-fn never fires (no early
        // evaluation). Span stays 'wide (block presence, not serialization,
        // decides it — structure is stable across restyles).
        try engine.evaluate("""
          (define cfg (configuration (screen 'pg-embed-static 'embed '("a")
            (open "a" "Agents"
              (key "j" "Jump" (lambda () 'ok))
              (panel "Live" (fake-list-block))))))
          (define p (panel-grid-payload-json (configuration-tree-ref cfg "pg-embed-static")))
        """)
        let payload = try engine.evaluate("p").asString()
        #expect(try engine.evaluate("(= render-fires 0)") == .true)
        #expect(!payload.contains("\"type\":\"window-list\""))
        #expect(payload.contains("\"span\":\"wide\""))
        #expect(payload.contains("\"label\":\"Jump\""))
    }

    @Test func activeSectionPopulatesListAndMarksActive() throws {
        let engine = try loadPanelGrid()
        // With the Visit on the section (active-key passed), the section's
        // live-list block serializes through block-json — the come-to-rest
        // snapshot populates — and the payload carries the active-section
        // marker plus the display root's identity for the JS restyle protocol.
        try engine.evaluate("""
          (define cfg (configuration (screen 'pg-embed-active 'embed '("a")
            (open "a" "Agents"
              (key "j" "Jump" (lambda () 'ok))
              (panel "Live" (fake-list-block))))))
          (define p (panel-grid-payload-json (configuration-tree-ref cfg "pg-embed-active")
                                             "a" "pg-embed-active"))
        """)
        let payload = try engine.evaluate("p").asString()
        #expect(payload.contains("\"activeSection\":\"a\""))
        #expect(payload.contains("\"rootId\":\"pg-embed-active\""))
        #expect(payload.contains("\"list\":{"))
        #expect(payload.contains("\"type\":\"window-list\""))
        #expect(payload.contains("\"app\":\"Safari\""))
        #expect(try engine.evaluate("(= render-fires 1)") == .true)
    }

    @Test func sectionWithoutListIsNarrow() throws {
        let engine = try loadPanelGrid()
        try engine.evaluate("""
          (define cfg (configuration (screen 'pg-embed-narrow 'embed '("a")
            (open "a" "Agents"
              (key "j" "Jump" (lambda () 'ok))))))
          (define p (panel-grid-payload-json (configuration-tree-ref cfg "pg-embed-narrow")))
        """)
        let payload = try engine.evaluate("p").asString()
        // The section's own span (the only span in this payload — no panels).
        #expect(payload.contains("\"span\":\"narrow\""))
    }

    @Test func bootstrapHtmlCarriesRootIdAndSections() throws {
        let engine = try loadPanelGrid()
        // The initial paint routes through the same anchoring as pushes: the
        // data-payload carries rootId (scope + anchor path) and the sections,
        // so a later within-root push can hit the JS restyle fast path.
        try engine.evaluate("""
          (define cfg (configuration (screen 'pg-embed-html 'embed '("a")
            (open "a" "Agents"
              (key "j" "Jump" (lambda () 'ok))))))
          (define html (render-overlay-html (configuration-tree-ref cfg "pg-embed-html") '("Root") '()))
        """)
        let html = try engine.evaluate("html").asString()
        #expect(html.contains("\"rootId\":\"pg-embed-html\""))
        #expect(html.contains("\"sections\":["))
    }

    @Test func overlayJsImplementsRestyleProtocol() throws {
        let engine = try loadPanelGrid()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("scheme path"); throw SchemeTestError.noSchemeDir
        }
        let js = try String(contentsOfFile: joinPath(schemePath, "ui/overlay.js"), encoding: .utf8)
        // Section cards join the panel grid; a same-root push with a moved
        // active section restyles (marker toggle + active-section content
        // refresh) instead of rebuilding the persistent root.
        #expect(js.contains("renderEmbedSection"))
        #expect(js.contains("restylePanelGridActiveSection"))
        #expect(js.contains("data-root-id"))
        #expect(js.contains("data-active-section"))
        #expect(js.contains("data-embed-key"))
    }

    @Test func baseCssDefinesEmbedSectionDimming() throws {
        let engine = try loadPanelGrid()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("scheme path"); throw SchemeTestError.noSchemeDir
        }
        let css = try String(contentsOfFile: joinPath(schemePath, "base.css"), encoding: .utf8)
        // Dimming is the display's statement of liveness (active rows ≡ live
        // keys): sections dim at the anchor; everything but the active
        // section dims while one is visited.
        #expect(css.contains(".embed-section"))
        #expect(css.contains("--embed-dim"))
        #expect(css.contains(".embed-section--active"))
        #expect(css.contains("[data-active-section]"))
    }

    // MARK: - row order (manual-panel-order-k24)

    // Rows declared "z" then "a" discriminate the two orderings: declaration
    // order renders Zulu before Alpha; key-sorting renders Alpha first.
    private func zulu(_ s: String) -> String.Index? { s.range(of: "Zulu")?.lowerBound }
    private func alpha(_ s: String) -> String.Index? { s.range(of: "Alpha")?.lowerBound }

    @Test func panelDefaultSortsRowsByKey() throws {
        let engine = try loadPanelGrid()
        try engine.evaluate("""
          (define cfg (configuration (screen 'pg-order-default
            (panel "Layouts"
              (key "z" "Zulu"  (lambda () 'ok))
              (key "a" "Alpha" (lambda () 'ok))))))
          (define p (panel-grid-payload-json (configuration-tree-ref cfg "pg-order-default")))
        """)
        let payload = try engine.evaluate("p").asString()
        // No 'order keyword → key-sorted: Alpha ("a") precedes Zulu ("z").
        #expect(alpha(payload)! < zulu(payload)!)
    }

    @Test func panelOrderDeclaredPreservesAuthoredRowOrder() throws {
        let engine = try loadPanelGrid()
        try engine.evaluate("""
          (define cfg (configuration (screen 'pg-order-declared
            (panel "Layouts" 'order 'declared
              (key "z" "Zulu"  (lambda () 'ok))
              (key "a" "Alpha" (lambda () 'ok))))))
          (define p (panel-grid-payload-json (configuration-tree-ref cfg "pg-order-declared")))
        """)
        let payload = try engine.evaluate("p").asString()
        // 'order 'declared → declaration order: Zulu before Alpha.
        #expect(zulu(payload)! < alpha(payload)!)
    }

    @Test func panelExplicitOrderKeysSortsRows() throws {
        let engine = try loadPanelGrid()
        try engine.evaluate("""
          (define cfg (configuration (screen 'pg-order-keys
            (panel "Layouts" 'order 'keys
              (key "z" "Zulu"  (lambda () 'ok))
              (key "a" "Alpha" (lambda () 'ok))))))
          (define p (panel-grid-payload-json (configuration-tree-ref cfg "pg-order-keys")))
        """)
        let payload = try engine.evaluate("p").asString()
        // Explicit 'order 'keys → sorted, same as the default.
        #expect(alpha(payload)! < zulu(payload)!)
    }

    @Test func screenOrderDeclaredInheritedByPanel() throws {
        let engine = try loadPanelGrid()
        try engine.evaluate("""
          (define cfg (configuration (screen 'pg-order-screen 'order 'declared
            (panel "Layouts"
              (key "z" "Zulu"  (lambda () 'ok))
              (key "a" "Alpha" (lambda () 'ok))))))
          (define p (panel-grid-payload-json (configuration-tree-ref cfg "pg-order-screen")))
        """)
        let payload = try engine.evaluate("p").asString()
        // The panel has no explicit 'order → inherits the screen default 'declared.
        #expect(zulu(payload)! < alpha(payload)!)
    }

    @Test func panelOrderOverridesScreenDefault() throws {
        let engine = try loadPanelGrid()
        try engine.evaluate("""
          (define cfg (configuration (screen 'pg-order-override 'order 'declared
            (panel "Layouts" 'order 'keys
              (key "z" "Zulu"  (lambda () 'ok))
              (key "a" "Alpha" (lambda () 'ok))))))
          (define p (panel-grid-payload-json (configuration-tree-ref cfg "pg-order-override")))
        """)
        let payload = try engine.evaluate("p").asString()
        // Panel's explicit 'order 'keys wins over the screen's 'declared default.
        #expect(alpha(payload)! < zulu(payload)!)
    }
}
