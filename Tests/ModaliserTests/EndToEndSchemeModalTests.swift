import CoreGraphics
import Foundation
import Testing
import LispKit
@testable import Modaliser

@Suite("End-to-end Scheme modal dispatch")
struct EndToEndSchemeModalTests {

    /// Simulates the full runtime: load all modules, load user config,
    /// then simulate F18 press → 's' key → verify action fires.
    @Test func f18ThenSExecutesAction() throws {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("Scheme directory not found")
            return
        }

        // Load modules in order (same as SchemeEngine.loadRootSchemeFile)
        let files = ["lib/util.scm", "core/keymap.scm", "core/state-machine.scm",
                     "core/event-dispatch.scm", "lib/dsl.scm"]
        for file in files {
            try engine.evaluateFile(joinPath(schemePath, file))
        }

        // Define a test config (mimics user config)
        try engine.evaluate("""
            (define test-result #f)
            (set-leader! 'global F18)
            (define-tree 'global
              (key "s" "Safari" (lambda () (set! test-result 'safari-launched))))
            """)

        // Verify hotkey is registered
        let kbLib = try engine.context.libraries.lookup(KeyboardLibrary.self)!
        #expect(kbLib.handlerRegistry.hotkeyHandlers[KeyCode.f18] != nil)

        // Simulate F18 press: call the hotkey handler directly
        kbLib.handlerRegistry.hotkeyHandlers[KeyCode.f18]!()

        // Should be modal now
        #expect(try engine.evaluate("modal-active?") == .true)

        // Simulate 's' keypress through the catch-all handler
        let catchAll = kbLib.handlerRegistry.catchAllHandler!
        let suppress = catchAll(CGKeyCode(1), [])  // keycode 1 = 's'
        #expect(suppress == true)

        // Action should have executed
        #expect(try engine.evaluate("test-result") == .symbol(engine.context.symbols.intern("safari-launched")))
        // Should be inactive now
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
            (set-leader! 'global F18)
            (define-tree 'global
              (group "w" "Windows"
                (key "c" "Center" (lambda () (set! test-result 'centered)))))
            """)

        let kbLib = try engine.context.libraries.lookup(KeyboardLibrary.self)!

        // F18
        kbLib.handlerRegistry.hotkeyHandlers[KeyCode.f18]!()
        #expect(try engine.evaluate("modal-active?") == .true)

        // 'w' (keycode 13)
        let catchAll = kbLib.handlerRegistry.catchAllHandler!
        _ = catchAll(CGKeyCode(13), [])  // 'w'
        #expect(try engine.evaluate("modal-active?") == .true)

        // 'c' (keycode 8)
        _ = catchAll(CGKeyCode(8), [])   // 'c'
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
            (set-leader! 'global F18)
            (define-tree 'global
              (key "s" "Safari" (lambda () #t)))
            """)

        let kbLib = try engine.context.libraries.lookup(KeyboardLibrary.self)!

        // F18 to enter
        kbLib.handlerRegistry.hotkeyHandlers[KeyCode.f18]!()
        #expect(try engine.evaluate("modal-active?") == .true)

        // F18 again via catch-all — should toggle off
        let catchAll = kbLib.handlerRegistry.catchAllHandler!
        let suppress = catchAll(KeyCode.f18, [])
        #expect(suppress == true)
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
            (set-leader! 'global F18)
            (define-tree 'global
              (key "s" "Safari" (lambda () #t)))
            """)

        let kbLib = try engine.context.libraries.lookup(KeyboardLibrary.self)!

        kbLib.handlerRegistry.hotkeyHandlers[KeyCode.f18]!()
        #expect(try engine.evaluate("modal-active?") == .true)

        let catchAll = kbLib.handlerRegistry.catchAllHandler!
        _ = catchAll(KeyCode.escape, [])
        #expect(try engine.evaluate("modal-active?") == .false)
    }
}

private func joinPath(_ base: String, _ component: String) -> String {
    base.hasSuffix("/") ? base + component : base + "/" + component
}
