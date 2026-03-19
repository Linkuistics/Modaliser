import AppKit

/// Renders the header section of the which-key overlay (breadcrumb + optional app icon).
enum OverlayHeaderRenderer {

    static func render(
        in container: NSView,
        header: String,
        icon: String?,
        at y: CGFloat,
        width: CGFloat,
        padding: CGFloat,
        lineHeight: CGFloat,
        theme: OverlayTheme
    ) {
        var x = padding

        // Optional app icon (for local/app-specific mode)
        if let bundleId = icon, !bundleId.isEmpty,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            let iconImage = NSWorkspace.shared.icon(forFile: url.path)
            iconImage.size = NSSize(width: lineHeight, height: lineHeight)
            let iconView = NSImageView(frame: NSRect(x: x, y: y - 2, width: lineHeight, height: lineHeight))
            iconView.image = iconImage
            container.addSubview(iconView)
            x += lineHeight + 6
        }

        let label = NSTextField(frame: NSRect(x: x, y: y, width: width - (x - padding), height: lineHeight))
        label.stringValue = header
        label.font = theme.font
        label.textColor = headerColor
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        container.addSubview(label)
    }

    private static var headerColor: NSColor {
        NSColor(white: 0.50, alpha: 1)
    }
}
