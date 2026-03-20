import Testing
import AppKit
@testable import Modaliser

@Suite("ClipboardMonitor")
struct ClipboardMonitorTests {

    // MARK: - Change detection

    @Test func detectsChangeCountIncrease() {
        let pasteboard = MockPasteboard()
        let store = ClipboardHistoryStore(baseDirectory: makeTempDir())
        let monitor = ClipboardMonitor(
            store: store,
            pasteboard: pasteboard,
            focusedAppBundleId: { "com.test.app" }
        )

        pasteboard.mockChangeCount = 1
        pasteboard.mockTypes = [.string]
        pasteboard.mockStringValue = "copied text"

        monitor.checkForChanges()

        #expect(store.entries.count == 1)
        #expect(store.entries[0].preview == "copied text")
    }

    @Test func ignoresUnchangedPasteboard() {
        let pasteboard = MockPasteboard()
        let store = ClipboardHistoryStore(baseDirectory: makeTempDir())
        let monitor = ClipboardMonitor(
            store: store,
            pasteboard: pasteboard,
            focusedAppBundleId: { "com.test.app" }
        )

        pasteboard.mockChangeCount = 1
        pasteboard.mockTypes = [.string]
        pasteboard.mockStringValue = "text"
        monitor.checkForChanges()

        // Same change count — should not add
        monitor.checkForChanges()

        #expect(store.entries.count == 1)
    }

    // MARK: - App exclusion

    @Test func excludesEntriesFromExcludedApps() {
        let pasteboard = MockPasteboard()
        let store = ClipboardHistoryStore(baseDirectory: makeTempDir())
        let monitor = ClipboardMonitor(
            store: store,
            pasteboard: pasteboard,
            focusedAppBundleId: { "com.1password.1password" }
        )
        monitor.excludedBundleIds = Set(["com.1password.1password"])

        pasteboard.mockChangeCount = 1
        pasteboard.mockTypes = [.string]
        pasteboard.mockStringValue = "secret password"

        monitor.checkForChanges()

        #expect(store.entries.isEmpty, "Should not store entries from excluded apps")
    }

    @Test func allowsEntriesFromNonExcludedApps() {
        let pasteboard = MockPasteboard()
        let store = ClipboardHistoryStore(baseDirectory: makeTempDir())
        let monitor = ClipboardMonitor(
            store: store,
            pasteboard: pasteboard,
            focusedAppBundleId: { "com.apple.Safari" }
        )
        monitor.excludedBundleIds = Set(["com.1password.1password"])

        pasteboard.mockChangeCount = 1
        pasteboard.mockTypes = [.string]
        pasteboard.mockStringValue = "safe text"

        monitor.checkForChanges()

        #expect(store.entries.count == 1)
    }

    // MARK: - Helpers

    private func makeTempDir() -> String {
        let dir = NSTemporaryDirectory() + "clipboard-mon-test-\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }
}

// MARK: - Mock Pasteboard

final class MockPasteboard: PasteboardReading {
    var mockChangeCount = 0
    var mockTypes: [NSPasteboard.PasteboardType]? = nil
    var mockStringValue: String? = nil
    var mockDataByType: [NSPasteboard.PasteboardType: Data] = [:]

    var changeCount: Int { mockChangeCount }
    var types: [NSPasteboard.PasteboardType]? { mockTypes }

    func data(forType type: NSPasteboard.PasteboardType) -> Data? {
        if let explicit = mockDataByType[type] { return explicit }
        if type == .string, let str = mockStringValue {
            return Data(str.utf8)
        }
        return nil
    }

    func string(forType type: NSPasteboard.PasteboardType) -> String? {
        if type == .string { return mockStringValue }
        return nil
    }
}
