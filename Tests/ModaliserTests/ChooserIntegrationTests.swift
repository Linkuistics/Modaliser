import CoreGraphics
import Foundation
import Testing
import LispKit
@testable import Modaliser

private func joinPath(_ base: String, _ component: String) -> String {
    base.hasSuffix("/") ? base + component : base + "/" + component
}

private enum ChooserTestError: Error {
    case noSchemeDir
}

@Suite("Chooser Integration")
struct ChooserIntegrationTests {


    /// Load all modules with WebView and fuzzy match stubs.
    private func loadAllModules() throws -> SchemeEngine {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("Scheme directory not found")
            throw ChooserTestError.noSchemeDir
        }

        // Stub WebView primitives
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
            (define webview-eval-calls '())
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

    // MARK: - Selector triggers chooser

    @Test func selectorNodeOpensChooser() throws {
        let engine = try loadAllModules()

        // Create a source function that returns test items
        try engine.evaluate("""
            (define test-items
              (list (list (cons 'text "Safari") (cons 'bundleId "com.apple.Safari"))
                    (list (cons 'text "Chrome") (cons 'bundleId "com.google.Chrome"))
                    (list (cons 'text "Firefox") (cons 'bundleId "org.mozilla.Firefox"))))
            (define (test-source) test-items)
            (define test-selected #f)
            (define-tree 'global
              (selector "a" "Find App"
                'prompt "Find app..."
                'source test-source
                'on-select (lambda (item) (set! test-selected item))))
            """)

        // Enter modal
        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        #expect(try engine.evaluate("modal-active?") == .true)

        // Press 'a' for the selector
        try engine.evaluate("(modal-handle-key \"a\")")

        // Modal should be exited
        #expect(try engine.evaluate("modal-active?") == .false)
        // Chooser should be open
        #expect(try engine.evaluate("chooser-open?") == .true)
        // WebView should be created with activating=true
        #expect(try engine.evaluate("(not (null? webview-create-calls))") == .true)
    }

    @Test func chooserCachesSourceItems() throws {
        let engine = try loadAllModules()
        try engine.evaluate("""
            (define test-items
              (list (list (cons 'text "Safari") (cons 'bundleId "com.apple.Safari"))
                    (list (cons 'text "Chrome") (cons 'bundleId "com.google.Chrome"))))
            (define (test-source) test-items)
            (define-tree 'global
              (selector "a" "Find App"
                'prompt "Find app..."
                'source test-source
                'on-select (lambda (item) #t)))
            """)

        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        try engine.evaluate("(modal-handle-key \"a\")")

        // Chooser should have cached all source items
        #expect(try engine.evaluate("(length chooser-items)").asInt64() == 2)
        #expect(try engine.evaluate("(cdr (assoc 'text (car chooser-items)))").asString() == "Safari")
    }

    // MARK: - Search filtering

    @Test func searchUpdatesQueryState() throws {
        let engine = try loadAllModules()
        try engine.evaluate("""
            (define test-items
              (list (list (cons 'text "Safari"))
                    (list (cons 'text "Chrome"))
                    (list (cons 'text "Firefox"))))
            (define (test-source) test-items)
            (define-tree 'global
              (selector "a" "Find"
                'prompt "Find..."
                'source test-source
                'on-select (lambda (item) #t)))
            """)

        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        try engine.evaluate("(modal-handle-key \"a\")")

        // Simulate search message
        try engine.evaluate("""
            (chooser-handle-search "saf")
            """)

        // Query state should be updated and selection reset
        #expect(try engine.evaluate("chooser-query").asString() == "saf")
        #expect(try engine.evaluate("chooser-selected-index").asInt64() == 0)
    }

    // MARK: - Selection index (navigation is handled by JS)

    @Test func selectionIndexStartsAtZero() throws {
        let engine = try loadAllModules()
        try engine.evaluate("""
            (define test-items
              (list (list (cons 'text "Alpha"))
                    (list (cons 'text "Beta"))
                    (list (cons 'text "Charlie"))))
            (define (test-source) test-items)
            (define-tree 'global
              (selector "a" "Find"
                'prompt "Find..."
                'source test-source
                'on-select (lambda (item) #t)))
            """)

        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        try engine.evaluate("(modal-handle-key \"a\")")
        #expect(try engine.evaluate("chooser-selected-index").asInt64() == 0)
    }

    // MARK: - Selection

    @Test func selectCallsOnSelectWithItem() throws {
        let engine = try loadAllModules()
        try engine.evaluate("""
            (define test-selected #f)
            (define test-items
              (list (list (cons 'text "Safari") (cons 'bundleId "com.apple.Safari"))
                    (list (cons 'text "Chrome") (cons 'bundleId "com.google.Chrome"))))
            (define (test-source) test-items)
            (define-tree 'global
              (selector "a" "Find App"
                'prompt "Find app..."
                'source test-source
                'on-select (lambda (item) (set! test-selected item))))
            """)

        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        try engine.evaluate("(modal-handle-key \"a\")")

        // Select Chrome (originalIndex 1) via message handler
        try engine.evaluate("""
            (chooser-message-handler (list (cons 'type "select") (cons 'originalIndex 1)))
            """)

        // on-select should have been called with the Chrome item
        #expect(try engine.evaluate("chooser-open?") == .false)
        #expect(try engine.evaluate("test-selected") != .false)
        let text = try engine.evaluate("(cdr (assoc 'text test-selected))").asString()
        #expect(text == "Chrome")
    }

    // MARK: - Cancel

    @Test func cancelClosesChooser() throws {
        let engine = try loadAllModules()
        try engine.evaluate("""
            (define test-items (list (list (cons 'text "Safari"))))
            (define (test-source) test-items)
            (define-tree 'global
              (selector "a" "Find"
                'prompt "Find..."
                'source test-source
                'on-select (lambda (item) #t)))
            """)

        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        try engine.evaluate("(modal-handle-key \"a\")")
        #expect(try engine.evaluate("chooser-open?") == .true)

        // Cancel via message handler
        try engine.evaluate("(close-chooser)")
        #expect(try engine.evaluate("chooser-open?") == .false)
    }

    // MARK: - Actions panel

    @Test func toggleActionsShowsPanel() throws {
        let engine = try loadAllModules()
        try engine.evaluate("""
            (define test-items (list (list (cons 'text "Safari"))))
            (define (test-source) test-items)
            (define-tree 'global
              (selector "a" "Find"
                'prompt "Find..."
                'source test-source
                'on-select (lambda (item) #t)
                'actions (list
                  (action "Open" 'description "Launch" 'key 'primary)
                  (action "Copy" 'description "Copy path"))))
            """)

        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        try engine.evaluate("(modal-handle-key \"a\")")
        #expect(try engine.evaluate("chooser-actions-visible?") == .false)

        try engine.evaluate("(chooser-handle-toggle-actions)")
        #expect(try engine.evaluate("chooser-actions-visible?") == .true)

        try engine.evaluate("(chooser-handle-toggle-actions)")
        #expect(try engine.evaluate("chooser-actions-visible?") == .false)
    }

    // MARK: - Secondary action

    @Test func secondaryActionExecutes() throws {
        let engine = try loadAllModules()
        try engine.evaluate("""
            (define secondary-fired #f)
            (define test-items
              (list (list (cons 'text "Safari") (cons 'path "/Apps/Safari.app"))))
            (define (test-source) test-items)
            (define-tree 'global
              (selector "a" "Find"
                'prompt "Find..."
                'source test-source
                'on-select (lambda (item) #t)
                'actions (list
                  (action "Open" 'description "Launch" 'key 'primary
                    'run (lambda (item) #t))
                  (action "Reveal" 'description "Show in Finder" 'key 'secondary
                    'run (lambda (item) (set! secondary-fired #t))))))
            """)

        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        try engine.evaluate("(modal-handle-key \"a\")")

        // Secondary action on first item (index 0)
        try engine.evaluate("""
            (chooser-message-handler (list (cons 'type "secondary-action") (cons 'originalIndex 0)))
            """)

        #expect(try engine.evaluate("secondary-fired") == .true)
        #expect(try engine.evaluate("chooser-open?") == .false)
    }

    // MARK: - Message handler routing

    @Test func messageHandlerRoutesCorrectly() throws {
        let engine = try loadAllModules()
        try engine.evaluate("""
            (define test-items (list (list (cons 'text "Alpha")) (list (cons 'text "Beta"))))
            (define (test-source) test-items)
            (define test-selected #f)
            (define-tree 'global
              (selector "a" "Find"
                'prompt "Find..."
                'source test-source
                'on-select (lambda (item) (set! test-selected item))))
            """)

        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        try engine.evaluate("(modal-handle-key \"a\")")

        // Test search message updates query state
        try engine.evaluate("(chooser-message-handler (list (cons 'type \"search\") (cons 'query \"test\")))")
        #expect(try engine.evaluate("chooser-query").asString() == "test")

        // Test select message with originalIndex
        try engine.evaluate("(chooser-message-handler (list (cons 'type \"select\") (cons 'originalIndex 1)))")
        #expect(try engine.evaluate("chooser-open?") == .false)
        #expect(try engine.evaluate("(cdr (assoc 'text test-selected))").asString() == "Beta")
    }

    // MARK: - Full keyboard flow

    @Test func fullFlowWithKeyboardAndChooser() throws {
        let engine = try loadAllModules()
        try engine.evaluate("""
            (define test-result #f)
            (define test-items
              (list (list (cons 'text "Safari") (cons 'bundleId "com.apple.Safari"))
                    (list (cons 'text "Chrome") (cons 'bundleId "com.google.Chrome"))
                    (list (cons 'text "Firefox") (cons 'bundleId "org.mozilla.Firefox"))))
            (define (test-source) test-items)
            (set-leader! 'global F18)
            (define-tree 'global
              (group "f" "Find"
                (selector "a" "Find App"
                  'prompt "Find app..."
                  'source test-source
                  'on-select (lambda (item) (set! test-result item)))))
            """)

        // Enter modal directly (simulates hotkey handler)
        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        #expect(try engine.evaluate("modal-active?") == .true)

        // 'f' → navigate into Find group
        try engine.evaluate("(modal-key-handler 3 0)")  // keycode 3 = 'f'
        #expect(try engine.evaluate("modal-active?") == .true)

        // 'a' → open chooser
        try engine.evaluate("(modal-key-handler 0 0)")  // keycode 0 = 'a'
        #expect(try engine.evaluate("modal-active?") == .false)
        #expect(try engine.evaluate("chooser-open?") == .true)

        // Select Chrome (originalIndex 1) via message handler
        try engine.evaluate("""
            (chooser-message-handler (list (cons 'type "select") (cons 'originalIndex 1)))
            """)

        #expect(try engine.evaluate("chooser-open?") == .false)
        let selected = try engine.evaluate("(cdr (assoc 'text test-result))").asString()
        #expect(selected == "Chrome")
    }

    // MARK: - Search resets selection

    @Test func searchResetsSelectionToZero() throws {
        let engine = try loadAllModules()
        try engine.evaluate("""
            (define test-items
              (list (list (cons 'text "Alpha"))
                    (list (cons 'text "Beta"))
                    (list (cons 'text "Charlie"))))
            (define (test-source) test-items)
            (define-tree 'global
              (selector "a" "Find"
                'prompt "Find..."
                'source test-source
                'on-select (lambda (item) #t)))
            """)

        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        try engine.evaluate("(modal-handle-key \"a\")")

        // Simulate JS having moved selection
        try engine.evaluate("(set! chooser-selected-index 2)")
        #expect(try engine.evaluate("chooser-selected-index").asInt64() == 2)

        // Search should reset selection to 0
        try engine.evaluate("(chooser-handle-search \"Al\")")
        #expect(try engine.evaluate("chooser-selected-index").asInt64() == 0)
    }
}
