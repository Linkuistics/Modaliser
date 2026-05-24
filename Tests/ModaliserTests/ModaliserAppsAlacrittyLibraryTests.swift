import Foundation
import Testing
@testable import Modaliser

/// Tests for `(modaliser apps alacritty)` — the Alacritty host backend
/// behind the (modaliser terminal) façade.
///
/// Detection-only by design: all 14 pane ops are #f, so every
/// capability predicate is #f when Alacritty alone is the active
/// backend. These tests run without Alacritty installed — the only
/// shell-outs the module makes are guarded so they return cleanly
/// when nothing is there:
///
///   * detect-fg-command's `pgrep -x alacritty` returns no pids; the
///     loop runs zero times and we get an empty echo (→ #f).
///   * configure-entry's probe shells `[ -d /Applications/Alacritty.app ]`
///     and reports 'no-app, which makes `alacritty-configured?` return
///     #t — the configure-entry stays hidden, exactly as intended for
///     a machine without Alacritty.
@Suite("(modaliser apps alacritty) library")
struct ModaliserAppsAlacrittyLibraryTests {
    @Test func importsAndExposesProcedures() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser apps alacritty))")
        // Public surface: register!, configure-entry, backend.
        _ = try engine.evaluate("register!")
        _ = try engine.evaluate("configure-entry")
        _ = try engine.evaluate("backend")
    }

    /// (register!) installs the backend keyed by 'alacritty +
    /// bundle-id "org.alacritty". When the frontmost app is Alacritty,
    /// the façade resolves it; the focused-terminal-path has length 1
    /// (host frame only — no mux discovered without a running shell).
    @Test func registerInstallsAlacrittyBackend() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser dsl) (modaliser state-machine)
                  (modaliser apps alacritty) (modaliser terminal))
        """)
        try engine.evaluate("(register!)")

        let pathLen = try engine.evaluate("""
          (parameterize ((current-frontmost-bundle-id
                           (lambda () "org.alacritty")))
            (length (focused-terminal-path)))
        """)
        // Without alacritty running, detect-fg returns #f and the
        // walk stops at the host — length 1.
        #expect(pathLen == .fixnum(1))

        let inChain = try engine.evaluate("""
          (parameterize ((current-frontmost-bundle-id
                           (lambda () "org.alacritty")))
            (in-chain? 'alacritty))
        """)
        #expect(inChain == .true)
    }

    /// Capability matrix: detection-only. Every predicate is #f
    /// because every op slot is #f (op-configured? AND of accessor →
    /// thunk → configured? short-circuits at the missing thunk).
    @Test func backendCapabilityMatrix() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser apps alacritty) (modaliser terminal))
        """)
        #expect(try engine.evaluate("(terminal-backend? backend)") == .true)
        try engine.evaluate("(register-backend! backend)")

        // All four coarse predicates are #f on Alacritty alone.
        for pred in ["supports-splits?",
                     "supports-move-pane?",
                     "supports-digit-jump?",
                     "supports-zoom?"] {
            #expect(try engine.evaluate("""
              (parameterize ((current-frontmost-bundle-id
                               (lambda () "org.alacritty")))
                (\(pred)))
            """) == .false, "expected (\(pred)) ⇒ #f")
        }

        // Per-op (supports? '…) is uniformly #f for every op.
        for op in ["focus-pane-left", "split-pane-right",
                   "move-pane-up", "focus-pane-by-digit",
                   "toggle-pane-zoom"] {
            #expect(try engine.evaluate("""
              (parameterize ((current-frontmost-bundle-id
                               (lambda () "org.alacritty")))
                (supports? '\(op)))
            """) == .false, "expected (supports? '\(op)) ⇒ #f")
        }
    }

    /// `(configure-entry)` returns a (cons (hidden . thunk) keynode)
    /// pair. The thunk is alacritty-configured? — true (= hidden) on
    /// any machine where /Applications/Alacritty.app doesn't exist or
    /// exists without com.apple.quarantine. The test machine is
    /// expected to be in one of those two states (no alacritty in
    /// CI), so the entry should report hidden = #t.
    @Test func configureEntryHiddenWhenNoApp() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser apps alacritty))
        """)
        // The car of the entry is (hidden . thunk); call the thunk.
        let hidden = try engine.evaluate("""
          (let* ((entry (configure-entry))
                 (hidden-pair (car entry))
                 (thunk (cdr hidden-pair)))
            (thunk))
        """)
        #expect(hidden == .true)
    }
}
