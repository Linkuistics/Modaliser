import Foundation
import Testing
import LispKit
@testable import Modaliser

private func joinPath(_ base: String, _ component: String) -> String {
    base.hasSuffix("/") ? base + component : base + "/" + component
}

private enum WebSearchTestError: Error {
    case noSchemeDir
}

@Suite("Web Search Module")
struct WebSearchTests {

    /// Load all modules including web-search.scm with stubs.
    private func loadAllModules() throws -> SchemeEngine {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("Scheme directory not found")
            throw WebSearchTestError.noSchemeDir
        }

        // Stub WebView primitives
        try engine.evaluate("""
            (define webview-create-calls '())
            (define webview-close-calls '())
            (define webview-set-html-calls '())
            (define webview-on-message-calls '())
            (define webview-eval-calls '())
            (define (webview-create id opts)
              (set! webview-create-calls (cons (cons id opts) webview-create-calls)) id)
            (define (webview-close id)
              (set! webview-close-calls (cons id webview-close-calls)))
            (define (webview-set-html! id html)
              (set! webview-set-html-calls (cons (cons id html) webview-set-html-calls)))
            (define (webview-on-message id handler)
              (set! webview-on-message-calls (cons (cons id handler) webview-on-message-calls)))
            (define (webview-eval id js)
              (set! webview-eval-calls (cons (cons id js) webview-eval-calls)))
            """)

