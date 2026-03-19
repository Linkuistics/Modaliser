import AppKit

/// NSTextFieldCell subclass that vertically centers text.
/// Default NSTextFieldCell aligns text to the top; this centers it for the footer label.
final class VerticalCenteringCell: NSTextFieldCell {
    override func titleRect(forBounds rect: NSRect) -> NSRect {
        var r = super.titleRect(forBounds: rect)
        let textH = attributedStringValue.size().height
        if textH < r.height {
            r.origin.y = rect.origin.y + (rect.height - textH) / 2
            r.size.height = textH
        }
        return r
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        super.drawInterior(withFrame: titleRect(forBounds: cellFrame), in: controlView)
    }

    override func select(
        withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText,
        delegate: Any?, start selStart: Int, length selLength: Int
    ) {
        super.select(
            withFrame: titleRect(forBounds: rect), in: controlView, editor: textObj,
            delegate: delegate, start: selStart, length: selLength
        )
    }

    override func edit(
        withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText,
        delegate: Any?, event: NSEvent?
    ) {
        super.edit(
            withFrame: titleRect(forBounds: rect), in: controlView, editor: textObj,
            delegate: delegate, event: event
        )
    }
}
