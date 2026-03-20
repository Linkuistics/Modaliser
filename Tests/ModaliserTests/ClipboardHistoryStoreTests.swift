import Testing
import Foundation
@testable import Modaliser

@Suite("ClipboardHistoryStore")
struct ClipboardHistoryStoreTests {

    // MARK: - Adding entries

    @Test func addEntryCreatesDirectoryAndIndex() throws {
        let dir = makeTempDir()
        let store = ClipboardHistoryStore(baseDirectory: dir)

        store.addEntry(
            types: ["public.utf8-plain-text": Data("hello".utf8)],
            appBundleId: "com.apple.Safari",
            preview: "hello"
        )

        let entries = store.entries
        #expect(entries.count == 1)
        #expect(entries[0].appBundleId == "com.apple.Safari")
        #expect(entries[0].preview == "hello")
        #expect(entries[0].types.contains("public.utf8-plain-text"))

        // Verify the UTI data file exists
        let dataPath = dir + "/entries/\(entries[0].id)/public.utf8-plain-text"
        #expect(FileManager.default.fileExists(atPath: dataPath))
    }

    @Test func addEntryWithMultipleUTITypes() throws {
        let dir = makeTempDir()
        let store = ClipboardHistoryStore(baseDirectory: dir)

        store.addEntry(
            types: [
                "public.utf8-plain-text": Data("hello".utf8),
                "public.html": Data("<b>hello</b>".utf8),
            ],
            appBundleId: "com.google.Chrome",
            preview: "hello"
        )

        let entry = store.entries[0]
        #expect(entry.types.count == 2)
        #expect(entry.types.contains("public.utf8-plain-text"))
        #expect(entry.types.contains("public.html"))
    }

    // MARK: - Ordering

    @Test func entriesAreReturnedMostRecentFirst() throws {
        let dir = makeTempDir()
        let store = ClipboardHistoryStore(baseDirectory: dir)

        store.addEntry(
            types: ["public.utf8-plain-text": Data("first".utf8)],
            appBundleId: "com.apple.Terminal",
            preview: "first"
        )
        store.addEntry(
            types: ["public.utf8-plain-text": Data("second".utf8)],
            appBundleId: "com.apple.Terminal",
            preview: "second"
        )

        #expect(store.entries[0].preview == "second")
        #expect(store.entries[1].preview == "first")
    }

    // MARK: - Limit enforcement

    @Test func enforcesHistoryLimit() throws {
        let dir = makeTempDir()
        let store = ClipboardHistoryStore(baseDirectory: dir, limit: 3)

        for i in 0..<5 {
            store.addEntry(
                types: ["public.utf8-plain-text": Data("item \(i)".utf8)],
                appBundleId: "test",
                preview: "item \(i)"
            )
        }

        #expect(store.entries.count == 3)
        // Most recent should be kept
        #expect(store.entries[0].preview == "item 4")
        #expect(store.entries[2].preview == "item 2")
    }

    @Test func limitEnforcementDeletesOldEntryDirectories() throws {
        let dir = makeTempDir()
        let store = ClipboardHistoryStore(baseDirectory: dir, limit: 2)

        store.addEntry(
            types: ["public.utf8-plain-text": Data("old".utf8)],
            appBundleId: "test",
            preview: "old"
        )
        let oldId = store.entries[0].id

        store.addEntry(
            types: ["public.utf8-plain-text": Data("mid".utf8)],
            appBundleId: "test",
            preview: "mid"
        )
        store.addEntry(
            types: ["public.utf8-plain-text": Data("new".utf8)],
            appBundleId: "test",
            preview: "new"
        )

        // Old entry directory should be deleted
        let oldPath = dir + "/entries/\(oldId)"
        #expect(!FileManager.default.fileExists(atPath: oldPath))
    }

    // MARK: - Deduplication

    @Test func duplicateEntryIsNotAdded() throws {
        let dir = makeTempDir()
        let store = ClipboardHistoryStore(baseDirectory: dir)

        let data = Data("same content".utf8)
        store.addEntry(types: ["public.utf8-plain-text": data], appBundleId: "test", preview: "same")
        store.addEntry(types: ["public.utf8-plain-text": data], appBundleId: "test", preview: "same")

        #expect(store.entries.count == 1)
    }

    // MARK: - Index persistence

    @Test func indexSurvivesReload() throws {
        let dir = makeTempDir()

        let store1 = ClipboardHistoryStore(baseDirectory: dir)
        store1.addEntry(
            types: ["public.utf8-plain-text": Data("persisted".utf8)],
            appBundleId: "com.test.app",
            preview: "persisted"
        )

        // Create a new store pointing at the same directory
        let store2 = ClipboardHistoryStore(baseDirectory: dir)
        #expect(store2.entries.count == 1)
        #expect(store2.entries[0].preview == "persisted")
    }

    // MARK: - Data retrieval

    @Test func loadEntryDataReturnsAllUTITypes() throws {
        let dir = makeTempDir()
        let store = ClipboardHistoryStore(baseDirectory: dir)

        store.addEntry(
            types: [
                "public.utf8-plain-text": Data("text".utf8),
                "public.png": Data([0x89, 0x50, 0x4E, 0x47]),
            ],
            appBundleId: "test",
            preview: "text"
        )

        let data = store.loadEntryData(id: store.entries[0].id)
        #expect(data.count == 2)
        #expect(data["public.utf8-plain-text"] == Data("text".utf8))
        #expect(data["public.png"] == Data([0x89, 0x50, 0x4E, 0x47]))
    }

    // MARK: - Clear

    @Test func clearRemovesAllEntries() throws {
        let dir = makeTempDir()
        let store = ClipboardHistoryStore(baseDirectory: dir)

        store.addEntry(types: ["public.utf8-plain-text": Data("a".utf8)], appBundleId: "test", preview: "a")
        store.addEntry(types: ["public.utf8-plain-text": Data("b".utf8)], appBundleId: "test", preview: "b")

        store.clear()

        #expect(store.entries.isEmpty)
    }

    // MARK: - Helpers

    private func makeTempDir() -> String {
        let dir = NSTemporaryDirectory() + "clipboard-test-\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }
}
