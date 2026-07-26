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
///   * the provisioning probe shells `[ -d /Applications/Alacritty.app ]`
///     and reports 'no-app, which makes `configured?` return #t — a row
///     gated on it stays hidden, exactly as intended for a machine
///     without Alacritty.
@Suite("(modaliser apps alacritty) library")
struct ModaliserAppsAlacrittyLibraryTests {
    @Test func importsAndExposesProcedures() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser apps alacritty))")
        // Public surface: fragment, the provisioning pair, backend.
        // No `configure-entry` — the key, the label and the choice to
        // hide-when-done are decisions the configuration authors around
        // these two facilities (ADR-0021).
        _ = try engine.evaluate("fragment")
        _ = try engine.evaluate("configure!")
        _ = try engine.evaluate("configured?")
        _ = try engine.evaluate("backend")
    }

    /// (terminal-install-backends! (list backend)) installs the backend
    /// keyed by 'alacritty + bundle-id "org.alacritty". When the
    /// frontmost app is Alacritty, the façade resolves it; the
    /// focused-terminal-path has length 1 (host frame only — no mux
    /// discovered without a running shell).
    @Test func installedBackendResolvesThroughFacade() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser apps alacritty) (modaliser terminal))
        """)
        try engine.evaluate("(terminal-install-backends! (list backend))")

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
        try engine.evaluate("(terminal-install-backends! (list backend))")

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

    /// `configured?` is the gate a configuration hands to 'hidden, so
    /// it is the surviving behavioural claim once the row itself moved
    /// to user space (ADR-0021). It reports #t — nothing to do, hide the
    /// row — on any machine where /Applications/Alacritty.app doesn't
    /// exist or exists without com.apple.quarantine. The test machine is
    /// expected to be in one of those two states (no alacritty in CI).
    @Test func configuredWhenNoQuarantinedApp() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser apps alacritty))
        """)
        #expect(try engine.evaluate("(configured?)") == .true)
    }
}
