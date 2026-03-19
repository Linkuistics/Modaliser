import AppKit

/// Renders the keybinding entries section of the which-key overlay.
/// Keys in accent blue, arrows in grey, group labels in orange with "…" suffix.
enum OverlayEntryRenderer {

    static func render(
        in container: NSView,
        entries: [OverlayEntry],
        at y: CGFloat,
        width: CGFloat,
        padding: CGFloat,
        indent: CGFloat,
        lineHeight: CGFloat,
        theme: OverlayTheme
    ) {
        for (i, entry) in entries.enumerated() {
            let entryY = y + CGFloat(entries.count - 1 - i) * lineHeight // bottom-up
            let x = padding + indent

            let attr = styledEntry(entry, theme: theme)
            let label = NSTextField(frame: NSRect(x: x, y: entryY, width: width - indent, height: lineHeight))
            label.attributedStringValue = attr
            label.isBezeled = false
            label.drawsBackground = false
            label.isEditable = false
            label.isSelectable = false
            container.addSubview(label)
        }
    }

    // MARK: - Private

    private static func styledEntry(_ entry: OverlayEntry, theme: OverlayTheme) -> NSAttributedString {
        let displayKey = entry.key == "space" ? "\u{2423}" : entry.key
        let paddedKey = displayKey.count < 2 ? displayKey + " " : displayKey
        let isGroup = entry.style == .group
        let suffix = isGroup ? " \u{2026}" : ""

        let attr = NSMutableAttributedString()
        attr.append(NSAttributedString(string: paddedKey, attributes: [
            .font: theme.font,
            .foregroundColor: theme.accent,
        ]))
        attr.append(NSAttributedString(string: " \u{2192} ", attributes: [
            .font: theme.font,
            .foregroundColor: arrowColor,
        ]))
        let labelColor = isGroup ? groupColor : theme.labelColor
        attr.append(NSAttributedString(string: entry.label + suffix, attributes: [
            .font: theme.font,
            .foregroundColor: labelColor,
        ]))
        return attr
    }

    private static var groupColor: NSColor {
        NSColor(red: 0.80, green: 0.45, blue: 0.10, alpha: 1)
    }

    private static var arrowColor: NSColor {
        NSColor(white: 0.50, alpha: 1)
    }
}
