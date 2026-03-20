import AppKit

/// Polls NSPasteboard for changes and stores clipboard entries.
final class ClipboardMonitor {
    private let store: ClipboardHistoryStore
    private let pasteboard: PasteboardReading
    private let focusedAppBundleId: () -> String?
    private var lastChangeCount: Int = 0
    var excludedBundleIds: Set<String> = []

    init(store: ClipboardHistoryStore, pasteboard: PasteboardReading, focusedAppBundleId: @escaping () -> String?) {
        self.store = store
        self.pasteboard = pasteboard
        self.focusedAppBundleId = focusedAppBundleId
        self.lastChangeCount = pasteboard.changeCount
    }

    /// Check if pasteboard has changed and store the new entry if so.
    func checkForChanges() {
        let currentCount = pasteboard.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        // Check app exclusion
        if let bundleId = focusedAppBundleId(), excludedBundleIds.contains(bundleId) {
            return
        }

        guard let types = pasteboard.types, !types.isEmpty else { return }

        var typeData: [String: Data] = [:]
        for type in types {
            if let data = pasteboard.data(forType: type) {
                typeData[type.rawValue] = data
            }
        }

        guard !typeData.isEmpty else { return }

        let preview = pasteboard.string(forType: .string) ?? ""
        let app = focusedAppBundleId() ?? ""

        store.addEntry(types: typeData, appBundleId: app, preview: preview)
    }
}
