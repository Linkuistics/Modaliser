import CoreGraphics
import Foundation
import Testing
import LispKit
@testable import Modaliser

@Suite("End-to-end Scheme modal dispatch")
struct EndToEndSchemeModalTests {

    @Test func hotkeyHandlersRegistered() throws {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("Scheme directory not found")
            return
        }

        let files = ["lib/util.scm", "core/keymap.scm", "core/state-machine.scm",
                     "core/event-dispatch.scm", "lib/dsl.scm"]
        for file in files {
            try engine.evaluateFile(joinPath(schemePath, file))
        }

        try engine.evaluate("""
            (set-leader! 'global F18)
            (define-tree 'global
              (key "s" "Safari" (lambda () #t)))
            """)

        let kbLib = try engine.context.libraries.lookup(KeyboardLibrary.self)!
        #expect(kbLib.handlerRegistry.hotkeyHandlers[KeyCode.f18] != nil)
    }

    @Test func f18ThenSExecutesAction() throws {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("Scheme directory not found")
            return
        }

        let files = ["lib/util.scm", "core/keymap.scm", "core/state-machine.scm",
                     "core/event-dispatch.scm", "lib/dsl.scm"]
        for file in files {
            try engine.evaluateFile(joinPath(schemePath, file))
        }

        try engine.evaluate("""
            (define test-result #f)
            (define-tree 'global
              (key "s" "Safari" (lambda () (set! test-result 'safari-launched))))
            """)

        // Enter modal directly (simulates what the hotkey handler does)
        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        #expect(try engine.evaluate("modal-active?") == .true)

        // Simulate 's' keypress through the modal key handler
        try engine.evaluate("(modal-key-handler 1 0)")  // keycode 1 = 's', no modifiers
        #expect(try engine.evaluate("test-result") == .symbol(engine.context.symbols.intern("safari-launched")))
        #expect(try engine.evaluate("modal-active?") == .false)
    }

    @Test func f18ThenGroupThenCommand() throws {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else { return }

        let files = ["lib/util.scm", "core/keymap.scm", "core/state-machine.scm",
                     "core/event-dispatch.scm", "lib/dsl.scm"]
        for file in files {
            try engine.evaluateFile(joinPath(schemePath, file))
        }

        try engine.evaluate("""
            (define test-result #f)
            (define-tree 'global
              (group "w" "Windows"
                (key "c" "Center" (lambda () (set! test-result 'centered)))))
            """)

        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        #expect(try engine.evaluate("modal-active?") == .true)

        // 'w' (keycode 13)
        try engine.evaluate("(modal-key-handler 13 0)")
        #expect(try engine.evaluate("modal-active?") == .true)

        // 'c' (keycode 8)
        try engine.evaluate("(modal-key-handler 8 0)")
        #expect(try engine.evaluate("test-result") == .symbol(engine.context.symbols.intern("centered")))
        #expect(try engine.evaluate("modal-active?") == .false)
    }

    @Test func f18ToggleExits() throws {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else { return }

        let files = ["lib/util.scm", "core/keymap.scm", "core/state-machine.scm",
                     "core/event-dispatch.scm", "lib/dsl.scm"]
        for file in files {
            try engine.evaluateFile(joinPath(schemePath, file))
        }

        try engine.evaluate("""
            (define-tree 'global
              (key "s" "Safari" (lambda () #t)))
            """)

        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        #expect(try engine.evaluate("modal-active?") == .true)

        // F18 again — should toggle off (leader keycode matches)
        try engine.evaluate("(modal-key-handler F18 0)")
        #expect(try engine.evaluate("modal-active?") == .false)
    }

    @Test func escapeExitsModal() throws {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else { return }

        let files = ["lib/util.scm", "core/keymap.scm", "core/state-machine.scm",
                     "core/event-dispatch.scm", "lib/dsl.scm"]
        for file in files {
            try engine.evaluateFile(joinPath(schemePath, file))
        }

        try engine.evaluate("""
            (define-tree 'global
              (key "s" "Safari" (lambda () #t)))
            """)

        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        #expect(try engine.evaluate("modal-active?") == .true)

        try engine.evaluate("(modal-key-handler ESCAPE 0)")
        #expect(try engine.evaluate("modal-active?") == .false)
    }
}

private func joinPath(_ base: String, _ component: String) -> String {
    base.hasSuffix("/") ? base + component : base + "/" + component
}
