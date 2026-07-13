import Foundation
import Testing
@testable import Modaliser

@Suite("(modaliser apps iterm) library")
struct ModaliserAppsItermLibraryTests {
    // The live pane list-block (chips) and the tab list-block (always live —
    // it snapshots every render) each carry a 'cursor-targets-fn accessor so the
    // selection cursor (list-cursor-k6) moves over the same label→target
    // snapshot the digit dispatch consults. A no-chips pane block, which never
    // refreshes its targets, must NOT attach the cursor.
    @Test func liveListBlocksCarryCursorTargets() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (prefix (modaliser apps iterm) iterm:))")
        try engine.evaluate("(define pb (iterm:pane-list-block 'chips? #t))")
        try engine.evaluate("(define tb (iterm:tab-list-block))")
        try engine.evaluate("(define pb-static (iterm:pane-list-block))")
        #expect(try engine.evaluate("(procedure? (cdr (assoc 'cursor-targets-fn pb)))") == .true)
        #expect(try engine.evaluate("(procedure? (cdr (assoc 'cursor-targets-fn tb)))") == .true)
        #expect(try engine.evaluate("(assoc 'cursor-targets-fn pb-static)") == .false)
    }

    @Test func registerInstallsItermTree() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine) (modaliser apps iterm))")
        // iTerm not running; AX query returns empty. Tree is registered
        // even with no pane-range children — the c/f/z/x static keys
        // remain. Pass 'install-context-suffix? #f to avoid mutating
        // shared (modaliser event-dispatch) state between tests.
        try engine.evaluate("(register! 'install-context-suffix? #f)")
        #expect(try engine.evaluate("(lookup-tree \"com.googlecode.iterm2\")") != .false)
        // The digit-pick mode is also registered, ready for the backend's
        // focus-pane-by-digit symbol ('iterm-pane-digit) to name.
        #expect(try engine.evaluate("(lookup-tree \"iterm-pane-digit\")") != .false)
    }

    /// (register!) hands a populated `<terminal-backend>` to the façade
    /// keyed by 'iterm and the iTerm bundle-id. With a stubbed frontmost
    /// query pointing at that bundle, the façade walks a single-frame
    /// path and exposes the iTerm backend as active.
    @Test func registerInstallsTerminalBackend() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser dsl) (modaliser state-machine)
                  (modaliser apps iterm) (modaliser terminal))
        """)
        try engine.evaluate("(register! 'install-context-suffix? #f)")
        // Force the façade to resolve as if iTerm were frontmost; the
        // detect-fg / focused-pane-id thunks still shell out, but they
        // return #f cleanly when iTerm isn't running, so the walk
        // produces exactly one frame.
        let pathLen = try engine.evaluate("""
          (parameterize ((current-frontmost-bundle-id
                           (lambda () "com.googlecode.iterm2")))
            (length (focused-terminal-path)))
        """)
        #expect(pathLen == .fixnum(1))
        let entry = try engine.evaluate("""
          (parameterize ((current-frontmost-bundle-id
                           (lambda () "com.googlecode.iterm2")))
            (car (focused-terminal-path)))
        """)
        // car of the alist entry is the backend symbol 'iterm.
        if case .pair(let head, _) = entry {
            #expect(head == .symbol(engine.context.symbols.intern("iterm")))
        } else {
            Issue.record("expected (iterm . frame) pair, got \(entry)")
        }
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
    // (rebuild-tree!) with no opts, so any 'focus-mode-id passed to
    // register! got reverted to the default 'iterm-panes-focus on
    // the first leader-press into iTerm — and the dynamic tree's "f" key
    // then crossed into (lookup-tree 'iterm-panes-focus), a tree id that
    // didn't exist for that user. The fix captures opts in register!
    // and threads them through to the suffix handler.
    @Test func registerOptsSurviveContextSuffixRebuild() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser dsl) (modaliser state-machine)
                  (modaliser event-dispatch) (modaliser apps iterm))
        """)
        // Register with a custom focus-mode id. install-context-suffix? defaults to #t,
        // so register! installs a closure that should re-apply opts on every
        // dispatcher call.
        try engine.evaluate("(register! 'focus-mode-id 'my-iterm-focus)")
        // The initial registration created the custom focus tree.
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
        try engine.evaluate("(register! 'install-context-suffix? #f 'focus-mode-id 'manual-focus)")
        #expect(try engine.evaluate("(lookup-tree \"manual-focus\")") != .false)
        // Invoke the handler with the same opts. The rebuild it does must
        // preserve the custom focus-mode id, not revert to 'iterm-panes-focus.
        _ = try engine.evaluate("""
          (context-suffix-handler "com.googlecode.iterm2"
                                        'focus-mode-id 'manual-focus)
        """)
        #expect(try engine.evaluate("(lookup-tree \"manual-focus\")") != .false)
        #expect(try engine.evaluate("(lookup-tree \"iterm-panes-focus\")") == .false)
    }

    // MARK: - Async provisioning (leaf provision-scripts-async-k8)

    /// ADR-0014: the provisioning script `iterm-configure!` runs on Continue
    /// (quit iTerm, poll pgrep for up to ~6s, edit prefs, relaunch) is a
    /// genuinely long blocking window, so it must fire through
    /// `run-shell-async` rather than synchronous `run-shell` — a leader
    /// press during that window must not stall the keyboard tap. This test
    /// only checks the seam's existence and default wiring: `iterm-configure!`
    /// itself is gated by a live `iterm-probe-configured?` system probe with
    /// no test seam of its own (unrelated pre-existing gap), so driving it
    /// end-to-end here would make the test's outcome depend on whether this
    /// machine's real iTerm already carries Modaliser's bindings — exactly
    /// the live-environment dependency feedback_no_live_env_mutation_in_tests
    /// warns against. Mirrors current-dialog-runner / current-herdr-async-
    /// runner: a parameterized indirection point defaulting to the real
    /// run-shell-async, so a future test driving iterm-configure! (once the
    /// probe itself gets a seam) can override it without touching a real
    /// iTerm installation.
    @Test func provisionRunnerSeamDefaultsToRealAsyncShell() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser shell) (modaliser apps iterm))")
        #expect(try engine.evaluate("(procedure? (current-iterm-provision-runner))") == .true)
        #expect(try engine.evaluate("(eq? (current-iterm-provision-runner) run-shell-async)") == .true)
    }

    /// The seam is a genuine parameter: overridable within a dynamic extent
    /// and restored outside it, same contract `current-dialog-runner` and
    /// `current-herdr-async-runner` already rely on.
    @Test func provisionRunnerSeamIsParameterizable() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser shell) (modaliser apps iterm))")
        try engine.evaluate("""
          (define stub (lambda (script callback) 'stubbed))
          (define during #f)
          (parameterize ((current-iterm-provision-runner stub))
            (set! during (eq? (current-iterm-provision-runner) stub)))
        """)
        #expect(try engine.evaluate("during") == .true)
        #expect(try engine.evaluate("(eq? (current-iterm-provision-runner) run-shell-async)") == .true)
    }
}
