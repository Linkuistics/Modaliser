import Testing
import Foundation
@testable import Modaliser

/// Mock presenter that records calls for testing.
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

@Suite("OverlayCoordinator")
struct OverlayCoordinatorTests {

    private func makePresenter() -> MockOverlayPresenter {
        MockOverlayPresenter()
    }

    private func makeCoordinator(presenter: MockOverlayPresenter) -> OverlayCoordinator {
        OverlayCoordinator(presenter: presenter, showDelay: 0)
    }

    private func makeSampleContent(header: String = "Global") -> OverlayContent {
        OverlayContent(
            header: header,
            headerIcon: nil,
            entries: [
                OverlayEntry(key: "s", label: "Safari", style: .command),
            ]
        )
    }

    // MARK: - Activate (show)

    @Test func activateShowsOverlay() {
        let presenter = makePresenter()
        let coordinator = makeCoordinator(presenter: presenter)

        coordinator.modalDidActivate(content: makeSampleContent())

        #expect(presenter.showCallCount == 1)
        #expect(presenter.lastShownContent?.header == "Global")
    }

    @Test func activateSetsVisibleFlag() {
        let presenter = makePresenter()
        let coordinator = makeCoordinator(presenter: presenter)

        coordinator.modalDidActivate(content: makeSampleContent())

        #expect(coordinator.isVisible)
    }

    // MARK: - Navigate (update)

    @Test func navigateUpdatesContentWhenVisible() {
        let presenter = makePresenter()
        let coordinator = makeCoordinator(presenter: presenter)

        coordinator.modalDidActivate(content: makeSampleContent())
        coordinator.modalDidNavigate(content: makeSampleContent(header: "Global \u{203A} Find"))

        #expect(presenter.showCallCount == 2)
        #expect(presenter.lastShownContent?.header == "Global \u{203A} Find")
    }

    @Test func navigateWhenNotVisibleStoresPendingContent() {
        let presenter = makePresenter()
        // Use a non-zero delay so activate doesn't show immediately
        let coordinator = OverlayCoordinator(presenter: presenter, showDelay: 10.0)

        coordinator.modalDidActivate(content: makeSampleContent(header: "Global"))
        coordinator.modalDidNavigate(content: makeSampleContent(header: "Updated"))

        #expect(presenter.showCallCount == 0) // Not visible yet, so no show call
    }

    // MARK: - Deactivate (dismiss)

    @Test func deactivateDismissesWhenVisible() {
        let presenter = makePresenter()
        let coordinator = makeCoordinator(presenter: presenter)

        coordinator.modalDidActivate(content: makeSampleContent())
        coordinator.modalDidDeactivate()

        #expect(presenter.dismissCallCount == 1)
        #expect(!coordinator.isVisible)
    }

    @Test func deactivateWhenNotVisibleDoesNotDismiss() {
        let presenter = makePresenter()
        let coordinator = makeCoordinator(presenter: presenter)

        coordinator.modalDidDeactivate()

        #expect(presenter.dismissCallCount == 0)
    }

    @Test func deactivateCancelsPendingTimer() {
        let presenter = makePresenter()
        // Use a long delay — deactivate should cancel the pending show
        let coordinator = OverlayCoordinator(presenter: presenter, showDelay: 10.0)

        coordinator.modalDidActivate(content: makeSampleContent())
        coordinator.modalDidDeactivate()

        #expect(presenter.showCallCount == 0) // Timer was cancelled
        #expect(presenter.dismissCallCount == 0) // Nothing visible to dismiss
    }

    // MARK: - Reactivation

    @Test func reactivateAfterDeactivateShowsNewContent() {
        let presenter = makePresenter()
        let coordinator = makeCoordinator(presenter: presenter)

        coordinator.modalDidActivate(content: makeSampleContent(header: "First"))
        coordinator.modalDidDeactivate()
        coordinator.modalDidActivate(content: makeSampleContent(header: "Second"))

        #expect(presenter.showCallCount == 2)
        #expect(presenter.lastShownContent?.header == "Second")
    }

    // MARK: - Full lifecycle

    @Test func fullLifecycleActivateNavigateDeactivate() {
        let presenter = makePresenter()
        let coordinator = makeCoordinator(presenter: presenter)

        // Activate
        coordinator.modalDidActivate(content: makeSampleContent(header: "Global"))
        #expect(presenter.showCallCount == 1)

        // Navigate deeper
        coordinator.modalDidNavigate(content: makeSampleContent(header: "Global \u{203A} Find"))
        #expect(presenter.showCallCount == 2)
        #expect(presenter.lastShownContent?.header == "Global \u{203A} Find")

        // Deactivate
        coordinator.modalDidDeactivate()
        #expect(presenter.dismissCallCount == 1)
        #expect(!coordinator.isVisible)
    }
}
