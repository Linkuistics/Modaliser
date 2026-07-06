import Foundation
import Testing
@testable import Modaliser

/// Tests for `(modaliser json)` — the small portable recursive-descent
/// JSON reader that the socket-API mux backends (herdr) parse their
/// compact single-line output with. Objects read back as alists (walked
/// by `json-ref`), arrays as vectors, scalars as themselves.
@Suite("(modaliser json) library")
struct ModaliserJsonLibraryTests {
    private func engine() throws -> SchemeEngine {
        let e = try SchemeEngine()
        try e.evaluate("(import (scheme base) (modaliser json))")
        return e
    }

    @Test func importsAndExposesProcedures() throws {
        let e = try engine()
        _ = try e.evaluate("json-parse")
        _ = try e.evaluate("json-ref")
    }

    /// A scalar string round-trips, and json-ref reaches a nested field.
    @Test func extractsNestedScalar() throws {
        let e = try engine()
        let r = try e.evaluate("""
          (json-ref (json-ref (json-parse "{\\"a\\":{\\"b\\":\\"hi\\"}}") "a") "b")
        """)
        #expect(r == .makeString("hi"))
    }

    /// The real `herdr pane current` payload: dig out `.result.pane.pane_id`.
    @Test func extractsHerdrPaneId() throws {
        let e = try engine()
        try e.evaluate("""
          (define j (json-parse "{\\"id\\":\\"cli:pane:current\\",\\"result\\":{\\"pane\\":{\\"agent_status\\":\\"unknown\\",\\"focused\\":true,\\"pane_id\\":\\"w9:p1\\",\\"revision\\":0,\\"workspace_id\\":\\"w9\\"},\\"type\\":\\"pane_current\\"}}"))
        """)
        let r = try e.evaluate("(json-ref (json-ref (json-ref j \"result\") \"pane\") \"pane_id\")")
        #expect(r == .makeString("w9:p1"))
    }

    /// Arrays parse to vectors; elements are objects walked by json-ref.
    /// Mirrors `.result.process_info.foreground_processes[-1].name` — the
    /// innermost foreground command herdr's detect-fg reads.
    @Test func extractsLastArrayElementField() throws {
        let e = try engine()
        let name = try e.evaluate("""
          (let* ((j    (json-parse "{\\"result\\":{\\"process_info\\":{\\"foreground_processes\\":[{\\"name\\":\\"zsh\\"},{\\"name\\":\\"nvim\\"}]}}}"))
                 (pi   (json-ref (json-ref j "result") "process_info"))
                 (fps  (json-ref pi "foreground_processes"))
                 (last (vector-ref fps (- (vector-length fps) 1))))
            (json-ref last "name"))
        """)
        #expect(name == .makeString("nvim"))
    }

    /// A list of pane objects → each pane_id, in source order.
    @Test func mapsArrayOfObjects() throws {
        let e = try engine()
        let joined = try e.evaluate("""
          (let* ((j (json-parse "{\\"result\\":{\\"panes\\":[{\\"pane_id\\":\\"w9:p1\\"},{\\"pane_id\\":\\"w9:p2\\"}]}}"))
                 (panes (json-ref (json-ref j "result") "panes")))
            (string-append (json-ref (vector-ref panes 0) "pane_id")
                           ","
                           (json-ref (vector-ref panes 1) "pane_id")))
        """)
        #expect(joined == .makeString("w9:p1,w9:p2"))
    }

    /// Numbers, booleans, null, and empty containers.
    @Test func handlesScalarsAndEmptyContainers() throws {
        let e = try engine()
        #expect(try e.evaluate("(json-parse \"42\")") == .fixnum(42))
        #expect(try e.evaluate("(json-parse \"-7\")") == .fixnum(-7))
        #expect(try e.evaluate("(json-ref (json-parse \"{\\\"b\\\":true}\") \"b\")") == .true)
        #expect(try e.evaluate("(json-ref (json-parse \"{\\\"b\\\":false}\") \"b\")") == .false)
        #expect(try e.evaluate("(eq? 'null (json-ref (json-parse \"{\\\"v\\\":null}\") \"v\"))") == .true)
        // Empty object → '() (a list); empty array → #() (a vector).
        #expect(try e.evaluate("(null? (json-parse \"{}\"))") == .true)
        #expect(try e.evaluate("(vector? (json-parse \"[]\"))") == .true)
        // Missing key and lookup into a non-object both degrade to #f.
        #expect(try e.evaluate("(json-ref (json-parse \"{\\\"a\\\":1}\") \"z\")") == .false)
        #expect(try e.evaluate("(json-ref (json-parse \"[1,2]\") \"a\")") == .false)
    }

    /// String escapes decode (whitespace-in-value, escaped quote, slash).
    @Test func decodesStringEscapes() throws {
        let e = try engine()
        let r = try e.evaluate("(json-ref (json-parse \"{\\\"p\\\":\\\"a\\\\/b c\\\"}\") \"p\")")
        #expect(r == .makeString("a/b c"))
    }
}
