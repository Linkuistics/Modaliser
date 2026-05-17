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

    @Test func includeSwitcherFalseDropsSelectWindowChild() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine) (modaliser window-actions))")
        try engine.evaluate("""
          (define g (actions 'include-switcher? #f))
          (define children (cdr (assoc 'children g)))
          (define has-switcher
            (let loop ((cs children))
              (cond ((null? cs) #f)
                    ((and (selector? (car cs))
                          (equal? (cdr (assoc 'key (car cs))) "s")) #t)
                    (else (loop (cdr cs))))))
        """)
        #expect(try engine.evaluate("has-switcher") == .false)
    }

    @Test func includeSwitcherTrueIncludesSelectWindowChild() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine) (modaliser window-actions))")
        try engine.evaluate("""
          (define g (actions))
          (define children (cdr (assoc 'children g)))
          (define has-switcher
            (let loop ((cs children))
              (cond ((null? cs) #f)
                    ((and (selector? (car cs))
                          (equal? (cdr (assoc 'key (car cs))) "s")) #t)
                    (else (loop (cdr cs))))))
        """)
        #expect(try engine.evaluate("has-switcher") == .true)
    }

    @Test func registerCreatesLookupableTree() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine) (modaliser window-actions))")
        try engine.evaluate("(register! 'tree-scope 'wa-test)")
        #expect(try engine.evaluate("(lookup-tree \"wa-test\")") != .false)
    }
}
