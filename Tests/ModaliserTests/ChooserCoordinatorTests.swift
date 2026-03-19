import Testing
import LispKit
@testable import Modaliser

@Suite("ChooserCoordinator")
struct ChooserCoordinatorTests {

    private func makeEngine() throws -> SchemeEngine {
        try SchemeEngine()
    }

    private func makeSelectorWithSource(_ engine: SchemeEngine) throws -> SelectorDefinition {
        let source = try engine.evaluate("""
            (lambda ()
              (list
                (list (cons 'text "Safari") (cons 'bundleId "com.apple.Safari"))
                (list (cons 'text "Mail") (cons 'bundleId "com.apple.Mail"))))
            """)
        let onSelect = try engine.evaluate("(lambda (c) (cdr (assoc 'text c)))")
        let actionRun = try engine.evaluate("(lambda (c) (cdr (assoc 'bundleId c)))")
        return SelectorDefinition(
            key: "a",
            label: "Find Apps",
            config: SelectorConfig(
                prompt: "Find app…",
                source: source,
                onSelect: onSelect,
                remember: nil,
                idField: nil,
                actions: [
                    ActionConfig(name: "Open", description: nil, trigger: .primary, run: onSelect),
                    ActionConfig(name: "Reveal", description: nil, trigger: .secondary, run: actionRun),
                ],
                fileRoots: nil
            )
        )
    }

    // MARK: - Opening a selector

    @Test func openSelectorCallsSourceAndShowsChooser() throws {
        let engine = try makeEngine()
        let presenter = MockChooserPresenter()
        let coordinator = ChooserCoordinator(
            presenter: presenter,
            sourceInvoker: SelectorSourceInvoker(engine: engine),
            executor: CommandExecutor(engine: engine),
            theme: .default
        )
        let selector = try makeSelectorWithSource(engine)

        coordinator.openSelector(selector)

        #expect(presenter.showCallCount == 1)
        #expect(presenter.lastChoices.count == 2)
        #expect(presenter.lastChoices[0].text == "Safari")
        #expect(presenter.lastPrompt == "Find app…")
        #expect(presenter.lastActions.count == 2)
    }

    @Test func openSelectorUsesDefaultPromptWhenNil() throws {
        let engine = try makeEngine()
        let presenter = MockChooserPresenter()
        let coordinator = ChooserCoordinator(
            presenter: presenter,
            sourceInvoker: SelectorSourceInvoker(engine: engine),
            executor: CommandExecutor(engine: engine),
            theme: .default
        )
        let source = try engine.evaluate("(lambda () '())")
        let selector = SelectorDefinition(
            key: "x",
            label: "Test",
            config: SelectorConfig(
                prompt: nil, source: source, onSelect: nil,
                remember: nil, idField: nil, actions: [], fileRoots: nil
            )
        )

        coordinator.openSelector(selector)

        #expect(presenter.lastPrompt == "Test")
    }

    // MARK: - Selection result dispatch

    @Test func selectedResultCallsOnSelect() throws {
        let engine = try makeEngine()
        _ = try engine.evaluate("(define selected-text #f)")
        let onSelect = try engine.evaluate("""
            (lambda (c) (set! selected-text (cdr (assoc 'text c))))
            """)
        let source = try engine.evaluate("""
            (lambda ()
              (list (list (cons 'text "Safari"))))
            """)
        let presenter = MockChooserPresenter()
        let coordinator = ChooserCoordinator(
            presenter: presenter,
            sourceInvoker: SelectorSourceInvoker(engine: engine),
            executor: CommandExecutor(engine: engine),
            theme: .default
        )
        let selector = SelectorDefinition(
            key: "a", label: "Apps",
            config: SelectorConfig(
                prompt: "Find…", source: source, onSelect: onSelect,
                remember: nil, idField: nil, actions: [], fileRoots: nil
            )
        )

        coordinator.openSelector(selector)
        let choice = presenter.lastChoices[0]
        presenter.simulateResult(.selected(choice, query: "saf"))

        let result = try engine.evaluate("selected-text")
        #expect(result == .makeString("Safari"))
    }

    @Test func actionResultCallsActionRunLambda() throws {
        let engine = try makeEngine()
        _ = try engine.evaluate("(define action-result #f)")
        let actionRun = try engine.evaluate("""
            (lambda (c) (set! action-result (cdr (assoc 'bundleId c))))
            """)
        let source = try engine.evaluate("""
            (lambda ()
              (list (list (cons 'text "Safari") (cons 'bundleId "com.apple.Safari"))))
            """)
        let presenter = MockChooserPresenter()
        let coordinator = ChooserCoordinator(
            presenter: presenter,
            sourceInvoker: SelectorSourceInvoker(engine: engine),
            executor: CommandExecutor(engine: engine),
            theme: .default
        )
        let selector = SelectorDefinition(
            key: "a", label: "Apps",
            config: SelectorConfig(
                prompt: "Find…", source: source, onSelect: nil,
                remember: nil, idField: nil,
                actions: [ActionConfig(name: "Reveal", description: nil, trigger: nil, run: actionRun)],
                fileRoots: nil
            )
        )

        coordinator.openSelector(selector)
        let choice = presenter.lastChoices[0]
        presenter.simulateResult(.action(actionIndex: 0, choice: choice, query: ""))

        let result = try engine.evaluate("action-result")
        #expect(result == .makeString("com.apple.Safari"))
    }

