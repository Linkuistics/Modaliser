import Testing
import AppKit
@testable import Modaliser

@Suite("Pasteboard Library", .serialized)
struct PasteboardLibraryTests {

    // MARK: - Library registration

    @Test func libraryNameIsPasteboardNamespace() throws {
        let engine = try SchemeEngine()
        // The library should be registered and importable
        let result = try engine.evaluate("(get-clipboard)")
        // Should not throw — function exists
        _ = result
    }

    // MARK: - set-clipboard!

    @Test func setClipboardWritesStringToPasteboard() throws {
        let engine = try SchemeEngine()
        try engine.evaluate(#"(set-clipboard! "hello from scheme")"#)

        let contents = NSPasteboard.general.string(forType: .string)
        #expect(contents == "hello from scheme")
    }

    @Test func setClipboardReturnsVoid() throws {
        let engine = try SchemeEngine()
        let result = try engine.evaluate(#"(set-clipboard! "test")"#)
        #expect(result == .void)
    }

    // MARK: - get-clipboard

    @Test func getClipboardReadsStringFromPasteboard() throws {
        let engine = try SchemeEngine()
        // Set clipboard via AppKit directly
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("native text", forType: .string)

        let result = try engine.evaluate("(get-clipboard)")
        #expect(try result.asString() == "native text")
    }

    @Test func getClipboardReturnsEmptyStringWhenEmpty() throws {
        let engine = try SchemeEngine()
        // Clear clipboard
        NSPasteboard.general.clearContents()

        let result = try engine.evaluate("(get-clipboard)")
        #expect(try result.asString() == "")
    }

    // MARK: - Round-trip

    @Test func setThenGetRoundTrips() throws {
        let engine = try SchemeEngine()
        try engine.evaluate(#"(set-clipboard! "round-trip test")"#)
        let result = try engine.evaluate("(get-clipboard)")
        #expect(try result.asString() == "round-trip test")
    }
}
