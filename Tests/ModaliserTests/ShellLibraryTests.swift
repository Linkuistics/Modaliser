import Testing
@testable import Modaliser

@Suite("Shell Library")
struct ShellLibraryTests {

    // MARK: - Library registration

    @Test func runShellFunctionExists() throws {
        let engine = try SchemeEngine()
        let result = try engine.evaluate(#"(run-shell "echo hello")"#)
        _ = result
    }

    // MARK: - run-shell

    @Test func runShellReturnsCommandOutput() throws {
        let engine = try SchemeEngine()
        let result = try engine.evaluate(#"(run-shell "echo hello")"#)
        #expect(try result.asString() == "hello\n")
    }

    @Test func runShellCapturesMultiLineOutput() throws {
        let engine = try SchemeEngine()
        let result = try engine.evaluate(#"(run-shell "printf 'line1\nline2'")"#)
        #expect(try result.asString() == "line1\nline2")
    }

    @Test func runShellReturnsEmptyStringForNoOutput() throws {
        let engine = try SchemeEngine()
        let result = try engine.evaluate(#"(run-shell "true")"#)
        #expect(try result.asString() == "")
    }

    @Test func runShellUsesShellForPipesAndRedirects() throws {
        let engine = try SchemeEngine()
        let result = try engine.evaluate(#"(run-shell "echo abc | tr a-z A-Z")"#)
        #expect(try result.asString() == "ABC\n")
    }

    @Test func runShellReturnsOutputEvenOnNonZeroExit() throws {
        let engine = try SchemeEngine()
        // 'ls' on a non-existent path outputs to stderr, stdout is empty
        let result = try engine.evaluate(#"(run-shell "echo err && exit 1")"#)
        #expect(try result.asString() == "err\n")
    }
}
