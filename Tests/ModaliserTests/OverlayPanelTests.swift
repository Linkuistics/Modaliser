import Testing
import AppKit
@testable import Modaliser

@Suite("OverlayPanel – in-place update")
@MainActor
struct OverlayPanelTests {

    private let theme = OverlayTheme.default

    private func makeContent(header: String = "Global", entryCount: Int = 3) -> OverlayContent {
        let entries = (0..<entryCount).map { i in
            OverlayEntry(key: String(Character(UnicodeScalar(97 + i)!)), label: "Item \(i)", style: .command)
        }
        return OverlayContent(header: header, headerIcon: nil, entries: entries)
    }

    // MARK: - Panel reuse

    @Test func showOverlayTwiceReusesSamePanel() {
        let overlay = OverlayPanel()

        overlay.showOverlay(content: makeContent(), theme: theme)
        let firstPanel = overlay.panel

        overlay.showOverlay(content: makeContent(header: "Updated"), theme: theme)
        let secondPanel = overlay.panel

        #expect(firstPanel != nil)
        #expect(firstPanel === secondPanel, "Panel should be reused, not recreated")
    }

    @Test func showOverlayAfterDismissCreatesNewPanel() {
        let overlay = OverlayPanel()

        overlay.showOverlay(content: makeContent(), theme: theme)
        let firstPanel = overlay.panel

        overlay.dismissOverlay()
        #expect(overlay.panel == nil)

        overlay.showOverlay(content: makeContent(), theme: theme)
        let newPanel = overlay.panel

        #expect(newPanel != nil)
        #expect(firstPanel !== newPanel, "After dismiss, a new panel should be created")
    }

    // MARK: - Panel resize

    @Test func showOverlayResizesPanelWhenEntryCountChanges() {
        let overlay = OverlayPanel()

        overlay.showOverlay(content: makeContent(entryCount: 3), theme: theme)
        let heightWith3 = overlay.panel?.frame.height ?? 0

        overlay.showOverlay(content: makeContent(entryCount: 7), theme: theme)
        let heightWith7 = overlay.panel?.frame.height ?? 0

        #expect(heightWith7 > heightWith3, "Panel should grow when entry count increases")
    }

    @Test func showOverlayShrinksWhenFewerEntries() {
        let overlay = OverlayPanel()

        overlay.showOverlay(content: makeContent(entryCount: 7), theme: theme)
        let heightWith7 = overlay.panel?.frame.height ?? 0

        overlay.showOverlay(content: makeContent(entryCount: 2), theme: theme)
        let heightWith2 = overlay.panel?.frame.height ?? 0

        #expect(heightWith2 < heightWith7, "Panel should shrink when entry count decreases")
    }

    // MARK: - Content update

    @Test func showOverlayUpdatesSubviews() {
        let overlay = OverlayPanel()

        overlay.showOverlay(content: makeContent(entryCount: 3), theme: theme)
        let subviewCountFirst = overlay.panel?.contentView?.subviews.count ?? 0

        overlay.showOverlay(content: makeContent(entryCount: 5), theme: theme)
        let subviewCountSecond = overlay.panel?.contentView?.subviews.count ?? 0

        #expect(subviewCountFirst > 0, "Should have subviews after first show")
        #expect(subviewCountSecond > 0, "Should have subviews after update")
        #expect(subviewCountSecond != subviewCountFirst, "Subview count should change with different entry counts")
    }

    // MARK: - Dismiss

    @Test func dismissOverlayClearsPanel() {
        let overlay = OverlayPanel()

        overlay.showOverlay(content: makeContent(), theme: theme)
        #expect(overlay.panel != nil)

        overlay.dismissOverlay()
        #expect(overlay.panel == nil)
    }
}
