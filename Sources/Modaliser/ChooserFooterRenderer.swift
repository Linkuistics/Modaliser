import AppKit

/// Footer rendering for the chooser window.
extension ChooserWindowController {

    func makeFooterLabel() -> NSTextField {
        let tf = NSTextField(frame: .zero)
        let cell = VerticalCenteringCell()
        cell.isBezeled = false
        cell.drawsBackground = false
        cell.isEditable = false
        cell.isSelectable = false
        cell.focusRingType = .none
        tf.cell = cell
        tf.isBezeled = false
        tf.drawsBackground = false
        tf.isEditable = false
        tf.isSelectable = false
        updateFooterText(tf)
        return tf
    }

    func updateFooter() {
        guard let label = footerLabel else { return }
        updateFooterText(label)
    }

    private func updateFooterText(_ label: NSTextField) {
        let para = NSMutableParagraphStyle()
        let rightStop = NSTextTab(textAlignment: .right, location: windowWidth - 32)
        para.tabStops = [rightStop]

        if actionPanel.isActive {
            label.attributedStringValue = styledFooter([
                ("\u{21A9}", true), (" run  ", false),
                ("1-9", true), (" shortcut  ", false),
                ("del", true), (" back", false),
                ("\t", false),
                ("esc", true), (" cancel", false),
            ], para: para)
        } else if helpExpanded {
            let secondaryName = selectorActions.first(where: { $0.trigger == .secondary })?.name ?? "action"
            let expandedPara = NSMutableParagraphStyle()
            label.attributedStringValue = styledFooter([
                ("\u{21A9}", true), (" open  ", false),
                ("\u{2318}", true), ("\u{21A9}", true), (" \(secondaryName)  ", false),
                ("\u{2318}", true), ("K", true), (" actions\u{2026}\n", false),
                ("\u{2191}\u{2193}", true), (" navigate  ", false),
                ("esc", true), (" cancel  ", false),
                ("\u{2318}", true), ("?", true), (" hide help", false),
            ], para: expandedPara)
        } else {
            label.attributedStringValue = styledFooter([
                ("\u{21A9}", true), (" open  ", false),
                ("\u{2318}", true), ("\u{21A9}", true), (" actions", false),
                ("\t", false),
                ("esc", true), (" cancel", false),
            ], para: para)
        }
    }

    /// Build styled footer: keys in accent, descriptions in subtext.
    /// Segments containing only command/return symbols get the system font.
    private func styledFooter(
        _ segments: [(String, Bool)], para: NSParagraphStyle? = nil
    ) -> NSAttributedString {
        let baseSize = chooserTheme.fontSize - 2
        let font = NSFont(name: chooserTheme.font.fontName, size: baseSize)
            ?? NSFont.monospacedSystemFont(ofSize: baseSize, weight: .regular)
        let cmdFont = NSFont.systemFont(ofSize: round(baseSize * 0.9375))
        let result = NSMutableAttributedString()
        for (text, isKey) in segments {
            var attrs: [NSAttributedString.Key: Any] = [
                .font: (text == "\u{2318}" || text == "\u{21A9}") ? cmdFont : font,
                .foregroundColor: isKey ? chooserTheme.accent : chooserTheme.subtextColor
            ]
            if let para { attrs[.paragraphStyle] = para }
            result.append(NSAttributedString(string: text, attributes: attrs))
        }
        return result
    }
}
