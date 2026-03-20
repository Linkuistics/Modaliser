import Foundation

/// Persists query→selection mappings for selector choosers.
/// Each selector with a `remember` name gets its own JSON file.
/// File format: {"query_lowercase": "selected_id", ...}
final class SearchMemory {

    private let dataDirectory: URL
    private var cache: [String: [String: String]] = [:]

    static let defaultDataDirectory: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".modaliser/data")
    }()

    init(dataDirectory: URL = SearchMemory.defaultDataDirectory) {
        self.dataDirectory = dataDirectory
    }

    /// Save a query→selection mapping.
    func save(name: String, query: String, selectedId: String) {
        let normalizedQuery = query.lowercased()
        guard !normalizedQuery.isEmpty else { return }

        var mappings = loadMappings(name: name)
        mappings[normalizedQuery] = selectedId
        cache[name] = mappings
        writeMappings(name: name, mappings: mappings)
    }

    /// Look up the remembered selection ID for a query.
    func rememberedId(name: String, query: String) -> String? {
        let normalizedQuery = query.lowercased()
        guard !normalizedQuery.isEmpty else { return nil }
        let mappings = loadMappings(name: name)
        return mappings[normalizedQuery]
    }

    /// Reorder choices, moving the remembered choice to the front.
    /// - Parameters:
    ///   - choices: The original list of choices
    ///   - query: The current search query
    ///   - name: The selector's remember name (nil = no reordering)
    ///   - idExtractor: Closure to extract the ID string from a choice
    func reorder<T>(choices: [T], query: String, name: String?, idExtractor: (T) -> String) -> [T] {
        guard let name, !query.isEmpty else { return choices }
        guard let rememberedId = rememberedId(name: name, query: query) else { return choices }

        var top: [T] = []
        var rest: [T] = []
        for choice in choices {
            if idExtractor(choice) == rememberedId {
                top.append(choice)
            } else {
                rest.append(choice)
            }
        }
        return top + rest
    }

    // MARK: - Private

    private func filePath(for name: String) -> URL {
        dataDirectory.appendingPathComponent("chooser_\(name).json")
    }

    private func loadMappings(name: String) -> [String: String] {
        if let cached = cache[name] { return cached }

        let path = filePath(for: name)
        guard let data = try? Data(contentsOf: path),
              let mappings = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        cache[name] = mappings
        return mappings
    }

    private func writeMappings(name: String, mappings: [String: String]) {
        let path = filePath(for: name)
        do {
            try FileManager.default.createDirectory(
                at: dataDirectory,
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(mappings)
            try data.write(to: path)
        } catch {
            NSLog("SearchMemory: failed to write %@: %@", path.path, "\(error)")
        }
    }
}
