import Foundation
import LispKit

/// Native LispKit library providing DP-based fuzzy string matching.
/// Scheme name: (modaliser fuzzy)
///
/// Provides:
///   (fuzzy-match query target) → (score (matched-indices...)) or #f
///   (fuzzy-filter query texts) → ((index score (matched-indices...)) ...) sorted by score desc
///   (chooser-cache-items! items) → void — cache items for async search
///   (chooser-async-search! query webview-id) → void — run search on background thread
final class FuzzyMatchLibrary: NativeLibrary {

    let searchEngine = ChooserSearchEngine()

    public required init(in context: Context) throws {
        try super.init(in: context)
    }

    public override class var name: [String] {
        ["modaliser", "fuzzy"]
    }

    public override func dependencies() {
        self.`import`(from: ["lispkit", "base"])
    }

    public override func declarations() {
        self.define(Procedure("fuzzy-match", fuzzyMatchFunction))
        self.define(Procedure("fuzzy-filter", fuzzyFilterFunction))
        self.define(Procedure("chooser-cache-items!", chooserCacheItemsFunction))
        self.define(Procedure("chooser-async-search!", chooserAsyncSearchFunction))
    }

    // MARK: - Primitives

    /// (fuzzy-match query target) → (score (matched-indices...)) or #f
    private func fuzzyMatchFunction(_ queryExpr: Expr, _ targetExpr: Expr) throws -> Expr {
        let query = try queryExpr.asString()
        let target = try targetExpr.asString()

        guard let result = FuzzyMatcher.match(query: query, target: target) else {
            return .false
        }

        return matchResultToExpr(result)
    }

    /// (fuzzy-filter query texts) → ((index score (matched-indices...)) ...) sorted by score desc
    /// texts: a list of strings to match against
    /// For large lists (1000+), matching runs concurrently across available cores.
    private func fuzzyFilterFunction(_ queryExpr: Expr, _ textsExpr: Expr) throws -> Expr {
        let query = try queryExpr.asString()

        // Collect strings from the list
        var texts: [String] = []
        var current = textsExpr
        while case .pair(let head, let tail) = current {
            texts.append(try head.asString())
            current = tail
        }

        let maxResults = 100

        // Empty query returns first maxResults items with score 1
        if query.isEmpty {
            var result: Expr = .null
            let limit = min(texts.count, maxResults)
            for i in stride(from: limit - 1, through: 0, by: -1) {
                let entry: Expr = .pair(
                    .fixnum(Int64(i)),
                    .pair(.fixnum(1), .pair(.null, .null))
                )
                result = .pair(entry, result)
            }
            return result
        }

        // Match each text — use concurrent processing for large lists
        // Match proportion bonus: queries that cover more of the target score higher.
        // "development" matching "Development" (100%) >> matching a 150-char path (7%).
        let queryLen = query.count
        func adjustedScore(_ rawScore: Int, targetLength: Int) -> Int {
            let proportion = (queryLen * 100) / max(targetLength, 1)
            return rawScore + proportion
        }

        typealias MatchResult = (index: Int, score: Int, indices: [Int])
        let matches: [MatchResult]

        if texts.count > 500 {
            let lock = NSLock()
            var concurrent: [MatchResult] = []
            DispatchQueue.concurrentPerform(iterations: texts.count) { i in
                if let result = FuzzyMatcher.match(query: query, target: texts[i]) {
                    let score = adjustedScore(result.score, targetLength: texts[i].count)
                    let entry = (index: i, score: score, indices: result.matchedIndices.sorted())
                    lock.lock()
                    concurrent.append(entry)
                    lock.unlock()
                }
            }
            matches = concurrent
        } else {
            var sequential: [MatchResult] = []
            for (i, text) in texts.enumerated() {
                if let result = FuzzyMatcher.match(query: query, target: text) {
                    let score = adjustedScore(result.score, targetLength: text.count)
                    sequential.append((index: i, score: score, indices: result.matchedIndices.sorted()))
                }
            }
            matches = sequential
        }

        // Sort by score descending, take top results
        let sorted = matches.sorted { $0.score > $1.score }.prefix(maxResults)

        // Convert to Scheme list
        var result: Expr = .null
        for match in sorted.reversed() {
            var indexList: Expr = .null
            for idx in match.indices.reversed() {
                indexList = .pair(.fixnum(Int64(idx)), indexList)
            }
            let entry: Expr = .pair(
                .fixnum(Int64(match.index)),
                .pair(.fixnum(Int64(match.score)), .pair(indexList, .null))
            )
            result = .pair(entry, result)
        }
        return result
    }

