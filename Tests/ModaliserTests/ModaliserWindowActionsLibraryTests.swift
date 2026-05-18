import Foundation
import Testing
@testable import Modaliser

@Suite("(modaliser window-actions) library")
struct ModaliserWindowActionsLibraryTests {
    @Test func groupBuilderReturnsGroupNode() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine) (modaliser window-actions))")
        try engine.evaluate("(define g (actions))")
        #expect(try engine.evaluate("(group? g)") == .true)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'key g)) \"w\")") == .true)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'label g)) \"Windows\")") == .true)
    }

    @Test func groupBuilderHonoursKeyAndLabelOptions() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser window-actions))")
        try engine.evaluate("(define g (actions 'key \"W\" 'label \"Win\"))")
        #expect(try engine.evaluate("(equal? (cdr (assoc 'key g)) \"W\")") == .true)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'label g)) \"Win\")") == .true)
    }

    @Test func registerCreatesLookupableTree() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine) (modaliser window-actions))")
        try engine.evaluate("(register! 'tree-scope 'wa-test)")
        #expect(try engine.evaluate("(lookup-tree \"wa-test\")") != .false)
    }

    @Test func defaultActionsGroupCarriesBlocksRendererAndPanels() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine) (modaliser window-actions))")
        try engine.evaluate("(define g (actions))")
        #expect(try engine.evaluate("(eq? (node-renderer g) 'blocks)") == .true)
        try engine.evaluate("""
          (define blocks (node-renderer-payload g 'blocks))
          (define wd (car blocks))
          (define panels (cdr (assoc 'panels wd)))
        """)
        // Six panels: full thirds, half thirds, two two-thirds, fill (m), center (c)
        #expect(try engine.evaluate("(= (length panels) 6)") == .true)
        try engine.evaluate("(define p1 (car panels))")
        #expect(try engine.evaluate("(eq? (cdr (assoc 'type p1)) 'grid)") == .true)
        #expect(try engine.evaluate("(= (cdr (assoc 'cols p1)) 3)") == .true)
    }

    @Test func defaultActionsHasNamedSelectorWithKeyN() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine) (modaliser window-actions))")
        try engine.evaluate("""
          (define g (actions))
          (define children (cdr (assoc 'children g)))
          (define named
            (let loop ((cs children))
              (cond ((null? cs) #f)
                    ((and (selector? (car cs))
                          (equal? (cdr (assoc 'key (car cs))) "n")) (car cs))
                    (else (loop (cdr cs))))))
        """)
        #expect(try engine.evaluate("(and named #t)") == .true)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'label named)) \"Named…\")") == .true)
    }

    @Test func defaultActionsHasRestoreKey() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine) (modaliser window-actions))")
        try engine.evaluate("""
          (define g (actions))
          (define children (cdr (assoc 'children g)))
          (define restore
            (let loop ((cs children))
              (cond ((null? cs) #f)
                    ((and (command? (car cs))
                          (equal? (cdr (assoc 'key (car cs))) "r")) (car cs))
                    (else (loop (cdr cs))))))
        """)
        #expect(try engine.evaluate("(and restore #t)") == .true)
    }

    @Test func divisionsBuilderGeneratesKeysForMatrix() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (prefix (modaliser window-actions) window:))")
        try engine.evaluate("(define result (window:divisions '((\"d\" \"f\" \"g\"))))")
        // result is a 2-element list: (panel-spec key-nodes)
        try engine.evaluate("(define spec (car result))")
        try engine.evaluate("(define keys (cadr result))")
        #expect(try engine.evaluate("(eq? (cdr (assoc 'type spec)) 'grid)") == .true)
        #expect(try engine.evaluate("(= (length keys) 3)") == .true)
        try engine.evaluate("(define k1 (car keys))")
        #expect(try engine.evaluate("(equal? (cdr (assoc 'key k1)) \"d\")") == .true)
    }

    @Test func windowRangeBindingExistsWithDisplay1dotdot() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine) (modaliser window-actions))")
        try engine.evaluate("""
          (define g (actions))
          (define children (cdr (assoc 'children g)))
          (define range-node
            (let loop ((cs children))
              (cond ((null? cs) #f)
                    ((equal? (cdr (assoc 'key (car cs))) "1..") (car cs))
                    (else (loop (cdr cs))))))
        """)
        #expect(try engine.evaluate("(and range-node #t)") == .true)
    }

    @Test func actionsGroupUsesBlocksRendererAfterMigration() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine) (modaliser window-actions))")
        try engine.evaluate("(define g (actions))")
        #expect(try engine.evaluate("(eq? (node-renderer g) 'blocks)") == .true)
        // Three blocks: window-diagram, which-key, window-list
        try engine.evaluate("(define blocks (node-renderer-payload g 'blocks))")
        #expect(try engine.evaluate("(= (length blocks) 3)") == .true)
        #expect(try engine.evaluate("(eq? (cdr (assoc 'type (list-ref blocks 0))) 'window-diagram)") == .true)
        #expect(try engine.evaluate("(eq? (cdr (assoc 'type (list-ref blocks 1))) 'which-key)") == .true)
        #expect(try engine.evaluate("(eq? (cdr (assoc 'type (list-ref blocks 2))) 'window-list)") == .true)
    }
}
