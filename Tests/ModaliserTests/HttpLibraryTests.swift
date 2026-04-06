import Testing
import Foundation
import LispKit
@testable import Modaliser

@Suite("HTTP Library – http-get")
@MainActor
struct HttpLibraryTests {

    // MARK: - Library registration

    @Test func httpGetFunctionExists() throws {
        let engine = try SchemeEngine()
        // Should not throw — the procedure is defined
        let result = try engine.evaluate("http-get")
        #expect(result != .void, "http-get should be a defined procedure")
    }

    // MARK: - Successful GET

    @Test func httpGetCallsCallbackWithResponseString() async throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(define http-result #f)")
        // Use a well-known public URL that returns a predictable JSON response
        try engine.evaluate("""
            (http-get "https://httpbin.org/get?test=hello"
              (lambda (response)
                (set! http-result response)))
            """)

        let result = try await waitForSchemeValue(engine: engine, variable: "http-result", timeout: 10.0)
        // httpbin.org/get returns JSON containing the query params
        let responseString = try result.asString()
        #expect(responseString.contains("hello"), "Response should contain the query parameter value")
    }

    // MARK: - Error handling

    @Test func httpGetCallsFalseOnInvalidUrl() async throws {
        let engine = try SchemeEngine()
        // Use a sentinel different from #f so we can detect the callback fired
        try engine.evaluate("(define http-result 'pending)")
        try engine.evaluate("""
            (http-get "http://localhost:1"
              (lambda (response)
                (set! http-result response)))
            """)

        let result = try await waitForSchemeValue(
            engine: engine,
            variable: "http-result",
            timeout: 10.0,
            predicate: { expr in
                if case .symbol(_) = expr { return false }  // still 'pending
                return true
            }
        )
        #expect(result == .false, "Callback should receive #f on network error")
    }

    // MARK: - Argument validation

    @Test func httpGetRequiresStringUrl() throws {
        let engine = try SchemeEngine()
        #expect(throws: Error.self) {
            try engine.evaluate("""
                (http-get 42 (lambda (r) r))
                """)
        }
    }

    @Test func httpGetRequiresProcedureCallback() throws {
        let engine = try SchemeEngine()
        #expect(throws: Error.self) {
            try engine.evaluate("""
                (http-get "http://example.com" "not-a-procedure")
                """)
        }
    }

    // MARK: - Helpers

    private func waitForSchemeValue(
        engine: SchemeEngine,
        variable: String,
        timeout: TimeInterval = 5.0,
        predicate: ((Expr) -> Bool)? = nil
    ) async throws -> Expr {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            let value = try engine.evaluate(variable)
            if let predicate = predicate {
                if predicate(value) { return value }
            } else {
                if case .false = value { continue }
                return value
            }
        }
        Issue.record("Timed out waiting for \(variable) to be set")
        return .false
    }
}
