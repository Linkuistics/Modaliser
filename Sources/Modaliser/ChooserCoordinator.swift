import Foundation
import LispKit

/// Orchestrates the chooser lifecycle: invokes Scheme source functions,
/// presents the chooser UI, and dispatches selection results to Scheme callbacks.
final class ChooserCoordinator {
    private let presenter: ChooserPresenting
    private let sourceInvoker: SelectorSourceInvoker
    private let executor: CommandExecutor
    private let theme: OverlayTheme
    private let searchMemory: SearchMemory
    private let fileIndexer = FileIndexer()
    private var activeSelector: SelectorDefinition?

    var isChooserOpen: Bool { presenter.isChooserVisible }

    init(
        presenter: ChooserPresenting,
        sourceInvoker: SelectorSourceInvoker,
        executor: CommandExecutor,
        theme: OverlayTheme,
        searchMemory: SearchMemory = SearchMemory()
    ) {
        self.presenter = presenter
        self.sourceInvoker = sourceInvoker
        self.executor = executor
        self.theme = theme
        self.searchMemory = searchMemory
    }

    /// Open the chooser for a selector definition.
    /// For standard selectors: calls the source lambda synchronously, shows results.
    /// For file selectors (fileRoots set): shows empty chooser, indexes in background.
    func openSelector(_ selector: SelectorDefinition) {
        activeSelector = selector
        let prompt = selector.config.prompt ?? selector.label

        if let fileRoots = selector.config.fileRoots {
            // File selector: show empty chooser, index in background
            presenter.showChooser(
                choices: [],
                actions: selector.config.actions,
                prompt: prompt,
                searchMode: .requireQuery
            ) { [weak self] result in
                self?.handleResult(result)
            }
            fileIndexer.index(roots: fileRoots) { [weak self] _ in
                guard let self = self, self.activeSelector != nil else { return }
                self.presenter.updateChoices(self.fileIndexer.choices)
            }
        } else {
            // Standard selector: load choices synchronously
            let choices = loadChoices(from: selector)
            presenter.showChooser(
                choices: choices,
                actions: selector.config.actions,
                prompt: prompt,
                searchMode: .showAll
            ) { [weak self] result in
                self?.handleResult(result)
            }
        }
    }

    // MARK: - Private

    private func loadChoices(from selector: SelectorDefinition) -> [ChooserChoice] {
        guard let source = selector.config.source else { return [] }
        do {
            return try sourceInvoker.invoke(source: source)
        } catch {
            NSLog("Selector source error: %@", "\(error)")
            return []
        }
    }

    private func handleResult(_ result: ChooserResult) {
        guard let selector = activeSelector else { return }
        activeSelector = nil

        switch result {
        case .selected(let choice, let query):
            saveToMemory(selector: selector, choice: choice, query: query)
            executeOnSelect(selector: selector, choice: choice)

        case .action(let actionIndex, let choice, let query):
            saveToMemory(selector: selector, choice: choice, query: query)
            executeAction(selector: selector, actionIndex: actionIndex, choice: choice)

        case .cancelled:
            break
        }
    }

    private func saveToMemory(selector: SelectorDefinition, choice: ChooserChoice, query: String) {
        guard let rememberName = selector.config.remember else { return }
        let idField = selector.config.idField ?? "text"
        guard let choiceId = extractField(from: choice.schemeValue, key: idField) else { return }
        searchMemory.save(name: rememberName, query: query, selectedId: choiceId)
    }

    private func extractField(from alist: Expr, key: String) -> String? {
        SchemeAlistLookup.lookupString(alist, key: key)
    }

    private func executeOnSelect(selector: SelectorDefinition, choice: ChooserChoice) {
        guard let onSelect = selector.config.onSelect else { return }
        do {
            try executor.execute(action: onSelect, argument: choice.schemeValue)
        } catch {
            NSLog("Selector onSelect error: %@", "\(error)")
        }
    }

    private func executeAction(selector: SelectorDefinition, actionIndex: Int, choice: ChooserChoice) {
        guard actionIndex >= 0, actionIndex < selector.config.actions.count else { return }
        let actionConfig = selector.config.actions[actionIndex]
        do {
            try executor.execute(action: actionConfig.run, argument: choice.schemeValue)
        } catch {
            NSLog("Selector action error: %@", "\(error)")
        }
    }
}
