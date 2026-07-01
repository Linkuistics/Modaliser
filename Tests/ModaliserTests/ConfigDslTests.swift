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
        try engine.evaluate("""
          (import (modaliser util)
                  (modaliser keymap)
                  (modaliser state-machine))
        """)
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")
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
        try engine.evaluate("""
          (import (modaliser util)
                  (modaliser keymap)
                  (modaliser state-machine))
        """)
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")
        try engine.evaluate("(import (modaliser terminal))")
        try engine.evaluate("(import (modaliser ax-hints))")
        try engine.evaluate("(import (modaliser dom))")
        try engine.evaluate("(import (modaliser web-search))")
        let files = [
            "ui/css.scm",
            "ui/overlay.scm",
            "ui/chooser.scm",
        ]
        for file in files {
            try engine.evaluateFile(joinPath(schemePath, file))
        }
        // Wire the chooser-push injection (mirrors root.scm).
        try engine.evaluate("(set-chooser-push! chooser-push-results)")
        return engine
    }

    // MARK: - selector function

    @Test func selectorProducesCorrectAlist() throws {
        let engine = try loadDsl()
        // selector is undecorated; (key K L (selector …)) injects key/label.
        try engine.evaluate("""
            (define test-sel (key "a" "Find Apps"
              (selector 'prompt "Find app…" 'remember "apps")))
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
            (define test-sel (key "a" "Find Apps" (selector 'prompt "Search…")))
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
            (define test-sel (key "f" "Find File"
              (selector 'source my-source 'on-select my-handler)))
            """)
        #expect(try engine.evaluate("(procedure? (cdr (assoc 'source test-sel)))") == .true)
        #expect(try engine.evaluate("(procedure? (cdr (assoc 'on-select test-sel)))") == .true)
    }

    @Test func selectorWithActionsListContainingActionNodes() throws {
        let engine = try loadDsl()
        try engine.evaluate("""
            (define test-sel (key "a" "Find Apps"
              (selector 'prompt "Find app…"
                        'actions (list
                          (action "Open" 'description "Launch" 'key 'primary)
                          (action "Reveal" 'description "Show in Finder" 'key 'secondary)))))
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
            (register-tree! 'global
              (key "f" "Find File"
                (selector 'prompt "Search…" 'source (lambda () '()))))
            """)
        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        #expect(try engine.evaluate("modal-active?") == .true)

        // Pressing 'f' hits the selector — currently exits modal (chooser is Phase 4)
        try engine.evaluate("(modal-handle-key \"f\")")
        #expect(try engine.evaluate("modal-active?") == .false)
        #expect(try engine.evaluate("(overlay-open?)") == .false)
    }

    @Test func selectorInGroupNavigationWorks() throws {
        let engine = try loadAllModules()
        try engine.evaluate("""
            (register-tree! 'global
              (group "f" "Find"
                (key "a" "Find Apps"
                  (selector 'prompt "Find app…" 'source (lambda () '())))
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

    // user-theme-css is populated at boot by root.scm slurping
    // ~/.config/modaliser/theme.css. The setter (set-overlay-css!) was
    // removed in the chip-theming refactor — CSS authoring moved to a real
    // .css file. Tests poke the variable directly to verify the cascade.

    @Test func customCssAppearsInRenderedOverlay() throws {
        let engine = try loadAllModules()
        try engine.evaluate("""
            (set! user-theme-css ":root { --overlay-bg: #333; }")
            (register-tree! 'global (key "s" "Safari" (lambda () 'ok)))
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
        #expect(try engine.evaluate("(lookup-tree \"com.googlecode.iterm2\")") != .false)

        // Verify hotkeys registered
        let kbLib = try engine.context.libraries.lookup(KeyboardLibrary.self)!
        #expect(kbLib.handlerRegistry.hotkeyHandlers[HotkeyKey(keyCode: KeyCode.f18, modifiers: [])] != nil)
        #expect(kbLib.handlerRegistry.hotkeyHandlers[HotkeyKey(keyCode: KeyCode.f17, modifiers: [])] != nil)
    }

    // MARK: - Migrated bundled config renders as panels (config-migration-k8)

    /// The bundled global tree, migrated to the layout DSL, registers as a
    /// panel-grid SCREEN whose grid is the authored panels — and a command
    /// stays reachable by its original key through the (transparent) panel, so
    /// dispatch is unchanged by the presentation restructure. After
    /// bare-loose-rows-k23 the former "General" panel is unwrapped: its keys
    /// (and the Windows drill-in) render BARE in the loose region, not a card.
    @Test func defaultGlobalTreeRendersAsPanelGrid() throws {
        let engine = try loadAllModules()
        guard let schemePath = engine.schemeDirectoryPath else { throw SchemeTestError.noSchemeDir }
        try engine.evaluateFile(schemePath + "/default-config.scm")

        // Registered as a panel-grid screen, not the legacy auto-layout.
        #expect(try engine.evaluate("(eq? (node-renderer (lookup-tree \"global\")) 'panel-grid)") == .true)

        // The top-level grid serialises the authored panels. (The top level
        // embeds no live-list block — the windows list lives a level down under
        // "w" — so this render fires no on-render side effects.)
        let json = try engine.evaluate("(panel-grid-payload-json (lookup-tree \"global\"))").asString()
        #expect(json.contains("\"type\":\"panel-grid\""))
        for label in ["Applications", "AI", "Search"] {
            #expect(json.contains("\"label\":\"\(label)\""), "missing panel \(label)")
        }
        // No "General" card — those keys moved to the loose region.
        #expect(!json.contains("\"label\":\"General\""))
        #expect(json.contains("\"loose\":["))
        #expect(json.contains("\"label\":\"Settings\""))
        #expect(json.contains("\"label\":\"Highlight Cursor\""))
        // The top-level Windows `open` folds into the loose region as a drill row.
        #expect(json.contains("\"label\":\"Windows\""))

        // Transparent dispatch preserved: "b" (Browser) keeps its path
        // through the Applications panel; "w" is the navigable Windows
        // drill-down (an `open`, lowered to a group).
        #expect(try engine.evaluate("(command? (find-child (lookup-tree \"global\") \"b\"))") == .true)
        #expect(try engine.evaluate("(equal? (node-label (find-child (lookup-tree \"global\") \"b\")) \"Browser\")") == .true)
        #expect(try engine.evaluate("(group? (find-child (lookup-tree \"global\") \"w\"))") == .true)
    }

    /// The "w" Windows drill-down renders as a panel grid: a headerless
    /// diagram panel, a Select panel (select/restore), a Windows panel (the
    /// live window list + chips), and a Displays panel (the display list +
    /// chips). Panels are transparent for dispatch, so the diagram's
    /// move-window keys and the Select panel's s/r keys keep their paths.
    @Test func defaultWindowsScreenRendersAsPanelGrid() throws {
        let engine = try loadAllModules()
        guard let schemePath = engine.schemeDirectoryPath else { throw SchemeTestError.noSchemeDir }
        try engine.evaluateFile(schemePath + "/default-config.scm")

        try engine.evaluate("""
          (define win (find-child (lookup-tree "global") "w"))
          (define (grid-panel root lbl)
            (let loop ((cs (node-children root)))
              (cond ((null? cs) #f)
                    ((and (category? (car cs)) (equal? (node-label (car cs)) lbl)) (car cs))
                    (else (loop (cdr cs))))))
        """)
        #expect(try engine.evaluate("(eq? (node-renderer win) 'panel-grid)") == .true)

        // The Select / Windows / Displays panels are present…
        #expect(try engine.evaluate("(category? (grid-panel win \"Select\"))") == .true)
        #expect(try engine.evaluate("(category? (grid-panel win \"Windows\"))") == .true)
        #expect(try engine.evaluate("(category? (grid-panel win \"Displays\"))") == .true)
        // …with the live window list under Windows and the display list under Displays.
        #expect(try engine.evaluate(
            "(eq? (cdr (assoc 'type (node-renderer-payload (grid-panel win \"Windows\") 'list))) 'window-list)") == .true)
        #expect(try engine.evaluate(
            "(eq? (cdr (assoc 'type (node-renderer-payload (grid-panel win \"Displays\") 'list))) 'display-list)") == .true)

        // Transparent dispatch preserved: move-window "d" (lifted from the
        // headerless diagram panel) and the Select panel's s/r keep their paths.
        #expect(try engine.evaluate("(command? (find-child win \"d\"))") == .true)
        #expect(try engine.evaluate("(selector? (find-child win \"s\"))") == .true)
        #expect(try engine.evaluate("(command? (find-child win \"r\"))") == .true)
    }

    @Test func defaultConfigWiresDisplayListBlock() throws {
        // The bundled default config must import the display-actions prefix and
        // embed the display-list block in the Windows sub-screen. Assert the
        // library + block are reachable the way the config uses them.
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (prefix (modaliser display-actions) display:))")
        try engine.evaluate("(define b (display:display-list-block 'chips? #t))")
        #expect(try engine.evaluate("(eq? (cdr (assoc 'type b)) 'display-list)") == .true)
        #expect(try engine.evaluate("(pair? (assoc 'block-children b))") == .true)
    }

    /// At least one per-app tree (iTerm) migrated to panels: a panel-grid
    /// screen whose grid carries the Splits / Panes panels, with the live pane
    /// list embedded, and whose commands keep their keys (transparent
    /// dispatch). Asserted structurally so the test never depends on a live
    /// iTerm (the pane block's on-render-fn talks to the app).
    @Test func defaultItermTreeRendersAsPanelGrid() throws {
        let engine = try loadAllModules()
        guard let schemePath = engine.schemeDirectoryPath else { throw SchemeTestError.noSchemeDir }
        try engine.evaluateFile(schemePath + "/default-config.scm")

        try engine.evaluate("""
          (define (grid-panel root lbl)
            (let loop ((cs (node-children root)))
              (cond ((null? cs) #f)
                    ((and (category? (car cs)) (equal? (node-label (car cs)) lbl)) (car cs))
                    (else (loop (cdr cs))))))
          (define it (lookup-tree "com.googlecode.iterm2"))
        """)
        #expect(try engine.evaluate("(eq? (node-renderer it) 'panel-grid)") == .true)
        #expect(try engine.evaluate("(category? (grid-panel it \"Splits\"))") == .true)
        // Panes panel embeds the live pane list under 'list (no render here,
        // so the on-render-fn never fires — purely structural).
        #expect(try engine.evaluate(
            "(eq? (cdr (assoc 'type (node-renderer-payload (grid-panel it \"Panes\") 'list))) 'iterm-panes)") == .true)
        // Transparent dispatch: "c" (Copy Mode) keeps its path; "t" is the
        // navigable Tab drill-down (an `open` → group).
        #expect(try engine.evaluate("(command? (find-child it \"c\"))") == .true)
        #expect(try engine.evaluate("(group? (find-child it \"t\"))") == .true)
    }

    // MARK: - Config-like pattern

    @Test func fullConfigPatternLoads() throws {
        let engine = try loadAllModules()
        // Simulate a config.scm-like structure with selectors and actions
        try engine.evaluate("""
            (set-leader! 'global F18)
            (set-leader! 'local F17)

            (register-tree! 'global
              (key "s" "Safari" (lambda () 'ok))
              (group "f" "Find"
                (key "a" "Find Apps"
                  (selector 'prompt "Find app…"
                            'source (lambda () '())
                            'on-select (lambda (c) c)
                            'actions (list
                              (action "Open" 'description "Launch" 'key 'primary
                                'run (lambda (c) c))
                              (action "Reveal" 'description "Show in Finder" 'key 'secondary
                                'run (lambda (c) c)))))
                (key "e" "Emoji" (lambda () 'ok)))
              (group "w" "Windows"
                (key "c" "Center" (lambda () 'ok))
                (key "s" "Switch Window"
                  (selector 'prompt "Select window…"
                            'source (lambda () '())
                            'on-select (lambda (c) c)))))

            (register-tree! 'com.apple.Safari
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

    // MARK: - set-leader! keyword args (modifiers, arm-when-frontmost)

    @Test func setLeaderWithModifiersRegistersUnderModifierKey() throws {
        let engine = try loadAllModules()
        try engine.evaluate("(set-leader! 'global F18 'modifiers '(shift))")
        let kbLib = try engine.context.libraries.lookup(KeyboardLibrary.self)!
        #expect(kbLib.handlerRegistry.hotkeyHandlers[
            HotkeyKey(keyCode: KeyCode.f18, modifiers: [.maskShift])] != nil)
        #expect(kbLib.handlerRegistry.hotkeyHandlers[
            HotkeyKey(keyCode: KeyCode.f18, modifiers: [])] == nil)
    }

    @Test func setLeaderWithArmBundleIdsRegistersBundleIds() throws {
        let engine = try loadAllModules()
        try engine.evaluate("""
            (set-leader! 'global F18
                         'arm-when-frontmost '("com.jumpdesktop.Jump-Desktop"))
            """)
        let kbLib = try engine.context.libraries.lookup(KeyboardLibrary.self)!
        let entry = kbLib.handlerRegistry.hotkeyHandlers[
            HotkeyKey(keyCode: KeyCode.f18, modifiers: [])]
        #expect(entry?.armBundleIds == ["com.jumpdesktop.Jump-Desktop"])
    }

    @Test func setLeaderAcceptsBothKeywordsInEitherOrder() throws {
        let engine = try loadAllModules()
        try engine.evaluate("""
            (set-leader! 'global F18
                         'arm-when-frontmost '("com.foo")
                         'modifiers '(shift ctrl))
            """)
        let kbLib = try engine.context.libraries.lookup(KeyboardLibrary.self)!
        let entry = kbLib.handlerRegistry.hotkeyHandlers[
            HotkeyKey(keyCode: KeyCode.f18, modifiers: [.maskShift, .maskControl])]
        #expect(entry != nil)
        #expect(entry?.armBundleIds == ["com.foo"])
    }

    // MARK: - set-leader! requires an explicit mode

    @Test func setLeaderWithoutModeRaisesError() throws {
        let engine = try loadAllModules()
        // The mode ('global / 'local) is required — a bare keycode
        // must not be accepted.
        #expect(throws: (any Error).self) {
            try engine.evaluate("(set-leader! F18)")
        }
    }

    @Test func setLeaderOmittedModeWithKeywordsRaisesError() throws {
        let engine = try loadAllModules()
        // A missing mode is an error even when keyword args follow.
        #expect(throws: (any Error).self) {
            try engine.evaluate("(set-leader! F18 'modifiers '(shift))")
        }
    }

    @Test func setLeaderUnknownKeywordRaisesError() throws {
        let engine = try loadAllModules()
        #expect(throws: (any Error).self) {
            try engine.evaluate("(set-leader! 'global F18 'frob 1)")
        }
    }

    @Test func keyStoresStickyTargetOption() throws {
        let engine = try loadDsl()
        try engine.evaluate("(define k (key \"h\" \"Left\" (lambda () 'ok) 'sticky-target 'iterm-panes-focus))")
        #expect(try engine.evaluate("(eq? (node-sticky-target k) 'iterm-panes-focus)") == .true)
    }

    @Test func keyWithoutStickyTargetReturnsFalse() throws {
        let engine = try loadDsl()
        try engine.evaluate("(define k (key \"h\" \"Left\" (lambda () 'ok)))")
        #expect(try engine.evaluate("(node-sticky-target k)") == .false)
    }

    @Test func keyRejectsUnknownTrailingKeyword() throws {
        let engine = try loadDsl()
        #expect(throws: (any Error).self) {
            try engine.evaluate("(key \"h\" \"Left\" (lambda () 'ok) 'frob 1)")
        }
    }

    @Test func stickyTargetKeyTransitionsModalIntoNamedMode() throws {
        // After firing a sticky-target key's action, modal-handle-key
        // should leave the modal active and reset its root to the named
        // sticky mode tree — so subsequent presses act inside that mode
        // without another leader.
        let engine = try loadAllModules()
        try engine.evaluate("""
            (define fired '())
            (register-tree! 'iterm-focus-test
              'sticky #t
              'display-name "Focus"
              (key "h" "Left" (lambda () (set! fired (cons 'left fired)))))
            (register-tree! 'transient-test
              (key "h" "Focus Left"
                (lambda () (set! fired (cons 'transient-left fired)))
                'sticky-target 'iterm-focus-test))
            """)
        try engine.evaluate("(modal-enter (lookup-tree \"transient-test\") F18)")
        try engine.evaluate("(modal-handle-key \"h\")")
        // The transient action fired
        #expect(try engine.evaluate("(equal? (car fired) 'transient-left)") == .true)
        // Modal is still active, now rooted at the sticky tree
        #expect(try engine.evaluate("modal-active?") == .true)
        #expect(try engine.evaluate("(eq? modal-root-node (lookup-tree \"iterm-focus-test\"))") == .true)
    }

    @Test func twoLiveListBlocksInOnePanelIsRejected() throws {
        // Regression guard (display-window-commands live-config bug): make-panel-node
        // allows AT MOST ONE embedded live-list block, so window:list-block and
        // display:display-list-block in the SAME panel raise at config-load time.
        // The user's panel-structured ~/.config/modaliser/config.scm hit exactly
        // this — config load threw, so the overlay never appeared. Fix: separate panels.
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (prefix (modaliser window-actions) window:) (prefix (modaliser display-actions) display:))")
        #expect(throws: (any Error).self) {
            try engine.evaluate("""
              (panel "Windows"
                (window:list-block 'chips? #t)
                (display:display-list-block 'chips? #t))
            """)
        }
    }

    @Test func windowAndDisplayListsInSeparatePanelsBuild() throws {
        // The fix shape: each live-list block in its OWN panel builds cleanly
        // (no error), both as 'category nodes that carry their embedded 'list.
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (prefix (modaliser window-actions) window:) (prefix (modaliser display-actions) display:))")
        try engine.evaluate("(define pw (panel \"Windows\" (window:list-block 'chips? #t)))")
        try engine.evaluate("(define pd (panel \"Displays\" (display:display-list-block 'chips? #t)))")
        #expect(try engine.evaluate("(eq? (cdr (assoc 'kind pw)) 'category)") == .true)
        #expect(try engine.evaluate("(eq? (cdr (assoc 'kind pd)) 'category)") == .true)
        #expect(try engine.evaluate("(pair? (assoc 'list pw))") == .true)
        #expect(try engine.evaluate("(pair? (assoc 'list pd))") == .true)
    }
}
