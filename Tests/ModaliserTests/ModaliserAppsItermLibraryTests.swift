import Foundation
import Testing
@testable import Modaliser

@Suite("(modaliser apps iterm) library")
struct ModaliserAppsItermLibraryTests {
    @Test func registerInstallsItermTree() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine) (modaliser apps iterm))")
        // iTerm not running; AX query returns empty. Tree is registered
        // even with no pane-range children — the c/f/z/x static keys
        // remain. Pass 'install-context-suffix? #f to avoid mutating
        // shared (modaliser event-dispatch) state between tests.
        try engine.evaluate("(register! 'install-context-suffix? #f)")
        #expect(try engine.evaluate("(lookup-tree \"com.googlecode.iterm2\")") != .false)
    }

    @Test func focusModeRegistersUnderDefaultId() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine) (modaliser apps iterm))")
        try engine.evaluate("(focus-mode-register!)")
        #expect(try engine.evaluate("(lookup-tree \"iterm-panes-focus\")") != .false)
    }

    @Test func contextSuffixReturnsFalseForOtherApps() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser apps iterm))")
        #expect(try engine.evaluate("(context-suffix-handler \"com.apple.Safari\")") == .false)
    }

    @Test func defaultPaneLabelsAreDigits() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser apps iterm))")
        #expect(try engine.evaluate("(= (length default-pane-labels) 10)") == .true)
        #expect(try engine.evaluate("(equal? (car default-pane-labels) \"1\")") == .true)
    }

    @Test func rebuildTreeLegacyHintOptionsRaises() throws {
        // The old 'hint-options keyword was removed in the chip-theming
        // refactor — chip styling moved to the .chip CSS rule. Passing
        // it should fail loudly with a migration message.
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser dsl) (modaliser state-machine) (modaliser apps iterm))
        """)
        #expect(throws: (any Error).self) {
            try engine.evaluate("(rebuild-tree! 'hint-options '())")
        }
    }

    @Test func focusModeTreeIsHjklOnly() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine) (modaliser apps iterm))")
        try engine.evaluate("(define cs (focus-mode-tree))")
        #expect(try engine.evaluate("(= (length cs) 4)") == .true)
        try engine.evaluate("""
          (define keys (map (lambda (c) (cdr (assoc 'key c))) cs))
        """)
        #expect(try engine.evaluate("(equal? keys '(\"h\" \"j\" \"k\" \"l\"))") == .true)
    }

    // Regression: prior to this test, context-suffix-handler called
    // (rebuild-tree!) with no opts, so any 'sticky-mode-id passed to
    // register! got reverted to the default 'iterm-panes-focus on
    // the first leader-press into iTerm — and the dynamic tree's "f" key
    // then dispatched to (enter-mode! 'iterm-panes-focus), a tree id that
    // didn't exist for that user. The fix captures opts in register!
    // and threads them through to the suffix handler.
    @Test func registerOptsSurviveContextSuffixRebuild() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser dsl) (modaliser state-machine)
                  (modaliser event-dispatch) (modaliser apps iterm))
        """)
        // Register with a custom sticky-mode id. install-context-suffix? defaults to #t,
        // so register! installs a closure that should re-apply opts on every
        // dispatcher call.
        try engine.evaluate("(register! 'sticky-mode-id 'my-iterm-focus)")
        // The initial registration created the custom sticky tree.
        #expect(try engine.evaluate("(lookup-tree \"my-iterm-focus\")") != .false)
        #expect(try engine.evaluate("(lookup-tree \"iterm-panes-focus\")") == .false)
        // Simulate a leader press into iTerm: the dispatcher calls local-context-suffix,
        // which runs the installed closure. PRE-FIX: this rebuilt with default opts,
        // re-registering the default 'iterm-panes-focus tree (alongside the custom one).
        // POST-FIX: forwarded opts re-register 'my-iterm-focus and 'iterm-panes-focus
        // remains unregistered.
        _ = try engine.evaluate("(local-context-suffix \"com.googlecode.iterm2\")")
        #expect(try engine.evaluate("(lookup-tree \"my-iterm-focus\")") != .false)
        #expect(try engine.evaluate("(lookup-tree \"iterm-panes-focus\")") == .false)
    }

    // Regression: same family as the test above, but for the standalone
    // exported (context-suffix-handler bundle-id . opts) form used by
    // users composing their own handler. Caller must be able to pass opts;
    // pre-fix the handler ignored everything after bundle-id.
    @Test func standaloneHandlerHonoursForwardedOpts() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine) (modaliser apps iterm))")
        // Skip the auto-install — we'll exercise the handler directly.
        try engine.evaluate("(register! 'install-context-suffix? #f 'sticky-mode-id 'manual-focus)")
        #expect(try engine.evaluate("(lookup-tree \"manual-focus\")") != .false)
        // Invoke the handler with the same opts. The rebuild it does must
        // preserve the custom sticky id, not revert to 'iterm-panes-focus.
        _ = try engine.evaluate("""
          (context-suffix-handler "com.googlecode.iterm2"
                                        'sticky-mode-id 'manual-focus)
        """)
        #expect(try engine.evaluate("(lookup-tree \"manual-focus\")") != .false)
        #expect(try engine.evaluate("(lookup-tree \"iterm-panes-focus\")") == .false)
    }
}
