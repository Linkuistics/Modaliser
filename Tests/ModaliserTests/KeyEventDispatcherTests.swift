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

    // MARK: - Overlay notifications

    private func makeSetupWithOverlay() throws -> (KeyEventDispatcher, MockOverlayPresenter) {
        let engine = try SchemeEngine()
        _ = try engine.evaluate("""
            (set-leader! 'global F18)
            (set-leader! 'local F17)
            (define-tree 'global
              (key "s" "Safari" (lambda () #t))
              (group "f" "Find"
                (key "a" "Apps" (lambda () #t))))
            """)
        let presenter = MockOverlayPresenter()
        let coordinator = OverlayCoordinator(presenter: presenter, showDelay: 0)
        let dispatcher = KeyEventDispatcher(
            registry: engine.registry,
            executor: CommandExecutor(engine: engine),
            overlayCoordinator: coordinator
        )
        return (dispatcher, presenter)
    }

    @Test func leaderKeyActivatesOverlay() throws {
        let (dispatcher, presenter) = try makeSetupWithOverlay()
        _ = dispatcher.handleKeyEvent(keyDown(KeyCode.f18))
        #expect(presenter.showCallCount == 1)
        #expect(presenter.lastShownContent?.header == "Global")
    }

    @Test func overlayShowsCorrectEntriesAtRoot() throws {
        let (dispatcher, presenter) = try makeSetupWithOverlay()
        _ = dispatcher.handleKeyEvent(keyDown(KeyCode.f18))
        let entries = presenter.lastShownContent?.entries ?? []
        #expect(entries.count == 2)
        #expect(entries[0].key == "f")
        #expect(entries[0].style == .group)
        #expect(entries[1].key == "s")
        #expect(entries[1].style == .command)
    }

    @Test func navigateIntoGroupUpdatesOverlay() throws {
        let (dispatcher, presenter) = try makeSetupWithOverlay()
        _ = dispatcher.handleKeyEvent(keyDown(KeyCode.f18))
        _ = dispatcher.handleKeyEvent(keyDown(3)) // "f" = Find
        #expect(presenter.showCallCount == 2)
        #expect(presenter.lastShownContent?.header == "Global \u{203A} Find")
    }

    @Test func escapeDeactivatesOverlay() throws {
        let (dispatcher, presenter) = try makeSetupWithOverlay()
        _ = dispatcher.handleKeyEvent(keyDown(KeyCode.f18))
        _ = dispatcher.handleKeyEvent(keyDown(KeyCode.escape))
        #expect(presenter.dismissCallCount == 1)
    }

    @Test func commandExecutionDeactivatesOverlay() throws {
        let (dispatcher, presenter) = try makeSetupWithOverlay()
        _ = dispatcher.handleKeyEvent(keyDown(KeyCode.f18))
        _ = dispatcher.handleKeyEvent(keyDown(1)) // "s" = Safari
        #expect(presenter.dismissCallCount == 1)
    }

    @Test func leaderRePressDuringModalDeactivatesOverlay() throws {
        let (dispatcher, presenter) = try makeSetupWithOverlay()
        _ = dispatcher.handleKeyEvent(keyDown(KeyCode.f18))
        _ = dispatcher.handleKeyEvent(keyDown(KeyCode.f18))
        #expect(presenter.dismissCallCount == 1)
    }

    @Test func deleteStepBackUpdatesOverlay() throws {
        let (dispatcher, presenter) = try makeSetupWithOverlay()
        _ = dispatcher.handleKeyEvent(keyDown(KeyCode.f18))
        _ = dispatcher.handleKeyEvent(keyDown(3)) // "f" = Find
        _ = dispatcher.handleKeyEvent(keyDown(KeyCode.delete))
        #expect(presenter.showCallCount == 3) // activate + navigate + step back
        #expect(presenter.lastShownContent?.header == "Global")
    }

    @Test func deleteAtRootDeactivatesOverlay() throws {
        let (dispatcher, presenter) = try makeSetupWithOverlay()
        _ = dispatcher.handleKeyEvent(keyDown(KeyCode.f18))
        _ = dispatcher.handleKeyEvent(keyDown(KeyCode.delete))
        #expect(presenter.dismissCallCount == 1)
    }

    @Test func noOverlayNotificationWhenCoordinatorIsNil() throws {
        // Original setup without overlay — should not crash
        let (dispatcher, _) = try makeSetup()
        _ = dispatcher.handleKeyEvent(keyDown(KeyCode.f18))
        _ = dispatcher.handleKeyEvent(keyDown(1))
        #expect(!dispatcher.isModalActive)
    }

    // MARK: - Chooser integration

    private func makeSetupWithChooser() throws -> (KeyEventDispatcher, MockChooserPresenter, SchemeEngine) {
        let engine = try SchemeEngine()
        _ = try engine.evaluate("""
            (set-leader! 'global F18)
            (define call-log '())
            (define-tree 'global
              (key "s" "Safari" (lambda () (set! call-log (cons 's call-log))))
              (group "f" "Find"
                (selector "a" "Find Apps"
                  'prompt "Find app…"
                  'source (lambda () (list (list (cons 'text "Safari"))))
                  'on-select (lambda (c) (set! call-log (cons 'selected call-log))))))
            """)
        let chooserPresenter = MockChooserPresenter()
        let chooserCoordinator = ChooserCoordinator(
            presenter: chooserPresenter,
            sourceInvoker: SelectorSourceInvoker(engine: engine),
            executor: CommandExecutor(engine: engine),
            theme: .default
        )
        let dispatcher = KeyEventDispatcher(
            registry: engine.registry,
            executor: CommandExecutor(engine: engine),
            chooserCoordinator: chooserCoordinator
        )
        return (dispatcher, chooserPresenter, engine)
    }

    @Test func selectorKeyOpensChooser() throws {
        let (dispatcher, chooserPresenter, _) = try makeSetupWithChooser()
        _ = dispatcher.handleKeyEvent(keyDown(KeyCode.f18)) // enter
        _ = dispatcher.handleKeyEvent(keyDown(3))            // "f" = Find
        _ = dispatcher.handleKeyEvent(keyDown(0))            // "a" = selector
        #expect(chooserPresenter.showCallCount == 1)
        #expect(chooserPresenter.lastPrompt == "Find app…")
        #expect(chooserPresenter.lastChoices.count == 1)
        #expect(!dispatcher.isModalActive) // modal exits when selector opens
    }

    @Test func leaderKeySuppressedWhenChooserIsOpen() throws {
        let (dispatcher, chooserPresenter, _) = try makeSetupWithChooser()
        _ = dispatcher.handleKeyEvent(keyDown(KeyCode.f18)) // enter
        _ = dispatcher.handleKeyEvent(keyDown(3))            // "f" = Find
        _ = dispatcher.handleKeyEvent(keyDown(0))            // "a" = selector opens
        #expect(chooserPresenter.isChooserVisible)

        // Leader key should be suppressed, not re-enter modal
        let result = dispatcher.handleKeyEvent(keyDown(KeyCode.f18))
        #expect(result == .suppress)
        #expect(!dispatcher.isModalActive)
    }

    @Test func chooserSelectionCallsOnSelect() throws {
        let (dispatcher, chooserPresenter, engine) = try makeSetupWithChooser()
        _ = dispatcher.handleKeyEvent(keyDown(KeyCode.f18))
        _ = dispatcher.handleKeyEvent(keyDown(3)) // "f"
        _ = dispatcher.handleKeyEvent(keyDown(0)) // "a" = selector

        let choice = chooserPresenter.lastChoices[0]
        chooserPresenter.simulateResult(.selected(choice, query: ""))

        let length = try engine.evaluate("(length call-log)")
        #expect(length == .fixnum(1))
    }
}
