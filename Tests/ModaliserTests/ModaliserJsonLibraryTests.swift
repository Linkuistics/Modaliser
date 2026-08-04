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

    /// Truncated input **raises** — it does not spin. `peek` answers `#\x0`
    /// past the end of the string rather than an end sentinel, and
    /// `parse-string`'s scan advances on any character that is not `"` or
    /// `\`, so an unterminated literal used to loop forever consing NULs.
    ///
    /// The distinction is the whole point. Every caller wraps `json-parse` in
    /// a `guard` and degrades to no data on a raise; none of them can catch a
    /// hang. `(modaliser wms paneru)`'s strip parse runs at come-to-rest — on
    /// the main thread, between one keypress and the next — so a truncated
    /// payload there would wedge the modal rather than show an empty listing.
    ///
    /// The cases are ordered by *where* the input stops: mid-key, mid-value,
    /// and immediately after the opening quote. All three enter the same scan.
    @Test(arguments: [
        #"{\"virtual_workspaces\":[{\"act"#,
        #"{\"app_name\":\"iTerm"#,
        #"{\"k\":\""#,
        #"[\"unterminated"#,
    ])
    func raisesRatherThanSpinningOnAnUnterminatedString(_ truncated: String) throws {
        let e = try engine()
        #expect(
            try e.evaluate("(eq? 'raised (guard (x (#t 'raised)) (json-parse \"\(truncated)\")))")
                == .true,
            "expected a raise, not a hang, for: \(truncated)")
    }

    /// Input that is not JSON at all raises **guardably** — an `error`, which
    /// `(guard (e (#t …)) …)` catches, not a host type error that escapes it.
    ///
    /// The distinction is not academic. `parse-value` falls through to
    /// `parse-number` for any character that starts no object, array, string
    /// or literal, so this is where shell noise and empty output land — and
    /// LispKit's `string->number` raises a *type* error on an empty string
    /// rather than answering #f. That error is not caught by `guard`, so every
    /// caller's degradation path was bypassed and the failure reached the host
    /// as a broken evaluation instead of "no data".
    ///
    /// Empty output is the case that matters most: it is exactly what
    /// `run-shell` answers when no runner is installed, when a binary is
    /// missing, or when a daemon is down.
    /// The last case takes the other branch — a token made of number
    /// characters that is still not a number — so both ways out of
    /// `parse-number` are pinned as guardable.
    @Test(arguments: [
        "",
        "paneru: command not found",
        "<html>",
        "1.2.3",
    ])
    func raisesGuardablyOnInputThatIsNotJson(_ garbage: String) throws {
        let e = try engine()
        #expect(
            try e.evaluate("(eq? 'raised (guard (x (#t 'raised)) (json-parse \"\(garbage)\")))")
                == .true,
            "expected a guardable raise for: \(garbage.isEmpty ? "(empty output)" : garbage)")
    }

    /// Structurally malformed input raises **guardably** too — the reader
    /// does not quietly accept a shape it can recover from.
    ///
    /// These four are here because they are what a *fast* reader tends to
    /// lose. Its scanner knows where the next token must begin, so it is
    /// always tempting to jump the cursor past a punctuation character
    /// rather than check it, and to read an escape character without
    /// bounds-checking first. None of that changes a well-formed parse, so
    /// nothing else in this suite would notice.
    ///
    /// The last two are the sharp ones, and they were confirmed against a
    /// draft that omitted the guards: `string-ref` past the end raises a
    /// **host** range error, which is *not* the guardable kind — it escapes
    /// the `guard` every caller wraps `json-parse` in and reaches the host
    /// as a failed evaluation, which is the one outcome this reader's
    /// malformed-input handling exists to prevent.
    ///
    /// - a **missing colon** between key and value (`{"a" 1}`), which a
    ///   reader that does `(+ k 1)` instead of `expect #\:` reads as if the
    ///   space were a colon;
    /// - a **non-string key** (`{a:1}`), the same hazard on the opening
    ///   quote. Both of these still raise without the check, by falling over
    ///   further along — so they pin the intent rather than close a live
    ///   hole, and a reader that jumped the cursor *and* recovered would
    ///   need them;
    /// - a **truncated escape** (`{"k":"a\`), where the escape character
    ///   itself is past the end of the input;
    /// - a **truncated `\u` escape**, the same hazard four characters wider.
    @Test(
        arguments: [
            #"{\"a\" 1}"#,
            #"{a:1}"#,
            #"{\"k\":\"a\\"#,
            #"{\"k\":\"a\\u00"#,
        ])
    func raisesGuardablyOnStructurallyMalformedInput(_ malformed: String) throws {
        let e = try engine()
        #expect(
            try e.evaluate("(eq? 'raised (guard (x (#t 'raised)) (json-parse \"\(malformed)\")))")
                == .true,
            "expected a guardable raise for: \(malformed)")
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
