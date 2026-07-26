import Foundation
import Testing
import LispKit
@testable import Modaliser

/// A bad config must never wedge the app (config-failure-degrades-k43).
///
/// The seam under test is `SchemeEngine.loadConfiguration` — the host-sequenced
/// config boot. It exists in Swift rather than in `root.scm` because LispKit's
/// `guard` only catches conditions a Scheme program *raised*; a read error, a
/// type error, or an unbound variable is thrown out of the virtual machine and
/// unwinds past every Scheme handler (ADR-0022). The host is the only place
/// that can see such an abort and still have an engine to talk to.
@Suite("Config robustness (degrade, never wedge)")
struct ConfigRobustnessTests {

    // MARK: - Fixtures

    /// An engine with the same module set `root.scm` establishes, minus the
    /// host-only parts (permissions, status bar, keyboard capture) — the
    /// environment a user config is evaluated into.
    private func bootedEngine() throws -> (SchemeEngine, String) {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else {
            throw SchemeTestError.noSchemeDir
        }
        try engine.evaluate("""
            (define webview-create-calls '())
            (define (webview-create id opts)
              (set! webview-create-calls (cons id webview-create-calls)) id)
            (define (webview-close id) #t)
            (define (webview-set-html! id html) #t)
            (define (webview-on-message id handler) #t)
            (define (webview-eval id js) #t)
            """)
        try engine.evaluate("""
          (import (modaliser util)
                  (modaliser keymap)
                  (modaliser fsm)
                  (modaliser configuration)
                  (modaliser handoff))
        """)
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")
        try engine.evaluate("(import (modaliser terminal))")
        try engine.evaluate("(import (modaliser ax-hints))")
        try engine.evaluate("(import (modaliser dom))")
        try engine.evaluate("(import (modaliser web-search))")
        for file in ["ui/css.scm", "ui/overlay.scm", "ui/chooser.scm"] {
            try engine.evaluateFile(schemePath + "/" + file)
        }
        try engine.evaluate("(set-chooser-push! chooser-push-results)")
        return (engine, schemePath)
    }

