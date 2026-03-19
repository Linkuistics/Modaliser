import AppKit
import LispKit

/// Controls the chooser window: search, selection, actions, and keyboard handling.
/// Implements ChooserPresenting so the coordinator can show/dismiss it.
final class ChooserWindowController: NSObject, ChooserPresenting {
    let chooserTheme: OverlayTheme
    private(set) var choices: [ChooserChoice] = []
    var selectorActions: [ActionConfig] = []
    var filteredChoices: [ChooserChoice] = []
    var filteredTextMatches: [Set<Int>] = []
    var filteredSubMatches: [Set<Int>] = []
    var selectedIndex: Int = 0
    var helpExpanded: Bool = false
    let actionPanel = ChooserActionPanel()
    var savedPrompt: String = ""
    var onResult: ((ChooserResult) -> Void)?

    var panel: KeyablePanel?
    var searchField: NSTextField?
    var tableView: NSTableView?
    var scrollView: NSScrollView?
    var footerLabel: NSTextField?
    var separatorTop: NSView?
    var separatorBottom: NSView?
    var eventMonitor: Any?
    var searchGeneration: Int = 0
    var searchDebounce: DispatchWorkItem?
    let searchQueue = DispatchQueue(label: "chooser.search", qos: .userInteractive)
    var deactivationObserver: Any?

    let windowWidth: CGFloat
    let maxRows: Int
    let rowHeight: CGFloat = 48
    let searchHeight: CGFloat = 40
    let footerHeight: CGFloat = 28
    let footerExpandedHeight: CGFloat = 48
    var searchFieldNaturalH: CGFloat = 22
    let cornerRadius: CGFloat = 10
    let borderWidth: CGFloat = 2

    var isChooserVisible: Bool { panel != nil }

    init(theme: OverlayTheme, width: CGFloat = 420, maxRows: Int = 8) {
        self.chooserTheme = theme
        self.windowWidth = width
        self.maxRows = maxRows
        super.init()
    }

    // MARK: - ChooserPresenting

    func showChooser(
        choices: [ChooserChoice],
        actions: [ActionConfig],
        prompt: String,
        theme: OverlayTheme,
        onResult: @escaping (ChooserResult) -> Void
    ) {
        self.choices = choices
        self.selectorActions = actions
        self.filteredChoices = choices
        self.filteredTextMatches = Array(repeating: [], count: choices.count)
        self.filteredSubMatches = Array(repeating: [], count: choices.count)
        self.selectedIndex = 0
        self.helpExpanded = false
        self.savedPrompt = prompt
        self.onResult = onResult
        self.actionPanel.deactivate()

        buildWindow(prompt: prompt)
        positionOnScreen()
        installKeyMonitor()

        deactivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.cancel()
        }

        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeFirstResponder(searchField)
    }

    func dismissChooser() {
        dismiss()
    }

    // MARK: - Selection management

    func moveSelection(by delta: Int) {
        let count = actionPanel.isActive ? actionPanel.actions.count : filteredChoices.count
        guard count > 0 else { return }
        if actionPanel.isActive {
            if delta > 0 { actionPanel.moveDown() } else { actionPanel.moveUp() }
        } else {
            selectedIndex = max(0, min(filteredChoices.count - 1, selectedIndex + delta))
        }
        tableView?.reloadData()
        scrollToSelected()
    }

    func scrollToSelected() {
        let index = actionPanel.isActive ? actionPanel.selectedIndex : selectedIndex
        tableView?.scrollRowToVisible(index)
    }

    var currentQuery: String {
        searchField?.stringValue ?? ""
    }

    func confirmSelection() {
        guard selectedIndex >= 0, selectedIndex < filteredChoices.count else {
            cancel()
            return
        }
        let choice = filteredChoices[selectedIndex]
        onResult?(.selected(choice, query: currentQuery))
        dismiss()
    }

    func triggerSecondaryAction() {
        guard selectedIndex >= 0, selectedIndex < filteredChoices.count else { return }
        let choice = filteredChoices[selectedIndex]
        if let idx = selectorActions.firstIndex(where: { $0.trigger == .secondary }) {
            onResult?(.action(actionIndex: idx, choice: choice, query: currentQuery))
            dismiss()
        } else {
            confirmSelection()
        }
    }

    func cancel() {
        onResult?(.cancelled)
        dismiss()
    }

    func dismiss() {
        searchDebounce?.cancel()
        searchGeneration += 1
        if let obs = deactivationObserver {
            NotificationCenter.default.removeObserver(obs)
            deactivationObserver = nil
        }
        removeKeyMonitor()
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        NSApp.deactivate()
    }

    func toggleHelp() {
        helpExpanded = !helpExpanded
        resizeTableArea()
    }

    /// Confirm selection by Cmd+digit (1-9).
    func confirmSelectionByIndex(_ index: Int) {
        guard index >= 0, index < filteredChoices.count else { return }
        selectedIndex = index
        confirmSelection()
    }
}
