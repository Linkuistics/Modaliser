import Testing
import AppKit
@testable import Modaliser

@Suite("OverlayTheme")
struct OverlayThemeTests {

    // MARK: - Default theme

    @Test func defaultThemeHasWarmBeigBackground() {
        let theme = OverlayTheme.default
        #expect(theme.background == NSColor(red: 0.99, green: 0.97, blue: 0.93, alpha: 1))
    }

    @Test func defaultThemeHasBlueAccent() {
        let theme = OverlayTheme.default
        #expect(theme.accent == NSColor(red: 0.13, green: 0.38, blue: 0.73, alpha: 1))
    }

    @Test func defaultThemeHasMenloFont() {
        let theme = OverlayTheme.default
        #expect(theme.font.familyName == "Menlo")
    }

    @Test func defaultThemeHasFontSize15() {
        let theme = OverlayTheme.default
        #expect(theme.fontSize == 15)
    }

    @Test func defaultThemeHasOverlayWidth320() {
        let theme = OverlayTheme.default
        #expect(theme.overlayWidth == 320)
    }

    // MARK: - Custom construction

    @Test func customThemeOverridesBackground() {
        let theme = OverlayTheme(
            background: NSColor.black,
            accent: OverlayTheme.default.accent,
            labelColor: OverlayTheme.default.labelColor,
            subtextColor: OverlayTheme.default.subtextColor,
            borderColor: OverlayTheme.default.borderColor,
            separatorColor: OverlayTheme.default.separatorColor,
            fontName: "Menlo",
            fontSize: 15,
            overlayWidth: 320
        )
        #expect(theme.background == NSColor.black)
    }

    @Test func customFontFallsBackToMonospacedSystem() {
        let theme = OverlayTheme(
            background: OverlayTheme.default.background,
            accent: OverlayTheme.default.accent,
            labelColor: OverlayTheme.default.labelColor,
            subtextColor: OverlayTheme.default.subtextColor,
            borderColor: OverlayTheme.default.borderColor,
            separatorColor: OverlayTheme.default.separatorColor,
            fontName: "NonExistentFont",
            fontSize: 14,
            overlayWidth: 320
        )
        #expect(theme.font == NSFont.monospacedSystemFont(ofSize: 14, weight: .regular))
    }

    // MARK: - Show delay

    @Test func defaultShowDelayIs200ms() {
        let theme = OverlayTheme.default
        #expect(theme.showDelay == 0.2)
    }
}