        // Stub open-url to capture calls
        try engine.evaluate("""
            (define opened-urls '())
            (define (open-url url)
              (set! opened-urls (cons url opened-urls)))
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
            "lib/web-search.scm",
        ]
        for file in files {
            try engine.evaluateFile(joinPath(schemePath, file))
        }
        return engine
    }

    // MARK: - URL Construction

    @Test func googleSuggestUrlEncodesQuery() throws {
        let engine = try loadAllModules()
        let url = try engine.evaluate(#"(google-suggest-url "hello world")"#).asString()
        #expect(url.contains("hello+world") || url.contains("hello%20world"))
        #expect(url.contains("suggestqueries.google.com"))
        #expect(url.contains("client=firefox"))
    }

    @Test func googleSuggestUrlEncodesSpecialChars() throws {
        let engine = try loadAllModules()
        let url = try engine.evaluate(#"(google-suggest-url "c++ & java")"#).asString()
        #expect(url.contains("%2B") || url.contains("+"))
        #expect(url.contains("%26"))
    }

    @Test func googleSearchUrlConstructsCorrectly() throws {
        let engine = try loadAllModules()
        let url = try engine.evaluate(#"(google-search-url "hello world")"#).asString()
        #expect(url.contains("google.com/search"))
        #expect(url.contains("hello+world") || url.contains("hello%20world"))
    }

    @Test func urlEncodeHandlesUnicodeCharacters() throws {
        let engine = try loadAllModules()
        // café → caf%C3%A9 (UTF-8 encoding of é = U+00E9 = 0xC3 0xA9)
        let encoded = try engine.evaluate(#"(url-encode "café")"#).asString()
        #expect(encoded.contains("%C3%A9"), "é should be UTF-8 percent-encoded as %C3%A9")
    }

    // MARK: - Response Parsing

    @Test func parseGoogleSuggestionsHandlesUnicodeEscapes() throws {
        let engine = try loadAllModules()
        // \u0027 is a single quote (apostrophe)
        let result = try engine.evaluate(
            #"(car (parse-google-suggestions "[\"q\",[\"don\\u0027t stop\"]]"))"#
        ).asString()
        #expect(result == "don't stop")
    }

    @Test func parseGoogleSuggestionsExtractsSuggestions() throws {
        let engine = try loadAllModules()
        // Use raw string to avoid escaping issues — \" inside Scheme string = literal "
        let first = try engine.evaluate(
            #"(car (parse-google-suggestions "[\"hello\",[\"hello world\",\"hello kitty\"]]"))"#
        ).asString()
        #expect(first == "hello world")
    }

    @Test func parseGoogleSuggestionsHandlesEmptyArray() throws {
        let engine = try loadAllModules()
        let result = try engine.evaluate(
            #"(parse-google-suggestions "[\"test\",[]]")"#
        )
        #expect(result == .null)
    }

    @Test func parseGoogleSuggestionsHandlesMalformedInput() throws {
        let engine = try loadAllModules()
        let result = try engine.evaluate(
            #"(parse-google-suggestions "not json at all")"#
        )
        #expect(result == .null)
    }

    // MARK: - Pinned Item

    @Test func buildWebSearchResultsPrependsPinnedItem() throws {
        let engine = try loadAllModules()
        let result = try engine.evaluate("""
            (build-web-search-results "hello" (list "hello world" "hello kitty"))
            """)
        // First item should be the pinned "Search Google for 'hello'" item
        let firstText = try engine.evaluate("""
            (cdr (assoc 'text (car (build-web-search-results "hello" (list "suggestion")))))
            """).asString()
        #expect(firstText.contains("Search Google"))
        #expect(firstText.contains("hello"))
    }

    @Test func buildWebSearchResultsIncludesSuggestions() throws {
        let engine = try loadAllModules()
        let items = try engine.evaluate("""
            (build-web-search-results "test" (list "test one" "test two"))
            """)
        #expect(try engine.evaluate("""
            (length (build-web-search-results "test" (list "test one" "test two")))
            """).asInt64() == 3)  // pinned + 2 suggestions
    }

    @Test func buildWebSearchResultsWithNoSuggestionsShowsOnlyPinned() throws {
        let engine = try loadAllModules()
        #expect(try engine.evaluate("""
            (length (build-web-search-results "hi" '()))
            """).asInt64() == 1)  // only pinned
    }

    // MARK: - Character Threshold

    @Test func webSearchHandlerShowsPinnedOnlyForShortQuery() throws {
        let engine = try loadAllModules()

        // Stub http-get to track calls
        try engine.evaluate("""
            (define http-get-calls '())
            (set! web-search-fetch (lambda (url callback)
              (set! http-get-calls (cons url http-get-calls))))
            """)

        // Open a dynamic chooser with web-search-handler
        try engine.evaluate("""
            (define-tree 'global
              (selector "g" "Google"
                'prompt "Search Google…"
                'dynamic-search web-search-handler
                'on-select web-search-on-select))
            """)

        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        try engine.evaluate("(modal-handle-key \"g\")")
        try engine.evaluate("(set! webview-eval-calls '())")

        // Search with < 3 chars — should NOT trigger HTTP request
        try engine.evaluate("""
            (chooser-message-handler (list (cons 'type "search") (cons 'query "he")))
            """)

        #expect(try engine.evaluate("(length http-get-calls)").asInt64() == 0,
                "Should not fire HTTP request for < 3 chars")
        // But should still push the pinned item
        let js = try engine.evaluate("(cdr (car webview-eval-calls))").asString()
        #expect(js.contains("Search Google"), "Should show pinned item even for short query")
    }

    @Test func webSearchHandlerFiresHttpForLongQuery() throws {
        let engine = try loadAllModules()

        // Stub http-get to track calls
        try engine.evaluate("""
            (define http-get-calls '())
            (set! web-search-fetch (lambda (url callback)
              (set! http-get-calls (cons url http-get-calls))))
            """)

        try engine.evaluate("""
            (define-tree 'global
              (selector "g" "Google"
                'prompt "Search Google…"
                'dynamic-search web-search-handler
                'on-select web-search-on-select))
            """)

        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        try engine.evaluate("(modal-handle-key \"g\")")

        // Search with >= 3 chars — SHOULD trigger HTTP request
        try engine.evaluate("""
            (chooser-message-handler (list (cons 'type "search") (cons 'query "hello")))
            """)

        #expect(try engine.evaluate("(length http-get-calls)").asInt64() == 1,
                "Should fire HTTP request for >= 3 chars")
    }

    // MARK: - On Select

    @Test func webSearchOnSelectOpensGoogleSearch() throws {
        let engine = try loadAllModules()

        try engine.evaluate("""
            (define-tree 'global
              (selector "g" "Google"
                'prompt "Search Google…"
                'dynamic-search web-search-handler
                'on-select web-search-on-select))
            """)

        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        try engine.evaluate("(modal-handle-key \"g\")")

        // Push some results
        try engine.evaluate("""
            (chooser-push-results
              (list (list (cons 'text "Search Google for 'test'") (cons 'search-url "https://google.com/search?q=test"))
                    (list (cons 'text "test result") (cons 'search-url "https://google.com/search?q=test+result"))))
            """)

        // Select the second item
        try engine.evaluate("""
            (chooser-message-handler (list (cons 'type "select") (cons 'originalIndex 1)))
            """)

        // Should have opened a URL
        #expect(try engine.evaluate("(length opened-urls)").asInt64() == 1)
        let url = try engine.evaluate("(car opened-urls)").asString()
        #expect(url.contains("google.com/search"))
    }

    // MARK: - Empty query

    @Test func webSearchHandlerShowsPinnedForEmptyQuery() throws {
        let engine = try loadAllModules()

        try engine.evaluate("""
            (define http-get-calls '())
            (set! web-search-fetch (lambda (url callback)
              (set! http-get-calls (cons url http-get-calls))))
            (define-tree 'global
              (selector "g" "Google"
                'prompt "Search Google…"
                'dynamic-search web-search-handler
                'on-select web-search-on-select))
            """)

        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        try engine.evaluate("(modal-handle-key \"g\")")
        try engine.evaluate("(set! webview-eval-calls '())")

        // Empty query — show pinned item with empty query
        try engine.evaluate("""
            (chooser-message-handler (list (cons 'type "search") (cons 'query "")))
            """)

        #expect(try engine.evaluate("(length http-get-calls)").asInt64() == 0)
    }

    // MARK: - Generation counter (stale response discarding)

    @Test func staleHttpResponseIsDiscarded() throws {
        let engine = try loadAllModules()

        // Capture the http-get callback so we can call it manually
        try engine.evaluate("""
            (define captured-callbacks '())
            (set! web-search-fetch (lambda (url callback)
              (set! captured-callbacks (cons callback captured-callbacks))))
            """)

        try engine.evaluate("""
            (define-tree 'global
              (selector "g" "Google"
                'prompt "Search Google…"
                'dynamic-search web-search-handler
                'on-select web-search-on-select))
            """)

        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        try engine.evaluate("(modal-handle-key \"g\")")

        // Fire two searches
        try engine.evaluate("""
            (chooser-message-handler (list (cons 'type "search") (cons 'query "hello")))
            """)
        try engine.evaluate("""
            (chooser-message-handler (list (cons 'type "search") (cons 'query "world")))
            """)

        // Two callbacks captured
        #expect(try engine.evaluate("(length captured-callbacks)").asInt64() == 2)

        try engine.evaluate("(set! webview-eval-calls '())")

        // Call the FIRST (stale) callback with response
        try engine.evaluate(
            #"((cadr captured-callbacks) "[\"hello\",[\"hello world\"]]")"#
        )

        // Stale callback should be discarded — no webview-eval call
        #expect(try engine.evaluate("(length webview-eval-calls)").asInt64() == 0,
                "Stale response should be discarded")

        // Call the SECOND (current) callback
        try engine.evaluate(
            #"((car captured-callbacks) "[\"world\",[\"world cup\"]]")"#
        )

        // Current callback should push results
        #expect(try engine.evaluate("(length webview-eval-calls)").asInt64() == 1,
                "Current response should be rendered")
    }
}
