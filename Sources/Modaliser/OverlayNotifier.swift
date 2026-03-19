/// Bridges modal state machine changes to the overlay coordinator.
/// Reads state from the machine, builds overlay content, and notifies the coordinator.
struct OverlayNotifier {
    private let coordinator: OverlayCoordinator
    private let contentBuilder = OverlayContentBuilder()

    init(coordinator: OverlayCoordinator) {
        self.coordinator = coordinator
    }

    func activated(machine: ModalStateMachine) {
        guard let content = buildContent(from: machine) else { return }
        coordinator.modalDidActivate(content: content)
    }

    func navigated(machine: ModalStateMachine) {
        guard let content = buildContent(from: machine) else { return }
        coordinator.modalDidNavigate(content: content)
    }

    func deactivated() {
        coordinator.modalDidDeactivate()
    }

    func afterStepBack(machine: ModalStateMachine) {
        if machine.isActive {
            navigated(machine: machine)
        } else {
            deactivated()
        }
    }

    // MARK: - Private

    private func buildContent(from machine: ModalStateMachine) -> OverlayContent? {
        let treeLabel = machine.currentMode == .global ? "Global" : "Local"
        return contentBuilder.buildContent(
            currentNode: machine.currentNode,
            path: machine.path,
            mode: machine.currentMode,
            treeLabel: treeLabel
        )
    }
}
