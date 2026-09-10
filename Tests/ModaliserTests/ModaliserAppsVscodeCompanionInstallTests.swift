import Foundation
import Testing

@testable import Modaliser

// Tests for the companion-install op in `(modaliser apps vscode)` —
// ADR-0028's "ships inside the .app, installs only when asked"
// (vscode-companion-install-k18).
//
// TWO SEAMS AND NOTHING ELSE. The payload directory is a parameter that
// defaults to #f, and every spawn goes through `current-shell-runner`,
// which a bare `SchemeEngine()` leaves uninstalled. So the suite reaches
// neither an app bundle nor `~/.vscode` — structurally, not by per-test
// discipline (ADR-0023). The one thing that touches the file system is
// the identity file each test writes into its own temporary directory,
// which is the payload's stand-in and is never `~/.vscode`.
//
// The assertions that matter are the two the op can get *quietly* wrong:
// that an un-configured build answers "not installed" and writes nothing
// rather than guessing a path, and that the command spawned is the
// shipped sweep script pointed at the payload — the sweep being the one
// `rm -rf` inside another application's directory.
@Suite("(modaliser apps vscode) companion install")
struct ModaliserAppsVscodeCompanionInstallTests {

    /// A throwaway directory standing in for `Contents/Resources`, with
    /// `ModaliserCompanion.id` stamped exactly as `build-app.sh` stamps
    /// it. Returns the payload directory the parameter would receive.
    private func payloadDirectory(
        identity: String = "antony.modaliser-companion-1.0.0"
    ) throws -> String {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("modaliser-companion-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true)
        let payload = root.appendingPathComponent("ModaliserCompanion")
        try FileManager.default.createDirectory(
            at: payload, withIntermediateDirectories: true)
        try "\(identity)\n".write(
            to: root.appendingPathComponent("ModaliserCompanion.id"),
            atomically: true, encoding: .utf8)
        return payload.path
    }

    /// An engine with the library imported and a recording shell runner
    /// installed. Import first, runner second — the paneru/grove
    /// ordering: `(modaliser terminal)` derives its tool path from a
    /// login-shell spawn at import time, and installing the runner first
    /// would feed that derivation this canned value.
    private func engine(answer: String = "no\n") throws -> SchemeEngine {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (prefix (modaliser apps vscode) code:)
                  (modaliser shell)
                  (only (modaliser util) string-contains?))
        """)
        try engine.evaluate("""
          (define seen '())
          (current-shell-runner
            (lambda (cmd) (set! seen (cons cmd seen)) "\(answer.replacingOccurrences(of: "\n", with: "\\n"))"))
        """)
        return engine
    }

    // MARK: - Surface

    @Test func exportsResolve() throws {
        let engine = try engine()
        #expect(try engine.evaluate("(procedure? code:companion-installed?)") == .true)
        #expect(try engine.evaluate("(procedure? code:install-companion!)") == .true)
        #expect(try engine.evaluate("(procedure? code:companion-identity)") == .true)
        #expect(try engine.evaluate("(procedure? code:companion-install-dir)") == .true)
        #expect(try engine.evaluate("(procedure? code:companion-install-command)") == .true)
        #expect(try engine.evaluate("(procedure? code:current-vscode-companion-payload-dir)") == .true)
    }

    /// The quarantine. The parameter ships unconfigured, which is what a
    /// bare `SchemeEngine()` — every test, and `swift run` too — sees.
    @Test func payloadDirectoryDefaultsToUnconfigured() throws {
        let engine = try engine()
        #expect(try engine.evaluate("(code:current-vscode-companion-payload-dir)") == .false)
    }

    // MARK: - Un-configured: not installed, and nothing spawned

    /// No payload means *not installed*, never an error and never a
    /// guess at a path. This is the `swift run` row of ADR-0028's table.
    @Test func unconfiguredPayloadReadsAsNotInstalled() throws {
        let engine = try engine(answer: "yes\n")
        #expect(try engine.evaluate("(code:companion-identity)") == .false)
        #expect(try engine.evaluate("(code:companion-install-dir)") == .false)
        #expect(try engine.evaluate("(code:companion-install-command)") == .false)
        #expect(try engine.evaluate("(code:companion-installed?)") == .false)
        // Not one command — the probe never even runs, because there is
        // no target path to probe for.
        #expect(try engine.evaluate("(= (length seen) 0)") == .true)
    }

    /// And the op is a no-op. Nothing is spawned, no dialog is raised,
    /// and it says so on the log rather than failing.
    @Test func unconfiguredInstallIsANoOp() throws {
        let engine = try engine()
        #expect(try engine.evaluate("(code:install-companion!)") == .false)
        #expect(try engine.evaluate("(= (length seen) 0)") == .true)
    }

    // MARK: - Configured: identity, destination, command

    @Test func identityComesFromTheStampedFile() throws {
        let engine = try engine()
        let payload = try payloadDirectory()
        try engine.evaluate("(code:current-vscode-companion-payload-dir \"\(payload)\")")
        #expect(try engine.evaluate(
            #"(equal? (code:companion-identity) "antony.modaliser-companion-1.0.0")"#) == .true)
    }

    /// The destination is `~/.vscode/extensions/<identity>` and only
    /// that — Insiders and other variants are out of scope (ADR-0028).
    @Test func destinationIsTheExtensionsDirectory() throws {
        let engine = try engine()
        let payload = try payloadDirectory()
        try engine.evaluate("(code:current-vscode-companion-payload-dir \"\(payload)\")")
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        #expect(try engine.evaluate(
            "(equal? (code:companion-install-dir) "
            + "\"\(home)/.vscode/extensions/antony.modaliser-companion-1.0.0\")") == .true)
    }

    /// The command is the SHIPPED sweep script, pointed at the payload —
    /// the property worth pinning, because the deletion rule existing in
    /// exactly one place is what ADR-0028 buys by shipping the script at
    /// all. Both words are single-quoted: a bundle may sit anywhere.
    ///
    /// And it ends by folding stderr into stdout and echoing the exit
    /// status, because `run-shell` returns stdout and nothing else — see
    /// the failure tests below for what that buys.
    @Test func installCommandRunsTheShippedSweepScript() throws {
        let engine = try engine()
        let payload = try payloadDirectory()
        try engine.evaluate("(code:current-vscode-companion-payload-dir \"\(payload)\")")
        #expect(try engine.evaluate(
            "(equal? (code:companion-install-command) "
            + "\"'\(payload).install.sh' '\(payload)'"
            + " 2>&1; echo \\\"modaliser-install-status=$?\\\"\")") == .true)
    }

    // MARK: - A confirmed write that fails must say so

    /// `run-shell` hands back stdout and nothing else — no exit code, no
    /// stderr — so without the status echo every failure of the sweep
    /// would be perfectly silent to a user who had just confirmed a
    /// write. These three pin the reading of it.
    @Test func aZeroStatusReadsAsSuccess() throws {
        let engine = try engine()
        #expect(try engine.evaluate(
            #"(code:companion-install-succeeded? "Installed\nmodaliser-install-status=0\n")"#)
            == .true)
    }

    @Test func aNonZeroStatusReadsAsFailure() throws {
        let engine = try engine()
        #expect(try engine.evaluate(
            #"(code:companion-install-succeeded? "rm: denied\nmodaliser-install-status=1\n")"#)
            == .false)
    }

    /// The case that must not read as success by absence: a tampered or
    /// older bundle with no script in it produces no status line at all.
    @Test func aMissingStatusLineReadsAsFailure() throws {
        let engine = try engine()
        #expect(try engine.evaluate(
            #"(code:companion-install-succeeded? "sh: no such file")"#) == .false)
        #expect(try engine.evaluate(#"(code:companion-install-succeeded? "")"#) == .false)
        #expect(try engine.evaluate("(code:companion-install-succeeded? #f)") == .false)
    }

    /// The status is read from the transcript's FINAL record, not found
    /// anywhere in it — and this is the test that pins the difference.
    ///
    /// Every other line of the transcript is the sweep script naming
    /// directories under `~/.vscode/extensions`, which is text this
    /// library does not choose. A directory named
    /// `antony.modaliser-companion-modaliser-install-status=0` matches
    /// the sweep's candidate glob, so the script prints it — and a run
    /// that genuinely ended `=1` would read as success under a
    /// substring search, telling a user who had just confirmed a write
    /// that it worked when it had not. Reproduced against a scratch
    /// extensions directory; this is that transcript, verbatim in shape.
    @Test func chatterCannotSpoofTheStatus() throws {
        let engine = try engine()
        #expect(try engine.evaluate(#"""
          (code:companion-install-succeeded?
            (string-append
              "Leaving /x/antony.modaliser-companion-modaliser-install-status=0"
              " (its package.json names ?.?)\n"
              "cp: /x/README.md: No such file or directory\n"
              "modaliser-install-status=1\n"))
        """#) == .false)
    }

    /// The mirror of it: the same chatter with a genuine success at the
    /// end still reads as success. Trailing blank lines are skipped —
    /// the shell's own trailing newline is one.
    @Test func chatterDoesNotHideAGenuineSuccess() throws {
        let engine = try engine()
        #expect(try engine.evaluate(#"""
          (code:companion-install-succeeded?
            (string-append
              "Removing /x/antony.modaliser-companion-0.9.0\n"
              "Installed /x/antony.modaliser-companion-1.0.0\n"
              "modaliser-install-status=0\n\n"))
        """#) == .true)
    }

    // MARK: - The probe

    /// The probe tests for the COMPLETION MARKER the sweep script writes
    /// last, not for the directory. A directory test would read a
    /// half-finished copy — a full disk, an I/O error after the mkdir —
    /// as *installed*, and the row that gates on it would then retire
    /// itself with no in-app way back to a reinstall.
    @Test func probeTestsForTheCompletionMarker() throws {
        let engine = try engine(answer: "yes\n")
        let payload = try payloadDirectory()
        try engine.evaluate("(code:current-vscode-companion-payload-dir \"\(payload)\")")
        #expect(try engine.evaluate("(code:companion-installed?)") == .true)
        #expect(try engine.evaluate("(= (length seen) 1)") == .true)
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        #expect(try engine.evaluate(
            "(equal? (car seen) \"[ -f "
            + "'\(home)/.vscode/extensions/antony.modaliser-companion-1.0.0"
            + "/.modaliser-installed'"
            + " ] && echo yes || echo no\")") == .true)
    }

    @Test func probeAnsweringNoReadsAsNotInstalled() throws {
        let engine = try engine(answer: "no\n")
        let payload = try payloadDirectory()
        try engine.evaluate("(code:current-vscode-companion-payload-dir \"\(payload)\")")
        #expect(try engine.evaluate("(code:companion-installed?)") == .false)
    }

    /// A row gated on the predicate has the overlay reading it on every
    /// render, so the probe is cached after the first answer — kitty's
    /// reason, and the same shape.
    @Test func predicateIsCachedAfterTheFirstProbe() throws {
        let engine = try engine(answer: "yes\n")
        let payload = try payloadDirectory()
        try engine.evaluate("(code:current-vscode-companion-payload-dir \"\(payload)\")")
        _ = try engine.evaluate("(code:companion-installed?)")
        _ = try engine.evaluate("(code:companion-installed?)")
        _ = try engine.evaluate("(code:companion-installed?)")
        #expect(try engine.evaluate("(= (length seen) 1)") == .true)
    }

    // MARK: - The write is never unconfirmed

    /// Already installed: idempotent, no dialog, no copy. The probe is
    /// the only command that runs.
    @Test func installWhenAlreadyInstalledCopiesNothing() throws {
        let engine = try engine(answer: "yes\n")
        let payload = try payloadDirectory()
        try engine.evaluate("(code:current-vscode-companion-payload-dir \"\(payload)\")")
        #expect(try engine.evaluate("(code:install-companion!)") == .true)
        #expect(try engine.evaluate("(= (length seen) 1)") == .true)
        #expect(try engine.evaluate("""
          (string-contains? (car seen) "install.sh")
        """) == .false)
    }

    /// Not installed: the op raises a dialog and copies NOTHING until
    /// that dialog comes back. This is the consent property stated as a
    /// test — the copy command must not appear on the shell runner from
    /// the press alone. The dialog itself goes out through the async
    /// dialog seam, which is uninstalled here, so nothing is raised.
    @Test func installWhenAbsentWritesNothingBeforeConfirmation() throws {
        let engine = try engine(answer: "no\n")
        let payload = try payloadDirectory()
        try engine.evaluate("(code:current-vscode-companion-payload-dir \"\(payload)\")")
        _ = try engine.evaluate("(code:install-companion!)")
        // One command only, and it is the probe.
        #expect(try engine.evaluate("(= (length seen) 1)") == .true)
        #expect(try engine.evaluate("""
          (string-contains? (car seen) "install.sh")
        """) == .false)
    }
}
