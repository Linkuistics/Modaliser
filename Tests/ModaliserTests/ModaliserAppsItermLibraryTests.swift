import Foundation
import Testing
@testable import Modaliser

@Suite("(modaliser apps iterm) library")
struct ModaliserAppsItermLibraryTests {
    @Test func registerInstallsItermTree() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine) (modaliser apps iterm))")
        // iTerm not running; AX query returns empty. Tree is registered
        // even with no pane-range children — the c/f/z/x static keys
        // remain. Pass 'install-context-suffix? #f to avoid mutating
        // shared (modaliser event-dispatch) state between tests.
        try engine.evaluate("(iterm-register! 'install-context-suffix? #f)")
        #expect(try engine.evaluate("(lookup-tree \"com.googlecode.iterm2\")") != .false)
    }

    @Test func focusModeRegistersUnderDefaultId() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine) (modaliser apps iterm))")
        try engine.evaluate("(iterm-focus-mode-register!)")
        #expect(try engine.evaluate("(lookup-tree \"iterm-panes-focus\")") != .false)
    }

    @Test func contextSuffixReturnsFalseForOtherApps() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser apps iterm))")
        #expect(try engine.evaluate("(iterm-context-suffix-handler \"com.apple.Safari\")") == .false)
    }

    @Test func defaultPaneLabelsAreDigits() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser apps iterm))")
        #expect(try engine.evaluate("(= (length iterm-default-pane-labels) 10)") == .true)
        #expect(try engine.evaluate("(equal? (car iterm-default-pane-labels) \"1\")") == .true)
    }

    @Test func focusModeTreeIsHjklOnly() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (modaliser state-machine) (modaliser apps iterm))")
        try engine.evaluate("(define cs (iterm-focus-mode-tree))")
        #expect(try engine.evaluate("(= (length cs) 4)") == .true)
        try engine.evaluate("""
          (define keys (map (lambda (c) (cdr (assoc 'key c))) cs))
        """)
        #expect(try engine.evaluate("(equal? keys '(\"h\" \"j\" \"k\" \"l\"))") == .true)
    }
}
