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

    @Test func defineTreeAutoPacksConsecutiveKeysIntoWhichKeyBlock() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine))")
        try engine.evaluate("""
          (define-tree 'global
            (key "a" "Apple"  (lambda () 'ok))
            (key "b" "Banana" (lambda () 'ok)))
        """)
        // Top-level renders as a block-list with one auto-packed which-key block.
        let root = "(lookup-tree \"global\")"
        #expect(try engine.evaluate("(cdr (assoc 'renderer \(root)))")
                == .symbol(engine.context.symbols.intern("blocks")))
        #expect(try engine.evaluate("(length (cdr (assoc 'blocks \(root))))").asInt64() == 1)
        let block = "(car (cdr (assoc 'blocks \(root))))"
        #expect(try engine.evaluate("(cdr (assoc 'type \(block)))")
                == .symbol(engine.context.symbols.intern("which-key")))
        #expect(try engine.evaluate("(length (cdr (assoc 'block-children \(block))))").asInt64() == 2)
        // Dispatch still works: children are lifted onto the root for find-child.
        #expect(try engine.evaluate("(command? (find-child \(root) \"a\"))") == .true)
        #expect(try engine.evaluate("(command? (find-child \(root) \"b\"))") == .true)
    }

    @Test func overlayAutoPacksConsecutiveKeysToo() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine))")
        // No explicit (which-key-block …) inside overlay — consecutive
        // (key …) forms are packed automatically, just like at top level.
        try engine.evaluate("""
          (define o (overlay
                      (key "a" "Apple"  (lambda () 'ok))
                      (key "b" "Banana" (lambda () 'ok))))
        """)
        #expect(try engine.evaluate("(length (cdr (assoc 'blocks o)))").asInt64() == 1)
        let block = "(car (cdr (assoc 'blocks o)))"
        #expect(try engine.evaluate("(cdr (assoc 'type \(block)))")
                == .symbol(engine.context.symbols.intern("which-key")))
        #expect(try engine.evaluate("(length (cdr (assoc 'block-children \(block))))").asInt64() == 2)
    }
}
