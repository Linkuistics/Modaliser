import Foundation
import Testing
@testable import Modaliser

@Suite("(modaliser ax-hints) library")
struct ModaliserAxHintsLibraryTests {
    @Test func labelPairsTruncatesAtMinLength() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser ax-hints))")
        try engine.evaluate("(define ps (label-pairs '(\"a\" \"b\" \"c\") '(1 2)))")
        #expect(try engine.evaluate("(= (length ps) 2)") == .true)
        #expect(try engine.evaluate("(equal? (car (car ps)) \"a\")") == .true)
        #expect(try engine.evaluate("(= (cdr (car ps)) 1)") == .true)
    }

    @Test func axTargetHintsHandlesEmpty() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser ax-hints))")
        #expect(try engine.evaluate("(null? (ax-target-hints '() '()))") == .true)
    }

    @Test func defaultHintOptionsIsAlist() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser ax-hints))")
        #expect(try engine.evaluate("(list? default-hint-options)") == .true)
        // Probe one expected key.
        #expect(try engine.evaluate("(equal? (cdr (assoc 'font-size default-hint-options)) 24)") == .true)
    }
}
