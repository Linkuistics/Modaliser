import AppKit
import LispKit

/// Native LispKit library providing clipboard history access.
/// Scheme name: (modaliser clipboard-history)
///
/// Provides: get-clipboard-history, clear-clipboard-history!, restore-clipboard-entry!,
///           set-clipboard-exclude!, set-clipboard-history-limit!
final class ClipboardHistoryLibrary: NativeLibrary {
    var store: ClipboardHistoryStore?
    var monitor: ClipboardMonitor?

    public required init(in context: Context) throws {
        try super.init(in: context)
    }

    public override class var name: [String] {
        ["modaliser", "clipboard-history"]
    }

    public override func dependencies() {
        self.`import`(from: ["lispkit", "base"])
    }

    public override func declarations() {
        self.define(Procedure("get-clipboard-history", getHistoryFunction))
        self.define(Procedure("clear-clipboard-history!", clearHistoryFunction))
        self.define(Procedure("restore-clipboard-entry!", restoreEntryFunction))
        self.define(Procedure("set-clipboard-exclude!", setExcludeFunction))
        self.define(Procedure("set-clipboard-history-limit!", setLimitFunction))
    }

    // MARK: - Functions

    /// (get-clipboard-history ['limit n]) -> list of alists
    private func getHistoryFunction(_ rest: Arguments) throws -> Expr {
        guard let store else { return .null }

        var maxEntries = store.entries.count
        var i = rest.startIndex
        while i < rest.endIndex {
            if case .symbol(let sym) = rest[i], sym.description == "limit" {
                let nextIndex = rest.index(after: i)
                if nextIndex < rest.endIndex, case .fixnum(let n) = rest[nextIndex] {
                    maxEntries = min(Int(n), store.entries.count)
                }
            }
            i = rest.index(after: i)
        }

        let symbols = context.symbols
        var result: Expr = .null
        for entry in store.entries.prefix(maxEntries).reversed() {
            let typesExpr = entry.types.reduce(Expr.null) { list, type in
                .pair(.makeString(type), list)
            }
            let alist = SchemeAlistLookup.makeAlist([
                ("id", .makeString(entry.id)),
                ("text", .makeString(entry.preview)),
                ("app", .makeString(entry.appBundleId)),
                ("types", typesExpr),
            ], symbols: symbols)
            result = .pair(alist, result)
        }
        return result
    }

    /// (clear-clipboard-history!) -> void
    private func clearHistoryFunction() -> Expr {
        store?.clear()
        return .void
    }

    /// (restore-clipboard-entry! id) -> void
    /// Loads all UTI data from the entry directory and writes to NSPasteboard.
    private func restoreEntryFunction(_ id: Expr) throws -> Expr {
        let entryId = try id.asString()
        guard let store else { return .void }

        let data = store.loadEntryData(id: entryId)
        guard !data.isEmpty else { return .void }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        for (uti, bytes) in data {
            pasteboard.setData(bytes, forType: NSPasteboard.PasteboardType(uti))
        }

        return .void
    }

    /// (set-clipboard-exclude! '("com.1password" ...)) -> void
    private func setExcludeFunction(_ list: Expr) throws -> Expr {
        var bundleIds: Set<String> = []
        var current = list
        while case .pair(let head, let tail) = current {
            if case .string(let str) = head {
                bundleIds.insert(str as String)
            }
            current = tail
        }
        monitor?.excludedBundleIds = bundleIds
        return .void
    }

    /// (set-clipboard-history-limit! n) -> void
    private func setLimitFunction(_ limit: Expr) throws -> Expr {
        let n = try limit.asInt(above: 1)
        store?.limit = n
        return .void
    }
}
