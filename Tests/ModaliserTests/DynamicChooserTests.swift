import Foundation
import Testing
import LispKit
@testable import Modaliser

private func joinPath(_ base: String, _ component: String) -> String {
    base.hasSuffix("/") ? base + component : base + "/" + component
}

private enum DynamicChooserTestError: Error {
    case noSchemeDir
}

@Suite("Dynamic Chooser Mode")
struct DynamicChooserTests {

    /// Load all modules with WebView stubs (including webview-eval).
    private func loadAllModules() throws -> SchemeEngine {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("Scheme directory not found")
            throw DynamicChooserTestError.noSchemeDir
        }

        // Stub WebView primitives — capture calls for assertions
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

    // MARK: - Dynamic selector opens chooser

    @Test func dynamicSelectorOpensChooserWithoutItems() throws {
        let engine = try loadAllModules()
        try engine.evaluate("""
            (define search-queries '())
            (define (my-dynamic-search query)
              (set! search-queries (cons query search-queries)))
            (define-tree 'global
              (selector "g" "Google"
                'prompt "Search Google…"
                'dynamic-search my-dynamic-search
                'on-select (lambda (item) #t)))
            """)

        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        try engine.evaluate("(modal-handle-key \"g\")")

        // Chooser should be open
        #expect(try engine.evaluate("chooser-open?") == .true)
        // Items should be empty (no static source)
        #expect(try engine.evaluate("(length chooser-items)").asInt64() == 0)
        // Dynamic search callback should be set
        #expect(try engine.evaluate("(procedure? chooser-dynamic-search)") == .true)
    }

    // MARK: - Ready message routes to dynamic callback

    @Test func readyMessageCallsDynamicSearch() throws {
        let engine = try loadAllModules()
        try engine.evaluate("""
            (define search-queries '())
            (define (my-dynamic-search query)
              (set! search-queries (cons query search-queries)))
            (define-tree 'global
              (selector "g" "Google"
                'prompt "Search…"
                'dynamic-search my-dynamic-search
                'on-select (lambda (item) #t)))
            """)

        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        try engine.evaluate("(modal-handle-key \"g\")")

        // Simulate JS ready message
        try engine.evaluate("""
            (chooser-message-handler (list (cons 'type "ready")))
            """)

        // Dynamic callback should have been called with empty string
        #expect(try engine.evaluate("(car search-queries)").asString() == "")
    }

    // MARK: - Search message routes to dynamic callback

    @Test func searchMessageCallsDynamicSearch() throws {
        let engine = try loadAllModules()
        try engine.evaluate("""
            (define search-queries '())
            (define (my-dynamic-search query)
              (set! search-queries (cons query search-queries)))
            (define-tree 'global
              (selector "g" "Google"
                'prompt "Search…"
                'dynamic-search my-dynamic-search
                'on-select (lambda (item) #t)))
            """)

        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        try engine.evaluate("(modal-handle-key \"g\")")

        // Simulate search message from JS
        try engine.evaluate("""
            (chooser-message-handler (list (cons 'type "search") (cons 'query "hello world")))
            """)

        // Dynamic callback should receive the query
        #expect(try engine.evaluate("(car search-queries)").asString() == "hello world")
        // Query state should be updated
        #expect(try engine.evaluate("chooser-query").asString() == "hello world")
    }

    // MARK: - chooser-push-results updates items

    @Test func pushResultsUpdatesChooserItems() throws {
        let engine = try loadAllModules()
        try engine.evaluate("""
            (define (my-dynamic-search query)
              (chooser-push-results
                (list (list (cons 'text "Result A"))
                      (list (cons 'text "Result B")))))
            (define-tree 'global
              (selector "g" "Google"
                'prompt "Search…"
                'dynamic-search my-dynamic-search
                'on-select (lambda (item) #t)))
            """)

        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        try engine.evaluate("(modal-handle-key \"g\")")

        // Trigger search which pushes results
        try engine.evaluate("""
            (chooser-message-handler (list (cons 'type "search") (cons 'query "test")))
            """)

        // Items should be updated
        #expect(try engine.evaluate("(length chooser-items)").asInt64() == 2)
        #expect(try engine.evaluate("(cdr (assoc 'text (car chooser-items)))").asString() == "Result A")
    }

    // MARK: - Push results generates JS updateResults call

