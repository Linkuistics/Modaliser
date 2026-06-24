import Foundation
import Testing
@testable import Modaliser

@Suite("(modaliser util) library")
struct ModaliserUtilLibraryTests {
    @Test func alistRefDefaultsToFalse() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser util))")
        #expect(try engine.evaluate("(alist-ref '((a . 1) (b . 2)) 'a)") == .fixnum(1))
        #expect(try engine.evaluate("(alist-ref '((a . 1)) 'missing)") == .false)
        #expect(try engine.evaluate("(alist-ref '() 'x 42)") == .fixnum(42))
    }

    @Test func stringJoinHandlesEmptyAndSingle() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser util))")
        #expect(try engine.evaluate("(string-join '() \"-\")").asString() == "")
        #expect(try engine.evaluate("(string-join '(\"a\") \"-\")").asString() == "a")
        #expect(try engine.evaluate("(string-join '(\"a\" \"b\" \"c\") \"-\")").asString() == "a-b-c")
    }

    @Test func propsToAlistPairsKeyValues() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser util))")
        #expect(try engine.evaluate(
            "(equal? (props->alist 'a 1 'b 2) '((a . 1) (b . 2)))"
        ) == .true)
    }

    @Test func stringContainsPredicateMatches() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser util))")
        #expect(try engine.evaluate("(string-contains? \"hello world\" \"world\")") == .true)
    }

    @Test func stringContainsPredicateMisses() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser util))")
        #expect(try engine.evaluate("(string-contains? \"hello world\" \"xyz\")") == .false)
    }

    @Test func stringSplitOnSingleCharSeparator() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser util))")
        #expect(try engine.evaluate(
            "(equal? (string-split \"a/b/c\" \"/\") '(\"a\" \"b\" \"c\"))"
        ) == .true)
    }

    @Test func stringSplitOnNewline() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser util))")
        #expect(try engine.evaluate(
            "(equal? (string-split \"one\\ntwo\\nthree\" \"\\n\") '(\"one\" \"two\" \"three\"))"
        ) == .true)
    }

    @Test func stringSplitEmptyInputReturnsListWithEmptyString() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser util))")
        // Locks in current LispKit (lispkit string)/string-split semantics so the
        // local replacement preserves them. If you discover the LispKit value is
        // different at the time of writing, update both this expectation and the
        // local string-split implementation in Task 2 to match — the goal is
        // *no behavioural change*, only a portable implementation.
        #expect(try engine.evaluate(
            "(equal? (string-split \"\" \"/\") '(\"\"))"
        ) == .true)
    }

    @Test func stringSplitNoMatchReturnsSingleton() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser util))")
        #expect(try engine.evaluate(
            "(equal? (string-split \"abc\" \"/\") '(\"abc\"))"
        ) == .true)
    }

    @Test func stringTrimStripsLeadingAndTrailingWhitespace() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser util))")
        #expect(try engine.evaluate("(string-trim \"  hello  \")").asString() == "hello")
        #expect(try engine.evaluate("(string-trim \"\\t hi \\n\")").asString() == "hi")
        #expect(try engine.evaluate("(string-trim \"nochange\")").asString() == "nochange")
        #expect(try engine.evaluate("(string-trim \"\")").asString() == "")
    }

    // escape-string is the single char-walk that replaced the four near-duplicate
    // escapers in ui/overlay.scm + ui/chooser.scm (audit finding C, escape-helper-merge-k36).
    // Each test below pins the EXACT escape table of one former escaper, so a drift
    // in the shared mechanism or in a call site's table is caught. Special chars are
    // built with integer->char and replacements with (string …) to keep the Scheme
    // source free of embedded backslashes/quotes — the part that must be exact.

    @Test func escapeStringPassesThroughCharsNotInTable() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser util))")
        #expect(try engine.evaluate("(escape-string \"hello\" '())").asString() == "hello")
        #expect(try engine.evaluate(
            "(escape-string \"\" (list (cons (integer->char 92) \"X\")))"
        ).asString() == "")
    }

    @Test func escapeStringApostropheTablePreservesStringReplaceApos() throws {
        // overlay.scm string-replace-apos: ' -> &#39;
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser util))")
        #expect(try engine.evaluate(
            "(let ((sq (integer->char 39)))"
            + " (escape-string (string #\\i #\\t sq #\\s) (list (cons sq \"&#39;\"))))"
        ).asString() == "it&#39;s")
    }

    @Test func escapeStringOverlayJsTablePreservesJsEscapeOverlay() throws {
        // overlay.scm js-escape-overlay: \\ -> \\\\, " -> \\", newline -> \\n
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser util))")
        #expect(try engine.evaluate(
            "(let ((bs (integer->char 92)) (dq (integer->char 34)) (nl (integer->char 10)))"
            + " (equal? (escape-string (string #\\a bs #\\b dq #\\c nl)"
            + "                        (list (cons bs (string bs bs))"
            + "                              (cons dq (string bs dq))"
            + "                              (cons nl (string bs #\\n))))"
            + "         (string #\\a bs bs #\\b bs dq #\\c bs #\\n)))"
        ) == .true)
    }

    @Test func escapeStringChooserJsTablePreservesJsEscape() throws {
        // chooser.scm js-escape: \\ -> \\\\, ' -> \\', newline -> \\n, return -> \\r
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser util))")
        #expect(try engine.evaluate(
            "(let ((bs (integer->char 92)) (sq (integer->char 39))"
            + "       (nl (integer->char 10)) (cr (integer->char 13)))"
            + " (equal? (escape-string (string #\\a bs sq nl cr)"
            + "                        (list (cons bs (string bs bs))"
            + "                              (cons sq (string bs sq))"
            + "                              (cons nl (string bs #\\n))"
            + "                              (cons cr (string bs #\\r))))"
            + "         (string #\\a bs bs bs sq bs #\\n bs #\\r)))"
        ) == .true)
    }

    @Test func escapeStringJsonTablePreservesJsonEscape() throws {
        // chooser.scm json-escape: \\ -> \\\\, " -> \\", newline -> \\n, return -> \\r, tab -> \\t
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser util))")
        #expect(try engine.evaluate(
            "(let ((bs (integer->char 92)) (dq (integer->char 34)) (nl (integer->char 10))"
            + "       (cr (integer->char 13)) (tb (integer->char 9)))"
            + " (equal? (escape-string (string bs dq nl cr tb)"
            + "                        (list (cons bs (string bs bs))"
            + "                              (cons dq (string bs dq))"
            + "                              (cons nl (string bs #\\n))"
            + "                              (cons cr (string bs #\\r))"
            + "                              (cons tb (string bs #\\t))))"
            + "         (string bs bs bs dq bs #\\n bs #\\r bs #\\t)))"
        ) == .true)
    }

    @Test func hashTableMakeAndSetAndRef() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser util))")
        try engine.evaluate("(define ht (make-hash-table string=? string-hash))")
        try engine.evaluate("(hash-table-set! ht \"alpha\" 1)")
        try engine.evaluate("(hash-table-set! ht \"beta\" 2)")
        #expect(try engine.evaluate("(hash-table-ref/default ht \"alpha\" #f)") == .fixnum(1))
        #expect(try engine.evaluate("(hash-table-ref/default ht \"beta\" #f)") == .fixnum(2))
        #expect(try engine.evaluate("(hash-table-ref/default ht \"missing\" #f)") == .false)
    }

    @Test func hashTableOverwriteOnRepeatSet() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser util))")
        try engine.evaluate("(define ht (make-hash-table string=? string-hash))")
        try engine.evaluate("(hash-table-set! ht \"k\" 1)")
        try engine.evaluate("(hash-table-set! ht \"k\" 2)")
        #expect(try engine.evaluate("(hash-table-ref/default ht \"k\" #f)") == .fixnum(2))
    }
}
