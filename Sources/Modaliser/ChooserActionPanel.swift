/// Manages the action panel state within the chooser.
/// Activated when the user presses Cmd+K to see available actions for the selected choice.
final class ChooserActionPanel {
    private(set) var isActive = false
    private(set) var actions: [ActionConfig] = []
    private(set) var selectedChoice: ChooserChoice?
    var selectedIndex = 0

    func activate(for choice: ChooserChoice, actions: [ActionConfig]) {
        self.selectedChoice = choice
        self.actions = actions
        self.selectedIndex = 0
        self.isActive = true
    }

    func deactivate() {
        self.isActive = false
        self.selectedChoice = nil
        self.actions = []
        self.selectedIndex = 0
    }

    func selectByDigit(_ digit: Int) -> ActionConfig? {
        let index = digit - 1
        guard index >= 0, index < actions.count else { return nil }
        return actions[index]
    }

    func currentAction() -> ActionConfig? {
        guard isActive, selectedIndex >= 0, selectedIndex < actions.count else { return nil }
        return actions[selectedIndex]
    }

    func moveUp() { selectedIndex = max(0, selectedIndex - 1) }
    func moveDown() { selectedIndex = min(actions.count - 1, selectedIndex + 1) }
}
