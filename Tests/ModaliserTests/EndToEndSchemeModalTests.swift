import CoreGraphics
import Foundation
import Testing
import LispKit
@testable import Modaliser

@Suite("End-to-end Scheme modal dispatch")
struct EndToEndSchemeModalTests {

    @Test func hotkeyHandlersRegistered() throws {
        let engine = try SchemeEngine()

        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser fsm))")
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")
        try engine.evaluate("(import (modaliser handoff) (modaliser configuration))")

        try engine.evaluate("""
            (modaliser:start! (configuration
              (leaders (leader 'global F18))
              (screen 'global
                (key "s" "Safari" (lambda () #t)))))
            """)

        let kbLib = try engine.context.libraries.lookup(KeyboardLibrary.self)!
        #expect(kbLib.handlerRegistry.hotkeyHandlers[HotkeyKey(keyCode: KeyCode.f18, modifiers: [])] != nil)
    }

    @Test func f18ThenSExecutesAction() throws {
        let engine = try SchemeEngine()

        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser fsm) (modaliser configuration))")
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")

        try engine.evaluate("""
            (define test-result #f)
            (fsm-install-graph! (lower-configuration (configuration
              (tree 'global
                (tree-root 'global
                  (key "s" "Safari" (lambda () (set! test-result 'safari-launched))))))))
            """)

        // Enter modal directly (simulates what the hotkey handler does)
        try engine.evaluate("(modal-activate! \"global\" '() F18)")
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
    /// Root cause: fsm-key-target-class pre-classified
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

        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser fsm) (modaliser configuration))")
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
            (fsm-install-graph! (lower-configuration (configuration
              (tree 'test-root
                (tree-root 'test-root 'provider narrow-provider
                  (key "z" "Zap" (lambda () #t)))))))
            """)

        let kbLib = try engine.context.libraries.lookup(KeyboardLibrary.self)!

        // keycode 0 = "a" (KeyboardLibrary.keyCodeToCharacter), no
        // modifiers — the exact live path a physical, unmodified "a"
        // keypress takes: CGEvent tap -> KeyboardHandlerRegistry.dispatch
        // -> the installed catch-all -> modal-key-handler.
        try engine.evaluate("(modal-activate! \"test-root\" '() F18)")
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

        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser fsm) (modaliser configuration))")
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")

        try engine.evaluate("""
            (define test-result #f)
            (fsm-install-graph! (lower-configuration (configuration
              (tree 'global
                (tree-root 'global
                  (key "H" "Split Left" (lambda () (set! test-result 'shift-H-fired))))))))
            """)

        try engine.evaluate("(modal-activate! \"global\" '() F18)")
        // keycode 4 = 'h'; pass MOD-SHIFT so the handler upcases to "H".
        try engine.evaluate("(modal-key-handler 4 MOD-SHIFT)")
        #expect(try engine.evaluate("test-result") == .symbol(engine.context.symbols.intern("shift-H-fired")))
    }

    @Test func ctrlAndAltModifiersDispatchToPrefixedBindings() throws {
        // Ctrl contributes a "C-" prefix and Alt an "M-" prefix to the
        // effective overlay key, so a binding can be declared on a
        // modified key. Ctrl+Shift+I → "C-I"; Alt+I → "M-i".
        let engine = try SchemeEngine()

        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser fsm) (modaliser configuration))")
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")

        try engine.evaluate("""
            (define ctrl-result #f)
            (define alt-result #f)
            (fsm-install-graph! (lower-configuration (configuration
              (tree 'global
                (tree-root 'global
                  (key "C-I" "Configure"  (lambda () (set! ctrl-result 'ctrl-shift-i)))
                  (key "M-i" "Alt Eye"    (lambda () (set! alt-result 'alt-i))))))))
            """)

        // keycode 34 = 'i'. Ctrl+Shift → "C-I".
        try engine.evaluate("(modal-activate! \"global\" '() F18)")
        try engine.evaluate("(modal-key-handler 34 (bitwise-ior MOD-CTRL MOD-SHIFT))")
        #expect(try engine.evaluate("ctrl-result") == .symbol(engine.context.symbols.intern("ctrl-shift-i")))

        // Alt alone → "M-i".
        try engine.evaluate("(modal-activate! \"global\" '() F18)")
        try engine.evaluate("(modal-key-handler 34 MOD-ALT)")
        #expect(try engine.evaluate("alt-result") == .symbol(engine.context.symbols.intern("alt-i")))
    }

    @Test func shiftedNonLetterKeyGetsShiftPrefix() throws {
        // Shift on a letter is carried by uppercasing it. Shift on a
        // non-letter (a digit, here) can't be — case is a no-op — so
        // the handler adds an "S-" prefix instead: Shift+1 → "S-1".
        let engine = try SchemeEngine()

        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser fsm) (modaliser configuration))")
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")

        try engine.evaluate("""
            (define result #f)
            (fsm-install-graph! (lower-configuration (configuration
              (tree 'global
                (tree-root 'global
                  (key "S-1" "Shifted One" (lambda () (set! result 'shift-1))))))))
            """)

        // keycode 18 = '1'. Shift+1 → "S-1".
        try engine.evaluate("(modal-activate! \"global\" '() F18)")
        try engine.evaluate("(modal-key-handler 18 MOD-SHIFT)")
        #expect(try engine.evaluate("result") == .symbol(engine.context.symbols.intern("shift-1")))
    }

    @Test func f18ThenGroupThenCommand() throws {
        let engine = try SchemeEngine()

        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser fsm) (modaliser configuration))")
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")

        try engine.evaluate("""
            (define test-result #f)
            (fsm-install-graph! (lower-configuration (configuration
              (tree 'global
                (tree-root 'global
                  (group "w" "Windows"
                    (key "c" "Center" (lambda () (set! test-result 'centered)))))))))
            """)

        try engine.evaluate("(modal-activate! \"global\" '() F18)")
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

        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser fsm) (modaliser configuration))")
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")

        try engine.evaluate("""
            (fsm-install-graph! (lower-configuration (configuration
              (tree 'global
                (tree-root 'global
                  (key "s" "Safari" (lambda () #t)))))))
            """)

        try engine.evaluate("(modal-activate! \"global\" '() F18)")
        #expect(try engine.evaluate("modal-active?") == .true)

        // F18 again — should toggle off (leader keycode matches)
        try engine.evaluate("(modal-key-handler F18 0)")
        #expect(try engine.evaluate("modal-active?") == .false)
    }

    @Test func escapeExitsModal() throws {
        let engine = try SchemeEngine()

        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser fsm) (modaliser configuration))")
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")

        try engine.evaluate("""
            (fsm-install-graph! (lower-configuration (configuration
              (tree 'global
                (tree-root 'global
                  (key "s" "Safari" (lambda () #t)))))))
            """)

        try engine.evaluate("(modal-activate! \"global\" '() F18)")
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
    /// naming a tree in the installed configuration, mirroring the seven
    /// real backends' shape post-migration. Pressing "g" resolves the
    /// symbol and crosses (capture stays — a procedure-valued 'next is
    /// never Terminal); the digit press that follows is itself Terminal,
    /// so it releases capture.
    @Test func digitJumpFacadeRecipeCrossesToDigitPickThenReleasesOnDigit() throws {
        let engine = try SchemeEngine()

        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser fsm) (modaliser configuration))")
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
            (define host
              (make-terminal-backend
                'stub-host "Stub Host" 'host "test.bundle" #f
                (lambda () #f) (lambda () "p")
                (lambda () 'x) (lambda () 'x) (lambda () 'x) (lambda () 'x)
                (lambda () 'x) (lambda () 'x) (lambda () 'x) (lambda () 'x)
                (lambda () 'x) (lambda () 'x) (lambda () 'x) (lambda () 'x)
                'stub-pane-digit (lambda () 'zoom)
                (lambda () #t)))
            (terminal-install-backends! (list host))
            (define cfg (configuration
              (tree 'stub-pane-digit
                (tree-root 'stub-pane-digit
                  (key-range "1.." "Pane <n>" (list "1" "2" "3")
                    (lambda (k) (set! focused k)))))
              (tree 'launcher
                (tree-root 'launcher
                  (key "g" "Goto pane" (lambda () (if #f #f))
                    'next terminal:focus-pane-by-digit)))))
            (fsm-install-graph! (lower-configuration cfg))
            """)

        try engine.evaluate("(modal-activate! \"launcher\" '() F18)")
        try engine.evaluate("""
            (parameterize ((current-frontmost-bundle-id (lambda () "test.bundle")))
              (modal-key-handler 5 0))
            """)  // keycode 5 = 'g'

        // Cross edge: still capturing, now rooted at the digit-pick tree.
        #expect(try engine.evaluate("modal-active?") == .true)
        #expect(try engine.evaluate(
            "(eq? modal-root-node (configuration-tree-ref cfg \"stub-pane-digit\"))") == .true)

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
