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
}
