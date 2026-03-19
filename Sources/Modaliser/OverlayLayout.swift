import Foundation

/// Layout constants for the which-key overlay panel.
/// Computed from entry count and theme settings.
struct OverlayLayout {
    let padding: CGFloat = 18
    let lineHeight: CGFloat = 24
    let gap: CGFloat = 8
    let smallGap: CGFloat = 4
    let separatorHeight: CGFloat = 1
    let indent: CGFloat = 10
    let width: CGFloat
    let totalHeight: CGFloat
    let textWidth: CGFloat

    init(entryCount: Int, theme: OverlayTheme) {
        self.width = theme.overlayWidth

        let headerHeight = lineHeight
        let entriesHeight = CGFloat(entryCount) * lineHeight
        let footerHeight = lineHeight
        self.totalHeight = padding + headerHeight + smallGap + separatorHeight + gap
            + entriesHeight + smallGap + separatorHeight + smallGap
            + footerHeight + smallGap

        self.textWidth = width - padding * 2
    }
}
