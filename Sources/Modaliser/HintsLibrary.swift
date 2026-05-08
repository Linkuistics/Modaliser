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
    ///   color       — optional CSS color: hex ("#ff3030") or named ("tomato"), default red
    ///   background  — optional CSS color: hex or named, default semi-transparent dark
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
            .flatMap { Self.parseCSSColor($0) } ?? NSColor.black
        let background = SchemeAlistLookup.lookupString(alist, key: "background")
            .flatMap { Self.parseCSSColor($0) } ?? NSColor.white
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
            .flatMap { Self.parseCSSColor($0) } ?? color

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

    /// Parse a CSS colour string into an NSColor. Accepts:
    ///   - "#rgb", "#rrggbb", or "#rrggbbaa"
    ///   - any of the 148 CSS Level 4 named colours (case-insensitive),
    ///     plus "transparent"
    /// Returns nil for any other format — callers fall back to a default.
    private static func parseCSSColor(_ s: String) -> NSColor? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#") {
            return parseHexColor(String(trimmed.dropFirst()))
        }
        if let rgba = cssNamedColors[trimmed.lowercased()] {
            return NSColor(srgbRed: CGFloat(rgba.0) / 255.0,
                           green:   CGFloat(rgba.1) / 255.0,
                           blue:    CGFloat(rgba.2) / 255.0,
                           alpha:   CGFloat(rgba.3) / 255.0)
        }
        // Bare hex with no leading '#' is occasionally produced by hand-written
        // configs; accept it for symmetry with the prefixed form.
        return parseHexColor(trimmed)
    }

    private static func parseHexColor(_ hex: String) -> NSColor? {
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

    /// CSS Level 4 named colours plus "transparent". Values are 8-bit sRGB
    /// (r, g, b, a). Source: https://www.w3.org/TR/css-color-4/#named-colors
    private static let cssNamedColors: [String: (UInt8, UInt8, UInt8, UInt8)] = [
        "transparent":          (0, 0, 0, 0),
        "aliceblue":            (240, 248, 255, 255),
        "antiquewhite":         (250, 235, 215, 255),
        "aqua":                 (0, 255, 255, 255),
        "aquamarine":           (127, 255, 212, 255),
        "azure":                (240, 255, 255, 255),
        "beige":                (245, 245, 220, 255),
        "bisque":               (255, 228, 196, 255),
        "black":                (0, 0, 0, 255),
        "blanchedalmond":       (255, 235, 205, 255),
        "blue":                 (0, 0, 255, 255),
        "blueviolet":           (138, 43, 226, 255),
        "brown":                (165, 42, 42, 255),
        "burlywood":            (222, 184, 135, 255),
        "cadetblue":            (95, 158, 160, 255),
        "chartreuse":           (127, 255, 0, 255),
        "chocolate":            (210, 105, 30, 255),
        "coral":                (255, 127, 80, 255),
        "cornflowerblue":       (100, 149, 237, 255),
        "cornsilk":             (255, 248, 220, 255),
        "crimson":              (220, 20, 60, 255),
        "cyan":                 (0, 255, 255, 255),
        "darkblue":             (0, 0, 139, 255),
        "darkcyan":             (0, 139, 139, 255),
        "darkgoldenrod":        (184, 134, 11, 255),
        "darkgray":             (169, 169, 169, 255),
        "darkgrey":             (169, 169, 169, 255),
        "darkgreen":            (0, 100, 0, 255),
        "darkkhaki":            (189, 183, 107, 255),
        "darkmagenta":          (139, 0, 139, 255),
        "darkolivegreen":       (85, 107, 47, 255),
        "darkorange":           (255, 140, 0, 255),
        "darkorchid":           (153, 50, 204, 255),
        "darkred":              (139, 0, 0, 255),
        "darksalmon":           (233, 150, 122, 255),
        "darkseagreen":         (143, 188, 143, 255),
        "darkslateblue":        (72, 61, 139, 255),
        "darkslategray":        (47, 79, 79, 255),
        "darkslategrey":        (47, 79, 79, 255),
        "darkturquoise":        (0, 206, 209, 255),
        "darkviolet":           (148, 0, 211, 255),
        "deeppink":             (255, 20, 147, 255),
        "deepskyblue":          (0, 191, 255, 255),
        "dimgray":              (105, 105, 105, 255),
        "dimgrey":              (105, 105, 105, 255),
        "dodgerblue":           (30, 144, 255, 255),
        "firebrick":            (178, 34, 34, 255),
        "floralwhite":          (255, 250, 240, 255),
        "forestgreen":          (34, 139, 34, 255),
        "fuchsia":              (255, 0, 255, 255),
        "gainsboro":            (220, 220, 220, 255),
        "ghostwhite":           (248, 248, 255, 255),
        "gold":                 (255, 215, 0, 255),
        "goldenrod":            (218, 165, 32, 255),
        "gray":                 (128, 128, 128, 255),
        "grey":                 (128, 128, 128, 255),
        "green":                (0, 128, 0, 255),
        "greenyellow":          (173, 255, 47, 255),
        "honeydew":             (240, 255, 240, 255),
        "hotpink":              (255, 105, 180, 255),
        "indianred":            (205, 92, 92, 255),
        "indigo":               (75, 0, 130, 255),
        "ivory":                (255, 255, 240, 255),
        "khaki":                (240, 230, 140, 255),
        "lavender":             (230, 230, 250, 255),
        "lavenderblush":        (255, 240, 245, 255),
        "lawngreen":            (124, 252, 0, 255),
        "lemonchiffon":         (255, 250, 205, 255),
        "lightblue":            (173, 216, 230, 255),
        "lightcoral":           (240, 128, 128, 255),
        "lightcyan":            (224, 255, 255, 255),
        "lightgoldenrodyellow": (250, 250, 210, 255),
        "lightgray":            (211, 211, 211, 255),
        "lightgrey":            (211, 211, 211, 255),
        "lightgreen":           (144, 238, 144, 255),
        "lightpink":            (255, 182, 193, 255),
        "lightsalmon":          (255, 160, 122, 255),
        "lightseagreen":        (32, 178, 170, 255),
        "lightskyblue":         (135, 206, 250, 255),
        "lightslategray":       (119, 136, 153, 255),
        "lightslategrey":       (119, 136, 153, 255),
        "lightsteelblue":       (176, 196, 222, 255),
        "lightyellow":          (255, 255, 224, 255),
        "lime":                 (0, 255, 0, 255),
        "limegreen":            (50, 205, 50, 255),
        "linen":                (250, 240, 230, 255),
        "magenta":              (255, 0, 255, 255),
        "maroon":               (128, 0, 0, 255),
        "mediumaquamarine":     (102, 205, 170, 255),
        "mediumblue":           (0, 0, 205, 255),
        "mediumorchid":         (186, 85, 211, 255),
        "mediumpurple":         (147, 112, 219, 255),
        "mediumseagreen":       (60, 179, 113, 255),
        "mediumslateblue":      (123, 104, 238, 255),
        "mediumspringgreen":    (0, 250, 154, 255),
        "mediumturquoise":      (72, 209, 204, 255),
        "mediumvioletred":      (199, 21, 133, 255),
        "midnightblue":         (25, 25, 112, 255),
        "mintcream":            (245, 255, 250, 255),
        "mistyrose":            (255, 228, 225, 255),
        "moccasin":             (255, 228, 181, 255),
        "navajowhite":          (255, 222, 173, 255),
        "navy":                 (0, 0, 128, 255),
        "oldlace":              (253, 245, 230, 255),
        "olive":                (128, 128, 0, 255),
        "olivedrab":            (107, 142, 35, 255),
        "orange":               (255, 165, 0, 255),
        "orangered":            (255, 69, 0, 255),
        "orchid":               (218, 112, 214, 255),
        "palegoldenrod":        (238, 232, 170, 255),
        "palegreen":            (152, 251, 152, 255),
        "paleturquoise":        (175, 238, 238, 255),
        "palevioletred":        (219, 112, 147, 255),
        "papayawhip":           (255, 239, 213, 255),
        "peachpuff":            (255, 218, 185, 255),
        "peru":                 (205, 133, 63, 255),
        "pink":                 (255, 192, 203, 255),
        "plum":                 (221, 160, 221, 255),
        "powderblue":           (176, 224, 230, 255),
        "purple":               (128, 0, 128, 255),
        "rebeccapurple":        (102, 51, 153, 255),
        "red":                  (255, 0, 0, 255),
        "rosybrown":            (188, 143, 143, 255),
        "royalblue":            (65, 105, 225, 255),
        "saddlebrown":          (139, 69, 19, 255),
        "salmon":               (250, 128, 114, 255),
        "sandybrown":           (244, 164, 96, 255),
        "seagreen":             (46, 139, 87, 255),
        "seashell":             (255, 245, 238, 255),
        "sienna":               (160, 82, 45, 255),
        "silver":               (192, 192, 192, 255),
        "skyblue":              (135, 206, 235, 255),
        "slateblue":            (106, 90, 205, 255),
        "slategray":            (112, 128, 144, 255),
        "slategrey":            (112, 128, 144, 255),
        "snow":                 (255, 250, 250, 255),
        "springgreen":          (0, 255, 127, 255),
        "steelblue":            (70, 130, 180, 255),
        "tan":                  (210, 180, 140, 255),
        "teal":                 (0, 128, 128, 255),
        "thistle":              (216, 191, 216, 255),
        "tomato":               (255, 99, 71, 255),
        "turquoise":            (64, 224, 208, 255),
        "violet":               (238, 130, 238, 255),
        "wheat":                (245, 222, 179, 255),
        "white":                (255, 255, 255, 255),
        "whitesmoke":           (245, 245, 245, 255),
        "yellow":                (255, 255, 0, 255),
        "yellowgreen":          (154, 205, 50, 255),
    ]
}
