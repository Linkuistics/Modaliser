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
