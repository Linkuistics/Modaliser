import AppKit

/// Renders the footer section of the which-key overlay (del back / esc cancel).
enum OverlayFooterRenderer {

    static func render(
        in container: NSView,
        at y: CGFloat,
        width: CGFloat,
        padding: CGFloat,
        lineHeight: CGFloat,
        theme: OverlayTheme
    ) {
        let para = NSMutableParagraphStyle()
        let rightStop = NSTextTab(textAlignment: .right, location: width - 4)
        para.tabStops = [rightStop]

        let attr = styledFooter(theme: theme, paragraphStyle: para)
        let label = NSTextField(frame: NSRect(x: padding, y: y, width: width, height: lineHeight))
        label.attributedStringValue = attr
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        container.addSubview(label)
    }

    // MARK: - Private

    private static func styledFooter(theme: OverlayTheme, paragraphStyle: NSParagraphStyle) -> NSAttributedString {
        let baseSize = theme.fontSize - 2
        let font = NSFont(name: theme.font.fontName, size: baseSize)
            ?? NSFont.monospacedSystemFont(ofSize: baseSize, weight: .regular)

        let segments: [(String, Bool)] = [
            ("del", true), (" back", false),
            ("\t", false),
            ("esc", true), (" cancel", false),
        ]

        let result = NSMutableAttributedString()
        for (text, isKey) in segments {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: isKey ? theme.accent : theme.subtextColor,
                .paragraphStyle: paragraphStyle,
            ]
            result.append(NSAttributedString(string: text, attributes: attrs))
        }
        return result
    }
}
