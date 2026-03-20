import Testing
import Foundation
@testable import Modaliser

@Suite("SearchMemory", .serialized)
struct SearchMemoryTests {

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("modaliser-test-\(UUID().uuidString)")
    }

    // MARK: - Persistence

    @Test func saveAndLoadMemory() throws {
        let dir = temporaryDirectory()
        let memory = SearchMemory(dataDirectory: dir)

        memory.save(name: "apps", query: "saf", selectedId: "com.apple.Safari")

        let loaded = SearchMemory(dataDirectory: dir)
        let id = loaded.rememberedId(name: "apps", query: "saf")
        #expect(id == "com.apple.Safari")

        try? FileManager.default.removeItem(at: dir)
    }

    @Test func queriesAreCaseInsensitive() throws {
        let dir = temporaryDirectory()
        let memory = SearchMemory(dataDirectory: dir)

        memory.save(name: "apps", query: "Safari", selectedId: "com.apple.Safari")

        #expect(memory.rememberedId(name: "apps", query: "safari") == "com.apple.Safari")
        #expect(memory.rememberedId(name: "apps", query: "SAFARI") == "com.apple.Safari")

        try? FileManager.default.removeItem(at: dir)
    }

    @Test func emptyQueryIsNotSaved() throws {
        let dir = temporaryDirectory()
        let memory = SearchMemory(dataDirectory: dir)

        memory.save(name: "apps", query: "", selectedId: "com.apple.Safari")

        #expect(memory.rememberedId(name: "apps", query: "") == nil)

        try? FileManager.default.removeItem(at: dir)
    }

    @Test func differentNamesAreSeparate() throws {
        let dir = temporaryDirectory()
        let memory = SearchMemory(dataDirectory: dir)

        memory.save(name: "apps", query: "saf", selectedId: "com.apple.Safari")
        memory.save(name: "files", query: "saf", selectedId: "/path/to/safety.txt")

        #expect(memory.rememberedId(name: "apps", query: "saf") == "com.apple.Safari")
        #expect(memory.rememberedId(name: "files", query: "saf") == "/path/to/safety.txt")

        try? FileManager.default.removeItem(at: dir)
    }

    @Test func overwritesPreviousSelection() throws {
        let dir = temporaryDirectory()
        let memory = SearchMemory(dataDirectory: dir)

        memory.save(name: "apps", query: "saf", selectedId: "com.apple.Safari")
        memory.save(name: "apps", query: "saf", selectedId: "org.other.SafeApp")

        #expect(memory.rememberedId(name: "apps", query: "saf") == "org.other.SafeApp")

        try? FileManager.default.removeItem(at: dir)
    }

    @Test func nonExistentNameReturnsNil() {
        let dir = temporaryDirectory()
        let memory = SearchMemory(dataDirectory: dir)

        #expect(memory.rememberedId(name: "nonexistent", query: "test") == nil)

        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Reordering

    @Test func reorderMovesRememberedChoiceToFront() throws {
        let dir = temporaryDirectory()
        let memory = SearchMemory(dataDirectory: dir)

        memory.save(name: "apps", query: "s", selectedId: "b")

        let choices = ["a", "b", "c"]
        let reordered = memory.reorder(choices: choices, query: "s", name: "apps") { $0 }

        #expect(reordered == ["b", "a", "c"])

        try? FileManager.default.removeItem(at: dir)
    }

    @Test func reorderWithNoMemoryPreservesOrder() {
        let dir = temporaryDirectory()
        let memory = SearchMemory(dataDirectory: dir)

        let choices = ["a", "b", "c"]
        let reordered = memory.reorder(choices: choices, query: "x", name: "apps") { $0 }

        #expect(reordered == ["a", "b", "c"])

        try? FileManager.default.removeItem(at: dir)
    }

    @Test func reorderWithEmptyQueryPreservesOrder() throws {
        let dir = temporaryDirectory()
        let memory = SearchMemory(dataDirectory: dir)

        memory.save(name: "apps", query: "s", selectedId: "b")

        let choices = ["a", "b", "c"]
        let reordered = memory.reorder(choices: choices, query: "", name: "apps") { $0 }

        #expect(reordered == ["a", "b", "c"])

        try? FileManager.default.removeItem(at: dir)
    }

    @Test func reorderWithNilNamePreservesOrder() {
        let dir = temporaryDirectory()
        let memory = SearchMemory(dataDirectory: dir)

        let choices = ["a", "b", "c"]
        let reordered = memory.reorder(choices: choices, query: "s", name: nil) { $0 }

        #expect(reordered == ["a", "b", "c"])

        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - File location

    @Test func memoryFileNamedBySelector() throws {
        let dir = temporaryDirectory()
        let memory = SearchMemory(dataDirectory: dir)

        memory.save(name: "apps", query: "test", selectedId: "id")

        let filePath = dir.appendingPathComponent("chooser_apps.json")
        #expect(FileManager.default.fileExists(atPath: filePath.path))

        try? FileManager.default.removeItem(at: dir)
    }
}
