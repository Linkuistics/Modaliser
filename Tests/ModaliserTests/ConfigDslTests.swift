import Foundation
import Testing
import LispKit
@testable import Modaliser

private func joinPath(_ base: String, _ component: String) -> String {
    base.hasSuffix("/") ? base + component : base + "/" + component
}

@Suite("Config DSL (selector, action, theming)")
struct ConfigDslTests {

    private func loadDsl() throws -> SchemeEngine {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("Scheme directory not found")
            throw SchemeTestError.noSchemeDir
        }
        let files = [
            "lib/util.scm",
            "core/keymap.scm",
            "core/state-machine.scm",
            "core/event-dispatch.scm",
            "lib/dsl.scm",
        ]
        for file in files {
            try engine.evaluateFile(joinPath(schemePath, file))
        }
        return engine
    }

    private func loadAllModules() throws -> SchemeEngine {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else {
            Issue.record("Scheme directory not found")
            throw SchemeTestError.noSchemeDir
        }
        // Stub WebView primitives
        try engine.evaluate("""
            (define webview-create-calls '())
            (define webview-close-calls '())
            (define webview-set-html-calls '())
            (define (webview-create id opts)
              (set! webview-create-calls (cons id webview-create-calls)) id)
            (define (webview-close id)
              (set! webview-close-calls (cons id webview-close-calls)))
            (define (webview-set-html! id html)
              (set! webview-set-html-calls (cons (cons id html) webview-set-html-calls)))
            (define (webview-on-message id handler) #t)
            (define (webview-eval id js) #t)
            """)
        let files = [
            "lib/util.scm",
            "lib/terminal.scm",
            "core/keymap.scm",
            "ui/dom.scm",
            "ui/css.scm",
            "core/state-machine.scm",
            "core/event-dispatch.scm",
            "ui/overlay.scm",
            "ui/chooser.scm",
            "lib/dsl.scm",
            "lib/web-search.scm",
            "lib/iterm.scm",
        ]
        for file in files {
            try engine.evaluateFile(joinPath(schemePath, file))
        }
        return engine
    }

    // MARK: - selector function

    @Test func selectorProducesCorrectAlist() throws {
        let engine = try loadDsl()
        try engine.evaluate("""
            (define test-sel (selector "a" "Find Apps" 'prompt "Find app…" 'remember "apps"))
            """)
        #expect(try engine.evaluate("(cdr (assoc 'kind test-sel))") == .symbol(engine.context.symbols.intern("selector")))
        #expect(try engine.evaluate("(cdr (assoc 'key test-sel))").asString() == "a")
        #expect(try engine.evaluate("(cdr (assoc 'label test-sel))").asString() == "Find Apps")
        #expect(try engine.evaluate("(cdr (assoc 'prompt test-sel))").asString() == "Find app…")
        #expect(try engine.evaluate("(cdr (assoc 'remember test-sel))").asString() == "apps")
    }

    @Test func selectorIsRecognizedByPredicate() throws {
        let engine = try loadDsl()
        try engine.evaluate("""
            (define test-sel (selector "a" "Find Apps" 'prompt "Search…"))
            """)
        #expect(try engine.evaluate("(selector? test-sel)") == .true)
        #expect(try engine.evaluate("(command? test-sel)") == .false)
        #expect(try engine.evaluate("(group? test-sel)") == .false)
    }

    @Test func selectorWithSourceAndOnSelect() throws {
        let engine = try loadDsl()
        try engine.evaluate("""
            (define my-source (lambda () '(("a" "b"))))
            (define my-handler (lambda (c) c))
            (define test-sel (selector "f" "Find File"
              'source my-source
              'on-select my-handler))
            """)
        #expect(try engine.evaluate("(procedure? (cdr (assoc 'source test-sel)))") == .true)
        #expect(try engine.evaluate("(procedure? (cdr (assoc 'on-select test-sel)))") == .true)
    }

    @Test func selectorWithActionsListContainingActionNodes() throws {
        let engine = try loadDsl()
        try engine.evaluate("""
            (define test-sel (selector "a" "Find Apps"
              'prompt "Find app…"
              'actions (list
                (action "Open" 'description "Launch" 'key 'primary)
                (action "Reveal" 'description "Show in Finder" 'key 'secondary))))
            """)
        let result = try engine.evaluate("(cdr (assoc 'actions test-sel))")
        #expect(result != .false)
        // Verify first action has correct structure
        #expect(try engine.evaluate("""
            (cdr (assoc 'name (car (cdr (assoc 'actions test-sel)))))
            """).asString() == "Open")
    }

    // MARK: - action function

    @Test func actionProducesCorrectAlist() throws {
        let engine = try loadDsl()
        try engine.evaluate("""
            (define test-act (action "Open" 'description "Launch or focus" 'key 'primary))
            """)
        #expect(try engine.evaluate("(cdr (assoc 'name test-act))").asString() == "Open")
        #expect(try engine.evaluate("(cdr (assoc 'description test-act))").asString() == "Launch or focus")
        #expect(try engine.evaluate("(cdr (assoc 'key test-act))") == .symbol(engine.context.symbols.intern("primary")))
    }

    @Test func actionWithRunLambda() throws {
        let engine = try loadDsl()
        try engine.evaluate("""
            (define test-act (action "Copy Path"
              'description "Copy full path"
              'run (lambda (c) (string-append "copied:" c))))
            """)
        #expect(try engine.evaluate("(procedure? (cdr (assoc 'run test-act)))") == .true)
        // Verify the lambda works
        #expect(try engine.evaluate("""
            ((cdr (assoc 'run test-act)) "/foo/bar")
            """).asString() == "copied:/foo/bar")
    }

    // MARK: - selector in tree (state machine integration)

    @Test func selectorInTreeExitsModalOnSelect() throws {
        let engine = try loadAllModules()
        try engine.evaluate("""
            (define-tree 'global
              (selector "f" "Find File"
                'prompt "Search…"
                'source (lambda () '())))
            """)
        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        #expect(try engine.evaluate("modal-active?") == .true)

        // Pressing 'f' hits the selector — currently exits modal (chooser is Phase 4)
        try engine.evaluate("(modal-handle-key \"f\")")
        #expect(try engine.evaluate("modal-active?") == .false)
        #expect(try engine.evaluate("overlay-open?") == .false)
    }

    @Test func selectorInGroupNavigationWorks() throws {
        let engine = try loadAllModules()
        try engine.evaluate("""
            (define-tree 'global
              (group "f" "Find"
                (selector "a" "Find Apps"
                  'prompt "Find app…"
                  'source (lambda () '()))
                (key "e" "Emoji" (lambda () 'ok))))
            """)
        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        try engine.evaluate("(modal-handle-key \"f\")")
        #expect(try engine.evaluate("modal-active?") == .true)

        // Now at "Find" group, pressing 'a' hits selector
        try engine.evaluate("(modal-handle-key \"a\")")
        #expect(try engine.evaluate("modal-active?") == .false)
    }

    // MARK: - set-theme! backward compatibility

    @Test func setThemeIsNoOp() throws {
        let engine = try loadDsl()
        // set-theme! should exist and not error
        try engine.evaluate("(set-theme! 'background \"#fff\" 'foreground \"#000\")")
        // No crash = pass
    }

    // MARK: - CSS theming

    @Test func setOverlayCssStoresCustomCss() throws {
        let engine = try loadAllModules()
        try engine.evaluate("""
            (set-overlay-css! ":root { --overlay-bg: #333; }")
            """)
        #expect(try engine.evaluate("overlay-custom-css").asString() == ":root { --overlay-bg: #333; }")
    }

    @Test func customCssAppearsInRenderedOverlay() throws {
        let engine = try loadAllModules()
        try engine.evaluate("""
            (set-overlay-css! ":root { --overlay-bg: #333; }")
            (define-tree 'global (key "s" "Safari" (lambda () 'ok)))
            """)
        let html = try engine.evaluate("""
            (render-overlay-html (lookup-tree "global") '("Global") '())
            """).asString()
        #expect(html.contains("--overlay-bg: #333"))
    }

    // MARK: - Config loading

    @Test func defaultConfigSchemeLoadsWithoutErrors() throws {
        let engine = try loadAllModules()
        guard let schemePath = engine.schemeDirectoryPath else {
            throw SchemeTestError.noSchemeDir
        }
        let configPath = schemePath + "/default-config.scm"
        try engine.evaluateFile(configPath)

        // Verify trees were registered from config
        #expect(try engine.evaluate("(lookup-tree \"global\")") != .false)
        #expect(try engine.evaluate("(lookup-tree \"com.apple.Safari\")") != .false)
        #expect(try engine.evaluate("(lookup-tree \"dev.zed.Zed\")") != .false)
        #expect(try engine.evaluate("(lookup-tree \"com.googlecode.iterm2\")") != .false)

        // Verify hotkeys registered
        let kbLib = try engine.context.libraries.lookup(KeyboardLibrary.self)!
        #expect(kbLib.handlerRegistry.hotkeyHandlers[HotkeyKey(keyCode: KeyCode.f18, modifiers: [])] != nil)
        #expect(kbLib.handlerRegistry.hotkeyHandlers[HotkeyKey(keyCode: KeyCode.f17, modifiers: [])] != nil)
    }

    // MARK: - Config-like pattern

    @Test func fullConfigPatternLoads() throws {
        let engine = try loadAllModules()
        // Simulate a config.scm-like structure with selectors and actions
        try engine.evaluate("""
            (set-leader! 'global F18)
            (set-leader! 'local F17)

            (define-tree 'global
              (key "s" "Safari" (lambda () 'ok))
              (group "f" "Find"
                (selector "a" "Find Apps"
                  'prompt "Find app…"
                  'source (lambda () '())
                  'on-select (lambda (c) c)
                  'actions (list
                    (action "Open" 'description "Launch" 'key 'primary
                      'run (lambda (c) c))
                    (action "Reveal" 'description "Show in Finder" 'key 'secondary
                      'run (lambda (c) c))))
                (key "e" "Emoji" (lambda () 'ok)))
              (group "w" "Windows"
                (key "c" "Center" (lambda () 'ok))
                (selector "s" "Switch Window"
                  'prompt "Select window…"
                  'source (lambda () '())
                  'on-select (lambda (c) c))))

            (define-tree 'com.apple.Safari
              (group "t" "Tabs"
                (key "n" "New Tab" (lambda () 'ok))))
            """)

        // Verify trees registered correctly
        #expect(try engine.evaluate("(lookup-tree \"global\")") != .false)
        #expect(try engine.evaluate("(lookup-tree \"com.apple.Safari\")") != .false)

        // Verify hotkeys registered
        let kbLib = try engine.context.libraries.lookup(KeyboardLibrary.self)!
        #expect(kbLib.handlerRegistry.hotkeyHandlers[HotkeyKey(keyCode: KeyCode.f18, modifiers: [])] != nil)
        #expect(kbLib.handlerRegistry.hotkeyHandlers[HotkeyKey(keyCode: KeyCode.f17, modifiers: [])] != nil)
    }

    // MARK: - set-leader! keyword args (modifiers, passthrough)

    @Test func setLeaderWithModifiersRegistersUnderModifierKey() throws {
        let engine = try loadAllModules()
        try engine.evaluate("(set-leader! 'global F18 'modifiers '(shift))")
        let kbLib = try engine.context.libraries.lookup(KeyboardLibrary.self)!
        #expect(kbLib.handlerRegistry.hotkeyHandlers[
            HotkeyKey(keyCode: KeyCode.f18, modifiers: [.maskShift])] != nil)
        #expect(kbLib.handlerRegistry.hotkeyHandlers[
            HotkeyKey(keyCode: KeyCode.f18, modifiers: [])] == nil)
    }

    @Test func setLeaderWithPassthroughRegistersBundleIds() throws {
        let engine = try loadAllModules()
        try engine.evaluate("""
            (set-leader! 'global F18
                         'passthrough-when-frontmost '("com.jumpdesktop.Jump-Desktop"))
            """)
        let kbLib = try engine.context.libraries.lookup(KeyboardLibrary.self)!
        let entry = kbLib.handlerRegistry.hotkeyHandlers[
            HotkeyKey(keyCode: KeyCode.f18, modifiers: [])]
        #expect(entry?.passthroughBundleIds == ["com.jumpdesktop.Jump-Desktop"])
    }

    @Test func setLeaderAcceptsBothKeywordsInEitherOrder() throws {
        let engine = try loadAllModules()
        try engine.evaluate("""
            (set-leader! 'global F18
                         'passthrough-when-frontmost '("com.foo")
                         'modifiers '(shift ctrl))
            """)
        let kbLib = try engine.context.libraries.lookup(KeyboardLibrary.self)!
        let entry = kbLib.handlerRegistry.hotkeyHandlers[
            HotkeyKey(keyCode: KeyCode.f18, modifiers: [.maskShift, .maskControl])]
        #expect(entry != nil)
        #expect(entry?.passthroughBundleIds == ["com.foo"])
    }

    @Test func setLeaderSingleArgFormStillWorks() throws {
        let engine = try loadAllModules()
        try engine.evaluate("(set-leader! F18)")
        let kbLib = try engine.context.libraries.lookup(KeyboardLibrary.self)!
        #expect(kbLib.handlerRegistry.hotkeyHandlers[
            HotkeyKey(keyCode: KeyCode.f18, modifiers: [])] != nil)
    }

    @Test func setLeaderSingleArgFormAcceptsModifiers() throws {
        let engine = try loadAllModules()
        try engine.evaluate("(set-leader! F18 'modifiers '(shift))")
        let kbLib = try engine.context.libraries.lookup(KeyboardLibrary.self)!
        #expect(kbLib.handlerRegistry.hotkeyHandlers[
            HotkeyKey(keyCode: KeyCode.f18, modifiers: [.maskShift])] != nil)
    }

    @Test func setLeaderUnknownKeywordRaisesError() throws {
        let engine = try loadAllModules()
        #expect(throws: (any Error).self) {
            try engine.evaluate("(set-leader! 'global F18 'frob 1)")
        }
    }
}
