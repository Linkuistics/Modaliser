import Testing
@testable import Modaliser

/// The *native* shell primitive — the raw `/bin/zsh -c` spawn.
///
/// These are the only tests in the suite that actually run a subprocess, and
/// they name `run-shell-native` deliberately: the portable `run-shell` the
/// backends call is a seam that stays inert under `swift test` (ADR-0023), so
/// covering the spawn itself means reaching past that seam on purpose. Every
/// command below is a self-contained `echo`/`printf` that touches nothing on
/// the machine.
@Suite("Shell Library (native)")
struct ShellLibraryTests {

    // MARK: - Library registration

    @Test func runShellNativeFunctionExists() throws {
        let engine = try SchemeEngine()
        let result = try engine.evaluate(#"(run-shell-native "echo hello")"#)
        _ = result
    }

    // MARK: - run-shell-native

    @Test func runShellReturnsCommandOutput() throws {
        let engine = try SchemeEngine()
        let result = try engine.evaluate(#"(run-shell-native "echo hello")"#)
        #expect(try result.asString() == "hello\n")
    }

    @Test func runShellCapturesMultiLineOutput() throws {
        let engine = try SchemeEngine()
        let result = try engine.evaluate(#"(run-shell-native "printf 'line1\nline2'")"#)
        #expect(try result.asString() == "line1\nline2")
    }

    @Test func runShellReturnsEmptyStringForNoOutput() throws {
        let engine = try SchemeEngine()
        let result = try engine.evaluate(#"(run-shell-native "true")"#)
        #expect(try result.asString() == "")
    }

    @Test func runShellUsesShellForPipesAndRedirects() throws {
        let engine = try SchemeEngine()
        let result = try engine.evaluate(#"(run-shell-native "echo abc | tr a-z A-Z")"#)
        #expect(try result.asString() == "ABC\n")
    }

    @Test func runShellReturnsOutputEvenOnNonZeroExit() throws {
        let engine = try SchemeEngine()
        // 'ls' on a non-existent path outputs to stderr, stdout is empty
        let result = try engine.evaluate(#"(run-shell-native "echo err && exit 1")"#)
        #expect(try result.asString() == "err\n")
    }
}
