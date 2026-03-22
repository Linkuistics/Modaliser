import Foundation
import Testing
import LispKit
@testable import Modaliser

private func joinPath(_ base: String, _ component: String) -> String {
    base.hasSuffix("/") ? base + component : base + "/" + component
}

@Suite("Scheme Core Smoke Tests")
struct SchemeCoreSmokeTests {

    // MARK: - Module loading

    @Test func utilModuleLoads() throws {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("Scheme directory not found")
            return
        }
        try engine.evaluateFile(joinPath(schemePath,"lib/util.scm"))
        // Verify functions are defined
        #expect(try engine.evaluate("(procedure? alist-ref)") == .true)
        #expect(try engine.evaluate("(procedure? props->alist)") == .true)
    }

    @Test func alistRefWorks() throws {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else { return }
        try engine.evaluateFile(joinPath(schemePath,"lib/util.scm"))

        #expect(try engine.evaluate("(alist-ref '((a . 1) (b . 2)) 'a)") == .fixnum(1))
        #expect(try engine.evaluate("(alist-ref '((a . 1) (b . 2)) 'b)") == .fixnum(2))
        #expect(try engine.evaluate("(alist-ref '((a . 1)) 'c)") == .false)
        #expect(try engine.evaluate("(alist-ref '((a . 1)) 'c 99)") == .fixnum(99))
    }

    @Test func propsToAlistWorks() throws {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else { return }
        try engine.evaluateFile(joinPath(schemePath,"lib/util.scm"))

        let result = try engine.evaluate("(props->alist 'a 1 'b 2)")
        // Should be ((a . 1) (b . 2))
        #expect(try engine.evaluate("(cdr (assoc 'a (props->alist 'a 1 'b 2)))") == .fixnum(1))
        #expect(try engine.evaluate("(cdr (assoc 'b (props->alist 'a 1 'b 2)))") == .fixnum(2))
    }

    @Test func keymapModuleLoads() throws {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else { return }
        try engine.evaluateFile(joinPath(schemePath,"lib/util.scm"))
        try engine.evaluateFile(joinPath(schemePath,"core/keymap.scm"))

        #expect(try engine.evaluate("(procedure? has-cmd?)") == .true)
        #expect(try engine.evaluate("(procedure? has-shift?)") == .true)
        #expect(try engine.evaluate("(procedure? has-alt?)") == .true)
        #expect(try engine.evaluate("(procedure? has-ctrl?)") == .true)
    }

    @Test func stateMachineModuleLoads() throws {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else { return }
        try engine.evaluateFile(joinPath(schemePath,"lib/util.scm"))
        try engine.evaluateFile(joinPath(schemePath,"core/keymap.scm"))
        try engine.evaluateFile(joinPath(schemePath,"core/state-machine.scm"))

        #expect(try engine.evaluate("(procedure? register-tree!)") == .true)
        #expect(try engine.evaluate("(procedure? lookup-tree)") == .true)
        #expect(try engine.evaluate("(procedure? modal-enter)") == .true)
        #expect(try engine.evaluate("(procedure? modal-exit)") == .true)
        #expect(try engine.evaluate("(procedure? modal-handle-key)") == .true)
        #expect(try engine.evaluate("(procedure? modal-step-back)") == .true)
    }

    @Test func dslModuleLoads() throws {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else { return }
        try engine.evaluateFile(joinPath(schemePath,"lib/util.scm"))
        try engine.evaluateFile(joinPath(schemePath,"core/keymap.scm"))
        try engine.evaluateFile(joinPath(schemePath,"core/state-machine.scm"))
        try engine.evaluateFile(joinPath(schemePath,"core/event-dispatch.scm"))
        try engine.evaluateFile(joinPath(schemePath,"lib/dsl.scm"))

        #expect(try engine.evaluate("(procedure? key)") == .true)
        #expect(try engine.evaluate("(procedure? group)") == .true)
        #expect(try engine.evaluate("(procedure? define-tree)") == .true)
        #expect(try engine.evaluate("(procedure? set-leader!)") == .true)
    }

    // MARK: - Tree registration and lookup

    @Test func registerAndLookupTree() throws {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else { return }
        try engine.evaluateFile(joinPath(schemePath,"lib/util.scm"))
        try engine.evaluateFile(joinPath(schemePath,"core/keymap.scm"))
        try engine.evaluateFile(joinPath(schemePath,"core/state-machine.scm"))
        try engine.evaluateFile(joinPath(schemePath,"core/event-dispatch.scm"))
        try engine.evaluateFile(joinPath(schemePath,"lib/dsl.scm"))

        try engine.evaluate("""
            (define-tree 'global
              (key "s" "Safari" (lambda () 'launched-safari)))
            """)

        let result = try engine.evaluate("(lookup-tree \"global\")")
        #expect(result != .false)
        #expect(try engine.evaluate("(group? (lookup-tree \"global\"))") == .true)
    }

    @Test func registerAppSpecificTree() throws {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else { return }
        try engine.evaluateFile(joinPath(schemePath,"lib/util.scm"))
        try engine.evaluateFile(joinPath(schemePath,"core/keymap.scm"))
        try engine.evaluateFile(joinPath(schemePath,"core/state-machine.scm"))
        try engine.evaluateFile(joinPath(schemePath,"core/event-dispatch.scm"))
        try engine.evaluateFile(joinPath(schemePath,"lib/dsl.scm"))

        try engine.evaluate("""
            (define-tree 'com.apple.Safari
              (key "t" "New Tab" (lambda () 'new-tab)))
            """)

        #expect(try engine.evaluate("(lookup-tree \"com.apple.Safari\")") != .false)
        #expect(try engine.evaluate("(lookup-tree \"nonexistent\")") == .false)
    }

    // MARK: - Modal navigation

    @Test func modalEnterAndExit() throws {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else { return }
        try engine.evaluateFile(joinPath(schemePath,"lib/util.scm"))
        try engine.evaluateFile(joinPath(schemePath,"core/keymap.scm"))
        try engine.evaluateFile(joinPath(schemePath,"core/state-machine.scm"))
        try engine.evaluateFile(joinPath(schemePath,"core/event-dispatch.scm"))
        try engine.evaluateFile(joinPath(schemePath,"lib/dsl.scm"))

        try engine.evaluate("""
            (define-tree 'global
              (key "s" "Safari" (lambda () 'ok)))
            """)

        #expect(try engine.evaluate("modal-active?") == .false)

        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        #expect(try engine.evaluate("modal-active?") == .true)

        // modal-enter registers a catch-all, so unregister it for test cleanup
        try engine.evaluate("(modal-exit)")
        #expect(try engine.evaluate("modal-active?") == .false)
    }

    @Test func modalHandleKeyExecutesCommand() throws {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else { return }
        try engine.evaluateFile(joinPath(schemePath,"lib/util.scm"))
        try engine.evaluateFile(joinPath(schemePath,"core/keymap.scm"))
        try engine.evaluateFile(joinPath(schemePath,"core/state-machine.scm"))
        try engine.evaluateFile(joinPath(schemePath,"core/event-dispatch.scm"))
        try engine.evaluateFile(joinPath(schemePath,"lib/dsl.scm"))

        try engine.evaluate("""
            (define action-called #f)
            (define-tree 'global
              (key "s" "Safari" (lambda () (set! action-called #t))))
            """)

        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        try engine.evaluate("(modal-handle-key \"s\")")

        #expect(try engine.evaluate("action-called") == .true)
        #expect(try engine.evaluate("modal-active?") == .false)
    }

    @Test func modalHandleKeyNavigatesGroup() throws {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else { return }
        try engine.evaluateFile(joinPath(schemePath,"lib/util.scm"))
        try engine.evaluateFile(joinPath(schemePath,"core/keymap.scm"))
        try engine.evaluateFile(joinPath(schemePath,"core/state-machine.scm"))
        try engine.evaluateFile(joinPath(schemePath,"core/event-dispatch.scm"))
        try engine.evaluateFile(joinPath(schemePath,"lib/dsl.scm"))

        try engine.evaluate("""
            (define-tree 'global
              (group "w" "Windows"
                (key "c" "Center" (lambda () 'centered))))
            """)

        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        try engine.evaluate("(modal-handle-key \"w\")")

        #expect(try engine.evaluate("modal-active?") == .true)
        #expect(try engine.evaluate("(equal? modal-current-path '(\"w\"))") == .true)

        try engine.evaluate("(modal-exit)")
    }

    @Test func modalStepBackWorks() throws {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else { return }
        try engine.evaluateFile(joinPath(schemePath,"lib/util.scm"))
        try engine.evaluateFile(joinPath(schemePath,"core/keymap.scm"))
        try engine.evaluateFile(joinPath(schemePath,"core/state-machine.scm"))
        try engine.evaluateFile(joinPath(schemePath,"core/event-dispatch.scm"))
        try engine.evaluateFile(joinPath(schemePath,"lib/dsl.scm"))

        try engine.evaluate("""
            (define-tree 'global
              (group "w" "Windows"
                (key "c" "Center" (lambda () 'centered))))
            """)

        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        try engine.evaluate("(modal-handle-key \"w\")")
        try engine.evaluate("(modal-step-back)")

        #expect(try engine.evaluate("modal-active?") == .true)
        #expect(try engine.evaluate("(null? modal-current-path)") == .true)

        try engine.evaluate("(modal-exit)")
    }

    @Test func modalStepBackFromRootExits() throws {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else { return }
        try engine.evaluateFile(joinPath(schemePath,"lib/util.scm"))
        try engine.evaluateFile(joinPath(schemePath,"core/keymap.scm"))
        try engine.evaluateFile(joinPath(schemePath,"core/state-machine.scm"))
        try engine.evaluateFile(joinPath(schemePath,"core/event-dispatch.scm"))
        try engine.evaluateFile(joinPath(schemePath,"lib/dsl.scm"))

        try engine.evaluate("""
            (define-tree 'global
              (key "s" "Safari" (lambda () 'ok)))
            """)

        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        try engine.evaluate("(modal-step-back)")

        #expect(try engine.evaluate("modal-active?") == .false)
    }

    // MARK: - DSL integration

    @Test func setLeaderRegistersHotkey() throws {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else { return }
        try engine.evaluateFile(joinPath(schemePath,"lib/util.scm"))
        try engine.evaluateFile(joinPath(schemePath,"core/keymap.scm"))
        try engine.evaluateFile(joinPath(schemePath,"core/state-machine.scm"))
        try engine.evaluateFile(joinPath(schemePath,"core/event-dispatch.scm"))
        try engine.evaluateFile(joinPath(schemePath,"lib/dsl.scm"))

        try engine.evaluate("""
            (define-tree 'global
              (key "s" "Safari" (lambda () 'ok)))
            (set-leader! F18)
            """)

        // Verify the hotkey was registered in the keyboard library
        let keyboardLib = try engine.context.libraries.lookup(KeyboardLibrary.self)
        #expect(keyboardLib?.handlerRegistry.hotkeyHandlers[KeyCode.f18] != nil)
    }

    @Test func fullLifecycleViaSchemeModules() throws {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else { return }
        try engine.evaluateFile(joinPath(schemePath,"lib/util.scm"))
        try engine.evaluateFile(joinPath(schemePath,"core/keymap.scm"))
        try engine.evaluateFile(joinPath(schemePath,"core/state-machine.scm"))
        try engine.evaluateFile(joinPath(schemePath,"core/event-dispatch.scm"))
        try engine.evaluateFile(joinPath(schemePath,"lib/dsl.scm"))

        try engine.evaluate("""
            (define test-action-log '())
            (define-tree 'global
              (key "s" "Safari" (lambda () (set! test-action-log (cons 'safari test-action-log))))
              (group "w" "Windows"
                (key "c" "Center" (lambda () (set! test-action-log (cons 'center test-action-log))))))
            """)

        // Simulate full flow: enter → navigate group → execute command
        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        #expect(try engine.evaluate("modal-active?") == .true)

        try engine.evaluate("(modal-handle-key \"w\")")
        #expect(try engine.evaluate("modal-active?") == .true)

        try engine.evaluate("(modal-handle-key \"c\")")
        #expect(try engine.evaluate("modal-active?") == .false)
        #expect(try engine.evaluate("(car test-action-log)") == .symbol(engine.context.symbols.intern("center")))
    }

    @Test func appSpecificTreeOverridesGlobal() throws {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else { return }
        try engine.evaluateFile(joinPath(schemePath,"lib/util.scm"))
        try engine.evaluateFile(joinPath(schemePath,"core/keymap.scm"))
        try engine.evaluateFile(joinPath(schemePath,"core/state-machine.scm"))
        try engine.evaluateFile(joinPath(schemePath,"core/event-dispatch.scm"))
        try engine.evaluateFile(joinPath(schemePath,"lib/dsl.scm"))

        try engine.evaluate("""
            (define which-tree #f)
            (define-tree 'global
              (key "s" "Safari" (lambda () (set! which-tree 'global))))
            (define-tree 'com.apple.Safari
              (key "t" "Tab" (lambda () (set! which-tree 'safari))))
            """)

        // App-specific tree should be found for Safari
        let safariTree = try engine.evaluate("(lookup-tree \"com.apple.Safari\")")
        #expect(safariTree != .false)

        // Global should still exist
        let globalTree = try engine.evaluate("(lookup-tree \"global\")")
        #expect(globalTree != .false)

        // The make-leader-handler uses (or app-tree global-tree), test that logic
        try engine.evaluate("""
            (let ((tree (or (lookup-tree "com.apple.Safari") (lookup-tree "global"))))
              (modal-enter tree F18))
            """)
        try engine.evaluate("(modal-handle-key \"t\")")
        #expect(try engine.evaluate("which-tree") == .symbol(engine.context.symbols.intern("safari")))
    }

    @Test func modalNoBindingExits() throws {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else { return }
        try engine.evaluateFile(joinPath(schemePath,"lib/util.scm"))
        try engine.evaluateFile(joinPath(schemePath,"core/keymap.scm"))
        try engine.evaluateFile(joinPath(schemePath,"core/state-machine.scm"))
        try engine.evaluateFile(joinPath(schemePath,"core/event-dispatch.scm"))
        try engine.evaluateFile(joinPath(schemePath,"lib/dsl.scm"))

        try engine.evaluate("""
            (define-tree 'global
              (key "s" "Safari" (lambda () 'ok)))
            """)

        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        try engine.evaluate("(modal-handle-key \"x\")")

        #expect(try engine.evaluate("modal-active?") == .false)
    }
}
