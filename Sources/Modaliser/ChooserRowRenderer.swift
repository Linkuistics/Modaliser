import AppKit

/// Table view data source/delegate and row rendering for the chooser.
extension ChooserWindowController: NSTableViewDataSource, NSTableViewDelegate {

    // MARK: - Data source

    func numberOfRows(in tableView: NSTableView) -> Int {
        actionPanel.isActive ? actionPanel.actions.count : filteredChoices.count
    }

    // MARK: - Delegate

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        rowHeight
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        actionPanel.isActive ? makeActionRow(row: row) : makeChoiceRow(row: row)
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if actionPanel.isActive {
            actionPanel.selectedIndex = row
        } else {
            selectedIndex = row
        }
        tableView.reloadData()
        return false
    }

    // MARK: - Choice row

    private func makeChoiceRow(row: Int) -> NSView {
        let choice = filteredChoices[row]
        let isSelected = (row == selectedIndex)
        let cellView = NSView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: rowHeight))

        if isSelected {
            addSelectionHighlight(to: cellView)
        }

        // Digit indicator (rows 0-8)
        let digitAreaWidth: CGFloat = row < 9 ? 22 : 6
        if row < 9 {
            let digitFont = NSFont(name: chooserTheme.font.fontName, size: chooserTheme.fontSize - 2)
                ?? NSFont.monospacedSystemFont(ofSize: chooserTheme.fontSize - 2, weight: .regular)
            let digitLabel = NSTextField(frame: NSRect(x: 4, y: (rowHeight - 16) / 2, width: 18, height: 16))
            digitLabel.stringValue = "\(row + 1)"
            digitLabel.isBezeled = false
            digitLabel.drawsBackground = false
            digitLabel.isEditable = false
            digitLabel.isSelectable = false
            digitLabel.font = digitFont
            digitLabel.textColor = chooserTheme.accent.withAlphaComponent(0.5)
            digitLabel.alignment = .center
            cellView.addSubview(digitLabel)
        }

        // Icon
        let iconX: CGFloat = digitAreaWidth
        let textX: CGFloat
        if let image = IconLoader.shared.icon(for: choice) {
            let iconView = NSImageView(frame: NSRect(x: iconX, y: 8, width: 32, height: 32))
            iconView.image = image
            iconView.imageScaling = .scaleProportionallyUpOrDown
            cellView.addSubview(iconView)
            textX = iconX + 32 + 8
        } else {
            textX = iconX + 4
        }

        // Text label with match highlighting
        let textMatches = row < filteredTextMatches.count ? filteredTextMatches[row] : []
        let textLabel = NSTextField(frame: NSRect(
            x: textX, y: rowHeight - 26, width: windowWidth - textX - 12, height: 18
        ))
        textLabel.attributedStringValue = highlightedString(
            choice.text, matches: textMatches, font: chooserTheme.font,
            baseColor: chooserTheme.labelColor, highlightColor: chooserTheme.accent
        )
        textLabel.isBezeled = false
        textLabel.drawsBackground = false
        textLabel.isEditable = false
        textLabel.isSelectable = false
        textLabel.lineBreakMode = .byTruncatingTail
        textLabel.cell?.truncatesLastVisibleLine = true
        cellView.addSubview(textLabel)

        // SubText
        if let sub = choice.subText, !sub.isEmpty {
            let subFont = NSFont(name: chooserTheme.font.fontName, size: chooserTheme.fontSize - 2)
                ?? NSFont.monospacedSystemFont(ofSize: chooserTheme.fontSize - 2, weight: .regular)
            let subMatches = row < filteredSubMatches.count ? filteredSubMatches[row] : []
            let subLabel = NSTextField(frame: NSRect(
                x: textX, y: 4, width: windowWidth - textX - 12, height: 16
            ))
            subLabel.attributedStringValue = highlightedString(
                sub, matches: subMatches, font: subFont,
                baseColor: chooserTheme.subtextColor, highlightColor: chooserTheme.accent
            )
            subLabel.isBezeled = false
            subLabel.drawsBackground = false
            subLabel.isEditable = false
            subLabel.isSelectable = false
            subLabel.lineBreakMode = .byTruncatingTail
            subLabel.cell?.truncatesLastVisibleLine = true
            cellView.addSubview(subLabel)
        }

        return cellView
    }

    // MARK: - Action row

    private func makeActionRow(row: Int) -> NSView {
        let action = actionPanel.actions[row]
        let isSelected = (row == actionPanel.selectedIndex)
        let digit = row + 1
        let cellView = NSView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: rowHeight))

        if isSelected {
            addSelectionHighlight(to: cellView)
        }

        let textX: CGFloat = 12

        // Digit label
        let digitLabel = NSTextField(frame: NSRect(x: textX, y: rowHeight - 26, width: 20, height: 18))
        digitLabel.stringValue = digit <= 9 ? "\(digit)" : ""
        digitLabel.isBezeled = false
        digitLabel.drawsBackground = false
        digitLabel.isEditable = false
        digitLabel.isSelectable = false
        digitLabel.font = chooserTheme.font
        digitLabel.textColor = chooserTheme.accent
        cellView.addSubview(digitLabel)

        // Action name
        let nameX = textX + 24
        let nameLabel = NSTextField(frame: NSRect(
            x: nameX, y: rowHeight - 26, width: windowWidth - nameX - 12, height: 18
        ))
        nameLabel.stringValue = action.name
        nameLabel.isBezeled = false
        nameLabel.drawsBackground = false
        nameLabel.isEditable = false
        nameLabel.isSelectable = false
        nameLabel.font = chooserTheme.font
        nameLabel.textColor = chooserTheme.labelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.cell?.truncatesLastVisibleLine = true
        cellView.addSubview(nameLabel)

        // Action description as subtext
        if let desc = action.description, !desc.isEmpty {
            let subFont = NSFont(name: chooserTheme.font.fontName, size: chooserTheme.fontSize - 2)
                ?? NSFont.monospacedSystemFont(ofSize: chooserTheme.fontSize - 2, weight: .regular)
            let subLabel = NSTextField(frame: NSRect(x: nameX, y: 4, width: windowWidth - nameX - 12, height: 16))
            subLabel.stringValue = desc
            subLabel.isBezeled = false
            subLabel.drawsBackground = false
            subLabel.isEditable = false
            subLabel.isSelectable = false
            subLabel.font = subFont
            subLabel.textColor = chooserTheme.subtextColor
            subLabel.lineBreakMode = .byTruncatingTail
            subLabel.cell?.truncatesLastVisibleLine = true
            cellView.addSubview(subLabel)
        }

        return cellView
    }

    // MARK: - Highlight helpers

    private func addSelectionHighlight(to cellView: NSView) {
        let leftBorder = NSView(frame: NSRect(x: 0, y: 0, width: 3, height: rowHeight))
        leftBorder.wantsLayer = true
        leftBorder.layer?.backgroundColor = chooserTheme.accent.cgColor
        cellView.addSubview(leftBorder)

        let bgView = NSView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: rowHeight))
        bgView.wantsLayer = true
        bgView.layer?.backgroundColor = chooserTheme.accent.withAlphaComponent(0.08).cgColor
        cellView.addSubview(bgView, positioned: .below, relativeTo: leftBorder)
    }

    /// Build attributed string with matched characters highlighted in accent + bold.
    func highlightedString(
        _ text: String, matches: Set<Int>, font: NSFont,
        baseColor: NSColor, highlightColor: NSColor
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: baseColor
        ])
        if !matches.isEmpty {
            let boldFont = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            for idx in matches {
                guard idx < text.count else { continue }
                let range = NSRange(location: idx, length: 1)
                result.addAttributes([
                    .foregroundColor: highlightColor,
                    .font: boldFont
                ], range: range)
            }
        }
        return result
    }
}
