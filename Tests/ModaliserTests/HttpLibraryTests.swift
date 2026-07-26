import Testing
import Foundation
import LispKit
@testable import Modaliser

/// The *native* fetch primitive — the raw `URLSession` request.
///
/// These tests name `http-get-native` deliberately: the portable `http-get` the
/// tree calls is a seam that stays inert under `swift test` (ADR-0023), so
/// covering the fetch itself means reaching past that seam on purpose.
///
/// They reach no endpoint even so. Every URL below is one the URL loading
/// system resolves **without leaving the machine** — a `data:` URL carrying its
/// own body, or a `file:` URL that does not exist — which is enough to drive the
/// whole primitive: argument validation, the URLSession round trip, marshalling
/// the bytes into a Scheme string, and the main-queue-plus-eval-lock hop that
/// hands the result to the callback. What a live `https://` fetch would add is
/// coverage of Foundation's HTTP stack and of a third party's uptime; the test
/// that used to do it went red on a 503 from httpbin.org
/// (test-live-network-contact-k51).
@Suite("HTTP Library (native)")
@MainActor
struct HttpLibraryTests {

    // MARK: - Library registration

    @Test func httpGetNativeFunctionExists() throws {
        let engine = try SchemeEngine()
        // Should not throw — the procedure is defined
        let result = try engine.evaluate("http-get-native")
        #expect(result != .void, "http-get-native should be a defined procedure")
    }

    // MARK: - Successful fetch

    @Test func callbackReceivesTheResponseBody() async throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(define http-result #f)")
        try engine.evaluate("""
            (http-get-native "data:text/plain,hello%20from%20a%20data%20url"
              (lambda (response)
                (set! http-result response)))
            """)

        let result = try await waitForSchemeValue(engine: engine, variable: "http-result", timeout: 10.0)
        let responseString = try result.asString()
        #expect(responseString == "hello from a data url",
                "Callback should receive the response body verbatim")
    }

    /// A multi-line body, so the string marshalling is pinned past the first
    /// newline rather than only on a single short token.
    @Test func callbackReceivesMultiLineBody() async throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(define http-result #f)")
        try engine.evaluate("""
            (http-get-native "data:text/plain,line1%0Aline2"
              (lambda (response)
                (set! http-result response)))
            """)

        let result = try await waitForSchemeValue(engine: engine, variable: "http-result", timeout: 10.0)
        #expect(try result.asString() == "line1\nline2")
    }

    // MARK: - Error handling

    /// A request that fails degrades to `#f` rather than raising — the value
    /// `(modaliser web-search)` already reads as "the endpoint told us
    /// nothing". Driven with a `file:` URL for a path that does not exist:
    /// deterministic and instant, where the old `http://localhost:1` version
    /// depended on nothing happening to be bound to port 1.
    @Test func callbackReceivesFalseOnFailedRequest() async throws {
        let engine = try SchemeEngine()
        // Use a sentinel different from #f so we can detect the callback fired
        try engine.evaluate("(define http-result 'pending)")
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("modaliser-k51-no-such-file.txt")
        try? FileManager.default.removeItem(at: missing)
        try engine.evaluate("""
            (http-get-native "\(missing.absoluteString)"
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
        #expect(result == .false, "Callback should receive #f on a failed request")
    }

    // MARK: - Argument validation

    @Test func httpGetRequiresStringUrl() throws {
        let engine = try SchemeEngine()
        #expect(throws: Error.self) {
            try engine.evaluate("""
                (http-get-native 42 (lambda (r) r))
                """)
        }
    }

    @Test func httpGetRequiresProcedureCallback() throws {
        let engine = try SchemeEngine()
        #expect(throws: Error.self) {
            try engine.evaluate("""
                (http-get-native "data:text/plain,x" "not-a-procedure")
                """)
        }
    }

    /// An unparseable URL is rejected before any request is attempted.
    @Test func httpGetRejectsMalformedUrl() throws {
        let engine = try SchemeEngine()
        #expect(throws: Error.self) {
            try engine.evaluate("""
                (http-get-native "" (lambda (r) r))
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