    private func writeConfig(_ body: String) throws -> String {
        let dir = NSTemporaryDirectory() + "modaliser-config-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = dir + "/config.scm"
        try body.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    /// True iff the bundled default's configuration reached the engine: its
    /// screens are in the graph and its leaders are armed.
    private func defaultConfigIsArmed(_ engine: SchemeEngine) throws -> Bool {
        guard try engine.evaluate("(fsm-state-ref \"global\")") != .false,
              try engine.evaluate("(fsm-state-ref \"com.googlecode.iterm2\")") != .false else {
            return false
        }
        let kbLib = try engine.context.libraries.lookup(KeyboardLibrary.self)!
        return kbLib.handlerRegistry.hotkeyHandlers[HotkeyKey(keyCode: KeyCode.f18, modifiers: [])] != nil
    }

    // MARK: - The happy path stays the happy path

    @Test func cleanConfigLoadsWithoutFallback() throws {
        let (engine, schemePath) = try bootedEngine()
        let outcome = engine.loadConfiguration(
            userConfigPath: schemePath + "/default-config.scm",
            fallbackPath: schemePath + "/default-config.scm")
        #expect(outcome == .loaded)
        #expect(outcome.errorText == nil)
        #expect(try defaultConfigIsArmed(engine))
    }

    // MARK: - The three failure modes

    /// (1) A Scheme *read* error — the config never parses.
    @Test func syntaxErrorDegradesToBundledDefault() throws {
        let (engine, schemePath) = try bootedEngine()
        let broken = try writeConfig("(import (modaliser dsl)\n(define x 1)\n")
        let outcome = engine.loadConfiguration(
            userConfigPath: broken,
            fallbackPath: schemePath + "/default-config.scm")

        guard case .degraded(let message) = outcome else {
            Issue.record("expected .degraded, got \(outcome)")
            return
        }
        #expect(message.contains("parenthesis"))
        #expect(try defaultConfigIsArmed(engine))
    }

    /// (2) A runtime error part-way through evaluation.
    @Test func evalErrorDegradesToBundledDefault() throws {
        let (engine, schemePath) = try bootedEngine()
        let broken = try writeConfig("(define marker 1)\n(car '())\n")
        let outcome = engine.loadConfiguration(
            userConfigPath: broken,
            fallbackPath: schemePath + "/default-config.scm")

        guard case .degraded(let message) = outcome else {
            Issue.record("expected .degraded, got \(outcome)")
            return
        }
        #expect(message.contains("type error"))
        #expect(try defaultConfigIsArmed(engine))
    }

    /// (3) Version skew: the config names a form this binary no longer binds.
    /// This is the case the public release cares about most — it is what a
    /// user's config hits after a library export is deleted.
    @Test func unboundSymbolDegradesToBundledDefault() throws {
        let (engine, schemePath) = try bootedEngine()
        let broken = try writeConfig("(define-tree \"global\" (list))\n")
        let outcome = engine.loadConfiguration(
            userConfigPath: broken,
            fallbackPath: schemePath + "/default-config.scm")

        guard case .degraded(let message) = outcome else {
            Issue.record("expected .degraded, got \(outcome)")
            return
        }
        #expect(message.contains("define-tree"))
        #expect(try defaultConfigIsArmed(engine))
    }

    // MARK: - Why the fallback is safe

    /// A config that dies *after* composing screens but *before* the Handoff
    /// has installed nothing (ADR-0018: validation is front-loaded, the
    /// one-shot latch sets only on success). That is precisely what lets the
    /// bundled default load into the same engine without colliding.
    @Test func partiallyEvaluatedConfigLeavesEngineInstallable() throws {
        let (engine, schemePath) = try bootedEngine()
        let broken = try writeConfig("""
            (import (modaliser dsl) (modaliser configuration) (modaliser handoff))
            (define half-built
              (screen 'global (key "x" "Nope" (command (lambda () #t)))))
            (car '())
            (modaliser:start! (configuration half-built))
            """)
        let outcome = engine.loadConfiguration(
            userConfigPath: broken,
            fallbackPath: schemePath + "/default-config.scm")

        #expect(outcome.errorText != nil)
        #expect(try defaultConfigIsArmed(engine))
        // The half-built screen never reached the graph — the "x" key the
        // broken config authored is not live.
        #expect(try engine.evaluate("(fsm-state-ref \"global\")") != .false)
    }

    // MARK: - Both halves failing is reported, not hidden

    @Test func fallbackFailureIsReportedSeparately() throws {
        let (engine, _) = try bootedEngine()
        let broken = try writeConfig("(car '())\n")
        let outcome = engine.loadConfiguration(
            userConfigPath: broken,
            fallbackPath: "/nonexistent/default-config.scm")

        guard case .failed(let userError, let fallbackError) = outcome else {
            Issue.record("expected .failed, got \(outcome)")
            return
        }
        #expect(userError.contains("type error"))
        #expect(!fallbackError.isEmpty)
        #expect(outcome.errorText == userError)
    }

    // MARK: - root.scm is the one file with nothing behind it

    /// `root.scm` cannot be evaluated under `swift test` — it asks for
    /// Accessibility permission and builds a status bar. But it is the single
    /// file whose failure leaves no menu and no capture to recover with, so at
    /// minimum it must read: parse it, and pin the two entry points the host
    /// calls into after loading it.
    @Test func rootSchemeFileParsesAndDeclaresItsHostEntryPoints() throws {
        let (engine, schemePath) = try bootedEngine()
        let rootPath = schemePath + "/root.scm"
        _ = try engine.context.evaluator.parse(file: rootPath)

        let source = try String(contentsOfFile: rootPath, encoding: .utf8)
        // ModaliserAppDelegate.bootConfiguration reads these three names.
        #expect(source.contains("(define user-config-path"))
        #expect(source.contains("(define default-config-path"))
        #expect(source.contains("(define (modaliser:config-load-finished! status message)"))
    }

    // MARK: - The error text is actionable

    /// The message a user sees names the thing that failed. LispKit attaches a
    /// source position to a *read* error but not to an unbound variable, so the
    /// text is the binding's name, not a line number — which is why the
    /// user-facing sentence naming the config file is composed in `root.scm`
    /// rather than left to the descriptor.
    @Test func errorTextNamesTheFailure() throws {
        let (engine, schemePath) = try bootedEngine()
        let broken = try writeConfig("(define ok 1)\n(no-such-binding 2)\n")
        let outcome = engine.loadConfiguration(
            userConfigPath: broken,
            fallbackPath: schemePath + "/default-config.scm")

        let message = try #require(outcome.errorText)
        #expect(message.contains("no-such-binding"))
        #expect(!message.contains("call trace"))
    }
}
