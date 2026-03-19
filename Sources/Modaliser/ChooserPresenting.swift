/// Protocol for presenting and dismissing the chooser window.
/// Abstraction allows testing the coordinator without real AppKit windows.
protocol ChooserPresenting: AnyObject {
    /// Show the chooser with the given choices, actions, prompt, search mode, and result callback.
    func showChooser(
        choices: [ChooserChoice],
        actions: [ActionConfig],
        prompt: String,
        searchMode: ChooserSearchMode,
        onResult: @escaping (ChooserResult) -> Void
    )

    /// Update the backing choices after the chooser is already shown.
    /// Used for async data sources like file indexing.
    func updateChoices(_ choices: [ChooserChoice])

    /// Dismiss the chooser window.
    func dismissChooser()

    /// Whether the chooser is currently visible.
    var isChooserVisible: Bool { get }
}
