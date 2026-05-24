import Foundation
import Testing
@testable import Modaliser

/// Tests for `(modaliser apps wezterm)` — the WezTerm host backend
/// behind the (modaliser terminal) façade.
///
/// These tests run without WezTerm being installed or running. The
/// shell-out helpers cleanly return #f / empty in that case, which is
/// the contract the façade expects, so we can verify wiring,
/// registration, and capability shape end-to-end without a real
/// session. Hand-verification of the 13 supported ops against a live
/// WezTerm window is the leaf's separate "Done when" item.
@Suite("(modaliser apps wezterm) library")
struct ModaliserAppsWeztermLibraryTests {
    @Test func importsAndExposesProcedures() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser apps wezterm))")
        // Public surface mirrors tmux / zellij (ADR-0003: ops live on
        // the façade). Both must bind without error.
        _ = try engine.evaluate("register!")
        _ = try engine.evaluate("backend")
    }

    /// (register!) installs the backend into the façade's registry,
    /// keyed by 'wezterm + bundle-id "com.github.wez.wezterm". When
    /// the frontmost app is WezTerm, the façade walks the path and
    /// resolves to this backend.
    @Test func registerInstallsWeztermBackend() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser dsl) (modaliser state-machine)
                  (modaliser apps wezterm) (modaliser terminal))
        """)
        try engine.evaluate("(register!)")

        let pathLen = try engine.evaluate("""
          (parameterize ((current-frontmost-bundle-id
                           (lambda () "com.github.wez.wezterm")))
            (length (focused-terminal-path)))
        """)
        // Without a running wezterm, detect-fg returns #f and the
        // path stops at the host — length 1.
        #expect(pathLen == .fixnum(1))

        let inChain = try engine.evaluate("""
          (parameterize ((current-frontmost-bundle-id
                           (lambda () "com.github.wez.wezterm")))
            (in-chain? 'wezterm))
        """)
        #expect(inChain == .true)
    }

    /// (register!) also wires the digit-pick mode so that the façade's
    /// (focus-pane-by-digit) thunk has a tree to (enter-mode!) into.
    @Test func registerInstallsDigitPickTree() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser dsl) (modaliser state-machine)
                  (modaliser apps wezterm))
        """)
        try engine.evaluate("(register!)")
        #expect(try engine.evaluate("(lookup-tree \"wezterm-pane-digit\")") != .false)
    }

    /// Capability matrix: WezTerm is 13/14 — move-pane is the gap.
    /// (supports-splits?) requires all 12 focus/split/move ops; with
    /// move-pane absent, it returns #f. The other three predicates
    /// all return #t.
    @Test func backendCapabilityMatrix() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser apps wezterm) (modaliser terminal))
        """)
        #expect(try engine.evaluate("(terminal-backend? backend)") == .true)
        try engine.evaluate("(register-backend! backend)")

        // splits? requires all four move-pane ops; WezTerm has none,
        // so the predicate is #f.
        #expect(try engine.evaluate("""
          (parameterize ((current-frontmost-bundle-id
                           (lambda () "com.github.wez.wezterm")))
            (supports-splits?))
        """) == .false)

        // move-pane? is the explicit gap.
        #expect(try engine.evaluate("""
          (parameterize ((current-frontmost-bundle-id
                           (lambda () "com.github.wez.wezterm")))
            (supports-move-pane?))
        """) == .false)

        // digit-jump and zoom both supported.
        #expect(try engine.evaluate("""
          (parameterize ((current-frontmost-bundle-id
                           (lambda () "com.github.wez.wezterm")))
            (supports-digit-jump?))
        """) == .true)
        #expect(try engine.evaluate("""
          (parameterize ((current-frontmost-bundle-id
                           (lambda () "com.github.wez.wezterm")))
            (supports-zoom?))
        """) == .true)

        // supports? for an individual op confirms granularity: focus
        // and split ops report #t, move-pane ops report #f.
        for op in ["focus-pane-left", "split-pane-right", "toggle-pane-zoom"] {
            #expect(try engine.evaluate("""
              (parameterize ((current-frontmost-bundle-id
                               (lambda () "com.github.wez.wezterm")))
                (supports? '\(op)))
            """) == .true, "expected (supports? '\(op)) ⇒ #t")
        }
        for op in ["move-pane-left", "move-pane-down"] {
            #expect(try engine.evaluate("""
              (parameterize ((current-frontmost-bundle-id
                               (lambda () "com.github.wez.wezterm")))
                (supports? '\(op)))
            """) == .false, "expected (supports? '\(op)) ⇒ #f")
        }
    }
}
