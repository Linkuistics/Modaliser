import Foundation
import Testing
import LispKit
@testable import Modaliser

private func joinPath(_ base: String, _ component: String) -> String {
    base.hasSuffix("/") ? base + component : base + "/" + component
}

@Suite("Overlay Rendering (ui/overlay.scm)")
struct OverlayRenderTests {

    private func loadOverlay() throws -> SchemeEngine {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("Scheme directory not found")
            throw SchemeTestError.noSchemeDir
        }
        let files = [
            "lib/util.scm",
            "core/keymap.scm",
            "ui/dom.scm",
            "ui/css.scm",
            "core/state-machine.scm",
            "core/event-dispatch.scm",
            "ui/overlay.scm",
            "lib/dsl.scm",
        ]
        for file in files {
            try engine.evaluateFile(joinPath(schemePath, file))
        }
        return engine
    }

    // MARK: - render-overlay-html (pure)

    @Test func renderOverlayHtmlProducesValidDocument() throws {
        let engine = try loadOverlay()
        try engine.evaluate("""
            (define-tree 'global
              (key "s" "Safari" (lambda () 'ok))
              (key "f" "Finder" (lambda () 'ok)))
            """)
        let result = try engine.evaluate("""
            (render-overlay-html (lookup-tree "global") '())
            """)
        let html = try result.asString()
        #expect(html.hasPrefix("<!DOCTYPE html>"))
        #expect(html.contains("<div class=\"overlay\">"))
        #expect(html.contains("Global"))
    }

    @Test func renderOverlayHtmlShowsEntries() throws {
        let engine = try loadOverlay()
        try engine.evaluate("""
            (define-tree 'global
              (key "s" "Safari" (lambda () 'ok))
              (key "f" "Finder" (lambda () 'ok)))
            """)
        let html = try engine.evaluate("""
            (render-overlay-html (lookup-tree "global") '())
            """).asString()
        #expect(html.contains("Safari"))
        #expect(html.contains("Finder"))
        #expect(html.contains("entry-key"))
        #expect(html.contains("entry-arrow"))
    }

    @Test func renderOverlayHtmlSortsEntriesByKey() throws {
        let engine = try loadOverlay()
        try engine.evaluate("""
            (define-tree 'global
              (key "z" "Zoom" (lambda () 'ok))
              (key "a" "Alacritty" (lambda () 'ok))
              (key "m" "Messages" (lambda () 'ok)))
            """)
        let html = try engine.evaluate("""
            (render-overlay-html (lookup-tree "global") '())
            """).asString()
        // 'a' should appear before 'm', and 'm' before 'z'
        let aPos = html.range(of: "Alacritty")!.lowerBound
        let mPos = html.range(of: "Messages")!.lowerBound
        let zPos = html.range(of: "Zoom")!.lowerBound
        #expect(aPos < mPos)
        #expect(mPos < zPos)
    }

    @Test func renderOverlayHtmlShowsGroupWithEllipsis() throws {
        let engine = try loadOverlay()
        try engine.evaluate("""
            (define-tree 'global
              (group "w" "Windows"
                (key "c" "Center" (lambda () 'ok))))
            """)
        let html = try engine.evaluate("""
            (render-overlay-html (lookup-tree "global") '())
            """).asString()
        // Group entries show label with ellipsis and group-label class
        #expect(html.contains("Windows \u{2026}"))
        #expect(html.contains("group-label"))
    }

    @Test func renderOverlayHtmlWithPath() throws {
        let engine = try loadOverlay()
        try engine.evaluate("""
            (define-tree 'global
              (group "w" "Windows"
                (key "c" "Center" (lambda () 'ok))
                (key "m" "Maximize" (lambda () 'ok))))
            """)
        let html = try engine.evaluate("""
            (render-overlay-html (lookup-tree "global") '("w"))
            """).asString()
        // Should show Windows' children, not root
        #expect(html.contains("Center"))
        #expect(html.contains("Maximize"))
        // Header should show breadcrumb with Global > w
        #expect(html.contains("Global"))
        #expect(html.contains("w"))
    }

    @Test func renderOverlayHtmlIncludesCSS() throws {
        let engine = try loadOverlay()
        try engine.evaluate("""
            (define-tree 'global
              (key "s" "Safari" (lambda () 'ok)))
            """)
        let html = try engine.evaluate("""
            (render-overlay-html (lookup-tree "global") '())
            """).asString()
        // Should include base.css content in a style tag
        #expect(html.contains("<style>"))
        #expect(html.contains("--overlay-bg"))
    }

    @Test func renderOverlayHtmlEscapesLabelContent() throws {
        let engine = try loadOverlay()
        try engine.evaluate("""
            (define-tree 'global
              (key "s" "Open <Script>" (lambda () 'ok)))
            """)
        let html = try engine.evaluate("""
            (render-overlay-html (lookup-tree "global") '())
            """).asString()
        // Label should be HTML-escaped
        #expect(html.contains("&lt;Script&gt;"))
        #expect(!html.contains("<Script>"))
    }

    @Test func renderOverlayHtmlSpaceKeyDisplaysSymbol() throws {
        let engine = try loadOverlay()
        try engine.evaluate("""
            (define-tree 'global
              (key " " "Space action" (lambda () 'ok)))
            """)
        let html = try engine.evaluate("""
            (render-overlay-html (lookup-tree "global") '())
            """).asString()
        #expect(html.contains("\u{2423}"))
    }

    // MARK: - Overlay state

    @Test func overlayProceduresExist() throws {
        let engine = try loadOverlay()
        #expect(try engine.evaluate("(procedure? show-overlay)") == .true)
        #expect(try engine.evaluate("(procedure? update-overlay)") == .true)
        #expect(try engine.evaluate("(procedure? hide-overlay)") == .true)
        #expect(try engine.evaluate("(procedure? render-overlay-html)") == .true)
    }

    @Test func overlayStartsClosed() throws {
        let engine = try loadOverlay()
        #expect(try engine.evaluate("overlay-open?") == .false)
    }

    @Test func setHostHeaderStoresAllThreeFields() throws {
        let engine = try loadOverlay()
        try engine.evaluate("""
            (set-host-header!
              'name "my-server"
              'background "#7a1f3d"
              'foreground "#ffffff")
            """)
        #expect(try engine.evaluate("host-header-name").asString() == "my-server")
        #expect(try engine.evaluate("host-header-background").asString() == "#7a1f3d")
        #expect(try engine.evaluate("host-header-foreground").asString() == "#ffffff")
    }

    @Test func setHostHeaderAcceptsNameOnly() throws {
        let engine = try loadOverlay()
        try engine.evaluate("(set-host-header! 'name \"local\")")
        #expect(try engine.evaluate("host-header-name").asString() == "local")
        #expect(try engine.evaluate("host-header-background") == .false)
        #expect(try engine.evaluate("host-header-foreground") == .false)
    }

    @Test func setHostHeaderRejectsUnknownKeyword() throws {
        let engine = try loadOverlay()
        #expect(throws: (any Error).self) {
            try engine.evaluate("(set-host-header! 'name \"x\" 'unknown 1)")
        }
    }

    @Test func hostHeaderCssEmptyWhenNoColoursSet() throws {
        let engine = try loadOverlay()
        try engine.evaluate("(set-host-header! 'name \"x\")")
        let css = try engine.evaluate("(host-header-css)").asString()
        #expect(css == "")
    }

    @Test func hostHeaderCssEmitsBothVariables() throws {
        let engine = try loadOverlay()
        try engine.evaluate("""
            (set-host-header! 'name "x" 'background "#000" 'foreground "#fff")
            """)
        let css = try engine.evaluate("(host-header-css)").asString()
        #expect(css.contains(":root"))
        #expect(css.contains("--color-host-bg: #000"))
        #expect(css.contains("--color-host-fg: #fff"))
    }

    @Test func hostHeaderCssEmitsOnlyTheSetVariable() throws {
        let engine = try loadOverlay()
        try engine.evaluate("(set-host-header! 'name \"x\" 'background \"#abc\")")
        let css = try engine.evaluate("(host-header-css)").asString()
        #expect(css.contains("--color-host-bg: #abc"))
        #expect(!css.contains("--color-host-fg"))
    }
}
