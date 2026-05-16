import Foundation
import Testing
@testable import Modaliser

@Suite("(modaliser space-switching) library")
struct ModaliserSpaceSwitchingLibraryTests {
    @Test func defaultBuilderReturnsKeyRangeOneToNine() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine) (modaliser space-switching))")
        try engine.evaluate("(define n (spaces-range-binding))")
        #expect(try engine.evaluate("(range-command? n)") == .true)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'key n)) \"1..9\")") == .true)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'label n)) \"Goto Space <n>\")") == .true)
        #expect(try engine.evaluate("(= (length (cdr (assoc 'keys n))) 9)") == .true)
    }

    @Test func keysOptionOverridesRange() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser space-switching))")
        try engine.evaluate("(define n (spaces-range-binding 'keys '(\"1\" \"2\" \"3\")))")
        #expect(try engine.evaluate("(equal? (cdr (assoc 'key n)) \"1..3\")") == .true)
    }

    @Test func displayKeyOptionOverridesDefault() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser space-switching))")
        try engine.evaluate("(define n (spaces-range-binding 'display-key \"1..\"))")
        #expect(try engine.evaluate("(equal? (cdr (assoc 'key n)) \"1..\")") == .true)
    }

    @Test func registerCreatesLookupableTree() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine) (modaliser space-switching))")
        try engine.evaluate("(spaces-1-9-register! 'tree-scope 'spaces-test)")
        #expect(try engine.evaluate("(lookup-tree \"spaces-test\")") != .false)
    }
}
