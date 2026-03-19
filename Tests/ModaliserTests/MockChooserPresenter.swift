import Foundation
@testable import Modaliser

/// Mock presenter that records calls and allows simulating user interaction.
final class MockChooserPresenter: ChooserPresenting {
    var showCallCount = 0
    var dismissCallCount = 0
    var lastChoices: [ChooserChoice] = []
    var lastActions: [ActionConfig] = []
    var lastPrompt: String?
    private(set) var isChooserVisible = false
    private var resultCallback: ((ChooserResult) -> Void)?

    func showChooser(
        choices: [ChooserChoice],
        actions: [ActionConfig],
        prompt: String,
        theme: OverlayTheme,
        onResult: @escaping (ChooserResult) -> Void
    ) {
        showCallCount += 1
        lastChoices = choices
        lastActions = actions
        lastPrompt = prompt
        isChooserVisible = true
        resultCallback = onResult
    }

    func dismissChooser() {
        dismissCallCount += 1
        isChooserVisible = false
        resultCallback = nil
    }

    /// Simulate the user completing the chooser interaction.
    func simulateResult(_ result: ChooserResult) {
        resultCallback?(result)
    }
}
