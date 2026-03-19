import Foundation
@testable import Modaliser

/// Mock presenter that records calls for testing.
/// Used by OverlayCoordinatorTests and KeyEventDispatcherTests.
final class MockOverlayPresenter: OverlayPresenting {
    var showCallCount = 0
    var lastShownContent: OverlayContent?
    var dismissCallCount = 0

    func showOverlay(content: OverlayContent, theme: OverlayTheme) {
        showCallCount += 1
        lastShownContent = content
    }

    func dismissOverlay() {
        dismissCallCount += 1
    }
}
