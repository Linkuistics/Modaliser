import CoreGraphics
import Foundation
import Testing
import LispKit
@testable import Modaliser

private func joinPath(_ base: String, _ component: String) -> String {
    base.hasSuffix("/") ? base + component : base + "/" + component
}

@Suite("Overlay Integration")
struct OverlayIntegrationTests {

    /// Load all modules including UI (dom, css, overlay).
    /// Stubs out WebView primitives to avoid NSPanel crashes in test runner.
    private func loadAllModules() throws -> SchemeEngine {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("Scheme directory not found")
            throw SchemeTestError.noSchemeDir
        }

        // Stub out WebView primitives before loading overlay.scm
        // These track calls without creating actual NSPanels
        try engine.evaluate("""
            (define webview-create-calls '())
            (define webview-close-calls '())
            (define webview-set-html-calls '())
            (define webview-message-handlers (make-hashtable string-hash string=?))
            (define (webview-create id opts)
              (set! webview-create-calls (cons id webview-create-calls)) id)
            (define (webview-close id)
              (set! webview-close-calls (cons id webview-close-calls)))
            (define (webview-set-html! id html)
              (set! webview-set-html-calls (cons (cons id html) webview-set-html-calls)))
            (define (webview-on-message id handler)
              (hashtable-set! webview-message-handlers id handler))
            ;; Test-only: simulate the Swift side delivering a panel message.
            (define (webview-dispatch-message id msg)
              (let ((h (hashtable-ref webview-message-handlers id #f)))
                (when h (h msg))))
            """)

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
        // Disable overlay delay for synchronous testing
        try engine.evaluate("(set! modal-overlay-delay 0)")
        return engine
    }

    // MARK: - Overlay lifecycle with modal

    @Test func modalEnterOpensOverlay() throws {
        let engine = try loadAllModules()
        try engine.evaluate("""
            (define-tree 'global
              (key "s" "Safari" (lambda () 'ok)))
            """)

        #expect(try engine.evaluate("overlay-open?") == .false)

        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")

        #expect(try engine.evaluate("overlay-open?") == .true)
        #expect(try engine.evaluate("modal-active?") == .true)

        try engine.evaluate("(modal-exit)")
        #expect(try engine.evaluate("overlay-open?") == .false)
    }

    @Test func modalExitClosesOverlay() throws {
        let engine = try loadAllModules()
        try engine.evaluate("""
            (define-tree 'global
              (key "s" "Safari" (lambda () 'ok)))
            """)

        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        #expect(try engine.evaluate("overlay-open?") == .true)

        try engine.evaluate("(modal-exit)")
        #expect(try engine.evaluate("overlay-open?") == .false)
    }

    @Test func groupNavigationUpdatesOverlay() throws {
        let engine = try loadAllModules()
        try engine.evaluate("""
            (define-tree 'global
              (group "w" "Windows"
                (key "c" "Center" (lambda () 'ok))
                (key "m" "Maximize" (lambda () 'ok))))
            """)

        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        #expect(try engine.evaluate("overlay-open?") == .true)

        // Navigate into group
        try engine.evaluate("(modal-handle-key \"w\")")
        #expect(try engine.evaluate("overlay-open?") == .true)
        #expect(try engine.evaluate("modal-active?") == .true)

        // Verify we can render the current overlay content (path should be ("w"))
        let html = try engine.evaluate("""
            (render-overlay-html modal-root-node modal-current-path)
            """).asString()
        #expect(html.contains("Center"))
        #expect(html.contains("Maximize"))

        try engine.evaluate("(modal-exit)")
    }

    @Test func commandExecutionClosesOverlay() throws {
        let engine = try loadAllModules()
        try engine.evaluate("""
            (define action-fired #f)
            (define-tree 'global
              (key "s" "Safari" (lambda () (set! action-fired #t))))
            """)

        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        #expect(try engine.evaluate("overlay-open?") == .true)

        try engine.evaluate("(modal-handle-key \"s\")")
        #expect(try engine.evaluate("action-fired") == .true)
        #expect(try engine.evaluate("overlay-open?") == .false)
        #expect(try engine.evaluate("modal-active?") == .false)
    }

    @Test func stepBackUpdatesOverlay() throws {
        let engine = try loadAllModules()
        try engine.evaluate("""
            (define-tree 'global
              (key "s" "Safari" (lambda () 'ok))
              (group "w" "Windows"
                (key "c" "Center" (lambda () 'ok))))
            """)

        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        try engine.evaluate("(modal-handle-key \"w\")")

        // Step back to root
        try engine.evaluate("(modal-step-back)")
        #expect(try engine.evaluate("overlay-open?") == .true)
        #expect(try engine.evaluate("modal-active?") == .true)
        #expect(try engine.evaluate("(null? modal-current-path)") == .true)

        // Overlay should now show root entries again
        let html = try engine.evaluate("""
            (render-overlay-html modal-root-node modal-current-path)
            """).asString()
        #expect(html.contains("Safari"))
        #expect(html.contains("Windows"))

        try engine.evaluate("(modal-exit)")
    }

    @Test func stepBackFromRootClosesOverlay() throws {
        let engine = try loadAllModules()
        try engine.evaluate("""
            (define-tree 'global
              (key "s" "Safari" (lambda () 'ok)))
            """)

        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        #expect(try engine.evaluate("overlay-open?") == .true)

        try engine.evaluate("(modal-step-back)")
        #expect(try engine.evaluate("overlay-open?") == .false)
        #expect(try engine.evaluate("modal-active?") == .false)
    }

    // MARK: - Full flow via keyboard simulation

    @Test func fullKeyboardFlowWithOverlay() throws {
        let engine = try loadAllModules()
        try engine.evaluate("""
            (define test-result #f)
            (define-tree 'global
              (group "w" "Windows"
                (key "c" "Center" (lambda () (set! test-result 'centered)))))
            """)

        // Enter modal directly
        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        #expect(try engine.evaluate("overlay-open?") == .true)
        #expect(try engine.evaluate("modal-active?") == .true)

        // 'w' → navigate into group, overlay updates
        try engine.evaluate("(modal-key-handler 13 0)")  // 'w'
        #expect(try engine.evaluate("overlay-open?") == .true)
        #expect(try engine.evaluate("modal-active?") == .true)

        // 'c' → execute action, overlay closes
        try engine.evaluate("(modal-key-handler 8 0)")   // 'c'
        #expect(try engine.evaluate("test-result") == .symbol(engine.context.symbols.intern("centered")))
        #expect(try engine.evaluate("overlay-open?") == .false)
        #expect(try engine.evaluate("modal-active?") == .false)
    }

    @Test func leaderToggleClosesOverlay() throws {
        let engine = try loadAllModules()
        try engine.evaluate("""
            (define-tree 'global
              (key "s" "Safari" (lambda () 'ok)))
            """)

        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        #expect(try engine.evaluate("overlay-open?") == .true)

        // Toggle off via F18 through modal-key-handler
        try engine.evaluate("(modal-key-handler F18 0)")
        #expect(try engine.evaluate("overlay-open?") == .false)
        #expect(try engine.evaluate("modal-active?") == .false)
    }

    @Test func escapeClosesOverlay() throws {
        let engine = try loadAllModules()
        try engine.evaluate("""
            (define-tree 'global
              (key "s" "Safari" (lambda () 'ok)))
            """)

        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        #expect(try engine.evaluate("overlay-open?") == .true)

        try engine.evaluate("(modal-key-handler ESCAPE 0)")
        #expect(try engine.evaluate("overlay-open?") == .false)
        #expect(try engine.evaluate("modal-active?") == .false)
    }

    @Test func unmatchedKeyClosesOverlay() throws {
        let engine = try loadAllModules()
        try engine.evaluate("""
            (define-tree 'global
              (key "s" "Safari" (lambda () 'ok)))
            """)

        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        #expect(try engine.evaluate("overlay-open?") == .true)

        // Press 'x' which has no binding → should exit and close overlay
        try engine.evaluate("(modal-key-handler 7 0)")  // keycode 7 = 'x'
        #expect(try engine.evaluate("overlay-open?") == .false)
        #expect(try engine.evaluate("modal-active?") == .false)
    }

    @Test func modalExitIsIdempotent() throws {
        let engine = try loadAllModules()
        try engine.evaluate("""
            (define-tree 'global
              (key "s" "Safari" (lambda () 'ok)))
            """)

        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        try engine.evaluate("(modal-exit)")
        #expect(try engine.evaluate("modal-active?") == .false)

        // Second exit while already inactive must be a no-op.
        let genBefore = try engine.evaluate("modal-overlay-generation")
        try engine.evaluate("(modal-exit)")
        #expect(try engine.evaluate("modal-active?") == .false)
        // Generation counter should NOT change (no spurious cancellation of a pending show).
        #expect(try engine.evaluate("modal-overlay-generation") == genBefore)
    }

    @Test func overlayCancelMessageExitsModal() throws {
        let engine = try loadAllModules()
        try engine.evaluate("""
            (define-tree 'global
              (key "s" "Safari" (lambda () 'ok)))
            """)

        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        #expect(try engine.evaluate("overlay-open?") == .true)
        #expect(try engine.evaluate("modal-active?") == .true)

        // Simulate the Swift side sending a cancel message for an outside click.
        try engine.evaluate("""
            (webview-dispatch-message "modaliser-overlay" '((type . "cancel")))
            """)

        #expect(try engine.evaluate("overlay-open?") == .false)
        #expect(try engine.evaluate("modal-active?") == .false)
    }

    // MARK: - Delay configuration

    @Test func setOverlayDelayUpdatesVariable() throws {
        let engine = try loadAllModules()
        // loadAllModules forces modal-overlay-delay to 0 for synchronous testing.
        try engine.evaluate("(set-overlay-delay! 0.75)")
        #expect(try engine.evaluate("modal-overlay-delay") == .flonum(0.75))

        // Scheme literal 0 is a fixnum; the setter stores it as-is.
        try engine.evaluate("(set-overlay-delay! 0)")
        #expect(try engine.evaluate("modal-overlay-delay") == .fixnum(0))
    }

    // MARK: - Overlay HTML content verification

    @Test func overlayContentMatchesCurrentPosition() throws {
        let engine = try loadAllModules()
        try engine.evaluate("""
            (define-tree 'global
              (key "s" "Safari" (lambda () 'ok))
              (group "w" "Windows"
                (key "c" "Center" (lambda () 'ok))
                (key "f" "Full Screen" (lambda () 'ok))))
            """)

        // At root: should show "s" and "w" entries
        let rootHtml = try engine.evaluate("""
            (render-overlay-html (lookup-tree "global") '())
            """).asString()
        #expect(rootHtml.contains("Safari"))
        #expect(rootHtml.contains("Windows"))
        #expect(!rootHtml.contains("Center"))

        // After navigating into group: should show "c" and "f"
        let groupHtml = try engine.evaluate("""
            (render-overlay-html (lookup-tree "global") '("w"))
            """).asString()
        #expect(groupHtml.contains("Center"))
        #expect(groupHtml.contains("Full Screen"))
        #expect(!groupHtml.contains("Safari"))
    }
}
