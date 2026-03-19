import AppKit

/// Window construction and layout for the chooser.
extension ChooserWindowController {

    func buildWindow(prompt: String) {
        let contentHeight = searchHeight + tableHeight() + currentFooterHeight() + 2
        let frame = NSRect(x: 0, y: 0, width: windowWidth, height: contentHeight)

        let p = KeyablePanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = false
        p.hidesOnDeactivate = false

        let container = NSView(frame: frame)
        container.wantsLayer = true
        container.layer?.cornerRadius = cornerRadius
        container.layer?.masksToBounds = true
        container.layer?.borderWidth = borderWidth
        container.layer?.borderColor = chooserTheme.borderColor.cgColor
        container.layer?.backgroundColor = chooserTheme.background.cgColor
        p.contentView = container

        var yOffset: CGFloat = currentFooterHeight()

        // Footer
        let footer = makeFooterLabel()
        footer.frame = NSRect(x: 12, y: 1, width: windowWidth - 24, height: currentFooterHeight())
        container.addSubview(footer)
        footerLabel = footer

        // Bottom separator
        let sepBottom = NSView(frame: NSRect(x: 0, y: yOffset, width: windowWidth, height: 1))
        sepBottom.wantsLayer = true
        sepBottom.layer?.backgroundColor = chooserTheme.separatorColor.cgColor
        container.addSubview(sepBottom)
        separatorBottom = sepBottom
        yOffset += 1

        // Table view
        let tv = NSTableView()
        tv.style = .plain
        tv.headerView = nil
        tv.backgroundColor = .clear
        tv.rowHeight = rowHeight
        tv.intercellSpacing = NSSize(width: 0, height: 0)
        tv.selectionHighlightStyle = .none
        tv.usesAlternatingRowBackgroundColors = false
        tv.allowsMultipleSelection = false
        tv.dataSource = self
        tv.delegate = self
        tv.focusRingType = .none

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.width = windowWidth - 4
        tv.addTableColumn(column)

        let sv = NSScrollView(frame: NSRect(x: 0, y: yOffset, width: windowWidth, height: tableHeight()))
        sv.documentView = tv
        sv.hasVerticalScroller = true
        sv.autohidesScrollers = true
        sv.hasHorizontalScroller = false
        sv.drawsBackground = false
        sv.borderType = .noBorder
        sv.verticalLineScroll = rowHeight
        sv.verticalPageScroll = rowHeight
        sv.automaticallyAdjustsContentInsets = false
        sv.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        container.addSubview(sv)
        scrollView = sv
        tableView = tv
        yOffset += tableHeight()

        // Top separator
        let sepTop = NSView(frame: NSRect(x: 0, y: yOffset, width: windowWidth, height: 1))
        sepTop.wantsLayer = true
        sepTop.layer?.backgroundColor = chooserTheme.separatorColor.cgColor
        container.addSubview(sepTop)
        separatorTop = sepTop
        yOffset += 1

        // Search field
        let sf = NSTextField(string: "")
        sf.font = chooserTheme.font
        searchFieldNaturalH = sf.intrinsicContentSize.height
        let fieldY = yOffset + round((searchHeight - searchFieldNaturalH) / 2) - 4
        sf.frame = NSRect(x: 12, y: fieldY, width: windowWidth - 24, height: searchFieldNaturalH)
        sf.isBezeled = false
        sf.drawsBackground = false
        sf.isEditable = true
        sf.isSelectable = true
        sf.focusRingType = .none
        sf.textColor = chooserTheme.labelColor
        sf.placeholderString = "\u{203A} " + prompt
        sf.cell?.wraps = false
        sf.cell?.isScrollable = true
        sf.delegate = self
        container.addSubview(sf)
        searchField = sf

        panel = p
        tv.reloadData()
    }

    // MARK: - Layout

    func tableHeight() -> CGFloat {
        let count = actionPanel.isActive ? actionPanel.actions.count : filteredChoices.count
        let visibleRows = min(count, maxRows)
        return CGFloat(max(visibleRows, 1)) * rowHeight
    }

    func currentFooterHeight() -> CGFloat {
        helpExpanded ? footerExpandedHeight : footerHeight
    }

    func positionOnScreen() {
        guard let screen = NSScreen.main, let p = panel else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - windowWidth / 2
        let windowHeight = p.frame.height
        let y = screenFrame.maxY - (screenFrame.height * 0.2) - windowHeight
        p.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func resizeTableArea() {
        guard let container = panel?.contentView else { return }
        let newTableH = tableHeight()
        let newFooterH = currentFooterHeight()
        let contentHeight = searchHeight + newTableH + newFooterH + 2

        var wFrame = panel!.frame
        let topY = wFrame.maxY
        wFrame.size.height = contentHeight
        wFrame.origin.y = topY - contentHeight
        panel?.setFrame(wFrame, display: false)

        container.frame = NSRect(x: 0, y: 0, width: windowWidth, height: contentHeight)

        var yOffset: CGFloat = 0
        footerLabel?.frame = NSRect(x: 12, y: 1, width: windowWidth - 24, height: newFooterH)
        yOffset = newFooterH

        separatorBottom?.frame = NSRect(x: 0, y: yOffset, width: windowWidth, height: 1)
        yOffset += 1

        scrollView?.frame = NSRect(x: 0, y: yOffset, width: windowWidth, height: newTableH)
        yOffset += newTableH

        separatorTop?.frame = NSRect(x: 0, y: yOffset, width: windowWidth, height: 1)
        yOffset += 1

        if let sf = searchField {
            let fieldY = yOffset + round((searchHeight - searchFieldNaturalH) / 2) - 4
            sf.frame = NSRect(x: 12, y: fieldY, width: windowWidth - 24, height: searchFieldNaturalH)
        }

        panel?.display()
    }
}
