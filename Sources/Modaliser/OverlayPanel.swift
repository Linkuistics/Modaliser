import AppKit
import QuartzCore

/// Renders the which-key overlay as a floating, non-activating NSPanel.
/// Reuses the panel across navigations and updates content in-place
/// to avoid flicker. Uses CATransaction to batch subview changes.
final class OverlayPanel: OverlayPresenting {
    private(set) var panel: NSPanel?
    private var containerView: NSView?

    func showOverlay(content: OverlayContent, theme: OverlayTheme) {
        let layout = OverlayLayout(entryCount: content.entries.count, theme: theme)

        if let existingPanel = panel, let existingContainer = containerView {
            updateInPlace(
                panel: existingPanel,
                container: existingContainer,
                content: content,
                theme: theme,
                layout: layout
            )
        } else {
            createAndShow(content: content, theme: theme, layout: layout)
        }
    }

    func dismissOverlay() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        containerView = nil
    }

    // MARK: - Private

    private func createAndShow(content: OverlayContent, theme: OverlayTheme, layout: OverlayLayout) {
        let p = createPanel(size: NSSize(width: layout.width, height: layout.totalHeight))
        let container = createContainer(frame: NSRect(origin: .zero, size: p.frame.size), theme: theme)
        p.contentView = container

        renderContent(in: container, content: content, theme: theme, layout: layout)
        positionOnScreen(panel: p, layout: layout)

        p.orderFront(nil)
        panel = p
        containerView = container
    }

    private func updateInPlace(
        panel: NSPanel,
        container: NSView,
        content: OverlayContent,
        theme: OverlayTheme,
        layout: OverlayLayout
    ) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        container.subviews.forEach { $0.removeFromSuperview() }

        let newSize = NSSize(width: layout.width, height: layout.totalHeight)
        container.frame = NSRect(origin: .zero, size: newSize)

        renderContent(in: container, content: content, theme: theme, layout: layout)

        panel.setContentSize(newSize)
        positionOnScreen(panel: panel, layout: layout)

        CATransaction.commit()
    }

    private func createPanel(size: NSSize) -> NSPanel {
        let p = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
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
        return p
    }

    private func createContainer(frame: NSRect, theme: OverlayTheme) -> NSView {
        let container = NSView(frame: frame)
        container.wantsLayer = true
        container.layer?.cornerRadius = 10
        container.layer?.masksToBounds = true
        container.layer?.borderWidth = 2
        container.layer?.borderColor = theme.borderColor.cgColor
        container.layer?.backgroundColor = theme.background.cgColor
        return container
    }

    private func renderContent(
        in container: NSView,
        content: OverlayContent,
        theme: OverlayTheme,
        layout: OverlayLayout
    ) {
        var y: CGFloat = layout.smallGap

        // Footer (bottom)
        OverlayFooterRenderer.render(in: container, at: y, width: layout.textWidth, padding: layout.padding, lineHeight: layout.lineHeight, theme: theme)
        y += layout.lineHeight + layout.smallGap

        // Separator 2
        renderSeparator(in: container, at: y, width: layout.textWidth, padding: layout.padding, theme: theme)
        y += layout.separatorHeight + layout.smallGap

        // Entries
        OverlayEntryRenderer.render(in: container, entries: content.entries, at: y, width: layout.textWidth, padding: layout.padding, indent: layout.indent, lineHeight: layout.lineHeight, theme: theme)
        y += CGFloat(content.entries.count) * layout.lineHeight + layout.gap

        // Separator 1
        renderSeparator(in: container, at: y, width: layout.textWidth, padding: layout.padding, theme: theme)
        y += layout.separatorHeight + layout.smallGap

        // Header (top)
        OverlayHeaderRenderer.render(in: container, header: content.header, icon: content.headerIcon, at: y, width: layout.textWidth, padding: layout.padding, lineHeight: layout.lineHeight, theme: theme)
    }

    private func renderSeparator(in container: NSView, at y: CGFloat, width: CGFloat, padding: CGFloat, theme: OverlayTheme) {
        let sep = NSView(frame: NSRect(x: padding, y: y, width: width, height: 1))
        sep.wantsLayer = true
        sep.layer?.backgroundColor = theme.separatorColor.cgColor
        container.addSubview(sep)
    }

    private func positionOnScreen(panel: NSPanel, layout: OverlayLayout) {
        guard let screen = NSScreen.main else { return }
        let sf = screen.visibleFrame
        let x = sf.midX - layout.width / 2
        let y = sf.maxY - (sf.height * 0.2) - layout.totalHeight
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
