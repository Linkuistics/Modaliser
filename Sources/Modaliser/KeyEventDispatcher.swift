import CoreGraphics
import Foundation

/// Result of handling a key event — tells the caller whether to suppress or pass through.
enum KeyEventHandlingResult: Equatable {
    /// Suppress the event (don't let it reach other apps).
    case suppress
    /// Pass the event through to the system.
    case passThrough
}

/// Translates raw keyboard events into modal state machine actions.
/// Handles leader key toggle, escape, delete, and regular key dispatch.
/// Sits between KeyboardCapture and ModalStateMachine.
final class KeyEventDispatcher {
    private let stateMachine: ModalStateMachine
    private let registry: CommandTreeRegistry
    private let executor: CommandExecutor
    private let overlayNotifier: OverlayNotifier?
    private let chooserCoordinator: ChooserCoordinator?

    /// Whether modal navigation is currently active.
    var isModalActive: Bool { stateMachine.isActive }

    /// The label of the current node in the navigation tree, or nil if idle.
    var currentNodeLabel: String? { stateMachine.currentNode?.label }

    init(
        registry: CommandTreeRegistry,
        executor: CommandExecutor,
        overlayCoordinator: OverlayCoordinator? = nil,
        chooserCoordinator: ChooserCoordinator? = nil
    ) {
        self.registry = registry
        self.executor = executor
        self.stateMachine = ModalStateMachine(registry: registry)
        self.overlayNotifier = overlayCoordinator.map { OverlayNotifier(coordinator: $0) }
        self.chooserCoordinator = chooserCoordinator
    }

    /// Handle a captured key event. Returns whether the event should be suppressed.
    func handleKeyEvent(_ event: CapturedKeyEvent) -> KeyEventHandlingResult {
        guard event.isKeyDown else { return .passThrough }

        // Block leader key when chooser is open — prevents re-entering modal while searching
        if let mode = leaderMode(for: event.keyCode) {
            if chooserCoordinator?.isChooserOpen == true {
                return .suppress
            }
            return handleLeaderKey(mode: mode)
        }

        guard stateMachine.isActive else { return .passThrough }

        if event.modifiers.contains(.maskCommand) {
            return .passThrough
        }

        switch event.keyCode {
        case KeyCode.escape:
            stateMachine.exitLeader()
            overlayNotifier?.deactivated()
            return .suppress

        case KeyCode.delete:
            stateMachine.stepBack()
            overlayNotifier?.afterStepBack(machine: stateMachine)
            return .suppress

        default:
            return handleModalKey(event.keyCode)
        }
    }

    // MARK: - Private

    private func handleLeaderKey(mode: LeaderMode) -> KeyEventHandlingResult {
        if stateMachine.isActive {
            stateMachine.exitLeader()
            overlayNotifier?.deactivated()
        } else {
            stateMachine.enterLeader(mode: mode)
            overlayNotifier?.activated(machine: stateMachine)
        }
        return .suppress
    }

    private func handleModalKey(_ keyCode: CGKeyCode) -> KeyEventHandlingResult {
        guard let character = KeyCodeMapping.character(for: keyCode) else {
            stateMachine.exitLeader()
            overlayNotifier?.deactivated()
            return .suppress
        }

        let result = stateMachine.handleKey(character)

        switch result {
        case .executed(let action):
            overlayNotifier?.deactivated()
            do {
                try executor.execute(action: action)
            } catch {
                NSLog("Command execution error: %@", "\(error)")
            }

        case .openSelector(let selectorDef):
            overlayNotifier?.deactivated()
            chooserCoordinator?.openSelector(selectorDef)

        case .navigated:
            overlayNotifier?.navigated(machine: stateMachine)

        case .noBinding:
            overlayNotifier?.deactivated()
        }

        return .suppress
    }

    private func leaderMode(for keyCode: CGKeyCode) -> LeaderMode? {
        if registry.leaderKey(for: .global) == keyCode { return .global }
        if registry.leaderKey(for: .local) == keyCode { return .local }
        return nil
    }
}
