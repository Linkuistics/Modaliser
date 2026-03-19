import AppKit

/// Action panel management for the chooser window controller.
extension ChooserWindowController {

    func openActionPanel() {
        guard selectedIndex >= 0, selectedIndex < filteredChoices.count else { return }
        guard !selectorActions.isEmpty else { return }

        let choice = filteredChoices[selectedIndex]
        actionPanel.activate(for: choice, actions: selectorActions)

        searchField?.isEditable = false
        searchField?.stringValue = "\u{2039} Actions for \(choice.text)"

        resizeTableArea()
        tableView?.reloadData()
        updateFooter()
    }

    func closeActionPanel() {
        actionPanel.deactivate()

        searchField?.isEditable = true
        searchField?.stringValue = ""
        searchField?.placeholderString = "\u{203A} " + savedPrompt

        resizeTableArea()
        tableView?.reloadData()
        updateFooter()
        panel?.makeFirstResponder(searchField)
    }

    /// Report an action panel result.
    func confirmActionSelection() {
        guard let action = actionPanel.currentAction(),
              let choice = actionPanel.selectedChoice else { return }
        guard let idx = selectorActions.firstIndex(where: { $0.name == action.name }) else { return }
        onResult?(.action(actionIndex: idx, choice: choice, query: currentQuery))
        dismiss()
    }

    /// Report a digit-selected action result.
    func confirmActionByDigit(_ digit: Int) {
        guard let action = actionPanel.selectByDigit(digit),
              let choice = actionPanel.selectedChoice else { return }
        guard let idx = selectorActions.firstIndex(where: { $0.name == action.name }) else { return }
        onResult?(.action(actionIndex: idx, choice: choice, query: currentQuery))
        dismiss()
    }
}
