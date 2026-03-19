import Foundation

/// Manages the which-key overlay lifecycle: show-with-delay, update, and dismiss.
/// Decoupled from AppKit via the OverlayPresenting protocol.
final class OverlayCoordinator {
    private let presenter: OverlayPresenting
    private let theme: OverlayTheme
    private let showDelay: TimeInterval
    private var delayTimer: Timer?
    private(set) var isVisible = false
    private var latestContent: OverlayContent?

    init(presenter: OverlayPresenting, showDelay: TimeInterval, theme: OverlayTheme = .default) {
        self.presenter = presenter
        self.showDelay = showDelay
        self.theme = theme
    }

    /// Called when modal mode is activated (leader key pressed).
    /// Starts the show-delay timer, or shows immediately if delay is zero.
    func modalDidActivate(content: OverlayContent) {
        latestContent = content
        if showDelay <= 0 {
            showNow()
        } else {
            startDelayTimer()
        }
    }

    /// Called when the user navigates within the modal tree.
    /// Updates immediately if visible, otherwise updates pending content.
    func modalDidNavigate(content: OverlayContent) {
        latestContent = content
        if isVisible {
            presenter.showOverlay(content: content, theme: theme)
        }
    }

    /// Called when modal mode is deactivated (command executed, escape, etc.).
    /// Dismisses immediately and cancels any pending show timer.
    func modalDidDeactivate() {
        delayTimer?.invalidate()
        delayTimer = nil
        latestContent = nil

        if isVisible {
            presenter.dismissOverlay()
            isVisible = false
        }
    }

    // MARK: - Private

    private func showNow() {
        guard let content = latestContent else { return }
        presenter.showOverlay(content: content, theme: theme)
        isVisible = true
    }

    private func startDelayTimer() {
        delayTimer?.invalidate()
        delayTimer = Timer.scheduledTimer(
            withTimeInterval: showDelay,
            repeats: false
        ) { [weak self] _ in
            self?.showNow()
        }
    }
}