    @Test func cancelledResultDoesNotCallScheme() throws {
        let engine = try makeEngine()
        _ = try engine.evaluate("(define was-called #f)")
        let onSelect = try engine.evaluate("(lambda (c) (set! was-called #t))")
        let source = try engine.evaluate("(lambda () (list (list (cons 'text \"X\"))))")
        let presenter = MockChooserPresenter()
        let coordinator = ChooserCoordinator(
            presenter: presenter,
            sourceInvoker: SelectorSourceInvoker(engine: engine),
            executor: CommandExecutor(engine: engine),
            theme: .default
        )
        let selector = SelectorDefinition(
            key: "x", label: "Test",
            config: SelectorConfig(
                prompt: "Test", source: source, onSelect: onSelect,
                remember: nil, idField: nil, actions: [], fileRoots: nil
            )
        )

        coordinator.openSelector(selector)
        presenter.simulateResult(.cancelled)

        let result = try engine.evaluate("was-called")
        #expect(result == .false)
    }

    // MARK: - Visibility

    @Test func isChooserOpenDelegatesToPresenter() throws {
        let engine = try makeEngine()
        let presenter = MockChooserPresenter()
        let coordinator = ChooserCoordinator(
            presenter: presenter,
            sourceInvoker: SelectorSourceInvoker(engine: engine),
            executor: CommandExecutor(engine: engine),
            theme: .default
        )

        #expect(!coordinator.isChooserOpen)

        let source = try engine.evaluate("(lambda () '())")
        let selector = SelectorDefinition(
            key: "x", label: "Test",
            config: SelectorConfig(
                prompt: nil, source: source, onSelect: nil,
                remember: nil, idField: nil, actions: [], fileRoots: nil
            )
        )
        coordinator.openSelector(selector)
        #expect(coordinator.isChooserOpen)
    }

    // MARK: - Search mode

    @Test func openSelectorWithoutFileRootsUsesShowAll() throws {
        let engine = try makeEngine()
        let presenter = MockChooserPresenter()
        let coordinator = ChooserCoordinator(
            presenter: presenter,
            sourceInvoker: SelectorSourceInvoker(engine: engine),
            executor: CommandExecutor(engine: engine),
            theme: .default
        )
        let source = try engine.evaluate("(lambda () '())")
        let selector = SelectorDefinition(
            key: "a", label: "Apps",
            config: SelectorConfig(
                prompt: "Find…", source: source, onSelect: nil,
                remember: nil, idField: nil, actions: [], fileRoots: nil
            )
        )

        coordinator.openSelector(selector)

        #expect(presenter.lastSearchMode == .showAll)
    }

    @Test func openSelectorWithFileRootsUsesRequireQuery() throws {
        let engine = try makeEngine()
        let presenter = MockChooserPresenter()
        let coordinator = ChooserCoordinator(
            presenter: presenter,
            sourceInvoker: SelectorSourceInvoker(engine: engine),
            executor: CommandExecutor(engine: engine),
            theme: .default
        )
        let source = try engine.evaluate("(lambda () '())")
        let selector = SelectorDefinition(
            key: "f", label: "Files",
            config: SelectorConfig(
                prompt: "Find file…", source: source, onSelect: nil,
                remember: nil, idField: nil, actions: [], fileRoots: ["~"]
            )
        )

        coordinator.openSelector(selector)

        #expect(presenter.lastSearchMode == .requireQuery)
    }

    @Test func openFileSelectorStartsWithEmptyChoices() throws {
        let engine = try makeEngine()
        let presenter = MockChooserPresenter()
        let coordinator = ChooserCoordinator(
            presenter: presenter,
            sourceInvoker: SelectorSourceInvoker(engine: engine),
            executor: CommandExecutor(engine: engine),
            theme: .default
        )
        let selector = SelectorDefinition(
            key: "f", label: "Files",
            config: SelectorConfig(
                prompt: "Find file…", source: nil, onSelect: nil,
                remember: nil, idField: nil, actions: [], fileRoots: ["~"]
            )
        )

        coordinator.openSelector(selector)

        // File selectors start empty (requireQuery mode), data loads asynchronously
        #expect(presenter.showCallCount == 1)
        #expect(presenter.lastChoices.isEmpty)
    }

    @Test func openStandardSelectorDoesNotCallSourceForFileRoots() throws {
        let engine = try makeEngine()
        let presenter = MockChooserPresenter()
        let coordinator = ChooserCoordinator(
            presenter: presenter,
            sourceInvoker: SelectorSourceInvoker(engine: engine),
            executor: CommandExecutor(engine: engine),
            theme: .default
        )
        // Standard selector (no fileRoots) with a source that returns data
        let source = try engine.evaluate("""
            (lambda () (list (list (cons 'text "Safari"))))
            """)
        let selector = SelectorDefinition(
            key: "a", label: "Apps",
            config: SelectorConfig(
                prompt: "Find…", source: source, onSelect: nil,
                remember: nil, idField: nil, actions: [], fileRoots: nil
            )
        )

        coordinator.openSelector(selector)

        #expect(presenter.showCallCount == 1)
        #expect(presenter.lastChoices.count == 1)
        #expect(presenter.lastSearchMode == .showAll)
    }

    // MARK: - Source error

    @Test func openSelectorWithNilSourceShowsEmptyChooser() throws {
        let engine = try makeEngine()
        let presenter = MockChooserPresenter()
        let coordinator = ChooserCoordinator(
            presenter: presenter,
            sourceInvoker: SelectorSourceInvoker(engine: engine),
            executor: CommandExecutor(engine: engine),
            theme: .default
        )
        let selector = SelectorDefinition(
            key: "x", label: "Test",
            config: SelectorConfig(
                prompt: "Test", source: nil, onSelect: nil,
                remember: nil, idField: nil, actions: [], fileRoots: nil
            )
        )

        coordinator.openSelector(selector)

        #expect(presenter.showCallCount == 1)
        #expect(presenter.lastChoices.isEmpty)
    }
}
