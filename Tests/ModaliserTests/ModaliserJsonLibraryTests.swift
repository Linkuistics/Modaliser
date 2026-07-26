import Foundation
import Testing
@testable import Modaliser

/// Tests for `(modaliser json)` — the small portable JSON reader and
/// writer the socket-API mux backends (herdr) speak through. Objects read
/// back as alists (walked by `json-ref`), arrays as vectors, scalars as
/// themselves; `json-write` renders that same representation back onto
/// the wire.
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

    // ─── json-write ─────────────────────────────────────────────────
    //
    // The writer is json-parse's mirror over the same representation, so
    // the herdr socket transport can build its `{"id","method","params"}`
    // request line without a per-backend ad-hoc encoder.

    @Test func writesScalars() throws {
        let e = try engine()
        #expect(try e.evaluate("(json-write 42)") == .makeString("42"))
        #expect(try e.evaluate("(json-write -7)") == .makeString("-7"))
        #expect(try e.evaluate("(json-write #t)") == .makeString("true"))
        #expect(try e.evaluate("(json-write #f)") == .makeString("false"))
        #expect(try e.evaluate("(json-write 'null)") == .makeString("null"))
        #expect(try e.evaluate("(json-write \"hi\")") == .makeString("\"hi\""))
    }

    /// Objects keep their alist order, so a request line is deterministic
    /// and therefore assertable in a test.
    @Test func writesObjectsInAlistOrder() throws {
        let e = try engine()
        let r = try e.evaluate("""
          (json-write '(("method" . "pane.focus") ("params" . (("pane_id" . "wC:p4")))))
        """)
        #expect(r == .makeString("{\"method\":\"pane.focus\",\"params\":{\"pane_id\":\"wC:p4\"}}"))
    }

    /// The two empty containers stay distinguishable, exactly as they are
    /// on the read side: '() is the empty object, #() the empty array.
    @Test func writesEmptyContainersDistinctly() throws {
        let e = try engine()
        #expect(try e.evaluate("(json-write '())") == .makeString("{}"))
        #expect(try e.evaluate("(json-write #())") == .makeString("[]"))
    }

    @Test func writesArraysAsVectors() throws {
        let e = try engine()
        #expect(try e.evaluate("(json-write #(1 \"a\" #t))") == .makeString("[1,\"a\",true]"))
    }

    /// A herdr tab/workspace label is arbitrary user text and reaches the
    /// wire through this escaper — the apostrophe that `sq-escape` existed
    /// for is unremarkable here, but a quote, a backslash, or a newline
    /// would produce an unparseable request line if left raw.
    @Test func escapesStringsForTheWire() throws {
        let e = try engine()
        #expect(try e.evaluate("(json-write \"it's\")") == .makeString("\"it's\""))
        #expect(try e.evaluate("(json-write \"a\\\"b\")") == .makeString("\"a\\\"b\""))
        #expect(try e.evaluate("(json-write \"a\\\\b\")") == .makeString("\"a\\\\b\""))
        #expect(try e.evaluate("(json-write \"a\\nb\")") == .makeString("\"a\\nb\""))
        // Other control characters take the \u form.
        #expect(try e.evaluate("(json-write (string (integer->char 1)))") == .makeString("\"\\u0001\""))
    }

    /// The property that matters: anything json-parse produces, json-write
    /// renders back to something json-parse reads identically.
    @Test func roundTripsThroughJsonParse() throws {
        let e = try engine()
        let same = try e.evaluate("""
          (let ((src "{\\"a\\":[1,{\\"b\\":\\"x y\\"},true,null],\\"c\\":{}}"))
            (equal? (json-parse src) (json-parse (json-write (json-parse src)))))
        """)
        #expect(same == .true)
    }
}
