import Foundation

/// Runs chooser search pipeline (fuzzy match + HTML render) on a background thread.
/// Results are pushed to the WebView on the main thread via a callback.
final class ChooserSearchEngine {

    struct Item {
        let searchText: String
        let displayText: String
        let path: String
        let kind: String  // "file", "directory", or ""
    }

    private(set) var items: [Item] = []
    private var searchGeneration = 0
    private let queue = DispatchQueue(label: "chooser-search", qos: .userInitiated)

    /// Cache items for subsequent searches.
    func setItems(_ items: [Item]) {
        self.items = items
    }

    struct SearchResult {
        let index: Int
        let score: Int
        let indices: [Int]
    }

    /// Run async fuzzy matching. Calls `completion` on main thread with results.
    func search(
        query: String,
        selectedIndex: Int,
        maxResults: Int = 100,
        completion: @escaping (_ results: [SearchResult]) -> Void
    ) {
        searchGeneration += 1
        let generation = searchGeneration
        let items = self.items
        let queryLen = query.count

        queue.async {
            guard generation == self.searchGeneration else { return }

            let results: [SearchResult]

            if query.isEmpty {
                let limit = min(items.count, maxResults)
                results = (0..<limit).map { SearchResult(index: $0, score: 1, indices: []) }
            } else {
                var matches: [SearchResult] = []
                let lock = NSLock()

                DispatchQueue.concurrentPerform(iterations: items.count) { i in
                    guard generation == self.searchGeneration else { return }
                    if let result = FuzzyMatcher.match(query: query, target: items[i].searchText) {
                        let proportion = (queryLen * 100) / max(items[i].searchText.count, 1)
                        let entry = SearchResult(
                            index: i,
                            score: result.score + proportion,
                            indices: result.matchedIndices.sorted()
                        )
                        lock.lock()
                        matches.append(entry)
                        lock.unlock()
                    }
                }

                guard generation == self.searchGeneration else { return }
                matches.sort { $0.score > $1.score }
                results = Array(matches.prefix(maxResults))
            }

            guard generation == self.searchGeneration else { return }

            DispatchQueue.main.async {
                guard generation == self.searchGeneration else { return }
                completion(results)
            }
        }
    }

    /// Cancel any in-progress search.
    func cancel() {
        searchGeneration += 1
    }

}