    // MARK: - Async chooser search

    /// (chooser-cache-items! items) → void
    /// Cache source items for background search. Items are alists with 'text, 'path, 'kind.
    private func chooserCacheItemsFunction(_ itemsExpr: Expr) throws -> Expr {
        var items: [ChooserSearchEngine.Item] = []
        var current = itemsExpr
        while case .pair(let head, let tail) = current {
            let text = SchemeAlistLookup.lookupString(head, key: "text") ?? ""
            let path = SchemeAlistLookup.lookupString(head, key: "path") ?? ""
            let kind = SchemeAlistLookup.lookupString(head, key: "kind") ?? ""
            // Directories match against name, files against full path
            let searchText = kind == "directory" ? text : (path.isEmpty ? text : path)
            items.append(ChooserSearchEngine.Item(
                searchText: searchText, displayText: text, path: path, kind: kind
            ))
            current = tail
        }
        searchEngine.setItems(items)
        return .void
    }

    /// (chooser-async-search! query webview-id) → void
    /// Run fuzzy matching on background thread. Pushes results as JSON to JS
    /// updateResults() function via webview-eval. No Scheme rendering needed.
    private func chooserAsyncSearchFunction(_ queryExpr: Expr, _ webviewIdExpr: Expr) throws -> Expr {
        let query = try queryExpr.asString()
        let webviewId = try webviewIdExpr.asString()
        guard let webViewLib = try? context.libraries.lookup(WebViewLibrary.self) else {
            return .void
        }
        let manager = webViewLib.webViewManager
        let items = searchEngine.items

        searchEngine.search(query: query, selectedIndex: 0) { results in
            // Build JSON array on main thread (fast — just string formatting)
            var json = "["
            for (i, r) in results.enumerated() {
                if i > 0 { json += "," }
                let item = items[r.index]
                let displayText = Self.escapeJSON(item.displayText)
                let searchText = Self.escapeJSON(item.searchText)
                let path = Self.escapeJSON(item.path)
                let indicesStr = r.indices.map { String($0) }.joined(separator: ",")
                json += "{\"d\":\"\(displayText)\",\"s\":\"\(searchText)\","
                json += "\"p\":\"\(path)\",\"k\":\"\(item.kind)\","
                json += "\"i\":[\(indicesStr)],\"x\":\(r.index)}"
            }
            json += "]"

            let js = "if(window.updateResults)updateResults(\(json),\(results.count));"
            manager.evaluateJavaScript(id: webviewId, script: js)
        }
        return .void
    }

    private static func escapeJSON(_ str: String) -> String {
        var result = ""
        result.reserveCapacity(str.count)
        for c in str {
            switch c {
            case "\\": result += "\\\\"
            case "\"": result += "\\\""
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default: result.append(c)
            }
        }
        return result
    }

    // MARK: - Helpers

    private func matchResultToExpr(_ result: FuzzyMatcher.MatchResult) -> Expr {
        var indexList: Expr = .null
        for idx in result.matchedIndices.sorted().reversed() {
            indexList = .pair(.fixnum(Int64(idx)), indexList)
        }
        return .pair(.fixnum(Int64(result.score)), .pair(indexList, .null))
    }

    private static func escapeJS(_ str: String) -> String {
        var result = ""
        result.reserveCapacity(str.count)
        for c in str {
            switch c {
            case "\\": result += "\\\\"
            case "'": result += "\\'"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            default: result.append(c)
            }
        }
        return result
    }
}
