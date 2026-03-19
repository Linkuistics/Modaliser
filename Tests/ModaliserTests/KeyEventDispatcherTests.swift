import Testing
import CoreGraphics
import LispKit
@testable import Modaliser

@Suite("KeyEventDispatcher")
struct KeyEventDispatcherTests {

    // MARK: - Helpers

    private func makeSetup() throws -> (KeyEventDispatcher, SchemeEngine) {
        let engine = try SchemeEngine()
        _ = try engine.evaluate("""
            (set-leader! 'global F18)
            (set-leader! 'local F17)
            (define call-log '())
            (define-tree 'global
              (key "s" "Safari"
                (lambda () (set! call-log (cons 's call-log))))
              (key "t" "Terminal"
                (lambda () (set! call-log (cons 't call-log))))
              (group "f" "Find"
                (key "a" "Apps"
                  (lambda () (set! call-log (cons 'a call-log))))))
            """)
        let dispatcher = KeyEventDispatcher(
            registry: engine.registry,
            executor: CommandExecutor(engine: engine)
        )
        return (dispatcher, engine)
    }

    private func keyDown(_ keyCode: CGKeyCode, modifiers: CGEventFlags = []) -> CapturedKeyEvent {
        CapturedKeyEvent(keyCode: keyCode, isKeyDown: true, modifiers: modifiers)
    }

    private func keyUp(_ keyCode: CGKeyCode, modifiers: CGEventFlags = []) -> CapturedKeyEvent {
        CapturedKeyEvent(keyCode: keyCode, isKeyDown: false, modifiers: modifiers)
    }

    // MARK: - Leader key activation

    @Test func leaderKeyActivatesModal() throws {
        let (dispatcher, _) = try makeSetup()
        let result = dispatcher.handleKeyEvent(keyDown(KeyCode.f18))
        #expect(result == .suppress)
        #expect(dispatcher.isModalActive)
    }

    @Test func leaderKeyRePressDuringModalExits() throws {
        let (dispatcher, _) = try makeSetup()
        _ = dispatcher.handleKeyEvent(keyDown(KeyCode.f18))
        let result = dispatcher.handleKeyEvent(keyDown(KeyCode.f18))
        #expect(result == .suppress)
        #expect(!dispatcher.isModalActive)
    }

    // MARK: - Key up passthrough

    @Test func keyUpEventsPassThrough() throws {
        let (dispatcher, _) = try makeSetup()
        let result = dispatcher.handleKeyEvent(keyUp(KeyCode.f18))
        #expect(result == .passThrough)
    }

    // MARK: - Command execution

    @Test func modalKeyExecutesCommand() throws {
        let (dispatcher, engine) = try makeSetup()
        _ = dispatcher.handleKeyEvent(keyDown(KeyCode.f18)) // enter
        _ = dispatcher.handleKeyEvent(keyDown(1))            // "s" = Safari
        let length = try engine.evaluate("(length call-log)")
        #expect(length == .fixnum(1))
        #expect(!dispatcher.isModalActive)
    }

    // MARK: - Group navigation

    @Test func modalKeyNavigatesIntoGroup() throws {
        let (dispatcher, _) = try makeSetup()
        _ = dispatcher.handleKeyEvent(keyDown(KeyCode.f18)) // enter
        _ = dispatcher.handleKeyEvent(keyDown(3))            // "f" = Find group
        #expect(dispatcher.isModalActive)
        #expect(dispatcher.currentNodeLabel == "Find")
    }

    @Test func commandInGroupExecutes() throws {
        let (dispatcher, engine) = try makeSetup()
        _ = dispatcher.handleKeyEvent(keyDown(KeyCode.f18)) // enter
        _ = dispatcher.handleKeyEvent(keyDown(3))            // "f" = Find
        _ = dispatcher.handleKeyEvent(keyDown(0))            // "a" = Apps
        let length = try engine.evaluate("(length call-log)")
        #expect(length == .fixnum(1))
        #expect(!dispatcher.isModalActive)
    }

    // MARK: - Escape exits

    @Test func escapeExitsModal() throws {
        let (dispatcher, _) = try makeSetup()
        _ = dispatcher.handleKeyEvent(keyDown(KeyCode.f18)) // enter
        let result = dispatcher.handleKeyEvent(keyDown(KeyCode.escape))
        #expect(result == .suppress)
        #expect(!dispatcher.isModalActive)
    }

    // MARK: - Delete steps back

    @Test func deleteStepsBackInGroup() throws {
        let (dispatcher, _) = try makeSetup()
        _ = dispatcher.handleKeyEvent(keyDown(KeyCode.f18)) // enter
        _ = dispatcher.handleKeyEvent(keyDown(3))            // "f" = Find
        #expect(dispatcher.currentNodeLabel == "Find")
        let result = dispatcher.handleKeyEvent(keyDown(KeyCode.delete))
        #expect(result == .suppress)
        #expect(dispatcher.currentNodeLabel == "Global")
        #expect(dispatcher.isModalActive)
    }

    @Test func deleteAtRootExitsModal() throws {
        let (dispatcher, _) = try makeSetup()
        _ = dispatcher.handleKeyEvent(keyDown(KeyCode.f18)) // enter
        _ = dispatcher.handleKeyEvent(keyDown(KeyCode.delete))
        #expect(!dispatcher.isModalActive)
    }

    // MARK: - Unknown key exits

    @Test func unknownKeyExitsModal() throws {
        let (dispatcher, _) = try makeSetup()
        _ = dispatcher.handleKeyEvent(keyDown(KeyCode.f18)) // enter
        let result = dispatcher.handleKeyEvent(keyDown(KeyCode.tab)) // tab is not mapped as modal key
        #expect(result == .suppress)
        #expect(!dispatcher.isModalActive)
    }

    // MARK: - Non-modal keys pass through when idle

    @Test func regularKeysPassThroughWhenIdle() throws {
        let (dispatcher, _) = try makeSetup()
        let result = dispatcher.handleKeyEvent(keyDown(0)) // "a"
        #expect(result == .passThrough)
    }

    // MARK: - All modal keys suppress when active

    @Test func modalKeySuppressesEvent() throws {
        let (dispatcher, _) = try makeSetup()
        _ = dispatcher.handleKeyEvent(keyDown(KeyCode.f18))
        let result = dispatcher.handleKeyEvent(keyDown(1)) // "s"
        #expect(result == .suppress)
    }

    // MARK: - Modifier keys ignored during modal

    @Test func modifierOnlyEventsPassThrough() throws {
        let (dispatcher, _) = try makeSetup()
        _ = dispatcher.handleKeyEvent(keyDown(KeyCode.f18)) // enter modal
        // Key with cmd modifier should pass through (not a modal key press)
        let result = dispatcher.handleKeyEvent(keyDown(0, modifiers: .maskCommand))
        #expect(result == .passThrough)
    }
}
