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

    /// ADR-0021's line, read off the fragment itself: (iterm:wiring)
    /// contributes the backend record and the machinery-named digit-jump
    /// tree — and NO screen under 'com.googlecode.iterm2. That absence
    /// is the contract, not an omission: which ops iTerm surfaces, on
    /// which keys, is the configuration's to author, so a library change
    /// can never silently re-take a key the user chose. 'iterm-panes-focus
    /// is likewise the configuration's — nothing in the wiring names it.
    ///
    /// Pure construction — no AX, no AppleScript.
    @Test func wiringCarriesIntegrationAndNoScreen() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser dsl) (prefix (modaliser configuration) config:)
                  (modaliser terminal) (prefix (modaliser apps iterm) iterm:))
        """)
        try engine.evaluate("(define cfg (config:configuration (iterm:wiring)))")
        // The digit-pick mode rides the wiring, ready for the backend's
        // focus-pane-by-digit symbol ('iterm-pane-digit) to name.
        #expect(try engine.evaluate("(config:configuration-tree-ref cfg \"iterm-pane-digit\")") != .false)
        #expect(try engine.evaluate("(terminal-backend? (config:configuration-backend-ref cfg 'iterm))") == .true)
        // The two the composition must supply.
        #expect(try engine.evaluate("(config:configuration-tree-ref cfg \"com.googlecode.iterm2\")") == .false)
        #expect(try engine.evaluate("(config:configuration-tree-ref cfg \"iterm-panes-focus\")") == .false)
    }

    /// The wiring carries a populated `<terminal-backend>` record
    /// keyed by 'iterm and the iTerm bundle-id; installing it via the
    /// façade's one install point and stubbing the frontmost query at
    /// that bundle, the façade walks a single-frame path and exposes the
    /// iTerm backend as active.
    @Test func wiringBackendRecordInstallsIntoTheFacade() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser dsl) (prefix (modaliser configuration) config:)
                  (prefix (modaliser apps iterm) iterm:) (modaliser terminal))
        """)
        try engine.evaluate("""
          (define cfg (config:configuration (iterm:wiring)))
          (terminal-install-backends!
            (list (config:configuration-backend-ref cfg 'iterm)))
        """)
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

    @Test func defaultPaneLabelsAreDigits() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser apps iterm))")
        #expect(try engine.evaluate("(= (length default-pane-labels) 10)") == .true)
        #expect(try engine.evaluate("(equal? (car default-pane-labels) \"1\")") == .true)
    }

    // (focus-mode-tree was here: it asserted that the library's focus
    // Walk bound exactly h/j/k/l. Deleted, not relocated, at
    // iterm-owns-its-bindings-k45 — the Walk is authored in the
    // configuration now, so asserting its key set asserts preference.
    // ADR-0021.)

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
    /// runner: a parameterized indirection point defaulting to `(modaliser
    /// shell)`'s `run-shell-async`, so a future test driving iterm-configure!
    /// (once the probe itself gets a seam) can override it without touching a
    /// real iTerm installation. Note that default is the *seam*, not the
    /// native spawn — under `swift test` no runner is installed behind it
    /// (ADR-0023), so even the un-overridden path reaches nothing.
    @Test func provisionRunnerSeamDefaultsToRealAsyncShell() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser shell) (modaliser apps iterm))")
        #expect(try engine.evaluate("(procedure? (current-iterm-provision-runner))") == .true)
        #expect(try engine.evaluate("(eq? (current-iterm-provision-runner) run-shell-async)") == .true)
    }

    /// The seam is a genuine parameter: overridable within a dynamic extent
    /// and restored outside it, same contract `current-dialog-runner` and
    /// `current-herdr-send-runner` already rely on.
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
