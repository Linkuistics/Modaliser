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

    /// Whether modal navigation is currently active.
    var isModalActive: Bool { stateMachine.isActive }

    /// The label of the current node in the navigation tree, or nil if idle.
    var currentNodeLabel: String? { stateMachine.currentNode?.label }

    init(registry: CommandTreeRegistry, executor: CommandExecutor) {
        self.registry = registry
        self.executor = executor
        self.stateMachine = ModalStateMachine(registry: registry)
    }

    /// Handle a captured key event. Returns whether the event should be suppressed.
    func handleKeyEvent(_ event: CapturedKeyEvent) -> KeyEventHandlingResult {
        // Only process key-down events
        guard event.isKeyDown else { return .passThrough }

        // Check if this is a leader key
        if let mode = leaderMode(for: event.keyCode) {
            return handleLeaderKey(mode: mode)
        }

        // If modal is not active, pass through
        guard stateMachine.isActive else { return .passThrough }

        // Ignore events with command modifier (let system shortcuts through)
        if event.modifiers.contains(.maskCommand) {
            return .passThrough
        }

        // Handle special keys
        switch event.keyCode {
        case KeyCode.escape:
            stateMachine.exitLeader()
            return .suppress

        case KeyCode.delete:
            stateMachine.stepBack()
            return .suppress

        default:
            return handleModalKey(event.keyCode)
        }
    }

    // MARK: - Private

    private func handleLeaderKey(mode: LeaderMode) -> KeyEventHandlingResult {
        if stateMachine.isActive {
            stateMachine.exitLeader()
        } else {
            stateMachine.enterLeader(mode: mode)
        }
        return .suppress
    }

    private func handleModalKey(_ keyCode: CGKeyCode) -> KeyEventHandlingResult {
        guard let character = KeyCodeMapping.character(for: keyCode) else {
            // Unmapped key — exit modal
            stateMachine.exitLeader()
            return .suppress
        }

        let result = stateMachine.handleKey(character)

        switch result {
        case .executed(let action):
            do {
                try executor.execute(action: action)
            } catch {
                NSLog("Command execution error: %@", "\(error)")
            }

        case .openSelector:
            // Selector handling will be implemented in Session 5
            NSLog("Selector opened (not yet implemented)")

        case .navigated, .noBinding:
            break
        }

        return .suppress
    }

    /// Check if a key code corresponds to a configured leader key.
    private func leaderMode(for keyCode: CGKeyCode) -> LeaderMode? {
        if registry.leaderKey(for: .global) == keyCode { return .global }
        if registry.leaderKey(for: .local) == keyCode { return .local }
        return nil
    }
}
