/// Protocol for displaying and dismissing the which-key overlay.
/// Abstraction allows testing the coordinator without real AppKit windows.
protocol OverlayPresenting: AnyObject {
    func showOverlay(content: OverlayContent, theme: OverlayTheme)
    func dismissOverlay()
}
