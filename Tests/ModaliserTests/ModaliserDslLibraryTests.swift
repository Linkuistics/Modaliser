import Foundation
import Testing
@testable import Modaliser

@Suite("(modaliser dsl) library")
struct ModaliserDslLibraryTests {
    @Test func keyConstructsCommandAlist() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine))")
        try engine.evaluate("""
          (define k (key "s" "Safari" (lambda () 'ok)))
        """)
        #expect(try engine.evaluate("(command? k)") == .true)
        #expect(try engine.evaluate("(cdr (assoc 'key k))").asString() == "s")
        #expect(try engine.evaluate("(cdr (assoc 'label k))").asString() == "Safari")
    }

    @Test func defineTreeRegistersTree() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine))")
        try engine.evaluate("""
          (define-tree 'global
            (key "s" "Safari" (lambda () 'ok)))
        """)
        #expect(try engine.evaluate("(lookup-tree \"global\")") != .false)
    }

    @Test func modifierSymbolsToMaskConvertsToBits() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser keyboard))")
        let expected = try engine.evaluate("(bitwise-ior MOD-SHIFT MOD-CTRL)")
        #expect(try engine.evaluate("(modifier-symbols->mask '(shift ctrl))") == expected)
    }
}
