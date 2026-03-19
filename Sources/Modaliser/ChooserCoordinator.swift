import Foundation

/// Orchestrates the chooser lifecycle: invokes Scheme source functions,
/// presents the chooser UI, and dispatches selection results to Scheme callbacks.
final class ChooserCoordinator {
    private let presenter: ChooserPresenting
    private let sourceInvoker: SelectorSourceInvoker
    private let executor: CommandExecutor
    private let theme: OverlayTheme
    private var activeSelector: SelectorDefinition?

    var isChooserOpen: Bool { presenter.isChooserVisible }

    init(
        presenter: ChooserPresenting,
        sourceInvoker: SelectorSourceInvoker,
        executor: CommandExecutor,
        theme: OverlayTheme
    ) {
        self.presenter = presenter
        self.sourceInvoker = sourceInvoker
        self.executor = executor
        self.theme = theme
    }

    /// Open the chooser for a selector definition.
    /// Calls the source lambda, marshals choices, and presents the UI.
    func openSelector(_ selector: SelectorDefinition) {
        activeSelector = selector
        let choices = loadChoices(from: selector)
        let prompt = selector.config.prompt ?? selector.label

        presenter.showChooser(
            choices: choices,
            actions: selector.config.actions,
            prompt: prompt,
            theme: theme
        ) { [weak self] result in
            self?.handleResult(result)
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
        case .selected(let choice, _):
            executeOnSelect(selector: selector, choice: choice)

        case .action(let actionIndex, let choice, _):
            executeAction(selector: selector, actionIndex: actionIndex, choice: choice)

        case .cancelled:
            break
        }
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
