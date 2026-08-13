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
                  (modaliser fsm))
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
                  (modaliser fsm)
                  (modaliser configuration)
                  (modaliser fsm)
                  (modaliser handoff))
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
            (fsm-install-graph! (lower-configuration (configuration
              (tree 'global
                (tree-root 'global
                  (key "f" "Find File"
                    (selector 'prompt "Search…" 'source (lambda () '()))))))))
            """)
        try engine.evaluate("(modal-activate! \"global\" '() F18)")
        #expect(try engine.evaluate("modal-active?") == .true)

        // Pressing 'f' hits the selector — currently exits modal (chooser is Phase 4)
        try engine.evaluate("(modal-handle-key \"f\")")
        #expect(try engine.evaluate("modal-active?") == .false)
        #expect(try engine.evaluate("(overlay-open?)") == .false)
    }

    @Test func selectorInGroupNavigationWorks() throws {
        let engine = try loadAllModules()
        try engine.evaluate("""
            (fsm-install-graph! (lower-configuration (configuration
              (tree 'global
                (tree-root 'global
                  (group "f" "Find"
                    (key "a" "Find Apps"
                      (selector 'prompt "Find app…" 'source (lambda () '())))
                    (key "e" "Emoji" (lambda () 'ok))))))))
            """)
        try engine.evaluate("(modal-activate! \"global\" '() F18)")
        try engine.evaluate("(modal-handle-key \"f\")")
        #expect(try engine.evaluate("modal-active?") == .true)

        // Now at "Find" group, pressing 'a' hits selector
        try engine.evaluate("(modal-handle-key \"a\")")
        #expect(try engine.evaluate("modal-active?") == .false)
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
            (define css-root (tree-root 'global (key "s" "Safari" (lambda () 'ok))))
            """)
        let html = try engine.evaluate("""
            (render-overlay-html css-root '("Global") '())
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

        // Verify the config's trees were lowered into the installed graph.
        #expect(try engine.evaluate("(fsm-state-ref \"global\")") != .false)
        #expect(try engine.evaluate("(fsm-state-ref \"com.apple.Safari\")") != .false)
        #expect(try engine.evaluate("(fsm-state-ref \"com.googlecode.iterm2\")") != .false)
        // Per-app screens are authored inline (seed-shrink-k17, ADR-0019) —
        // spot-check one machinery-backed and one pure-preference screen.
        #expect(try engine.evaluate("(fsm-state-ref \"company.thebrowser.dia\")") != .false)
        #expect(try engine.evaluate("(fsm-state-ref \"com.apple.finder\")") != .false)
        // The inner tools' screens are the seed's too (ADR-0021): each
        // library ships only its wiring, whose context entry names these
        // scopes, so a seed that stopped authoring them would lower to a
        // dangling reference rather than to a working install.
        #expect(try engine.evaluate("(fsm-state-ref \"herdr\")") != .false)
        #expect(try engine.evaluate("(fsm-state-ref \"zellij\")") != .false)
        #expect(try engine.evaluate("(fsm-state-ref \"nvim\")") != .false)

        // Verify hotkeys registered
        let kbLib = try engine.context.libraries.lookup(KeyboardLibrary.self)!
        #expect(kbLib.handlerRegistry.hotkeyHandlers[HotkeyKey(keyCode: KeyCode.f18, modifiers: [])] != nil)
        #expect(kbLib.handlerRegistry.hotkeyHandlers[HotkeyKey(keyCode: KeyCode.f17, modifiers: [])] != nil)
    }

    /// The same seam, extended over `Scheme/examples/*.scm` (ADR-0021).
    ///
    /// An example is a complete, working configuration for a setup a
    /// fresh install does not seed — tmux, Chrome and paneru today. It is never
    /// loaded at
    /// runtime, so nothing else would notice it rotting; evaluating each
    /// one into its OWN fresh engine (a configuration installs once, and
    /// two examples would collide on scope) turns "an example stopped
    /// composing" into a red suite instead of silent rot.
    ///
    /// What this can and cannot catch depends on how the example is written.
    /// `paneru.scm` branches on `installed?`, which is false here (no shell
    /// runner — ADR-0023), so it names BOTH branches' screens as values and
    /// selects between them: an inline `if` would leave the paneru half
    /// unevaluated and a renamed op would sail through green.
    @Test func exampleConfigsLoadWithoutErrors() throws {
        guard let schemePath = try SchemeEngine().schemeDirectoryPath else {
            throw SchemeTestError.noSchemeDir
        }
        let examplesDir = joinPath(schemePath, "examples")
        let names = try FileManager.default
            .contentsOfDirectory(atPath: examplesDir)
            .filter { $0.hasSuffix(".scm") }
            .sorted()
        // The directory itself is the contract: an empty examples/ would
        // pass every assertion below vacuously.
        #expect(!names.isEmpty, "no examples found in \(examplesDir)")

        for name in names {
            let engine = try loadAllModules()
            try engine.evaluateFile(joinPath(examplesDir, name))
            // It installed: the graph carries the example's screens and
            // both leaders are armed.
            #expect(try engine.evaluate("(fsm-state-ref \"global\")") != .false,
                    "\(name): no global screen in the installed graph")
            let kbLib = try engine.context.libraries.lookup(KeyboardLibrary.self)!
            #expect(kbLib.handlerRegistry
                        .hotkeyHandlers[HotkeyKey(keyCode: KeyCode.f17, modifiers: [])] != nil,
                    "\(name): local leader not armed")
        }
    }

    // MARK: - Migrated bundled config renders as panels (config-migration-k8)

    /// The bundled global tree, migrated to the layout DSL, contributes a
    /// panel-grid SCREEN whose grid is the authored panels — and a command
    /// stays reachable by its original key through the (transparent) panel, so
    /// dispatch is unchanged by the presentation restructure. After
    /// bare-loose-rows-k23 the former "General" panel is unwrapped: its keys
    /// (and the Windows drill-in) render BARE in the loose region, not a card.
    @Test func defaultGlobalTreeRendersAsPanelGrid() throws {
        let engine = try loadAllModules()
        guard let schemePath = engine.schemeDirectoryPath else { throw SchemeTestError.noSchemeDir }
        try engine.evaluateFile(schemePath + "/default-config.scm")

        // The installed configuration value carries the global screen's root
        // node; a panel-grid screen (structured display), not the legacy
        // auto-layout.
        try engine.evaluate("(define g-root (configuration-tree-ref (modaliser:configuration) \"global\"))")
        #expect(try engine.evaluate("(pair? (node-display-ref g-root 'panels))") == .true)

        // The top-level grid serialises the authored panels. (The top level
        // embeds no live-list block — the windows list lives a level down under
        // "w" — so this render fires no on-render side effects.)
        let json = try engine.evaluate("(panel-grid-payload-json g-root)").asString()
        #expect(json.contains("\"type\":\"panel-grid\""))
        for label in ["Applications", "Search"] {
            #expect(json.contains("\"label\":\"\(label)\""), "missing panel \(label)")
        }
        // No "General" card — those keys moved to the loose region.
        #expect(!json.contains("\"label\":\"General\""))
        #expect(json.contains("\"loose\":["))
        #expect(json.contains("\"label\":\"Settings\""))
        #expect(json.contains("\"label\":\"Highlight Cursor\""))
        #expect(json.contains("\"label\":\"Play/Pause\""))
        // The top-level Windows `open` folds into the loose region as a drill row.
        #expect(json.contains("\"label\":\"Windows\""))

        // Transparent dispatch preserved: "b" (Browser) keeps its path
        // through the Applications panel; "w" is the navigable Windows
        // drill-down (an `open`, lowered to a group).
        #expect(try engine.evaluate("(command? (find-child g-root \"b\"))") == .true)
        #expect(try engine.evaluate("(equal? (node-label (find-child g-root \"b\")) \"Browser\")") == .true)
        #expect(try engine.evaluate("(group? (find-child g-root \"w\"))") == .true)
    }

    /// The seeded Play/Pause row is a **Terminal** command at the global
    /// screen's top level — the overlay closes when it fires, like every other
    /// loose action there. Asserted structurally because `'next` is easy to add
    /// by accident when a transport cluster (next/prev/volume) is eventually
    /// bound beside it, and a Walk edge there would silently change what a
    /// single press does.
    @Test func defaultGlobalPlayPauseIsATerminalTopLevelCommand() throws {
        let engine = try loadAllModules()
        guard let schemePath = engine.schemeDirectoryPath else { throw SchemeTestError.noSchemeDir }
        try engine.evaluateFile(schemePath + "/default-config.scm")

        try engine.evaluate("""
          (define pp (find-child (configuration-tree-ref (modaliser:configuration) "global") "p"))
        """)
        #expect(try engine.evaluate("(command? pp)") == .true)
        #expect(try engine.evaluate("(equal? (node-label pp) \"Play/Pause\")") == .true)
        #expect(try engine.evaluate("(node-next pp)") == .false)  // Terminal: no walk edge
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
          (define win (find-child (configuration-tree-ref (modaliser:configuration) "global") "w"))
          ;; A panel of ROOT's resolved render plan, by label — panels live
          ;; in the display value; resolve-display is pure (no on-render).
          (define (grid-panel root lbl)
            (let loop ((ps (cdr (assoc 'panels
                                       (resolve-display (node-children root)
                                                        (node-display root))))))
              (cond ((null? ps) #f)
                    ((equal? (cdr (assoc 'label (car ps))) lbl) (car ps))
                    (else (loop (cdr ps))))))
        """)
        #expect(try engine.evaluate("(pair? (node-display-ref win 'panels))") == .true)

        // The Select / Windows / Displays panels are present…
        #expect(try engine.evaluate("(pair? (grid-panel win \"Select\"))") == .true)
        #expect(try engine.evaluate("(pair? (grid-panel win \"Windows\"))") == .true)
        #expect(try engine.evaluate("(pair? (grid-panel win \"Displays\"))") == .true)
        // …with the live window list under Windows and the display list under Displays.
        #expect(try engine.evaluate(
            "(eq? (cdr (assoc 'type (cdr (assoc 'list (grid-panel win \"Windows\"))))) 'window-list)") == .true)
        #expect(try engine.evaluate(
            "(eq? (cdr (assoc 'type (cdr (assoc 'list (grid-panel win \"Displays\"))))) 'display-list)") == .true)

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
    ///
    /// Since iterm-owns-its-bindings-k45 the screen is authored in the
    /// SEED rather than delivered by the library, so this now pins the
    /// seeded composition (as the herdr tests below do) rather than a
    /// library constructor's output.
    @Test func defaultItermTreeRendersAsPanelGrid() throws {
        let engine = try loadAllModules()
        guard let schemePath = engine.schemeDirectoryPath else { throw SchemeTestError.noSchemeDir }
        try engine.evaluateFile(schemePath + "/default-config.scm")

        try engine.evaluate("""
          (define (grid-panel root lbl)
            (let loop ((ps (cdr (assoc 'panels
                                       (resolve-display (node-children root)
                                                        (node-display root))))))
              (cond ((null? ps) #f)
                    ((equal? (cdr (assoc 'label (car ps))) lbl) (car ps))
                    (else (loop (cdr ps))))))
          (define it (configuration-tree-ref (modaliser:configuration) "com.googlecode.iterm2"))
        """)
        #expect(try engine.evaluate("(pair? (node-display-ref it 'panels))") == .true)
        #expect(try engine.evaluate("(pair? (grid-panel it \"Splits\"))") == .true)
        // Panes panel embeds the live pane list in the plan's 'list slot
        // (resolve-display is pure, so the on-render-fn never fires —
        // purely structural).
        #expect(try engine.evaluate(
            "(eq? (cdr (assoc 'type (cdr (assoc 'list (grid-panel it \"Panes\"))))) 'iterm-panes)") == .true)
        // Transparent dispatch: "c" (Copy Mode) keeps its path; "t" is the
        // navigable Tab drill-down (an `open` → group).
        #expect(try engine.evaluate("(command? (find-child it \"c\"))") == .true)
        #expect(try engine.evaluate("(group? (find-child it \"t\"))") == .true)
    }

    /// ADR-0021's seam for iTerm: the library ships (iterm:wiring) — the
    /// backend record and the digit-jump tree — and the CONFIG authors
    /// the screen. That split moves one real risk into user space: the
    /// splits, moves, copy mode and zoom ops all ride on eight iTerm key
    /// bindings that only `configure!` writes, and nothing in the library
    /// can surface that action any more. A seed that dropped the row
    /// would leave a fresh install with ops that silently do nothing, so
    /// the row — and its self-retiring gate — is pinned here.
    ///
    /// Structural only: `configured?` is never called (it shells out to
    /// `defaults`/PlistBuddy), just checked for identity against the
    /// node's 'hidden slot. No live iTerm.
    @Test func seededItermScreenAuthorsTheProvisioningRowAndWiring() throws {
        let engine = try loadAllModules()
        guard let schemePath = engine.schemeDirectoryPath else { throw SchemeTestError.noSchemeDir }
        try engine.evaluateFile(schemePath + "/default-config.scm")
        try engine.evaluate("""
          (import (prefix (modaliser apps iterm) iterm:))
          (define cfg (modaliser:configuration))
          (define root (configuration-tree-ref cfg "com.googlecode.iterm2"))
          (define setup (find-child root "C-I"))
        """)
        #expect(try engine.evaluate("(command? setup)") == .true)
        #expect(try engine.evaluate("(eq? (cdr (assoc 'action setup)) iterm:configure!)") == .true)
        // The gate is the library's probe, passed through the `key`
        // macro's 'hidden keyword — which is what retires the row on the
        // next overlay open, with no relaunch.
        #expect(try engine.evaluate("(eq? (cdr (assoc 'hidden setup)) iterm:configured?)") == .true)
        // The machinery-named scope the backend record references by key.
        // Its PRESENCE is what makes the seed a working reference rather
        // than a nearly-working one.
        #expect(try engine.evaluate("(pair? (configuration-tree-ref cfg \"iterm-pane-digit\"))") == .true)
        #expect(try engine.evaluate("(terminal-backend? (configuration-backend-ref cfg 'iterm))") == .true)
    }

    /// herdr-copy-mode-k16 / herdr-copy-mode-key-k34 — the herdr tree ships
    /// zero iTerm controls by design, so herdr's own text-inspection surfaces
    /// are unreachable there without explicit bindings. herdr has TWO, and
    /// they are distinct ops, not spellings of one: copy mode (per-pane
    /// selection in the LIVE pane, `copy_mode`, default `prefix [`) and
    /// scrollback (the focused pane's buffer opened in an editor,
    /// `edit_scrollback`, default `prefix e`). k16 shipped only the latter, on
    /// `c`; k34 gave copy mode that `c` and moved scrollback to `C`. iTerm's
    /// own copy mode is unsuitable for either — it selects across the whole
    /// herdr canvas, ignoring per-pane layout.
    ///
    /// Loads the real bundled config (which authors the 'herdr screen
    /// inline, ADR-0021) and asserts both bindings are exposed with the
    /// right labels, guarding against a future edit dropping one or
    /// collapsing the pair back into a single key. Structural only — the
    /// keystroke bodies stay untested by design, the same trust level as the
    /// Quit group's Detach key. (No live iTerm, no live herdr.)
    @Test func herdrEntryNodeExposesCopyModeAndScrollback() throws {
        let engine = try loadAllModules()
        guard let schemePath = engine.schemeDirectoryPath else { throw SchemeTestError.noSchemeDir }
        try engine.evaluateFile(schemePath + "/default-config.scm")

        try engine.evaluate("(define v (configuration-tree-ref (modaliser:configuration) \"herdr\"))")
        #expect(try engine.evaluate("(command? (find-child v \"c\"))") == .true)
        #expect(try engine.evaluate("(equal? (node-label (find-child v \"c\")) \"Copy Mode\")") == .true)
        #expect(try engine.evaluate("(command? (find-child v \"C\"))") == .true)
        #expect(try engine.evaluate("(equal? (node-label (find-child v \"C\")) \"Scrollback\")") == .true)

        // The pair is the plane rule's one exception, so pin BOTH halves of
        // why it is safe: `c`/`C` are case-distinct children (a case-folding
        // regression would silently collapse them into one binding), and `C`
        // does not shadow a drill capital — P T S W A Q all still resolve to
        // their own navigable nodes.
        #expect(try engine.evaluate("(eq? (find-child v \"c\") (find-child v \"C\"))") == .false)
        for capital in ["P", "T", "S", "W", "A", "Q"] {
            #expect(try engine.evaluate("(group? (find-child v \"\(capital)\"))") == .true)
        }
    }

    /// ADR-0021's seam for herdr: the library ships (herdr:wiring) — the
    /// context entry, the backend record, the digit-jump tree — and the
    /// CONFIG authors the screen. That split moves one real risk into user
    /// space: the jump space only works if the screen wires the provider
    /// and the chip hooks itself, and nothing in the library can do it for
    /// them. So the seeded composition, which is what every fresh install
    /// runs AND the reference every user copies from, is pinned here.
    ///
    /// `screen` stores both hooks uncomposed (display-dsl-surface-k23
    /// removed the old compose-hooks detour — block hook fns fire
    /// structurally from run-on-enter/run-on-leave instead), so the root's
    /// node-on-enter/node-on-leave are eq? to the library's exports
    /// directly. The unconditional 'entry/'exit slots must stay unset —
    /// the double-fire trap. Structural only: never invokes the hooks, so
    /// no AX / hints-show dependency, and no live herdr.
    @Test func seededHerdrScreenWiresTheJumpSpaceAndItsWalk() throws {
        let engine = try loadAllModules()
        guard let schemePath = engine.schemeDirectoryPath else { throw SchemeTestError.noSchemeDir }
        try engine.evaluateFile(schemePath + "/default-config.scm")
        try engine.evaluate("""
          (import (prefix (modaliser muxes herdr) herdr:))
          (define cfg (modaliser:configuration))
          (define root (configuration-tree-ref cfg "herdr"))
        """)
        // The jump space's three halves, all config-side wiring now.
        #expect(try engine.evaluate("(eq? (node-provider root) herdr:herdr-jump-provider)") == .true)
        #expect(try engine.evaluate("(eq? (node-on-enter root) herdr:paint-jump-chips!)") == .true)
        #expect(try engine.evaluate("(eq? (node-on-leave root) herdr:clear-jump-chips!)") == .true)
        #expect(try engine.evaluate("(not (node-entry root))") == .true)
        #expect(try engine.evaluate("(not (node-exit root))") == .true)
        // The two machinery-named scopes the wiring and the Focus rows
        // reference by key. A rename of either is a load-time closure
        // error, but their PRESENCE is what makes the seed a working
        // reference rather than a nearly-working one.
        #expect(try engine.evaluate("(pair? (configuration-tree-ref cfg \"herdr-panes-focus\"))") == .true)
        #expect(try engine.evaluate("(pair? (configuration-tree-ref cfg \"herdr-pane-digit\"))") == .true)
        #expect(try engine.evaluate("""
          (equal? (configuration-context-ref cfg "herdr")
                  '((tree . herdr) (backend . herdr)))
        """) == .true)
    }

    // MARK: - Config-like pattern

    @Test func fullConfigPatternLoads() throws {
        let engine = try loadAllModules()
        // Simulate a config.scm-like structure with selectors and actions,
        // composed as one configuration value and installed via the one-shot
        // handoff (which also arms the leaders).
        try engine.evaluate("""
            (modaliser:start! (configuration
              (leaders (leader 'global F18)
                       (leader 'local F17))

              (tree 'global
                (tree-root 'global
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
                                'on-select (lambda (c) c))))))

              (tree 'com.apple.Safari
                (tree-root 'com.apple.Safari
                  (group "t" "Tabs"
                    (key "n" "New Tab" (lambda () 'ok)))))))
            """)

        // Verify the trees lowered into the installed graph
        #expect(try engine.evaluate("(fsm-state-ref \"global\")") != .false)
        #expect(try engine.evaluate("(fsm-state-ref \"com.apple.Safari\")") != .false)

        // Verify hotkeys registered
        let kbLib = try engine.context.libraries.lookup(KeyboardLibrary.self)!
        #expect(kbLib.handlerRegistry.hotkeyHandlers[HotkeyKey(keyCode: KeyCode.f18, modifiers: [])] != nil)
        #expect(kbLib.handlerRegistry.hotkeyHandlers[HotkeyKey(keyCode: KeyCode.f17, modifiers: [])] != nil)
    }

    // MARK: - leader spec keyword args (modifiers, arm-when-frontmost)

    @Test func leaderWithModifiersRegistersUnderModifierKey() throws {
        let engine = try loadAllModules()
        try engine.evaluate("""
            (modaliser:start! (configuration
              (leaders (leader 'global F18 'modifiers '(shift)))
              (screen 'global (key "s" "Safari" (lambda () #t)))))
            """)
        let kbLib = try engine.context.libraries.lookup(KeyboardLibrary.self)!
        #expect(kbLib.handlerRegistry.hotkeyHandlers[
            HotkeyKey(keyCode: KeyCode.f18, modifiers: [.maskShift])] != nil)
        #expect(kbLib.handlerRegistry.hotkeyHandlers[
            HotkeyKey(keyCode: KeyCode.f18, modifiers: [])] == nil)
    }

    @Test func leaderWithArmBundleIdsRegistersBundleIds() throws {
        let engine = try loadAllModules()
        try engine.evaluate("""
            (modaliser:start! (configuration
              (leaders (leader 'global F18
                               'arm-when-frontmost '("com.jumpdesktop.Jump-Desktop")))
              (screen 'global (key "s" "Safari" (lambda () #t)))))
            """)
        let kbLib = try engine.context.libraries.lookup(KeyboardLibrary.self)!
        let entry = kbLib.handlerRegistry.hotkeyHandlers[
            HotkeyKey(keyCode: KeyCode.f18, modifiers: [])]
        #expect(entry?.armBundleIds == ["com.jumpdesktop.Jump-Desktop"])
    }

    @Test func leaderAcceptsBothKeywordsInEitherOrder() throws {
        let engine = try loadAllModules()
        try engine.evaluate("""
            (modaliser:start! (configuration
              (leaders (leader 'global F18
                               'arm-when-frontmost '("com.foo")
                               'modifiers '(shift ctrl)))
              (screen 'global (key "s" "Safari" (lambda () #t)))))
            """)
        let kbLib = try engine.context.libraries.lookup(KeyboardLibrary.self)!
        let entry = kbLib.handlerRegistry.hotkeyHandlers[
            HotkeyKey(keyCode: KeyCode.f18, modifiers: [.maskShift, .maskControl])]
        #expect(entry != nil)
        #expect(entry?.armBundleIds == ["com.foo"])
    }

    // MARK: - leader specs require an explicit mode

    @Test func leaderWithoutModeRaisesError() throws {
        let engine = try loadAllModules()
        // The mode ('global / 'local) is required — a bare keycode
        // must not be accepted.
        #expect(throws: (any Error).self) {
            try engine.evaluate("(leader F18)")
        }
    }

    @Test func leaderOmittedModeWithKeywordsRaisesError() throws {
        let engine = try loadAllModules()
        // A missing mode is an error even when keyword args follow.
        #expect(throws: (any Error).self) {
            try engine.evaluate("(leader F18 'modifiers '(shift))")
        }
    }

    @Test func leaderUnknownKeywordRaisesError() throws {
        let engine = try loadAllModules()
        #expect(throws: (any Error).self) {
            try engine.evaluate("(leader 'global F18 'frob 1)")
        }
    }

    @Test func keyStoresNextOption() throws {
        let engine = try loadDsl()
        try engine.evaluate("(define k (key \"h\" \"Left\" (lambda () 'ok) 'next 'iterm-panes-focus))")
        #expect(try engine.evaluate("(eq? (node-next k) 'iterm-panes-focus)") == .true)
    }

    @Test func keyWithoutNextReturnsFalse() throws {
        let engine = try loadDsl()
        try engine.evaluate("(define k (key \"h\" \"Left\" (lambda () 'ok)))")
        #expect(try engine.evaluate("(node-next k)") == .false)
    }

    @Test func keyRejectsUnknownTrailingKeyword() throws {
        let engine = try loadDsl()
        #expect(throws: (any Error).self) {
            try engine.evaluate("(key \"h\" \"Left\" (lambda () 'ok) 'frob 1)")
        }
    }

    @Test func crossEdgeKeyTransitionsModalIntoNamedMode() throws {
        // After firing a leaf whose 'next names a different tree in the
        // installed configuration (a cross edge), modal-handle-key should
        // leave the modal active and switch its root to that tree — so
        // subsequent presses act inside that mode without another leader.
        let engine = try loadAllModules()
        try engine.evaluate("""
            (define fired '())
            (define cross-cfg (configuration
              (tree 'iterm-focus-test
                (tree-root 'iterm-focus-test
                  'display-name "Focus"
                  (key "h" "Left" (lambda () (set! fired (cons 'left fired))) 'next 'self)))
              (tree 'transient-test
                (tree-root 'transient-test
                  (key "h" "Focus Left"
                    (lambda () (set! fired (cons 'transient-left fired)))
                    'next 'iterm-focus-test)))))
            (fsm-install-graph! (lower-configuration cross-cfg))
            """)
        try engine.evaluate("(modal-activate! \"transient-test\" '() F18)")
        try engine.evaluate("(modal-handle-key \"h\")")
        // The transient action fired
        #expect(try engine.evaluate("(equal? (car fired) 'transient-left)") == .true)
        // Modal is still active, now rooted at the crossed-into tree
        #expect(try engine.evaluate("modal-active?") == .true)
        #expect(try engine.evaluate("(eq? modal-root-node (configuration-tree-ref cross-cfg \"iterm-focus-test\"))") == .true)
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
        // (no error), both as panel-specs that carry their embedded 'list.
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (prefix (modaliser window-actions) window:) (prefix (modaliser display-actions) display:))")
        try engine.evaluate("(define pw (panel \"Windows\" (window:list-block 'chips? #t)))")
        try engine.evaluate("(define pd (panel \"Displays\" (display:display-list-block 'chips? #t)))")
        #expect(try engine.evaluate("(eq? (cdr (assoc 'kind pw)) 'panel-spec)") == .true)
        #expect(try engine.evaluate("(eq? (cdr (assoc 'kind pd)) 'panel-spec)") == .true)
        #expect(try engine.evaluate("(pair? (assoc 'list pw))") == .true)
        #expect(try engine.evaluate("(pair? (assoc 'list pd))") == .true)
    }
}
