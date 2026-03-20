import Testing
import Foundation
import LispKit
@testable import Modaliser

@Suite("SnippetsLibrary")
struct SnippetsLibraryTests {

    // MARK: - File parsing

    @Test func getSnippetsReturnsEntriesFromFile() throws {
        let dir = try makeTempConfigDir()
        try """
        (((name . "Greeting") (content . "Hello!") (tags "email"))
         ((name . "Bug Template") (content . "## Steps\\n## Expected") (tags "dev")))
        """.write(toFile: dir + "/snippets.scm", atomically: true, encoding: .utf8)

        let engine = try makeEngine(configDir: dir)
        let result = try engine.evaluate("(get-snippets)")

        let entries = schemeListToArray(result)
        #expect(entries.count == 2)
        #expect(SchemeAlistLookup.lookupString(entries[0], key: "text") == "Greeting")
        #expect(SchemeAlistLookup.lookupString(entries[0], key: "content") == "Hello!")
    }

    @Test func getSnippetsReturnsEmptyListForMissingFile() throws {
        let dir = try makeTempConfigDir()
        let engine = try makeEngine(configDir: dir)
        let result = try engine.evaluate("(get-snippets)")
        #expect(schemeListToArray(result).isEmpty)
    }

    // MARK: - Tag filtering

    @Test func getSnippetsFiltersByTag() throws {
        let dir = try makeTempConfigDir()
        try """
        (((name . "Greeting") (content . "Hello!") (tags "email"))
         ((name . "Date") (content . "{{date}}") (tags "utility"))
         ((name . "Bug") (content . "template") (tags "dev" "email")))
        """.write(toFile: dir + "/snippets.scm", atomically: true, encoding: .utf8)

        let engine = try makeEngine(configDir: dir)
        let result = try engine.evaluate(#"(get-snippets 'tag "email")"#)

        let entries = schemeListToArray(result)
        #expect(entries.count == 2)
        #expect(SchemeAlistLookup.lookupString(entries[0], key: "text") == "Greeting")
        #expect(SchemeAlistLookup.lookupString(entries[1], key: "text") == "Bug")
    }

    // MARK: - expand-snippet

    @Test func expandSnippetReplacesDatePlaceholder() throws {
        let engine = try makeEngine(configDir: try makeTempConfigDir())
        let result = try engine.evaluate(#"(expand-snippet "Today is {{date}}")"#)
        let str = try result.asString()
        // Should contain a date in ISO format (YYYY-MM-DD)
        #expect(str.contains("2026-"), "Should contain current year, got: \(str)")
        #expect(!str.contains("{{date}}"), "Placeholder should be replaced")
    }

    @Test func expandSnippetReplacesTimePlaceholder() throws {
        let engine = try makeEngine(configDir: try makeTempConfigDir())
        let result = try engine.evaluate(#"(expand-snippet "Now: {{time}}")"#)
        let str = try result.asString()
        #expect(str.contains(":"), "Should contain time with colon separator, got: \(str)")
        #expect(!str.contains("{{time}}"), "Placeholder should be replaced")
    }

    @Test func expandSnippetReplacesDatetimePlaceholder() throws {
        let engine = try makeEngine(configDir: try makeTempConfigDir())
        let result = try engine.evaluate(#"(expand-snippet "{{datetime}}")"#)
        let str = try result.asString()
        #expect(str.contains("2026-"), "Should contain date")
        #expect(str.contains(":"), "Should contain time")
    }

    @Test func expandSnippetReplacesClipboardPlaceholder() throws {
        let engine = try makeEngine(configDir: try makeTempConfigDir())
        // Set clipboard to a known value
        try engine.evaluate(#"(set-clipboard! "test-clip")"#)
        let result = try engine.evaluate(#"(expand-snippet "clip: {{clipboard}}")"#)
        let str = try result.asString()
        #expect(str == "clip: test-clip")
    }

    @Test func expandSnippetLeavesTextWithoutPlaceholders() throws {
        let engine = try makeEngine(configDir: try makeTempConfigDir())
        let result = try engine.evaluate(#"(expand-snippet "plain text")"#)
        #expect(try result.asString() == "plain text")
    }

    // MARK: - Helpers

    private func makeTempConfigDir() throws -> String {
        let dir = NSTemporaryDirectory() + "modaliser-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeEngine(configDir: String) throws -> SchemeEngine {
        let engine = try SchemeEngine()
        try engine.context.libraries.register(libraryType: SnippetsLibrary.self)
        if let lib = try engine.context.libraries.lookup(SnippetsLibrary.self) {
            lib.configDirectory = configDir
        }
        try engine.context.environment.import(SnippetsLibrary.name)
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
