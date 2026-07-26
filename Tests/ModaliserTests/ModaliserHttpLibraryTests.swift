import Testing
@testable import Modaliser

/// `(modaliser http)` — the seam every outward fetch in the tree passes through
/// (test-live-network-contact-k51, ADR-0023).
///
/// The property under test is a *negative* one, and it is the reason a green run
/// no longer needs `--skip HttpLibraryTests`: with no runner installed, an
/// `http-get` call reaches no endpoint. The tree has one HTTP consumer —
/// `(modaliser web-search)`'s Google Suggest fetch — so these assertions carry
/// it, and would carry any future one.
@Suite("(modaliser http) seam")
struct ModaliserHttpLibraryTests {

    private func engineWithHttp() throws -> SchemeEngine {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser http))")
        return engine
    }

    // MARK: - Inert by default

    /// The whole point: a bare engine has no runner, so nothing can be fetched.
    /// `swift test` never runs root.scm, which is the only installer.
    @Test func noRunnerIsInstalledByDefault() throws {
        let engine = try engineWithHttp()
        #expect(try engine.evaluate("(current-http-runner)") == .false)
    }

    /// An uninstalled runner answers the callback with `#f` — the same value
    /// `(modaliser web-search)` already reads as "network error, keep showing
    /// just the pinned suggestion". No caller needs a branch for the inert
    /// case, which is why the seam dropped under the one consumer without
    /// editing it.
    @Test func callbackReceivesFalseWhenInert() throws {
        let engine = try engineWithHttp()
        try engine.evaluate("(define answer 'pending)")
        try engine.evaluate("""
            (http-get "data:text/plain,definitely-not-fetched"
              (lambda (response) (set! answer response)))
            """)
        #expect(try engine.evaluate("answer") == .false,
                "The callback must fire — answered, not stranded (ADR-0014)")
    }

    /// The endpoint the suite used to fetch on every green run, now reaching
    /// nothing. Written with the real URL rather than a placeholder so the test
    /// reads as what it protects against.
    @Test func thePublicEndpointReachesNothingWhenInert() throws {
        let engine = try engineWithHttp()
        try engine.evaluate("(define answer 'pending)")
        try engine.evaluate("""
            (http-get "https://httpbin.org/get?test=hello"
              (lambda (response) (set! answer response)))
            """)
        #expect(try engine.evaluate("answer") == .false)
    }

    /// Same, for the endpoint nothing had *yet* reached: Google Suggest is one
    /// three-character query away from any test that drives the web-search
    /// chooser, and before the seam existed that was the only thing keeping the
    /// suite off it.
    @Test func googleSuggestReachesNothingWhenInert() throws {
        let engine = try engineWithHttp()
        try engine.evaluate("(define answer 'pending)")
        try engine.evaluate("""
            (http-get "https://suggestqueries.google.com/complete/search?client=firefox&q=hello"
              (lambda (response) (set! answer response)))
            """)
        #expect(try engine.evaluate("answer") == .false)
    }

    // MARK: - An installed runner is used

    /// What root.scm does at bootstrap, in miniature: install a runner and the
    /// seam dispatches to it, verbatim URL in.
    @Test func installedRunnerReceivesTheUrl() throws {
        let engine = try engineWithHttp()
        try engine.evaluate("""
            (define seen '())
            (current-http-runner
              (lambda (url callback)
                (set! seen (cons url seen))
                (callback "canned body")))
            (define answer #f)
            (http-get "https://example.test/q?x=1"
              (lambda (response) (set! answer response)))
            """)
        #expect(try engine.evaluate("answer").asString() == "canned body")
        #expect(try engine.evaluate("(car seen)").asString() == "https://example.test/q?x=1")
    }

    /// Genuinely a parameter, so a test can scope a canned runner to one
    /// dynamic extent and leave the suite inert outside it.
    @Test func runnerIsParameterizable() throws {
        let engine = try engineWithHttp()
        try engine.evaluate("""
            (define during #f)
            (define after 'pending)
            (parameterize ((current-http-runner
                             (lambda (url callback) (callback "inside"))))
              (http-get "https://example.test/" (lambda (r) (set! during r))))
            (http-get "https://example.test/" (lambda (r) (set! after r)))
            """)
        #expect(try engine.evaluate("during").asString() == "inside")
        #expect(try engine.evaluate("after") == .false)
    }

    // MARK: - The native capability is a separate library

    /// The native fetch exists and is reachable — by its own name, from the
    /// host. The seam's inertness is a wiring fact, not a missing capability,
    /// and root.scm closes exactly this gap at boot.
    @Test func theNativeFetchIsDistinctlyNamed() throws {
        let engine = try SchemeEngine()
        #expect(try engine.evaluate("(procedure? http-get-native)") == .true)
    }

    // MARK: - The host install

    /// `root.scm` cannot be evaluated under `swift test` (it asks for
    /// Accessibility and builds a status bar), so the install is pinned
    /// textually — the same way the shell seam's is, and the way
    /// ConfigRobustnessTests pins root.scm's host entry points.
    ///
    /// Unlike the shell runners this pins *presence*, not position: nothing in
    /// the tree fetches at import time, so no import may be reordered ahead of
    /// it to any effect. What would break silently is the install going
    /// missing — production would then run with an inert seam and a web search
    /// that returns only its pinned row, with nothing raised anywhere.
    @Test func rootSchemeInstallsTheHttpRunner() throws {
        let engine = try SchemeEngine()
        let schemePath = try #require(engine.schemeDirectoryPath)
        let source = try String(contentsOfFile: schemePath + "/root.scm", encoding: .utf8)
        #expect(source.contains("(current-http-runner http-get-native)"))
    }

    /// …and the forms that install it actually evaluate. The textual pin above
    /// cannot see a typo *inside* the `only` clause: root.scm imports the native
    /// library as `(only (modaliser http-native) http-get-native)`, and a
    /// misspelled export there would parse, satisfy the pin, and fail at boot —
    /// where nothing would raise, because the seam degrades silently. So run
    /// root.scm's exact wiring here, in a bare engine.
    ///
    /// (ConfigRobustnessTests parses root.scm on every run; what it cannot do is
    /// evaluate it — the real file asks for Accessibility and builds a status
    /// bar.)
    @Test func theRootSchemeWiringFormsEvaluate() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser http))")
        try engine.evaluate("(import (only (modaliser http-native) http-get-native))")
        #expect(try engine.evaluate("(current-http-runner)") == .false,
                "inert until the install runs")

        try engine.evaluate("(current-http-runner http-get-native)")
        #expect(try engine.evaluate("(procedure? (current-http-runner))") == .true,
                "the install must leave a live runner behind")
    }
}
