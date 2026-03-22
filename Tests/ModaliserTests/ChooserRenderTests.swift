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

        let files = [
            "lib/util.scm",
            "core/keymap.scm",
            "ui/dom.scm",
            "ui/css.scm",
            "core/state-machine.scm",
            "core/event-dispatch.scm",
            "ui/overlay.scm",
            "ui/chooser.scm",
            "lib/dsl.scm",
        ]
        for file in files {
            try engine.evaluateFile(joinPath(schemePath, file))
        }
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
    }

    /// Set up chooser-items so render-chooser-html can look up source items.
    private let testItemsSetup = """
        (set! chooser-items
          (list (list (cons 'text "Safari") (cons 'bundleId "com.apple.Safari"))
                (list (cons 'text "Chrome") (cons 'bundleId "com.google.Chrome"))))
        """

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
        let engine = try loadAllModules()
        try engine.evaluate(testItemsSetup)
        let html = try engine.evaluate("""
            (render-chooser-html "Find app…"
              '((0 "Safari" ()) (1 "Chrome" ()))
              "" 1 #f '())
            """).asString()
        #expect(html.contains("selected"))
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
        #expect(try engine.evaluate("chooser-open?") == .false)
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
}
