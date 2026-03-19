/// Protocol for presenting and dismissing the chooser window.
/// Abstraction allows testing the coordinator without real AppKit windows.
protocol ChooserPresenting: AnyObject {
    /// Show the chooser with the given choices, actions, prompt, and result callback.
    func showChooser(
        choices: [ChooserChoice],
        actions: [ActionConfig],
        prompt: String,
        theme: OverlayTheme,
        onResult: @escaping (ChooserResult) -> Void
    )

    /// Dismiss the chooser window.
    func dismissChooser()

    /// Whether the chooser is currently visible.
    var isChooserVisible: Bool { get }
}
