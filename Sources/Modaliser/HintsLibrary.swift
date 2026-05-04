import AppKit
import LispKit

/// Native LispKit library providing a generic on-screen hint overlay system.
/// Scheme name: (modaliser hints)
///
/// A "hint" is a single character (or short string) drawn large at a screen
/// rectangle. Used for picking among visually-identifiable targets — iTerm
/// panes today; macOS windows or browser tabs in the future.
///
/// Provides: hints-show, hints-hide
final class HintsLibrary: NativeLibrary {

    /// Live hint panels, kept alive until hints-hide is called.
    private var panels: [NSPanel] = []

    public required init(in context: Context) throws {
        try super.init(in: context)
    }

    public override class var name: [String] {
        ["modaliser", "hints"]
    }

    public override func dependencies() {
        self.`import`(from: ["lispkit", "base"])
    }

    public override func declarations() {
        self.define(Procedure("hints-show", hintsShowFunction))
        self.define(Procedure("hints-hide", hintsHideFunction))
    }

    // MARK: - Procedures

    /// (hints-show hint-list) → void
    ///
    /// hint-list is a list of alists. Each alist may contain:
    ///   label       — required string, drawn centered in the panel
    ///   x, y, w, h  — required ints, screen rectangle in AX coords (top-left origin)
    ///   color       — optional CSS-ish hex string ("#ff3030"), default red
    ///   background  — optional CSS-ish hex, default semi-transparent dark
    ///   font-size   — optional fixnum, default = min(w, h) * 0.5
    private func hintsShowFunction(_ hintsExpr: Expr) throws -> Expr {
        // Always close any prior set first — hints are an exclusive overlay.
        closeAllPanels()

        var current = hintsExpr
        while case .pair(let entry, let tail) = current {
            if let panel = makeHintPanel(from: entry) {
                panels.append(panel)
            }
            current = tail
        }
        return .void
    }

    /// (hints-hide) → void
    private func hintsHideFunction() -> Expr {
        closeAllPanels()
        return .void
    }

    // MARK: - Panel construction

    private func makeHintPanel(from alist: Expr) -> NSPanel? {
        guard let label = SchemeAlistLookup.lookupString(alist, key: "label"),
              let x = SchemeAlistLookup.lookupFixnum(alist, key: "x"),
              let y = SchemeAlistLookup.lookupFixnum(alist, key: "y"),
              let w = SchemeAlistLookup.lookupFixnum(alist, key: "w"),
              let h = SchemeAlistLookup.lookupFixnum(alist, key: "h")
        else { return nil }

        // Defaults chosen to read like a small chip: black text on white,
        // medium weight, modest corner rounding. Caller can override any.
        let color = SchemeAlistLookup.lookupString(alist, key: "color")
            .flatMap { Self.parseHexColor($0) } ?? NSColor.black
        let background = SchemeAlistLookup.lookupString(alist, key: "background")
            .flatMap { Self.parseHexColor($0) } ?? NSColor.white
        let fontSize = SchemeAlistLookup.lookupFixnum(alist, key: "font-size")
            .map { CGFloat($0) } ?? CGFloat(min(w, h))
        let padding = SchemeAlistLookup.lookupFixnum(alist, key: "padding")
            .map { CGFloat($0) } ?? 0
        let cornerRadius = SchemeAlistLookup.lookupFixnum(alist, key: "corner-radius")
            .map { CGFloat($0) } ?? 4
        let borderWidth = SchemeAlistLookup.lookupFixnum(alist, key: "border-width")
            .map { CGFloat($0) } ?? 0
        // Border defaults to the text colour — keeps the chip coherent and
        // makes white-on-white configurations still visible. Override with
        // an explicit border-color to break that coupling.
        let borderColor = SchemeAlistLookup.lookupString(alist, key: "border-color")
            .flatMap { Self.parseHexColor($0) } ?? color

        // AX coords use top-left origin; Cocoa NSPanel uses bottom-left of the
        // primary screen. Flip y here so callers can pass AX rects unchanged.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let cocoaY = primaryHeight - CGFloat(y) - CGFloat(h)
        let frame = NSRect(x: CGFloat(x), y: cocoaY,
                           width: CGFloat(w), height: CGFloat(h))

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true

        let content = NSView(frame: NSRect(origin: .zero, size: frame.size))
        content.wantsLayer = true
        content.layer?.backgroundColor = background.cgColor
        content.layer?.cornerRadius = cornerRadius
        if borderWidth > 0 {
            content.layer?.borderWidth = borderWidth
            content.layer?.borderColor = borderColor.cgColor
        }

        let textField = NSTextField(labelWithString: label)
        textField.font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        textField.textColor = color
        textField.alignment = .center
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(textField)
        // Padding here is the inset between the panel rim and the text bbox.
        // For a chip that hugs its glyph, callers size w/h = font + 2*padding
        // (a single rule), then padding is just visual breathing room around
        // the centered label rather than an extra margin to honor.
        NSLayoutConstraint.activate([
            textField.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            textField.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            textField.leadingAnchor.constraint(
                greaterThanOrEqualTo: content.leadingAnchor, constant: padding),
            textField.trailingAnchor.constraint(
                lessThanOrEqualTo: content.trailingAnchor, constant: -padding),
        ])

        panel.contentView = content
        panel.orderFrontRegardless()
        return panel
    }

    private func closeAllPanels() {
        for p in panels {
            p.orderOut(nil)
            p.close()
        }
        panels.removeAll()
    }

    // MARK: - Helpers

    /// Parse "#rgb", "#rrggbb", or "#rrggbbaa" into an NSColor.
    /// Returns nil for any other format — callers fall back to a default.
    private static func parseHexColor(_ s: String) -> NSColor? {
        var hex = s.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex.removeFirst() }
        let len = hex.count
        guard len == 3 || len == 6 || len == 8,
              let v = UInt64(hex, radix: 16) else { return nil }
        let r, g, b, a: CGFloat
        switch len {
        case 3:
            r = CGFloat((v >> 8) & 0xF) / 15.0
            g = CGFloat((v >> 4) & 0xF) / 15.0
            b = CGFloat(v & 0xF) / 15.0
            a = 1.0
        case 6:
            r = CGFloat((v >> 16) & 0xFF) / 255.0
            g = CGFloat((v >> 8) & 0xFF) / 255.0
            b = CGFloat(v & 0xFF) / 255.0
            a = 1.0
        default: // 8
            r = CGFloat((v >> 24) & 0xFF) / 255.0
            g = CGFloat((v >> 16) & 0xFF) / 255.0
            b = CGFloat((v >> 8) & 0xFF) / 255.0
            a = CGFloat(v & 0xFF) / 255.0
        }
        return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
}
