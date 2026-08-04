import Testing
@testable import Modaliser

/// Tests for `(modaliser wms paneru)` — paneru's ops and the installation
/// predicate (paneru-ops-k6, `docs/specs/paneru-window-management.md`).
///
/// Everything here runs through **one seam**: `current-shell-runner`
/// (ADR-0023). No paneru daemon is contacted, no `paneru` binary is resolved,
/// and nothing is asserted about the developer's machine — the canned runner
/// both answers the probe and records the exact command every op would have
/// spawned.
///
/// The exact-command assertions are the point of this suite rather than
/// belt-and-braces. `send-cmd` has no error channel: probed against the live
/// daemon, an unrecognised command exits 0 and prints nothing, so a mistyped
/// wire form fails *invisibly* on a real desktop. These strings are the only
/// place the wire format is pinned.
@Suite("(modaliser wms paneru) library")
struct ModaliserWmsPaneruLibraryTests {

    /// An engine with paneru imported and a recording runner installed.
    ///
    /// Ordering is deliberate: the import comes first so `(modaliser terminal)`
    /// derives `modaliser-tool-path` with **no** runner installed and degrades
    /// to the ADR-0017 floor. Installing the runner first would feed the
    /// login-shell derivation this canned value and bake it into the preamble
    /// every assertion below reads back.
    private func engineWithRecordingRunner(probeAnswer: String = "/opt/homebrew/bin/paneru")
        throws -> SchemeEngine
    {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser wms paneru)
                  (modaliser shell)
                  (only (modaliser terminal) modaliser-tool-path))
        """)
        try engine.evaluate("""
          (define seen '())
          (current-shell-runner
            (lambda (cmd) (set! seen (cons cmd seen)) \(literal(probeAnswer))))
        """)
        return engine
    }

    /// A Swift string as a *Scheme source* string literal. The canned answer
    /// crosses two languages to get here, and the interesting probe answers are
    /// newline-terminated (a real `command -v` prints one), which LispKit's
    /// reader rejects raw inside a literal.
    private func literal(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    /// The preamble the library bakes at load: `export PATH=<derived>:$PATH; `.
    /// Read off the engine rather than hardcoded, so the assertions pin the
    /// *paneru* half of each command and stay indifferent to ADR-0017's floor.
    private func preamble(_ engine: SchemeEngine) throws -> String {
        "export PATH=" + (try engine.evaluate("modaliser-tool-path").asString()) + ":$PATH; "
    }

    // MARK: - Surface

    /// The seven ops and the predicate all bind — each name is public contract
    /// the moment a config can reference it. Nothing else is exported: paneru
    /// sits behind no façade, so there is no backend record and no `wiring`.
    @Test func exportsSevenOpsAndThePredicate() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser wms paneru))")
        for op in [
            "focus-west", "focus-east",
            "swap-west", "swap-east",
            "grow", "shrink",
            "center"
        ] {
            #expect(try engine.evaluate("(procedure? \(op))") == .true,
                    "expected \(op) to be an exported 0-arg op")
        }
        #expect(try engine.evaluate("(procedure? installed?)") == .true)
    }

    // MARK: - The wire forms

    /// Each op's exact command string, asserted one op at a time.
    ///
    /// The tail is space-separated — `window focus east`, never the
    /// underscored `window_focus_east`, which is the TOML *binding* name in the
    /// user's paneru.toml and is not something `send-cmd` accepts. Getting that
    /// wrong is silent on a live desktop; here it is a red test.
    @Test(arguments: [
        ("focus-west", "window focus west"),
        ("focus-east", "window focus east"),
        ("swap-west", "window swap west"),
        ("swap-east", "window swap east"),
        ("grow", "window grow"),
        ("shrink", "window shrink"),
        ("center", "window center")
    ])
    func opSendsItsExactCommand(op: String, tail: String) throws {
        let engine = try engineWithRecordingRunner()
        try engine.evaluate("(\(op))")
        let sent = try engine.evaluate("(car seen)").asString()
        let expected = try preamble(engine) + "paneru send-cmd \(tail) 2>/dev/null"
        #expect(sent == expected)
    }

    /// One op is one spawn — no probe, no query, no retry riding along. Worth
    /// pinning because these ops sit on the dispatch path and a composition may
    /// re-arm them in place with `'next 'self`.
    @Test func anOpSpawnsExactlyOneCommand() throws {
        let engine = try engineWithRecordingRunner()
        try engine.evaluate("(focus-east)")
        #expect(try engine.evaluate("(length seen)") == .fixnum(1))
    }

    // MARK: - The installation predicate

    /// `command -v paneru` through the derived tool path (ADR-0017), and the
    /// answer is read off stdout: a resolved path means installed.
    @Test func installedIsTrueWhenTheProbeResolvesAPath() throws {
        let engine = try engineWithRecordingRunner(probeAnswer: "/opt/homebrew/bin/paneru\n")
        #expect(try engine.evaluate("(installed?)") == .true)
        let probe = try engine.evaluate("(car seen)").asString()
        let expected = try preamble(engine) + "command -v paneru 2>/dev/null"
        #expect(probe == expected)
    }

    /// Empty output is absent. This is the same degradation every backend
    /// already reads as "the tool told us nothing" (ADR-0017), which is what
    /// lets the inert seam and a genuinely missing binary share one path.
    @Test func installedIsFalseWhenTheProbeAnswersNothing() throws {
        let engine = try engineWithRecordingRunner(probeAnswer: "")
        #expect(try engine.evaluate("(installed?)") == .false)
    }

    /// Whitespace-only output is absent too — a shell that answered with a bare
    /// newline has still resolved nothing.
    @Test func installedIsFalseWhenTheProbeAnswersWhitespace() throws {
        let engine = try engineWithRecordingRunner(probeAnswer: "  \n")
        #expect(try engine.evaluate("(installed?)") == .false)
    }

    // MARK: - Inert by default (ADR-0023)

    /// With no runner installed — every engine `swift test` builds — the
    /// predicate is false, so the **Paneru-installed composition** takes its
    /// non-paneru branch and nothing else in this library ever runs. That is
    /// row 3 of the spec's degradation table, and it is why the paneru screen
    /// can never compose under test.
    @Test func predicateIsFalseInABareEngineAndNothingSpawns() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser wms paneru) (modaliser shell))")
        #expect(try engine.evaluate("(current-shell-runner)") == .false)
        #expect(try engine.evaluate("(installed?)") == .false)
        // And an op fired anyway reaches nothing, returning the seam's "".
        #expect(try engine.evaluate("(focus-west)").asString() == "")
    }
}
