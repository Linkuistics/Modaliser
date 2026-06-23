import Foundation
import Testing
import LispKit
@testable import Modaliser

private func joinPath(_ base: String, _ component: String) -> String {
    base.hasSuffix("/") ? base + component : base + "/" + component
}

// Integration tests for the selection-cursor DISPATCH + renderer wiring
// (list-cursor-k6): the overlay registers the active list's cursor while
// serializing a screen (begin-pass / offer / end-pass in renderer-body-json),
// the panel-grid payload carries the selected index, and the modal key path
// moves the cursor (↑↓ / k j) and activates the highlighted row (⏎) by reusing
// the existing digit-range dispatch.
@Suite("Selection-cursor dispatch + renderer")
struct ListCursorDispatchTests {

    // Mirrors PanelGridRendererTests.loadPanelGrid, plus a cursor-targets-fn on
    // the fake list block and a range action that records the activated key — so
    // ⏎ activation is observable.
    private func loadCursor() throws -> SchemeEngine {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("Scheme directory not found"); throw SchemeTestError.noSchemeDir
        }
        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser state-machine))")
        try engine.evaluate("(import (modaliser event-dispatch) (modaliser dsl) (modaliser dom))")
        try engine.evaluate("(import (modaliser list-cursor))")
        for file in ["ui/css.scm", "ui/overlay.scm"] {
            try engine.evaluateFile(joinPath(schemePath, file))
        }
        // A live-list block-spec shaped like window:list-block: a 'type, an
        // on-render-fn (return-and-merge live rows), a 'cursor-targets-fn (the
        // movable targets accessor — a stable thunk over a 3-row alist), and a
        // hidden 1.. digit range whose action records which key fired.
        try engine.evaluate("""
          (define activated-key #f)
          (define cursor-rows (list (cons "1" 'win-a) (cons "2" 'win-b) (cons "3" 'win-c)))
          (define (cursor-targets) cursor-rows)
          (define (fake-list-block)
            (list (cons 'type 'window-list)
                  (cons 'on-render-fn
                        (lambda ()
                          (list (cons 'windows
                                  (list (list (cons 'label "1") (cons 'app "A") (cons 'title "x") (cons 'visible #t))
                                        (list (cons 'label "2") (cons 'app "B") (cons 'title "y") (cons 'visible #t))
                                        (list (cons 'label "3") (cons 'app "C") (cons 'title "z") (cons 'visible #t)))))))
                  (cons 'cursor-targets-fn cursor-targets)
                  (cons 'block-children
                        (list (cons (cons 'hidden #t)
                                    (key-range "1.." "Win <n>" (list "1" "2" "3")
                                      (lambda (k) (set! activated-key k))))))))
        """)
        return engine
    }

    // Rendering a screen with a live-list panel activates the cursor and the
    // panel-grid payload carries the selected index of the owning list.
    @Test func renderActivatesCursorAndPayloadCarriesSelected() throws {
        let engine = try loadCursor()
        try engine.evaluate("""
          (screen 'cur-render (panel "Live" (fake-list-block)))
          (define p (renderer-body-json 'panel-grid (lookup-tree "cur-render")))
        """)
        #expect(try engine.evaluate("(list-cursor-active?)") == .true)
        #expect(try engine.evaluate("p").asString().contains("\"selected\":0"))
    }

    // A screen with no live list leaves the cursor inert after a render pass.
    @Test func renderWithoutListClearsCursor() throws {
        let engine = try loadCursor()
        try engine.evaluate("""
          (screen 'cur-list  (panel "Live" (fake-list-block)))
          (screen 'cur-plain (panel "Cmds" (key "c" "Center" (lambda () 'ok))))
          (renderer-body-json 'panel-grid (lookup-tree "cur-list"))
        """)
        #expect(try engine.evaluate("(list-cursor-active?)") == .true)
        try engine.evaluate("(renderer-body-json 'panel-grid (lookup-tree \"cur-plain\"))")
        #expect(try engine.evaluate("(list-cursor-active?)") == .false)
    }

    // k / j move the selection cursor when one is active (binding-free keys fall
    // through to cursor nav); the payload's selected index follows.
    @Test func kAndJMoveCursor() throws {
        let engine = try loadCursor()
        try engine.evaluate("""
          (screen 'cur-kj (panel "Live" (fake-list-block)))
          (modal-enter (lookup-tree "cur-kj") F18)
          (renderer-body-json 'panel-grid (lookup-tree "cur-kj"))
        """)
        try engine.evaluate("(modal-handle-key \"j\")")
        #expect(try engine.evaluate("(list-cursor-index)") == .fixnum(1))
        try engine.evaluate("(modal-handle-key \"j\")")
        #expect(try engine.evaluate("(list-cursor-index)") == .fixnum(2))
        try engine.evaluate("(modal-handle-key \"k\")")
        #expect(try engine.evaluate("(list-cursor-index)") == .fixnum(1))
        // The modal stays active — cursor nav never exits.
        #expect(try engine.evaluate("modal-active?") == .true)
    }

    // ↑ / ↓ (arrow keycodes, which keycode->char doesn't map) move the cursor
    // through modal-key-handler.
    @Test func arrowKeysMoveCursor() throws {
        let engine = try loadCursor()
        try engine.evaluate("""
          (screen 'cur-arrow (panel "Live" (fake-list-block)))
          (modal-enter (lookup-tree "cur-arrow") F18)
          (renderer-body-json 'panel-grid (lookup-tree "cur-arrow"))
        """)
        #expect(try engine.evaluate("(modal-key-handler DOWN 0)") == .true)
        #expect(try engine.evaluate("(list-cursor-index)") == .fixnum(1))
        #expect(try engine.evaluate("(modal-key-handler DOWN 0)") == .true)
        #expect(try engine.evaluate("(list-cursor-index)") == .fixnum(2))
        #expect(try engine.evaluate("(modal-key-handler UP 0)") == .true)
        #expect(try engine.evaluate("(list-cursor-index)") == .fixnum(1))
    }

    // ⏎ activates the highlighted row: it dispatches the row's digit through the
    // existing range-command path, so the digit action fires with the selected
    // label and the (transient) modal exits afterwards.
    @Test func returnActivatesHighlightedRow() throws {
        let engine = try loadCursor()
        try engine.evaluate("""
          (screen 'cur-enter (panel "Live" (fake-list-block)))
          (modal-enter (lookup-tree "cur-enter") F18)
          (renderer-body-json 'panel-grid (lookup-tree "cur-enter"))
          (modal-handle-key "j")
        """)  // move to row index 1 (label "2")
        #expect(try engine.evaluate("(modal-key-handler RETURN 0)") == .true)
        #expect(try engine.evaluate("activated-key") == .makeString("2"))
        // ⏎ on a list selection activates and exits (transient cleanup).
        #expect(try engine.evaluate("modal-active?") == .false)
    }

    // With no cursor active, Return still confirm-exits (unchanged behaviour).
    @Test func returnWithoutCursorConfirmExits() throws {
        let engine = try loadCursor()
        try engine.evaluate("""
          (screen 'cur-noenter (panel "Cmds" (key "c" "Center" (lambda () 'ok))))
          (modal-enter (lookup-tree "cur-noenter") F18)
          (renderer-body-json 'panel-grid (lookup-tree "cur-noenter"))
        """)
        #expect(try engine.evaluate("(list-cursor-active?)") == .false)
        #expect(try engine.evaluate("(modal-key-handler RETURN 0)") == .true)
        #expect(try engine.evaluate("modal-active?") == .false)
        #expect(try engine.evaluate("activated-key") == .false)
    }

    // An explicit binding for j wins over cursor nav — find-child resolves the
    // command before the unbound-key cursor fallback runs.
    @Test func boundKeyWinsOverCursorNav() throws {
        let engine = try loadCursor()
        try engine.evaluate("""
          (define j-fired #f)
          (screen 'cur-jbound
            (panel "Live"
              (key "j" "Jump" (lambda () (set! j-fired #t)))
              (fake-list-block)))
          (modal-enter (lookup-tree "cur-jbound") F18)
          (renderer-body-json 'panel-grid (lookup-tree "cur-jbound"))
          (modal-handle-key "j")
        """)
        #expect(try engine.evaluate("j-fired") == .true)
        // The cursor did not move — the bound command consumed the key.
        #expect(try engine.evaluate("(list-cursor-index)") == .fixnum(0))
    }

    // Each live-list JS renderer marks the row at block.selected with the
    // .is-focused class the base.css cursor styling (accent left-bar + tint)
    // attaches to. The block CSS for it-row gains the .is-focused rule its
    // wl-row / ip-row siblings already carry (added by visual-skin-k5).
    @Test func jsRenderersMarkSelectedRowAndCssCoversAllLists() throws {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("scheme path"); throw SchemeTestError.noSchemeDir
        }
        for block in ["window-list", "iterm-panes", "iterm-tabs"] {
            let js = try String(
                contentsOfFile: joinPath(schemePath, "lib/modaliser/blocks/\(block).js"),
                encoding: .utf8)
            #expect(js.contains("is-focused"), "\(block).js should mark the focused row")
            #expect(js.contains("selected"), "\(block).js should read block.selected")
        }
        let css = try String(contentsOfFile: joinPath(schemePath, "base.css"), encoding: .utf8)
        #expect(css.contains(".it-row.is-focused"))
    }

    // The footer advertises the nav keys whenever a list cursor is active.
    @Test func footerAdvertisesNavKeysWhenCursorActive() throws {
        let engine = try loadCursor()
        try engine.evaluate("""
          (screen 'cur-foot (panel "Live" (fake-list-block)))
          (renderer-body-json 'panel-grid (lookup-tree "cur-foot"))
          (define f (footer-html-for-path '()))
        """)
        let footer = try engine.evaluate("f").asString()
        #expect(footer.contains("move"))
        #expect(footer.contains("select"))
    }
}
