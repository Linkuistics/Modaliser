import LispKit

/// Shared helpers for reading values from Scheme association lists (alists).
/// Alists are the standard data interchange format between Swift and Scheme in Modaliser.
/// Format: ((key1 . value1) (key2 . value2) ...)
enum SchemeAlistLookup {

    /// Look up a string value by symbol key in a Scheme alist.
    /// Returns nil if the key is not found or the value is not a string.
    static func lookupString(_ alist: Expr, key: String) -> String? {
        var current = alist
        while case .pair(let entry, let tail) = current {
            if case .pair(.symbol(let s), let value) = entry, s.identifier == key {
                return try? value.asString()
            }
            current = tail
        }
        return nil
    }

    /// Look up a fixnum value by symbol key in a Scheme alist.
    /// Returns nil if the key is not found or the value is not a fixnum.
    static func lookupFixnum(_ alist: Expr, key: String) -> Int64? {
        var current = alist
        while case .pair(let entry, let tail) = current {
            if case .pair(.symbol(let s), .fixnum(let n)) = entry, s.identifier == key {
                return n
            }
            current = tail
        }
        return nil
    }

    /// Look up a raw Expr value by symbol key in a Scheme alist.
    /// Returns nil if the key is not found.
    static func lookupExpr(_ alist: Expr, key: String) -> Expr? {
        var current = alist
        while case .pair(let entry, let tail) = current {
            if case .pair(.symbol(let s), let value) = entry, s.identifier == key {
                return value
            }
            current = tail
        }
        return nil
    }

    /// Build a Scheme alist from key-value pairs, interning symbols via the given table.
    static func makeAlist(_ entries: [(String, Expr)], symbols: SymbolTable) -> Expr {
        var result: Expr = .null
        for (key, value) in entries.reversed() {
            let pair = Expr.pair(.symbol(symbols.intern(key)), value)
            result = .pair(pair, result)
        }
        return result
    }
}
