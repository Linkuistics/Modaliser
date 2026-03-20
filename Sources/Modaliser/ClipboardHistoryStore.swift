import Foundation

/// Metadata for a single clipboard history entry.
struct ClipboardHistoryEntry {
    let id: String
    let timestamp: TimeInterval
    let appBundleId: String
    let types: [String]
    let preview: String
}

/// Directory-based clipboard history storage.
/// Each entry gets a numbered directory containing one file per UTI type.
/// Metadata is tracked in memory and persisted to index.scm.
final class ClipboardHistoryStore {
    private let baseDirectory: String
    private let fileManager = FileManager.default
    private(set) var entries: [ClipboardHistoryEntry] = []
    private var nextId: Int = 1
    var limit: Int

    init(baseDirectory: String, limit: Int = 500) {
        self.baseDirectory = baseDirectory
        self.limit = limit
        ensureDirectoriesExist()
        loadIndex()
    }

    /// Add a new clipboard entry with data for each UTI type.
    func addEntry(types: [String: Data], appBundleId: String, preview: String) {
        guard !types.isEmpty else { return }

        // Dedup: skip if identical to most recent entry
        if let latest = entries.first, isDuplicate(latest: latest, newTypes: types) {
            return
        }

        let id = String(format: "%04d", nextId)
        nextId += 1

        let entryDir = baseDirectory + "/entries/" + id
        try? fileManager.createDirectory(atPath: entryDir, withIntermediateDirectories: true)

        for (uti, data) in types {
            let filePath = entryDir + "/" + uti
            try? data.write(to: URL(fileURLWithPath: filePath))
        }

        let entry = ClipboardHistoryEntry(
            id: id,
            timestamp: Date().timeIntervalSince1970,
            appBundleId: appBundleId,
            types: Array(types.keys),
            preview: String(preview.prefix(200))
        )

        entries.insert(entry, at: 0)
        enforceLimit()
        saveIndex()
    }

    /// Load all UTI data for a given entry ID.
    func loadEntryData(id: String) -> [String: Data] {
        let entryDir = baseDirectory + "/entries/" + id
        guard let files = try? fileManager.contentsOfDirectory(atPath: entryDir) else {
            return [:]
        }
        var result: [String: Data] = [:]
        for file in files {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: entryDir + "/" + file)) {
                result[file] = data
            }
        }
        return result
    }

    /// Remove all entries and their data.
    func clear() {
        for entry in entries {
            let entryDir = baseDirectory + "/entries/" + entry.id
            try? fileManager.removeItem(atPath: entryDir)
        }
        entries.removeAll()
        nextId = 1
        saveIndex()
    }

    // MARK: - Private

    private func ensureDirectoriesExist() {
        try? fileManager.createDirectory(
            atPath: baseDirectory + "/entries",
            withIntermediateDirectories: true
        )
    }

    private func isDuplicate(latest: ClipboardHistoryEntry, newTypes: [String: Data]) -> Bool {
        let latestData = loadEntryData(id: latest.id)
        guard latestData.keys.sorted() == newTypes.keys.sorted() else { return false }
        for (key, value) in newTypes {
            if latestData[key] != value { return false }
        }
        return true
    }

    private func enforceLimit() {
        while entries.count > limit {
            let removed = entries.removeLast()
            let entryDir = baseDirectory + "/entries/" + removed.id
            try? fileManager.removeItem(atPath: entryDir)
        }
    }

    // MARK: - Index persistence

    private var indexPath: String { baseDirectory + "/index.scm" }

    private func saveIndex() {
        var lines: [String] = ["("]
        for entry in entries {
            let typesStr = entry.types.map { #""\#($0)""# }.joined(separator: " ")
            let escapedPreview = entry.preview
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            lines.append("""
              ((id . "\(entry.id)") (timestamp . \(Int(entry.timestamp))) \
            (app . "\(entry.appBundleId)") (types \(typesStr)) \
            (preview . "\(escapedPreview)"))
            """)
        }
        lines.append(")")
        let content = lines.joined(separator: "\n")
        try? content.write(toFile: indexPath, atomically: true, encoding: .utf8)
    }

    private func loadIndex() {
        guard let content = try? String(contentsOfFile: indexPath, encoding: .utf8) else { return }

        // Simple s-expr index parser. Format:
        // (((id . "0001") (timestamp . 123) (app . "com.x") (types "t1" "t2") (preview . "...")))
        entries = parseIndex(content)
        if let maxId = entries.compactMap({ Int($0.id) }).max() {
            nextId = maxId + 1
        }
    }

    private func parseIndex(_ content: String) -> [ClipboardHistoryEntry] {
        // Use a lightweight approach: regex-based extraction of each entry's fields.
        // The index is machine-generated, so format is predictable.
        var result: [ClipboardHistoryEntry] = []

        let entryPattern = #"\(\(id\s*\.\s*"([^"]+)"\)\s*\(timestamp\s*\.\s*(\d+)\)\s*\(app\s*\.\s*"([^"]+)"\)\s*\(types\s*((?:"[^"]*"\s*)*)\)\s*\(preview\s*\.\s*"([^"\\]*(?:\\.[^"\\]*)*)"\)\)"#
        guard let regex = try? NSRegularExpression(pattern: entryPattern) else { return [] }

        let nsContent = content as NSString
        let matches = regex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))

        for match in matches {
            let id = nsContent.substring(with: match.range(at: 1))
            let timestamp = TimeInterval(nsContent.substring(with: match.range(at: 2))) ?? 0
            let app = nsContent.substring(with: match.range(at: 3))
            let typesRaw = nsContent.substring(with: match.range(at: 4))
            let preview = nsContent.substring(with: match.range(at: 5))
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")

            // Parse types: "t1" "t2" -> ["t1", "t2"]
            let typePattern = #""([^"]+)""#
            var types: [String] = []
            if let typeRegex = try? NSRegularExpression(pattern: typePattern) {
                let typeMatches = typeRegex.matches(in: typesRaw, range: NSRange(location: 0, length: (typesRaw as NSString).length))
                types = typeMatches.map { (typesRaw as NSString).substring(with: $0.range(at: 1)) }
            }

            result.append(ClipboardHistoryEntry(
                id: id,
                timestamp: timestamp,
                appBundleId: app,
                types: types,
                preview: preview
            ))
        }

        return result
    }
}
