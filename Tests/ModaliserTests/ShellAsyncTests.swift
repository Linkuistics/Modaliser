import Testing
import Foundation
import LispKit
@testable import Modaliser

@Suite("Shell Library – run-shell-async")
@MainActor
struct ShellAsyncTests {

    // MARK: - Sync regression

    @Test func syncRunShellStillWorks() throws {
        let engine = try SchemeEngine()
        let result = try engine.evaluate(#"(run-shell "echo hello")"#)
        #expect(try result.asString() == "hello\n")
    }

    // MARK: - Async callback

    @Test func asyncCallbackReceivesCorrectOutput() async throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(define async-result #f)")
        try engine.evaluate("""
            (run-shell-async "echo hello"
              (lambda (code out err)
                (set! async-result (list code out err))))
            """)

        let result = try await waitForSchemeValue(engine: engine, variable: "async-result")
        let values = listToArray(result)
        #expect(values.count == 3)
        #expect(try values[0].asInt64() == 0, "Exit code should be 0")
        #expect(try values[1].asString() == "hello\n", "Stdout should contain output")
        #expect(try values[2].asString() == "", "Stderr should be empty")
    }

    @Test func asyncCallbackReceivesNonZeroExitCode() async throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(define async-result #f)")
        try engine.evaluate("""
            (run-shell-async "exit 42"
              (lambda (code out err)
                (set! async-result (list code out err))))
            """)

        let result = try await waitForSchemeValue(engine: engine, variable: "async-result")
        let values = listToArray(result)
        #expect(values.count >= 1)
        #expect(try values[0].asInt64() == 42, "Exit code should be 42")
    }

    @Test func asyncCallbackReceivesStderr() async throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(define async-result #f)")
        try engine.evaluate("""
            (run-shell-async "echo err >&2"
              (lambda (code out err)
                (set! async-result (list code out err))))
            """)

        let result = try await waitForSchemeValue(engine: engine, variable: "async-result")
        let values = listToArray(result)
        #expect(values.count >= 3)
        #expect(try values[2].asString() == "err\n", "Stderr should contain error output")
    }

    // MARK: - Timeout

    @Test func timeoutKillsProcessAndReportsTimeout() async throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(define async-result #f)")
        try engine.evaluate("""
            (run-shell-async "sleep 30"
              (lambda (code out err)
                (set! async-result (list code out err)))
              'timeout 1)
            """)

        let result = try await waitForSchemeValue(engine: engine, variable: "async-result", timeout: 5.0)
        let values = listToArray(result)
        #expect(values.count >= 3)
        #expect(try values[0].asInt64() == -1, "Exit code should be -1 on timeout")
        #expect(try values[2].asString() == "timeout", "Stderr should be 'timeout'")
    }

    // MARK: - Helpers

    /// Yield the main actor repeatedly until a Scheme variable is no longer #f.
    /// Task.sleep suspends the current task, allowing GCD main queue blocks to execute.
    private func waitForSchemeValue(
        engine: SchemeEngine,
        variable: String,
        timeout: TimeInterval = 5.0
    ) async throws -> Expr {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            let value = try engine.evaluate(variable)
            if case .false = value {
                continue
            }
            return value
        }
        Issue.record("Timed out waiting for \(variable) to be set")
        return .false
    }

    /// Convert a Scheme list to a Swift array.
    private func listToArray(_ expr: Expr) -> [Expr] {
        var result: [Expr] = []
        var current = expr
        while case .pair(let head, let tail) = current {
            result.append(head)
            current = tail
        }
        return result
    }
}
