import AppKit

/// Visual theme for the which-key overlay and future chooser window.
/// Configurable via the Scheme DSL `(set-theme! ...)` function.
struct OverlayTheme {
    let background: NSColor
    let accent: NSColor
    let labelColor: NSColor
    let subtextColor: NSColor
    let borderColor: NSColor
    let separatorColor: NSColor
    let font: NSFont
    let fontSize: CGFloat
    let overlayWidth: CGFloat
    let showDelay: TimeInterval

    static let `default` = OverlayTheme(
        background: NSColor(red: 0.99, green: 0.97, blue: 0.93, alpha: 1),
        accent: NSColor(red: 0.13, green: 0.38, blue: 0.73, alpha: 1),
        labelColor: NSColor(white: 0.22, alpha: 1),
        subtextColor: NSColor(white: 0.67, alpha: 1),
        borderColor: NSColor(white: 0.60, alpha: 1),
        separatorColor: NSColor(white: 0.80, alpha: 1),
        fontName: "Menlo",
        fontSize: 15,
        overlayWidth: 320,
        showDelay: 0.2
    )

    init(
        background: NSColor,
        accent: NSColor,
        labelColor: NSColor,
        subtextColor: NSColor,
        borderColor: NSColor,
        separatorColor: NSColor,
        fontName: String,
        fontSize: CGFloat,
        overlayWidth: CGFloat,
        showDelay: TimeInterval = 0.2
    ) {
        self.background = background
        self.accent = accent
        self.labelColor = labelColor
        self.subtextColor = subtextColor
        self.borderColor = borderColor
        self.separatorColor = separatorColor
        self.fontSize = fontSize
        self.overlayWidth = overlayWidth
        self.showDelay = showDelay
        self.font = NSFont(name: fontName, size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }
}