    @Test func pushResultsCallsJsUpdateResults() throws {
        let engine = try loadAllModules()
        try engine.evaluate("""
            (define (my-dynamic-search query)
              (chooser-push-results
                (list (list (cons 'text "Alpha"))
                      (list (cons 'text "Beta")))))
            (define-tree 'global
              (selector "g" "Google"
                'prompt "Search…"
                'dynamic-search my-dynamic-search
                'on-select (lambda (item) #t)))
            """)

        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        try engine.evaluate("(modal-handle-key \"g\")")

        // Clear eval calls from setup
        try engine.evaluate("(set! webview-eval-calls '())")

        // Trigger dynamic search
        try engine.evaluate("""
            (chooser-message-handler (list (cons 'type "search") (cons 'query "test")))
            """)

        // Should have called webview-eval with JSON containing both items
        let js = try engine.evaluate("(cdr (car webview-eval-calls))").asString()
        #expect(js.contains("Alpha"))
        #expect(js.contains("Beta"))
        #expect(js.contains("updateResults"))
    }

    // MARK: - Select works with dynamic items

    @Test func selectWorksWithDynamicItems() throws {
        let engine = try loadAllModules()
        try engine.evaluate("""
            (define selected-item #f)
            (define (my-dynamic-search query)
              (chooser-push-results
                (list (list (cons 'text "First"))
                      (list (cons 'text "Second"))
                      (list (cons 'text "Third")))))
            (define-tree 'global
              (selector "g" "Google"
                'prompt "Search…"
                'dynamic-search my-dynamic-search
                'on-select (lambda (item) (set! selected-item item))))
            """)

        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        try engine.evaluate("(modal-handle-key \"g\")")

        // Trigger search to populate items
        try engine.evaluate("""
            (chooser-message-handler (list (cons 'type "search") (cons 'query "test")))
            """)

        // Simulate selecting item at index 1 (Second)
        try engine.evaluate("""
            (chooser-message-handler (list (cons 'type "select") (cons 'originalIndex 1)))
            """)

        // on-select should receive the correct item
        #expect(try engine.evaluate("chooser-open?") == .false)
        #expect(try engine.evaluate("(cdr (assoc 'text selected-item))").asString() == "Second")
    }

    // MARK: - Close resets dynamic search state

    @Test func closeResetsDynamicSearchState() throws {
        let engine = try loadAllModules()
        try engine.evaluate("""
            (define (my-dynamic-search query) #t)
            (define-tree 'global
              (selector "g" "Google"
                'prompt "Search…"
                'dynamic-search my-dynamic-search
                'on-select (lambda (item) #t)))
            """)

        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        try engine.evaluate("(modal-handle-key \"g\")")
        #expect(try engine.evaluate("(procedure? chooser-dynamic-search)") == .true)

        try engine.evaluate("(close-chooser)")
        #expect(try engine.evaluate("chooser-dynamic-search") == .false)
    }

    // MARK: - Static selector still works (regression)

    @Test func staticSelectorStillRoutesThroughAsyncSearch() throws {
        let engine = try loadAllModules()
        try engine.evaluate("""
            (define test-items
              (list (list (cons 'text "Safari"))
                    (list (cons 'text "Chrome"))))
            (define (test-source) test-items)
            (define-tree 'global
              (selector "a" "Find App"
                'prompt "Find app…"
                'source test-source
                'on-select (lambda (item) #t)))
            """)

        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        try engine.evaluate("(modal-handle-key \"a\")")

        // Chooser should be open with items cached
        #expect(try engine.evaluate("chooser-open?") == .true)
        #expect(try engine.evaluate("(length chooser-items)").asInt64() == 2)
        // Dynamic search should NOT be set
        #expect(try engine.evaluate("chooser-dynamic-search") == .false)
    }

    // MARK: - JSON escaping in push results

    @Test func pushResultsEscapesSpecialCharacters() throws {
        let engine = try loadAllModules()
        try engine.evaluate("""
            (define (my-dynamic-search query)
              (chooser-push-results
                (list (list (cons 'text "He said \\"hello\\""))
                      (list (cons 'text "Line1\\nLine2")))))
            (define-tree 'global
              (selector "g" "Google"
                'prompt "Search…"
                'dynamic-search my-dynamic-search
                'on-select (lambda (item) #t)))
            """)

        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        try engine.evaluate("(modal-handle-key \"g\")")
        try engine.evaluate("(set! webview-eval-calls '())")

        try engine.evaluate("""
            (chooser-message-handler (list (cons 'type "search") (cons 'query "test")))
            """)

        // Should not crash and JS should contain properly escaped JSON
        let js = try engine.evaluate("(cdr (car webview-eval-calls))").asString()
        #expect(js.contains("updateResults"))
        // Verify double-quotes are escaped in JSON
        #expect(js.contains("\\\"hello\\\""), "Double-quotes should be escaped")
        // Verify newlines are escaped in JSON
        #expect(js.contains("\\n"), "Newlines should be escaped")
    }
}
