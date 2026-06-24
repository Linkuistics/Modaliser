import Foundation
import Testing
import LispKit
@testable import Modaliser

private func joinPath(_ base: String, _ component: String) -> String {
    base.hasSuffix("/") ? base + component : base + "/" + component
}

@Suite("Chooser Rendering")
struct ChooserRenderTests {

    /// Load all modules including chooser. Stubs WebView primitives.
    private func loadAllModules() throws -> SchemeEngine {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("Scheme directory not found")
            throw SchemeTestError.noSchemeDir
        }

        // Stub WebView primitives — track calls without creating actual NSPanels
        try engine.evaluate("""
            (define webview-create-calls '())
            (define webview-close-calls '())
            (define webview-set-html-calls '())
            (define webview-on-message-calls '())
            (define (webview-create id opts)
              (set! webview-create-calls (cons (cons id opts) webview-create-calls)) id)
            (define (webview-close id)
              (set! webview-close-calls (cons id webview-close-calls)))
            (define (webview-set-html! id html)
              (set! webview-set-html-calls (cons (cons id html) webview-set-html-calls)))
            (define (webview-on-message id handler)
              (set! webview-on-message-calls (cons (cons id handler) webview-on-message-calls)))
            """)

        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser state-machine))")
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dom))")
        let files = [
            "ui/css.scm",
            "ui/overlay.scm",
            "ui/chooser.scm",
        ]
        for file in files {
            try engine.evaluateFile(joinPath(schemePath, file))
        }
        try engine.evaluate("(import (modaliser dsl))")
        return engine
    }

    // MARK: - HTML rendering (pure functions)

    @Test func renderChooserHtmlContainsSearchInput() throws {
        let engine = try loadAllModules()
        let html = try engine.evaluate("""
            (render-chooser-html "Find app…" '() "" 0 #f '())
            """).asString()
        #expect(html.contains("<input"))
        #expect(html.contains("chooser-input"))
        #expect(html.contains("chooser"))
    }

    @Test func renderChooserHtmlContainsPrompt() throws {
        let engine = try loadAllModules()
        let html = try engine.evaluate("""
            (render-chooser-html "Find app…" '() "" 0 #f '())
            """).asString()
        #expect(html.contains("Find app"))
        #expect(html.contains("chooser-header"))
        #expect(html.contains("breadcrumb"))
    }

    /// Set up chooser-items so render-chooser-html can look up source items.
    private let testItemsSetup = """
        (set! chooser-items
          (list (list (cons 'text "Safari") (cons 'bundleId "com.apple.Safari"))
                (list (cons 'text "Chrome") (cons 'bundleId "com.google.Chrome"))))
        """

    @Test func renderChooserHtmlFooterShowsNavigationSigils() throws {
        // Footer carries item count plus the navigation hints — ⎋ exit,
        // ⏎ choose, ↑↓ select — so users have the contract visible.
        // Backspace is intentionally absent (delete-in-input belongs to
        // the input field; back-up is the overlay's concern).
        let engine = try loadAllModules()
        try engine.evaluate(testItemsSetup)
        let html = try engine.evaluate("""
            (render-chooser-html "Find app…"
              '((0 "Safari" ()) (1 "Chrome" ()))
              "" 0 #f '())
            """).asString()
        #expect(html.contains("2 items"))
        #expect(html.contains("\u{238B}"))   // ⎋ escape
        #expect(html.contains("\u{23CE}"))   // ⏎ return
        #expect(html.contains("\u{2191}"))   // ↑ up
        #expect(html.contains("\u{2193}"))   // ↓ down
        #expect(!html.contains("\u{232B}"))  // ⌫ backspace omitted
    }

    // footer-applicability-k21: at zero results there is nothing to choose or
    // select, so those hints are greyed in place (the shared .footer-hint--
    // disabled class); ⎋ exit stays live because it always applies.
    @Test func chooserFooterDimsChooseSelectAtZeroResults() throws {
        let engine = try loadAllModules()
        let footer = try engine.evaluate("(chooser-footer-html 0)").asString()
        // ⏎ choose and ↑↓ select are dimmed …
        #expect(footer.contains(
            "<span class=\"footer-hint footer-hint--disabled\">"
            + "<span class=\"sigil sigil-return\">\u{23CE}</span> choose</span>"))
        #expect(footer.contains(
            "<span class=\"footer-hint footer-hint--disabled\">"
            + "<span class=\"sigil sigil-arrows\">\u{2191}\u{2193}</span> select</span>"))
        // … but ⎋ exit is a live (undimmed) hint.
        #expect(footer.contains(
            "<span class=\"footer-hint\">"
            + "<span class=\"sigil sigil-escape\">\u{238B}</span> exit</span>"))
    }

    // At one or more results every hint applies, so none carry the disabled
    // class — the dimming restores when the list re-populates.
    @Test func chooserFooterRestoresHintsAtNonZeroResults() throws {
        let engine = try loadAllModules()
        let footer = try engine.evaluate("(chooser-footer-html 2)").asString()
        #expect(!footer.contains("footer-hint--disabled"))
        // The live hints are still wrapped in .footer-hint spans.
        #expect(footer.contains(
            "<span class=\"footer-hint\">"
            + "<span class=\"sigil sigil-return\">\u{23CE}</span> choose</span>"))
    }

    // The JS dynamic-update path (chooserFooterHtml in chooser.js) bypasses
    // Scheme on the native fuzzy-search path, so it must mirror the same
    // dimming. Assert the embedded JS source carries the disabled-class
    // mechanism keyed off the result count.
    @Test func chooserJsFooterMirrorsDisabledMechanism() throws {
        let engine = try loadAllModules()
        let js = try engine.evaluate("chooser-js").asString()
        #expect(js.contains("footer-hint--disabled"))
        // The JS footer hints fan out per-command (count > 0 gates choose/select).
        #expect(js.contains("count > 0"))
    }

    @Test func renderChooserHtmlShowsItems() throws {
        let engine = try loadAllModules()
        try engine.evaluate(testItemsSetup)
        let html = try engine.evaluate("""
            (render-chooser-html "Find app…"
              '((0 "Safari" ()) (1 "Chrome" ()))
              "" 0 #f '())
            """).asString()
        #expect(html.contains("Safari"))
        #expect(html.contains("Chrome"))
    }

    @Test func renderChooserHtmlHighlightsSelectedRow() throws {
        // The selected row carries the shared .is-focused marking (the same
        // selection-cursor class the embedded pane/window lists use), not a
        // chooser-private "selected" class.
        let engine = try loadAllModules()
        try engine.evaluate(testItemsSetup)
        let html = try engine.evaluate("""
            (render-chooser-html "Find app…"
              '((0 "Safari" ()) (1 "Chrome" ()))
              "" 1 #f '())
            """).asString()
        #expect(html.contains("is-focused"))
    }

    @Test func renderChooserHtmlUsesSharedListRowVocabulary() throws {
        // chooser-restyle-k7: result rows adopt the shared .list-row /
        // .list-main / .list-title classes so the chooser reads as one family
        // with the embedded pane/window lists. Guards against a regression to
        // the chooser-private .chooser-row* names.
        let engine = try loadAllModules()
        try engine.evaluate(testItemsSetup)
        let html = try engine.evaluate("""
            (render-chooser-html "Find app…"
              '((0 "Safari" ()) (1 "Chrome" ()))
              "" 0 #f '())
            """).asString()
        #expect(html.contains("list-row"))
        #expect(html.contains("list-main"))
        #expect(html.contains("list-title"))
        // No chooser-private row class survives. (The bare token still appears
        // in the embedded JS as the function name render-chooser-row, so match
        // the class attribute precisely rather than the substring.)
        #expect(!html.contains("class=\"chooser-row"))
    }

    @Test func renderChooserHtmlHighlightsMatchedCharacters() throws {
        let engine = try loadAllModules()
        try engine.evaluate(testItemsSetup)
        let html = try engine.evaluate("""
            (render-chooser-html "Find app…"
              '((0 "Safari" (0 2)))
              "sf" 0 #f '())
            """).asString()
        #expect(html.contains("class=\"match\""))
    }

    @Test func renderChooserHtmlShowsFooterCount() throws {
        let engine = try loadAllModules()
        try engine.evaluate(testItemsSetup)
        let html = try engine.evaluate("""
            (render-chooser-html "Find app…"
              '((0 "Safari" ()) (1 "Chrome" ()))
              "" 0 #f '())
            """).asString()
        #expect(html.contains("2"))
    }

    @Test func renderChooserHtmlShowsActionsWhenVisible() throws {
        let engine = try loadAllModules()
        try engine.evaluate(testItemsSetup)
        let html = try engine.evaluate("""
            (render-chooser-html "Find app…"
              '((0 "Safari" ()))
              "" 0 #t
              '(((name . "Open") (description . "Launch or focus") (key . primary))
                ((name . "Copy Path") (description . "Copy full path"))))
            """).asString()
        #expect(html.contains("chooser-actions"))
        #expect(html.contains("Open"))
        #expect(html.contains("Copy Path"))
    }

    @Test func renderChooserHtmlHidesActionsWhenNotVisible() throws {
        let engine = try loadAllModules()
        try engine.evaluate(testItemsSetup)
        let html = try engine.evaluate("""
            (render-chooser-html "Find app…"
              '((0 "Safari" ()))
              "" 0 #f
              '(((name . "Open") (description . "Launch"))))
            """).asString()
        #expect(!html.contains("<div class=\"chooser-actions\">"))
    }

    @Test func renderChooserHtmlShowsEmptyState() throws {
        let engine = try loadAllModules()
        let html = try engine.evaluate("""
            (render-chooser-html "Find app…" '() "xyz" 0 #f '())
            """).asString()
        #expect(html.contains("0"))
    }

    // MARK: - Highlight match rendering

    @Test func highlightMatchesWrapsMatchedChars() throws {
        let engine = try loadAllModules()
        let html = try engine.evaluate("""
            (html->string (highlight-matches "Safari" '(0 2)))
            """).asString()
        // S should be highlighted, a not, f highlighted
        #expect(html.contains("<span class=\"match\">S</span>"))
        #expect(html.contains("<span class=\"match\">f</span>"))
    }

    @Test func highlightMatchesNoIndicesReturnsPlainText() throws {
        let engine = try loadAllModules()
        let html = try engine.evaluate("""
            (html->string (highlight-matches "Safari" '()))
            """).asString()
        #expect(!html.contains("<span"))
        #expect(html.contains("Safari"))
    }

    @Test func highlightMatchesEscapesHtml() throws {
        let engine = try loadAllModules()
        let html = try engine.evaluate("""
            (html->string (highlight-matches "A&B" '(0)))
            """).asString()
        #expect(html.contains("&amp;"))
    }

    // MARK: - Chooser JavaScript

    @Test func renderChooserHtmlContainsJavaScript() throws {
        let engine = try loadAllModules()
        let html = try engine.evaluate("""
            (render-chooser-html "Find…" '() "" 0 #f '())
            """).asString()
        #expect(html.contains("postMessage"))
        #expect(html.contains("keydown"))
    }

    // MARK: - Chooser state management

    @Test func chooserStateInitializedCorrectly() throws {
        let engine = try loadAllModules()
        #expect(try engine.evaluate("(chooser-open?)") == .false)
        #expect(try engine.evaluate("chooser-items") == .null)
    }

    // MARK: - Utility functions
    // split-lines and file-basename moved to native Swift index-files

    @Test func itemDisplayTextExtractsTextField() throws {
        let engine = try loadAllModules()
        let text = try engine.evaluate("""
            (item-display-text (list (cons 'text "Safari") (cons 'path "/Apps")))
            """).asString()
        #expect(text == "Safari")
    }

    @Test func renderChooserHtmlBreadcrumbIncludesPrompt() throws {
        let engine = try loadAllModules()
        // The breadcrumb consumes modal-root-segments + (list prompt)
        try engine.evaluate("(set-modal-root-segments! '(\"Global\"))")
        let html = try engine.evaluate("""
            (render-chooser-html "Find app…" '() "" 0 #f '())
            """).asString()
        #expect(html.contains("chooser-header"))
        #expect(html.contains("breadcrumb"))
        #expect(html.contains("Global"))
        #expect(html.contains("Find app"))
        #expect(html.contains("breadcrumb-sep"))
    }

    @Test func renderChooserHtmlBreadcrumbStripsTrailingEllipsis() throws {
        // "Find app…" ends with U+2026 — the breadcrumb segment should
        // drop it so the chooser header reads "Global » Find app"
        // instead of "Global » Find app…".
        let engine = try loadAllModules()
        try engine.evaluate("(set-modal-root-segments! '(\"Global\"))")
        let html = try engine.evaluate("""
            (render-chooser-html "Find app…" '() "" 0 #f '())
            """).asString()
        let breadcrumb = String(html[html.range(of: "<header")!.lowerBound ..<
                                     html.range(of: "</header>")!.upperBound])
        #expect(breadcrumb.contains("Find app"))
        #expect(!breadcrumb.contains("Find app\u{2026}"))
    }

    @Test func chooserPromptSegmentLeavesNonEllipsisStringsAlone() throws {
        let engine = try loadAllModules()
        #expect(try engine.evaluate("(chooser-prompt-segment \"hello\")").asString()
                  == "hello")
        #expect(try engine.evaluate("(chooser-prompt-segment \"\")").asString()
                  == "")
    }

    @Test func renderChooserHtmlPrependsHostSegment() throws {
        let engine = try loadAllModules()
        try engine.evaluate(
            "(set-modal-root-segments! '(\"my-server\" \"Global\"))")
        let html = try engine.evaluate("""
            (render-chooser-html "Find app…" '() "" 0 #f '())
            """).asString()
        #expect(html.contains("my-server"))
        #expect(html.contains("Global"))
        #expect(html.contains("Find app"))
    }

}
