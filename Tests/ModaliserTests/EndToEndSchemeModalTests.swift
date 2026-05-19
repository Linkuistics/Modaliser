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
            (define-tree 'global
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
            (define-tree 'global
              (key "H" "Split Left" (lambda () (set! test-result 'shift-H-fired))))
            """)

        try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
        // keycode 4 = 'h'; pass MOD-SHIFT so the handler upcases to "H".
        try engine.evaluate("(modal-key-handler 4 MOD-SHIFT)")
        #expect(try engine.evaluate("test-result") == .symbol(engine.context.symbols.intern("shift-H-fired")))
    }

    @Test func f18ThenGroupThenCommand() throws {
        let engine = try SchemeEngine()

        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser state-machine))")
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")

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

        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser state-machine))")
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")

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

        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser state-machine))")
        try engine.evaluate("(import (modaliser event-dispatch))")
        try engine.evaluate("(import (modaliser dsl))")

        try engine.evaluate("""
            (define-tree 'global
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
            (define-tree "com.googlecode.iterm2"
              (key "t" "Tabs" (lambda () 'plain)))
            (define-tree "com.googlecode.iterm2/zellij"
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
            (define-tree "com.googlecode.iterm2"
              (key "t" "Tabs" (lambda () 'plain)))
            (define-tree "com.googlecode.iterm2/zellij"
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
}

private func joinPath(_ base: String, _ component: String) -> String {
    base.hasSuffix("/") ? base + component : base + "/" + component
}
