import AppKit
import LispKit
import CoreGraphics

/// Parses hex colour strings for the cursor highlight ring.
enum CursorColor {
    /// Accepts "#RRGGBB", "RRGGBB", "#RGB", or "RGB". Returns nil on bad input.
    static func parse(_ hex: String) -> NSColor? {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        let chars = Array(s)
        let r: Int, g: Int, b: Int
        switch chars.count {
        case 3:
            guard let rr = Int(String([chars[0], chars[0]]), radix: 16),
                  let gg = Int(String([chars[1], chars[1]]), radix: 16),
                  let bb = Int(String([chars[2], chars[2]]), radix: 16) else { return nil }
            r = rr; g = gg; b = bb
        case 6:
            guard let rr = Int(String(chars[0...1]), radix: 16),
                  let gg = Int(String(chars[2...3]), radix: 16),
                  let bb = Int(String(chars[4...5]), radix: 16) else { return nil }
            r = rr; g = gg; b = bb
        default:
            return nil
        }
        return NSColor(srgbRed: CGFloat(r) / 255.0,
                       green: CGFloat(g) / 255.0,
                       blue: CGFloat(b) / 255.0,
                       alpha: 1.0)
    }
}

/// Resolved parameters for one highlight flash.
struct CursorHighlightOptions {
    var color: NSColor
    var size: CGFloat
    var thickness: CGFloat
    var glow: CGFloat
    var duration: Double
    var nudge: Bool

    /// Defaults per the spec.
    static var defaults: CursorHighlightOptions {
        CursorHighlightOptions(
            color: CursorColor.parse("#FFCC33") ?? .systemYellow,
            size: 240, thickness: 6, glow: 18, duration: 0.45, nudge: true
        )
    }

    /// Extract a Double from a Scheme number (fixnum or flonum), else nil.
    static func number(_ e: Expr) -> Double? {
        switch e {
        case .fixnum(let n): return Double(n)
        case .flonum(let d): return d
        default: return nil
        }
    }

    /// Interpret keyword pairs into options. Unknown keys ignored; invalid
    /// values leave the corresponding default in place.
    static func from(_ pairs: [(String, Expr)]) -> CursorHighlightOptions {
        var o = CursorHighlightOptions.defaults
        for (key, value) in pairs {
            switch key {
            case "color":
                if let s = try? value.asString(), let c = CursorColor.parse(s) { o.color = c }
            case "size":      if let n = number(value) { o.size = CGFloat(n) }
            case "thickness": if let n = number(value) { o.thickness = CGFloat(n) }
            case "glow":      if let n = number(value) { o.glow = CGFloat(n) }
            case "duration":  if let n = number(value) { o.duration = n }
            case "nudge":     if case .false = value { o.nudge = false } else { o.nudge = true }
            default: break
            }
        }
        return o
    }
}
