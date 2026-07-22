import CoreGraphics
import Foundation
import Testing
import LispKit
@testable import Modaliser

@Suite("End-to-end Scheme modal dispatch")
struct EndToEndSchemeModalTests {

    @Test func hotkeyHandlersRegistered() throws {
        let engine = try SchemeEngine()

        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser state-machine))")
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")

        try engine.evaluate("""
            (set-leader! 'global F18)
            (register-tree! 'global
              (key "s" "Safari" (lambda () #t)))
            """)

        let kbLib = try engine.context.libraries.lookup(KeyboardLibrary.self)!
        #expect(kbLib.handlerRegistry.hotkeyHandlers[HotkeyKey(keyCode: KeyCode.f18, modifiers: [])] != nil)
    }

    @Test func f18ThenSExecutesAction() throws {
        let engine = try SchemeEngine()

        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser state-machine))")
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")

        try engine.evaluate("""
            (define test-result #f)
            (register-tree! 'global
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

    /// Regression for narrowing-live-dispatch-anomaly-k35: a confirmed
    /// two-key jump-label leader (herdr's narrowing prefix state — a
    /// PROVIDED resting state reached via a provider-supplied key edge,
    /// muxes/herdr.sld's jump-prefix-state) exited the modal instead of
    /// narrowing, in real (live keyboard capture) use. Reproduced here
    /// minimally with a bare provider standing in for herdr-jump-provider,
    /// exercising the same fsm-key-target-class/fire-terminal-leaf! path
    /// without herdr's own JSON/query machinery.
    ///
    /// Root cause: fsm-key-target-class (state-machine.sld) pre-classified
    /// the "a" edge's target via fsm-state-class, which only reads the
    /// PERMANENT graph's edge table — the target here is a PROVIDED
    /// (visit-scoped) resting state, whose edges live only in this Visit's
    /// %fsm-visit-provided, so it read back as zero-edges 'terminal. That
    /// misrouted modal-handle-key into fire-terminal-leaf!, which arms a
    /// pending capture-release teardown on the assumption that a Terminal
    /// leaf's wrapped 'entry slot will consume it — but a resting provided
    /// state has no 'entry slot at all, so the teardown fires
    /// unconditionally right after fsm-step! returns: unregister-all-keys!
    /// (the live catch-all deregisters) and hide-overlay (the chip windows
    /// close) — even though the FSM itself landed correctly on the
    /// narrowed, still-active provided state.
    ///
    /// modal-current-path/modal-active? alone can't catch this — both are
    /// DERIVED from the FSM's own (correct) state, so they read right
    /// regardless of whether the capture/overlay teardown wrongly fired
    /// alongside. Checking the KeyboardHandlerRegistry's catch-all directly
    /// (as this test does), after dispatch through the real keycode path
    /// (modal-key-handler, exactly what KeyboardLibrary's installed
    /// catch-all calls), is what exposes it.
    @Test func minimalProvidedRestingStateNarrowsWithoutDeregisteringCatchAll() throws {
        let engine = try SchemeEngine()

        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser state-machine) (modaliser fsm))")
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")

        // provided-state needs an explicit 'payload alist (not the default
        // #f) and its own 'up edge back to the root: while narrowed, this
        // state IS modal-current-node (node-on-enter/node-on-leave call
        // `assoc` on it) and modal-current-path's ancestors-within-tree
        // climbs via 'up edges, not id-prefix stripping — see herdr.sld's
        // jump-prefix-state for the same two requirements in production.
        try engine.evaluate("""
            (define (narrow-provider)
              (list (cons 'edges (list (edge "a" "test-root/a")))
                    (cons 'states (list (provided-state "test-root/a" 'payload '()
                                          (edge 'up "test-root")
                                          (edge "d" "test-root/a/landed"))))))
            (register-tree! 'test-root 'provider narrow-provider
              (key "z" "Zap" (lambda () #t)))
            """)

        let kbLib = try engine.context.libraries.lookup(KeyboardLibrary.self)!

        // keycode 0 = "a" (KeyboardLibrary.keyCodeToCharacter), no
        // modifiers — the exact live path a physical, unmodified "a"
        // keypress takes: CGEvent tap -> KeyboardHandlerRegistry.dispatch
        // -> the installed catch-all -> modal-key-handler.
        try engine.evaluate("(modal-enter (lookup-tree \"test-root\") F18)")
        try engine.evaluate("(modal-key-handler 0 0)")

        // "a" narrows into the provided resting state — it must not fire
        // and must not exit.
        #expect(try engine.evaluate("(equal? modal-current-path (list \"a\"))") == .true)
        #expect(try engine.evaluate("modal-active?") == .true)
        // The bug: the wrongly-armed pending teardown deregisters the
        // catch-all even though the engine stayed active and narrowed
        // correctly — this is what "zero Modaliser windows remain" in
        // live use actually was.
        #expect(kbLib.handlerRegistry.catchAllHandler != nil)
    }

    @Test func shiftedLetterDispatchesToUppercaseBinding() throws {
        // Regression: modal-key-handler upcases via (string-upcase …) when
        // the shift modifier is held. string-upcase lives in (scheme char),
        // not (scheme base) — if event-dispatch doesn't import it, the
        // handler errors at runtime and the modal becomes unresponsive
        // (catch-all gets deregistered by the Swift safety wrapper).
        let engine = try SchemeEngine()

        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser state-machine))")
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")

        try engine.evaluate("""
            (define test-result #f)
            (register-tree! 'global
              (key "H" "Split Left" (lambda () (set! test-result 'shift-H-fired))))
            """)

        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        // keycode 4 = 'h'; pass MOD-SHIFT so the handler upcases to "H".
        try engine.evaluate("(modal-key-handler 4 MOD-SHIFT)")
        #expect(try engine.evaluate("test-result") == .symbol(engine.context.symbols.intern("shift-H-fired")))
    }

    @Test func ctrlAndAltModifiersDispatchToPrefixedBindings() throws {
        // Ctrl contributes a "C-" prefix and Alt an "M-" prefix to the
        // effective overlay key, so a binding can be declared on a
        // modified key. Ctrl+Shift+I → "C-I"; Alt+I → "M-i".
        let engine = try SchemeEngine()

        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser state-machine))")
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")

        try engine.evaluate("""
            (define ctrl-result #f)
            (define alt-result #f)
            (register-tree! 'global
              (key "C-I" "Configure"  (lambda () (set! ctrl-result 'ctrl-shift-i)))
              (key "M-i" "Alt Eye"    (lambda () (set! alt-result 'alt-i))))
            """)

        // keycode 34 = 'i'. Ctrl+Shift → "C-I".
        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        try engine.evaluate("(modal-key-handler 34 (bitwise-ior MOD-CTRL MOD-SHIFT))")
        #expect(try engine.evaluate("ctrl-result") == .symbol(engine.context.symbols.intern("ctrl-shift-i")))

        // Alt alone → "M-i".
        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        try engine.evaluate("(modal-key-handler 34 MOD-ALT)")
        #expect(try engine.evaluate("alt-result") == .symbol(engine.context.symbols.intern("alt-i")))
    }

    @Test func shiftedNonLetterKeyGetsShiftPrefix() throws {
        // Shift on a letter is carried by uppercasing it. Shift on a
        // non-letter (a digit, here) can't be — case is a no-op — so
        // the handler adds an "S-" prefix instead: Shift+1 → "S-1".
        let engine = try SchemeEngine()

        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser state-machine))")
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")

        try engine.evaluate("""
            (define result #f)
            (register-tree! 'global
              (key "S-1" "Shifted One" (lambda () (set! result 'shift-1))))
            """)

        // keycode 18 = '1'. Shift+1 → "S-1".
        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        try engine.evaluate("(modal-key-handler 18 MOD-SHIFT)")
        #expect(try engine.evaluate("result") == .symbol(engine.context.symbols.intern("shift-1")))
    }

    @Test func f18ThenGroupThenCommand() throws {
        let engine = try SchemeEngine()

        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser state-machine))")
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")

        try engine.evaluate("""
            (define test-result #f)
            (register-tree! 'global
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

        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser state-machine))")
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")

        try engine.evaluate("""
            (register-tree! 'global
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

        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser state-machine))")
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")

        try engine.evaluate("""
            (register-tree! 'global
              (key "s" "Safari" (lambda () #t)))
            """)

        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        #expect(try engine.evaluate("modal-active?") == .true)

        try engine.evaluate("(modal-key-handler ESCAPE 0)")
        #expect(try engine.evaluate("modal-active?") == .false)
    }

    @Test func terminalLibraryLoadsWithoutError() throws {
        let engine = try SchemeEngine()
        // Just load it — any parse / reference error surfaces here.
        try engine.evaluate("(import (modaliser terminal))")

        // Smoke check: the three user-facing bindings exist.
        #expect(try engine.evaluate("(procedure? focused-iterm-tty)") == .true)
        #expect(try engine.evaluate("(procedure? tty-foreground-command)") == .true)
        #expect(try engine.evaluate("(procedure? focused-terminal-foreground-command)") == .true)
    }

    @Test func localContextSuffixRoutesToSuffixedTree() throws {
        let engine = try SchemeEngine()

        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser state-machine))")
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")

        // Register a plain tree and a /zellij variant, then override the hook
        // to return the suffix unconditionally. resolve-app-tree should pick
        // the variant.
        try engine.evaluate("""
            (register-tree! "com.googlecode.iterm2"
              (key "t" "Tabs" (lambda () 'plain)))
            (register-tree! "com.googlecode.iterm2/zellij"
              (key "z" "Zellij" (lambda () 'zellij)))
            (set-local-context-suffix! (lambda (bundle-id) "/zellij"))
            """)

        let resolved = try engine.evaluate(
            "(resolve-app-tree \"com.googlecode.iterm2\")"
        )
        // resolve-app-tree returns the tree alist; find the first child's label.
        #expect(resolved != .false, "resolve-app-tree returned #f")
        let firstChildLabel = try engine.evaluate("""
            (cdr (assoc 'label (car (cdr (assoc 'children (resolve-app-tree "com.googlecode.iterm2"))))))
            """)
        if case .string(let ms) = firstChildLabel {
            #expect((ms as String) == "Zellij", "expected Zellij tree, got label \(ms)")
        } else {
            Issue.record("Expected string label, got \(firstChildLabel)")
        }
    }

    @Test func localContextSuffixFallsBackWhenHookReturnsFalse() throws {
        let engine = try SchemeEngine()

        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser state-machine))")
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")

        try engine.evaluate("""
            (register-tree! "com.googlecode.iterm2"
              (key "t" "Tabs" (lambda () 'plain)))
            (register-tree! "com.googlecode.iterm2/zellij"
              (key "z" "Zellij" (lambda () 'zellij)))
            ;; default local-context-suffix returns #f — no override
            """)

        let firstChildLabel = try engine.evaluate("""
            (cdr (assoc 'label (car (cdr (assoc 'children (resolve-app-tree "com.googlecode.iterm2"))))))
            """)
        if case .string(let ms) = firstChildLabel {
            #expect((ms as String) == "Tabs", "expected plain iTerm tree, got label \(ms)")
        } else {
            Issue.record("Expected string label, got \(firstChildLabel)")
        }
    }

    /// dispatch-cutover-k11: make-leader-handler's 'local mode now resolves
    /// through resolve-entry-for-bundle (the FSM entry table) instead of
    /// resolve-app-tree, with the suffix variant's gate wired to
    /// local-context-suffix at registration time (screen → register-tree-
    /// entry!). These mirror the resolve-app-tree tests above one layer
    /// down, exercising the entry-table resolver resolve-app-tree's own
    /// production caller (make-leader-handler) now uses instead.
    @Test func resolveEntryForBundleRoutesToTheSuffixedVariantWhenItsGatePasses() throws {
        let engine = try SchemeEngine()

        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser state-machine))")
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")

        try engine.evaluate("""
            (screen "com.googlecode.iterm2"
              (key "t" "Tabs" (lambda () 'plain)))
            (screen "com.googlecode.iterm2/zellij"
              (key "z" "Zellij" (lambda () 'zellij)))
            (set-local-context-suffix! (lambda (bundle-id) "/zellij"))
            """)

        let name = try engine.evaluate("(resolve-entry-for-bundle \"com.googlecode.iterm2\")")
        if case .string(let ms) = name {
            #expect((ms as String) == "com.googlecode.iterm2/zellij")
        } else {
            Issue.record("Expected string entry name, got \(name)")
        }
    }

    @Test func resolveEntryForBundleFallsBackToTheBaseWhenNoSuffixGatePasses() throws {
        let engine = try SchemeEngine()

        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser state-machine))")
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")

        try engine.evaluate("""
            (screen "com.googlecode.iterm2"
              (key "t" "Tabs" (lambda () 'plain)))
            (screen "com.googlecode.iterm2/zellij"
              (key "z" "Zellij" (lambda () 'zellij)))
            ;; default local-context-suffix returns #f — no variant's gate passes
            """)

        let name = try engine.evaluate("(resolve-entry-for-bundle \"com.googlecode.iterm2\")")
        if case .string(let ms) = name {
            #expect((ms as String) == "com.googlecode.iterm2")
        } else {
            Issue.record("Expected string entry name, got \(name)")
        }
    }

    @Test func resolveEntryForBundleReturnsFalseForAnUnregisteredBundle() throws {
        let engine = try SchemeEngine()

        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser state-machine))")
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")

        #expect(try engine.evaluate("(resolve-entry-for-bundle \"com.example.unregistered\")") == .false)
    }

    @Test func resolveEntryForBundleNeverMatchesGlobalOrAnUnrelatedApp() throws {
        // The bundle-id prefix filter excludes 'global (and any other app's
        // entries) outright — an always-passing gate elsewhere in the table
        // must never leak into a different bundle's resolution.
        let engine = try SchemeEngine()

        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser state-machine))")
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")

        try engine.evaluate("""
            (screen 'global (key "s" "Safari" (lambda () 'ok)))
            (screen "com.apple.Safari" (key "t" "Tab" (lambda () 'ok)))
            """)

        let name = try engine.evaluate("(resolve-entry-for-bundle \"com.apple.Safari\")")
        if case .string(let ms) = name {
            #expect((ms as String) == "com.apple.Safari")
        } else {
            Issue.record("Expected string entry name, got \(name)")
        }
    }

    @Test func itermZellijPredicateMatchesBothCommands() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser terminal))")

        // Mirror the predicate the user config defines, then test matching.
        try engine.evaluate("""
            (define mock-cmd "zellij")
            (define (focused-terminal-foreground-command) mock-cmd)
            (define (iterm-running-zellij?)
              (let ((cmd (focused-terminal-foreground-command)))
                (and cmd
                     (or (string-contains? cmd "zellij")
                         (string-contains? cmd "zj")))))
            """)

        #expect(try engine.evaluate("(iterm-running-zellij?)") == .true)

        try engine.evaluate("(set! mock-cmd \"zj --session foo\")")
        #expect(try engine.evaluate("(iterm-running-zellij?)") == .true)

        try engine.evaluate("(set! mock-cmd \"/opt/homebrew/bin/zellij -s work\")")
        #expect(try engine.evaluate("(iterm-running-zellij?)") == .true)

        try engine.evaluate("(set! mock-cmd \"-zsh\")")
        #expect(try engine.evaluate("(iterm-running-zellij?)") == .false)

        try engine.evaluate("(set! mock-cmd #f)")
        #expect(try engine.evaluate("(iterm-running-zellij?)") == .false)
    }

    @Test func itermSubscopePrecedenceNvimOverZellij() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser terminal))")

        // Install Scheme-level stubs for the two environmental probes, then
        // mirror the exact body of local-context-suffix from the user
        // config. NOTE: production user configs must install via
        // (set-local-context-suffix! …) because the real procedure lives
        // inside the (modaliser event-dispatch) library; this test stays
        // at top level only because it doesn't import event-dispatch and
        // exercises the procedure standalone.
        try engine.evaluate("""
            (define mock-fg #f)
            (define mock-focused-nvim #f)
            (define (focused-terminal-foreground-command) mock-fg)
            (define (focused-nvim-socket) mock-focused-nvim)
            (define (local-context-suffix bundle-id)
              (cond
                ((equal? bundle-id "com.googlecode.iterm2")
                 (let ((cmd (focused-terminal-foreground-command)))
                   (cond
                     ((not cmd) #f)
                     ((string-contains? cmd "nvim") "/nvim")
                     ((or (string-contains? cmd "zellij")
                          (string-contains? cmd "zj"))
                      (if (focused-nvim-socket) "/zellij+nvim" "/zellij"))
                     (else #f))))
                (else #f)))
            """)

        // Case 1: nvim directly in iTerm — fast path, no RPC.
        try engine.evaluate("(set! mock-fg \"nvim\")")
        try engine.evaluate("(set! mock-focused-nvim #f)")
        let s1 = try engine.evaluate("(local-context-suffix \"com.googlecode.iterm2\")")
        if case .string(let ms) = s1 {
            #expect((ms as String) == "/nvim", "nvim-direct → /nvim, got \(ms)")
        } else { Issue.record("expected string, got \(s1)") }

        // Case 2: zellij foreground, an nvim claims focus → merged tree.
        try engine.evaluate("(set! mock-fg \"zellij\")")
        try engine.evaluate("(set! mock-focused-nvim \"/tmp/nvim.sock\")")
        let s2 = try engine.evaluate("(local-context-suffix \"com.googlecode.iterm2\")")
        if case .string(let ms) = s2 {
            #expect((ms as String) == "/zellij+nvim", "nvim-in-zellij → /zellij+nvim, got \(ms)")
        } else { Issue.record("expected string, got \(s2)") }

        // Case 3: zellij foreground, no nvim claims focus → zellij tree.
        try engine.evaluate("(set! mock-fg \"zellij\")")
        try engine.evaluate("(set! mock-focused-nvim #f)")
        let s3 = try engine.evaluate("(local-context-suffix \"com.googlecode.iterm2\")")
        if case .string(let ms) = s3 {
            #expect((ms as String) == "/zellij", "zellij-only → /zellij, got \(ms)")
        } else { Issue.record("expected string, got \(s3)") }

        // Case 4: plain shell, nothing special.
        try engine.evaluate("(set! mock-fg \"-zsh\")")
        try engine.evaluate("(set! mock-focused-nvim #f)")
        #expect(try engine.evaluate("(local-context-suffix \"com.googlecode.iterm2\")") == .false,
                "plain shell → #f")

        // Case 5: foreground probe failed (iTerm AppleScript refused etc.).
        try engine.evaluate("(set! mock-fg #f)")
        #expect(try engine.evaluate("(local-context-suffix \"com.googlecode.iterm2\")") == .false,
                "probe-failed → #f")

        // Case 6: non-iTerm app, suffix always #f regardless of terminal state.
        try engine.evaluate("(set! mock-fg \"nvim\")")
        #expect(try engine.evaluate("(local-context-suffix \"dev.zed.Zed\")") == .false,
                "non-iTerm bundle-id → #f")
    }

    @Test func focusedNvimSocketReturnsFirstClaimant() throws {
        let engine = try SchemeEngine()

        // Define a local version of focused-nvim-socket using stubbed
        // list-nvim-sockets and nvim-server-focused? at top level.
        // (import (modaliser terminal))'s exported focused-nvim-socket
        // calls module-internal bindings that stubs can't shadow after
        // the library is sealed, so we exercise the scanning loop logic
        // with an inline reimplementation using the same algorithm.
        try engine.evaluate("""
            (define mock-socks '())
            (define mock-focused-sock #f)
            (define (list-nvim-sockets) mock-socks)
            (define (nvim-server-focused? s)
              (and mock-focused-sock (string=? s mock-focused-sock)))
            (define (focused-nvim-socket)
              (let loop ((socks (list-nvim-sockets)))
                (cond
                  ((null? socks) #f)
                  ((nvim-server-focused? (car socks)) (car socks))
                  (else (loop (cdr socks))))))
            """)

        // No nvims → #f.
        #expect(try engine.evaluate("(focused-nvim-socket)") == .false)

        // One nvim, claims focus.
        try engine.evaluate("(set! mock-socks '(\"/tmp/a.sock\"))")
        try engine.evaluate("(set! mock-focused-sock \"/tmp/a.sock\")")
        let s1 = try engine.evaluate("(focused-nvim-socket)")
        if case .string(let ms) = s1 {
            #expect((ms as String) == "/tmp/a.sock")
        } else { Issue.record("expected string, got \(s1)") }

        // Two nvims, only the second claims focus.
        try engine.evaluate("(set! mock-socks '(\"/tmp/a.sock\" \"/tmp/b.sock\"))")
        try engine.evaluate("(set! mock-focused-sock \"/tmp/b.sock\")")
        let s2 = try engine.evaluate("(focused-nvim-socket)")
        if case .string(let ms) = s2 {
            #expect((ms as String) == "/tmp/b.sock")
        } else { Issue.record("expected string, got \(s2)") }

        // Two nvims, none claims focus.
        try engine.evaluate("(set! mock-focused-sock #f)")
        #expect(try engine.evaluate("(focused-nvim-socket)") == .false)
    }

    /// The generic digit-jump recipe from
    /// docs/how-to/terminal-pane-aware-tree.md, end to end: a config binds
    /// `(key "g" "Goto pane" (lambda () (if #f #f)) 'next
    /// terminal:focus-pane-by-digit)` — a no-op action, all the work done
    /// by the procedure-valued 'next edge (digit-jump-facade-async-k7). The
    /// stub backend's focus-pane-by-digit slot is a plain mode-id symbol
    /// naming a real registered tree, mirroring the seven real backends'
    /// shape post-migration. Pressing "g" resolves the symbol and crosses
    /// (capture stays — a procedure-valued 'next is never Terminal); the
    /// digit press that follows is itself Terminal, so it releases capture.
    @Test func digitJumpFacadeRecipeCrossesToDigitPickThenReleasesOnDigit() throws {
        let engine = try SchemeEngine()

        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser state-machine))")
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")
        try engine.evaluate("(import (modaliser terminal))")
        // The generic recipe is written against the terminal: prefix a
        // config gets via (import (prefix (modaliser terminal) terminal:))
        // (default-config.scm:33) — mirror that here rather than the bare
        // (modaliser terminal) import above.
        try engine.evaluate("(import (prefix (modaliser terminal) terminal:))")

        try engine.evaluate("""
            (define focused #f)
            (register-tree! 'stub-pane-digit
              (key-range "1.." "Pane <n>" (list "1" "2" "3")
                (lambda (k) (set! focused k))))
            (define host
              (make-terminal-backend
                'stub-host "Stub Host" 'host "test.bundle" #f
                (lambda () #f) (lambda () "p")
                (lambda () 'x) (lambda () 'x) (lambda () 'x) (lambda () 'x)
                (lambda () 'x) (lambda () 'x) (lambda () 'x) (lambda () 'x)
                (lambda () 'x) (lambda () 'x) (lambda () 'x) (lambda () 'x)
                'stub-pane-digit (lambda () 'zoom)
                (lambda () #t)))
            (register-backend! host)
            (register-tree! 'launcher
              (key "g" "Goto pane" (lambda () (if #f #f))
                'next terminal:focus-pane-by-digit))
            """)

        try engine.evaluate("(modal-enter (lookup-tree \"launcher\") F18)")
        try engine.evaluate("""
            (parameterize ((current-frontmost-bundle-id (lambda () "test.bundle")))
              (modal-key-handler 5 0))
            """)  // keycode 5 = 'g'

        // Cross edge: still capturing, now rooted at the digit-pick tree.
        #expect(try engine.evaluate("modal-active?") == .true)
        #expect(try engine.evaluate(
            "(eq? modal-root-node (lookup-tree \"stub-pane-digit\"))") == .true)

        // keycode 18 = '1' — Terminal (no 'next): releases capture and runs
        // the digit action.
        try engine.evaluate("(modal-key-handler 18 0)")
        let focused = try engine.evaluate("focused")
        if case .string(let ms) = focused {
            #expect((ms as String) == "1")
        } else {
            Issue.record("expected string \"1\", got \(focused)")
        }
        #expect(try engine.evaluate("modal-active?") == .false)
    }
}

private func joinPath(_ base: String, _ component: String) -> String {
    base.hasSuffix("/") ? base + component : base + "/" + component
}
