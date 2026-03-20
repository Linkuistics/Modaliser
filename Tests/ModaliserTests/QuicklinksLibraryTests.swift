import Testing
import Foundation
import LispKit
@testable import Modaliser

@Suite("QuicklinksLibrary")
struct QuicklinksLibraryTests {

    // MARK: - File parsing

    @Test func getQuicklinksReturnsEntriesFromFile() throws {
        let dir = try makeTempConfigDir()
        try """
        (((name . "GitHub") (url . "https://github.com") (icon . "globe") (tags "dev"))
         ((name . "Mail") (url . "https://mail.google.com") (icon . "envelope") (tags "comms")))
        """.write(toFile: dir + "/quicklinks.scm", atomically: true, encoding: .utf8)

        let engine = try makeEngine(configDir: dir)
        let result = try engine.evaluate("(get-quicklinks)")

        let entries = schemeListToArray(result)
        #expect(entries.count == 2)

        let first = entries[0]
        #expect(SchemeAlistLookup.lookupString(first, key: "text") == "GitHub")
        #expect(SchemeAlistLookup.lookupString(first, key: "url") == "https://github.com")
        #expect(SchemeAlistLookup.lookupString(first, key: "icon") == "globe")
    }

    @Test func getQuicklinksReturnsEmptyListForEmptyFile() throws {
        let dir = try makeTempConfigDir()
        try "()".write(toFile: dir + "/quicklinks.scm", atomically: true, encoding: .utf8)

        let engine = try makeEngine(configDir: dir)
        let result = try engine.evaluate("(get-quicklinks)")

        #expect(schemeListToArray(result).isEmpty)
    }

    @Test func getQuicklinksReturnsEmptyListForMissingFile() throws {
        let dir = try makeTempConfigDir()

        let engine = try makeEngine(configDir: dir)
        let result = try engine.evaluate("(get-quicklinks)")

        #expect(schemeListToArray(result).isEmpty)
    }

    // MARK: - Name to text transformation

    @Test func nameFieldIsRenamedToText() throws {
        let dir = try makeTempConfigDir()
        try #"(((name . "Test") (url . "http://test.com")))"#
            .write(toFile: dir + "/quicklinks.scm", atomically: true, encoding: .utf8)

        let engine = try makeEngine(configDir: dir)
        let result = try engine.evaluate("(get-quicklinks)")

        let entries = schemeListToArray(result)
        #expect(entries.count == 1)
        #expect(SchemeAlistLookup.lookupString(entries[0], key: "text") == "Test")
        #expect(SchemeAlistLookup.lookupString(entries[0], key: "name") == nil,
                "'name' should be renamed to 'text'")
    }

    // MARK: - Tag filtering

    @Test func getQuicklinksFiltersByTag() throws {
        let dir = try makeTempConfigDir()
        try """
        (((name . "GitHub") (url . "https://github.com") (tags "dev"))
         ((name . "Mail") (url . "https://mail.google.com") (tags "comms"))
         ((name . "CI") (url . "https://ci.example.com") (tags "dev" "ops")))
        """.write(toFile: dir + "/quicklinks.scm", atomically: true, encoding: .utf8)

        let engine = try makeEngine(configDir: dir)
        let result = try engine.evaluate(#"(get-quicklinks 'tag "dev")"#)

        let entries = schemeListToArray(result)
        #expect(entries.count == 2)
        #expect(SchemeAlistLookup.lookupString(entries[0], key: "text") == "GitHub")
        #expect(SchemeAlistLookup.lookupString(entries[1], key: "text") == "CI")
    }

    @Test func filterByNonexistentTagReturnsEmpty() throws {
        let dir = try makeTempConfigDir()
        try #"(((name . "GitHub") (url . "https://github.com") (tags "dev")))"#
            .write(toFile: dir + "/quicklinks.scm", atomically: true, encoding: .utf8)

        let engine = try makeEngine(configDir: dir)
        let result = try engine.evaluate(#"(get-quicklinks 'tag "nonexistent")"#)

        #expect(schemeListToArray(result).isEmpty)
    }

    // MARK: - Helpers

    private func makeTempConfigDir() throws -> String {
        let dir = NSTemporaryDirectory() + "modaliser-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeEngine(configDir: String) throws -> SchemeEngine {
        let engine = try SchemeEngine()
        try engine.context.libraries.register(libraryType: QuicklinksLibrary.self)
        if let lib = try engine.context.libraries.lookup(QuicklinksLibrary.self) {
            lib.configDirectory = configDir
        }
        try engine.context.environment.import(QuicklinksLibrary.name)
        return engine
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
