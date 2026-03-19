import AppKit
import LispKit

/// Parses Scheme `'symbol value` pairs into an OverlayTheme.
/// Used by the `set-theme!` DSL function.
struct ThemeConfigParser {

    /// Build a theme from alternating `'symbol value` property pairs.
    func parseTheme(from properties: [(String, Expr)]) -> OverlayTheme {
        let defaults = OverlayTheme.default
        return OverlayTheme(
            background: colorProp(properties, key: "bg") ?? defaults.background,
            accent: colorProp(properties, key: "accent") ?? defaults.accent,
            labelColor: colorProp(properties, key: "label") ?? defaults.labelColor,
            subtextColor: colorProp(properties, key: "subtext") ?? defaults.subtextColor,
            borderColor: colorProp(properties, key: "border") ?? defaults.borderColor,
            separatorColor: colorProp(properties, key: "separator") ?? defaults.separatorColor,
            fontName: stringProp(properties, key: "font") ?? defaults.font.familyName ?? "Menlo",
            fontSize: CGFloat(doubleProp(properties, key: "font-size") ?? Double(defaults.fontSize)),
            overlayWidth: CGFloat(doubleProp(properties, key: "overlay-width") ?? Double(defaults.overlayWidth)),
            showDelay: doubleProp(properties, key: "show-delay") ?? defaults.showDelay
        )
    }

    // MARK: - Private

    private func stringProp(_ props: [(String, Expr)], key: String) -> String? {
        for (k, v) in props where k == key {
            return try? v.asString()
        }
        return nil
    }

    private func doubleProp(_ props: [(String, Expr)], key: String) -> Double? {
        for (k, v) in props where k == key {
            if case .fixnum(let n) = v { return Double(n) }
            if case .flonum(let n) = v { return n }
        }
        return nil
    }

    private func colorProp(_ props: [(String, Expr)], key: String) -> NSColor? {
        for (k, v) in props where k == key {
            var components: [Double] = []
            var current = v
            while case .pair(let head, let tail) = current {
                if case .flonum(let n) = head { components.append(n) }
                else if case .fixnum(let n) = head { components.append(Double(n)) }
                current = tail
            }
            if components.count >= 3 {
                return NSColor(red: components[0], green: components[1], blue: components[2], alpha: 1)
            }
        }
        return nil
    }
}
