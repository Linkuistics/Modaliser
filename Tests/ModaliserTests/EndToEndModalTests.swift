import Testing
import CoreGraphics
import LispKit
@testable import Modaliser

@Suite("End-to-end modal flow")
struct EndToEndModalTests {

    // MARK: - Helpers

    private func keyDown(_ keyCode: CGKeyCode) -> CapturedKeyEvent {
        CapturedKeyEvent(keyCode: keyCode, isKeyDown: true, modifiers: [])
    }

    /// Load the project's config.scm and return a fully wired dispatcher + engine.
    private func makeDispatcherFromConfig() throws -> (KeyEventDispatcher, SchemeEngine) {
        let engine = try SchemeEngine()
        // Add tracking so we can verify actions were called
        _ = try engine.evaluate("(define execution-log '())")
        _ = try engine.evaluate("""
            (define (track-action name)
              (lambda () (set! execution-log (cons name execution-log))))
            """)
        // Build a test tree that uses trackable lambdas
        _ = try engine.evaluate("""
            (set-leader! 'global F18)
            (define-tree 'global
              (key "s" "Safari" (track-action "safari"))
              (key "t" "Terminal" (track-action "terminal"))
              (group "f" "Find"
                (key "a" "Apps" (track-action "find-apps"))
                (key "b" "Browser" (track-action "find-browser")))
              (group "w" "Windows"
                (key "c" "Center" (track-action "center-window"))
                (key "m" "Maximize" (track-action "maximize-window"))))
            """)
        let executor = CommandExecutor(engine: engine)
        let dispatcher = KeyEventDispatcher(
            registry: engine.registry,
            executor: executor
        )
        return (dispatcher, engine)
    }

    // MARK: - Full key sequences

    @Test func f18ThenSExecutesSafari() throws {
        let (dispatcher, engine) = try makeDispatcherFromConfig()
        _ = dispatcher.handleKeyEvent(keyDown(KeyCode.f18))
        _ = dispatcher.handleKeyEvent(keyDown(1)) // "s"
        let log = try engine.evaluate("execution-log")
        let first = try engine.evaluate("(car execution-log)")
        #expect(first == .makeString("safari"))
    }

    @Test func f18ThenFThenAExecutesFindApps() throws {
        let (dispatcher, engine) = try makeDispatcherFromConfig()
        _ = dispatcher.handleKeyEvent(keyDown(KeyCode.f18))
        _ = dispatcher.handleKeyEvent(keyDown(3)) // "f"
        _ = dispatcher.handleKeyEvent(keyDown(0)) // "a"
        let first = try engine.evaluate("(car execution-log)")
        #expect(first == .makeString("find-apps"))
    }

    @Test func f18ThenWThenMExecutesMaximize() throws {
        let (dispatcher, engine) = try makeDispatcherFromConfig()
        _ = dispatcher.handleKeyEvent(keyDown(KeyCode.f18))
        _ = dispatcher.handleKeyEvent(keyDown(13)) // "w"
        _ = dispatcher.handleKeyEvent(keyDown(46)) // "m"
        let first = try engine.evaluate("(car execution-log)")
        #expect(first == .makeString("maximize-window"))
    }

    @Test func escapeExitsWithoutExecution() throws {
        let (dispatcher, engine) = try makeDispatcherFromConfig()
        _ = dispatcher.handleKeyEvent(keyDown(KeyCode.f18))
        _ = dispatcher.handleKeyEvent(keyDown(KeyCode.escape))
        let log = try engine.evaluate("execution-log")
        #expect(log == .null) // empty list
    }

    @Test func deleteStepsBackThenContinue() throws {
        let (dispatcher, engine) = try makeDispatcherFromConfig()
        _ = dispatcher.handleKeyEvent(keyDown(KeyCode.f18))
        _ = dispatcher.handleKeyEvent(keyDown(3)) // "f" → Find
        _ = dispatcher.handleKeyEvent(keyDown(KeyCode.delete)) // back to root
        _ = dispatcher.handleKeyEvent(keyDown(1)) // "s" → Safari
        let first = try engine.evaluate("(car execution-log)")
        #expect(first == .makeString("safari"))
    }

    @Test func reactivateAfterExecution() throws {
        let (dispatcher, engine) = try makeDispatcherFromConfig()
        // First sequence: Safari
        _ = dispatcher.handleKeyEvent(keyDown(KeyCode.f18))
        _ = dispatcher.handleKeyEvent(keyDown(1)) // "s"
        // Second sequence: Terminal
        _ = dispatcher.handleKeyEvent(keyDown(KeyCode.f18))
        _ = dispatcher.handleKeyEvent(keyDown(17)) // "t"
        let length = try engine.evaluate("(length execution-log)")
        #expect(length == .fixnum(2))
        let first = try engine.evaluate("(car execution-log)")
        #expect(first == .makeString("terminal"))
    }

    @Test func unknownKeyExitsAndNoExecution() throws {
        let (dispatcher, engine) = try makeDispatcherFromConfig()
        _ = dispatcher.handleKeyEvent(keyDown(KeyCode.f18))
        _ = dispatcher.handleKeyEvent(keyDown(6)) // "z" — no binding
        let log = try engine.evaluate("execution-log")
        #expect(log == .null)
        #expect(dispatcher.stateMachine.isIdle)
    }

    @Test func keysWhenIdlePassThrough() throws {
        let (dispatcher, _) = try makeDispatcherFromConfig()
        let result = dispatcher.handleKeyEvent(keyDown(0)) // "a" when idle
        #expect(result == .passThrough)
    }

    @Test func allModalKeySuppressWhenActive() throws {
        let (dispatcher, _) = try makeDispatcherFromConfig()
        let leaderResult = dispatcher.handleKeyEvent(keyDown(KeyCode.f18))
        #expect(leaderResult == .suppress)
        let keyResult = dispatcher.handleKeyEvent(keyDown(1)) // "s"
        #expect(keyResult == .suppress)
    }
}
