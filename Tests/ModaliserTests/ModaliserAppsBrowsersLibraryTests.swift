import Foundation
import Testing
@testable import Modaliser

@Suite("(modaliser apps safari) library")
struct ModaliserAppsSafariLibraryTests {
    @Test func registerInstallsSafariTree() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine) (modaliser apps safari))")
        try engine.evaluate("(safari-register!)")
        #expect(try engine.evaluate("(lookup-tree \"com.apple.Safari\")") != .false)
    }

    @Test func treeBuilderReturnsListOfGroups() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine) (modaliser apps safari))")
        try engine.evaluate("(define cs (safari-tree))")
        #expect(try engine.evaluate("(list? cs)") == .true)
        #expect(try engine.evaluate("(group? (car cs))") == .true)
    }

    @Test func safariExtraBindingsAppended() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine) (modaliser apps safari))")
        try engine.evaluate("""
          (define extra (list (key "x" "Extra" (lambda () 'ok))))
          (define cs (safari-tree 'extra-bindings extra))
          (define last (let loop ((xs cs))
                         (cond ((null? (cdr xs)) (car xs))
                               (else (loop (cdr xs))))))
        """)
        #expect(try engine.evaluate("(command? last)") == .true)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'key last)) \"x\")") == .true)
    }
}

@Suite("(modaliser apps chrome) library")
struct ModaliserAppsChromeLibraryTests {
    @Test func registerInstallsChromeTree() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine) (modaliser apps chrome))")
        try engine.evaluate("(chrome-register!)")
        #expect(try engine.evaluate("(lookup-tree \"com.google.Chrome\")") != .false)
    }

    @Test func chromeTreeStructureMatchesSafari() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine) (modaliser apps chrome))")
        try engine.evaluate("(define cs (chrome-tree))")
        #expect(try engine.evaluate("(list? cs)") == .true)
        #expect(try engine.evaluate("(= (length cs) 2)") == .true) // Tabs + Browser
    }
}
