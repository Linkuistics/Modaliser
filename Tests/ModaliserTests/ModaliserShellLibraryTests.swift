import Testing
@testable import Modaliser

/// `(modaliser shell)` — the seam every backend shells out through
/// (test-live-backend-contact-k38, ADR-0023).
///
/// The property under test is a *negative* one and the reason the suite is
/// safe to run on a developer's own machine: with no runner installed, a
/// `run-shell` call spawns nothing. Every backend in the tree — tmux, zellij,
/// wezterm, kitty, ghostty, alacritty, iTerm, nvim, the ADR-0017 tool probes —
/// funnels through here, so these few assertions carry all of them.
@Suite("(modaliser shell) seam")
struct ModaliserShellLibraryTests {

    private func engineWithShell() throws -> SchemeEngine {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser shell))")
        return engine
    }

    // MARK: - Inert by default

    /// The whole point: a bare engine has no runner, so nothing can spawn.
    /// `swift test` never runs root.scm, which is the only installer.
    @Test func noRunnerIsInstalledByDefault() throws {
        let engine = try engineWithShell()
        #expect(try engine.evaluate("(current-shell-runner)") == .false)
        #expect(try engine.evaluate("(current-shell-async-runner)") == .false)
    }

    /// An uninstalled runner degrades to "" — the same empty output a backend
    /// already reads as "the tool told us nothing" (ADR-0017). No caller needs
    /// a new branch for the inert case; that is why the seam could be dropped
    /// under 14 libraries without touching one of them.
    @Test func runShellReturnsEmptyStringWhenInert() throws {
        let engine = try engineWithShell()
        let result = try engine.evaluate(#"(run-shell "echo definitely-not-run")"#)
        #expect(try result.asString() == "")
    }

    /// A command that would be loudly visible if it ran still yields "".
    /// Written with a real backend command rather than an `echo` so the test
    /// reads as what it protects against.
    @Test func liveToolCommandReachesNothingWhenInert() throws {
        let engine = try engineWithShell()
        let result = try engine.evaluate(#"(run-shell "tmux display-message -p '#{pane_id}' 2>/dev/null")"#)
        #expect(try result.asString() == "")
    }

    /// The async half answers rather than hanging: same (-1 "" reason) shape
    /// the native runner uses for a timeout or a failed spawn, so a caller
    /// waiting on a dialog result is not stranded (ADR-0014).
    @Test func runShellAsyncFiresCallbackWithFailureShapeWhenInert() throws {
        let engine = try engineWithShell()
        try engine.evaluate("(define answer #f)")
        try engine.evaluate("""
            (run-shell-async "echo definitely-not-run"
              (lambda (code out err) (set! answer (list code out err))))
            """)
        #expect(try engine.evaluate("(car answer)") == .fixnum(-1))
        #expect(try engine.evaluate("(cadr answer)").asString() == "")
        #expect(try engine.evaluate("(string? (caddr answer))") == .true)
    }

    // MARK: - Installed runners are used

    /// What root.scm does at bootstrap, in miniature: install a runner and the
    /// seam dispatches to it, verbatim command in.
    @Test func installedRunnerReceivesTheCommand() throws {
        let engine = try engineWithShell()
        try engine.evaluate("""
            (define seen '())
            (current-shell-runner
              (lambda (cmd) (set! seen (cons cmd seen)) "canned"))
            """)
        let result = try engine.evaluate(#"(run-shell "tmux select-pane -L")"#)
        #expect(try result.asString() == "canned")
        #expect(try engine.evaluate("(car seen)").asString() == "tmux select-pane -L")
    }

    /// Genuinely a parameter, so a test can scope a canned runner to one
    /// dynamic extent and leave the suite inert outside it.
    @Test func runnerIsParameterizable() throws {
        let engine = try engineWithShell()
        try engine.evaluate("""
            (define during #f)
            (parameterize ((current-shell-runner (lambda (cmd) "inside")))
              (set! during (run-shell "anything")))
            """)
        #expect(try engine.evaluate("during").asString() == "inside")
        #expect(try engine.evaluate(#"(run-shell "anything")"#).asString() == "")
    }

    /// The async runner forwards the trailing options the native procedure
    /// accepts ('timeout N), so installing it loses nothing.
    @Test func installedAsyncRunnerReceivesTrailingOptions() throws {
        let engine = try engineWithShell()
        try engine.evaluate("""
            (define seen #f)
            (current-shell-async-runner
              (lambda (cmd callback . opts) (set! seen opts) (callback 0 "ok" "")))
            (define answer #f)
            (run-shell-async "echo hi"
              (lambda (code out err) (set! answer out))
              'timeout 5)
            """)
        #expect(try engine.evaluate("answer").asString() == "ok")
        #expect(try engine.evaluate("(equal? seen '(timeout 5))") == .true)
    }

    // MARK: - The native capability is a separate library

    /// The native runners exist and are reachable — by their own names, from
    /// the host. The seam's inertness is a wiring fact, not a missing
    /// capability, and root.scm closes exactly this gap at boot.
    @Test func nativeRunnersAreDistinctlyNamed() throws {
        let engine = try SchemeEngine()
        #expect(try engine.evaluate("(procedure? run-shell-native)") == .true)
        #expect(try engine.evaluate("(procedure? run-shell-async-native)") == .true)
    }

    // MARK: - The host install, and the ordering it depends on

    /// `(modaliser terminal)` derives `modaliser-tool-path` from a login-shell
    /// spawn **at import time** (ADR-0017 Layer 1), so whichever runner is
    /// installed *before* that import is the one the derivation gets. Driven
    /// with a canned runner rather than a real login shell: spawning one would
    /// execute the developer's own `.zprofile`, which is 216 of the 419
    /// commands this seam exists to stop.
    @Test func aRunnerInstalledBeforeTheImportFeedsTheToolPathDerivation() throws {
        let engine = try engineWithShell()
        try engine.evaluate("""
            (current-shell-runner (lambda (cmd) "/canned/login/bin:/usr/bin"))
            """)
        try engine.evaluate("(import (modaliser terminal))")
        let path = try engine.evaluate("modaliser-tool-path").asString()
        #expect(path.contains("/canned/login/bin"))
        // …and the ADR-0017 floor still survives behind it.
        #expect(path.contains("/opt/homebrew/bin"))
    }

    /// With no runner installed the same derivation degrades to the floor
    /// alone — correct under test, and the failure mode `root.scm`'s ordering
    /// exists to keep out of production.
    @Test func toolPathDegradesToTheFloorWhenNoRunnerIsInstalled() throws {
        let engine = try engineWithShell()
        try engine.evaluate("(import (modaliser terminal))")
        let path = try engine.evaluate("modaliser-tool-path").asString()
        #expect(path == "/opt/homebrew/bin:/usr/local/bin:/usr/sbin")
    }

    /// `root.scm` cannot be evaluated under `swift test` (it asks for
    /// Accessibility and builds a status bar), so the ordering constraint is
    /// pinned textually — the same way ConfigRobustnessTests pins root.scm's
    /// host entry points. If the install ever drifts below another import,
    /// production silently bakes the ADR-0017 floor into every backend's PATH
    /// preamble; nothing else would notice.
    @Test func rootSchemeInstallsTheRunnersAheadOfEveryOtherImport() throws {
        let engine = try SchemeEngine()
        let schemePath = try #require(engine.schemeDirectoryPath)
        let source = try String(contentsOfFile: schemePath + "/root.scm", encoding: .utf8)

        let syncInstall = try #require(source.range(of: "(current-shell-runner run-shell-native)"))
        let asyncInstall = try #require(
            source.range(of: "(current-shell-async-runner run-shell-async-native)"))
        let firstOtherImport = try #require(source.range(of: "(import (modaliser util)"))

        #expect(syncInstall.upperBound < firstOtherImport.lowerBound)
        #expect(asyncInstall.upperBound < firstOtherImport.lowerBound)
    }
}
