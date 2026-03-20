import Testing
import Foundation
import AppKit
import LispKit
@testable import Modaliser

@Suite("ClipboardHistoryLibrary")
struct ClipboardHistoryLibraryTests {

    @Test func getClipboardHistoryReturnsEntries() throws {
        let (engine, store, _) = try makeSetup()

        store.addEntry(
            types: ["public.utf8-plain-text": Data("hello".utf8)],
            appBundleId: "com.test",
            preview: "hello"
        )
        store.addEntry(
            types: ["public.utf8-plain-text": Data("world".utf8)],
            appBundleId: "com.test",
            preview: "world"
        )

        let result = try engine.evaluate("(get-clipboard-history)")
        let entries = schemeListToArray(result)
        #expect(entries.count == 2)
        #expect(SchemeAlistLookup.lookupString(entries[0], key: "text") == "world")
        #expect(SchemeAlistLookup.lookupString(entries[1], key: "text") == "hello")
    }

    @Test func getClipboardHistoryWithLimit() throws {
        let (engine, store, _) = try makeSetup()

        for i in 0..<5 {
            store.addEntry(
                types: ["public.utf8-plain-text": Data("item \(i)".utf8)],
                appBundleId: "com.test",
                preview: "item \(i)"
            )
        }

        let result = try engine.evaluate("(get-clipboard-history 'limit 2)")
        let entries = schemeListToArray(result)
        #expect(entries.count == 2)
    }

    @Test func clearClipboardHistory() throws {
        let (engine, store, _) = try makeSetup()

        store.addEntry(
            types: ["public.utf8-plain-text": Data("data".utf8)],
            appBundleId: "com.test",
            preview: "data"
        )
        #expect(store.entries.count == 1)

        try engine.evaluate("(clear-clipboard-history!)")
        #expect(store.entries.isEmpty)
    }

    @Test func setClipboardExclude() throws {
        let (engine, _, monitor) = try makeSetup()

        try engine.evaluate(#"(set-clipboard-exclude! '("com.1password.1password" "com.secret.app"))"#)
        #expect(monitor.excludedBundleIds.contains("com.1password.1password"))
        #expect(monitor.excludedBundleIds.contains("com.secret.app"))
    }

    @Test func setClipboardHistoryLimit() throws {
        let (engine, store, _) = try makeSetup()

        try engine.evaluate("(set-clipboard-history-limit! 100)")
        #expect(store.limit == 100)
    }

    // MARK: - Helpers

    private func makeSetup() throws -> (SchemeEngine, ClipboardHistoryStore, ClipboardMonitor) {
        let dir = NSTemporaryDirectory() + "clipboard-lib-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let store = ClipboardHistoryStore(baseDirectory: dir)
        let monitor = ClipboardMonitor(
            store: store,
            pasteboard: NSPasteboard.general,
            focusedAppBundleId: { nil }
        )

        let engine = try SchemeEngine()
        try engine.context.libraries.register(libraryType: ClipboardHistoryLibrary.self)
        if let lib = try engine.context.libraries.lookup(ClipboardHistoryLibrary.self) {
            lib.store = store
            lib.monitor = monitor
        }
        try engine.context.environment.import(ClipboardHistoryLibrary.name)
        return (engine, store, monitor)
    }

    private func schemeListToArray(_ expr: Expr) -> [Expr] {
        var result: [Expr] = []
        var current = expr
        while case .pair(let head, let tail) = current {
            result.append(head)
            current = tail
        }
        return result
    }
}
