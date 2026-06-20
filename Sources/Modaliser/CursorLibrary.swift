import AppKit

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
