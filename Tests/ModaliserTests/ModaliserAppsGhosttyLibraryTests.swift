import Foundation
import Testing
@testable import Modaliser

/// Tests for `(modaliser apps ghostty)` — the Ghostty host backend
/// behind the (modaliser terminal) façade.
///
/// These tests run without Ghostty being installed or running. The
/// AppleScript wrapper's `is running` guard makes every probe call
/// short-circuit to "" in that case, which the façade treats as #f /
/// empty — the contract that lets these tests verify wiring,
/// registration, and capability shape end-to-end without a real
/// session. Hand-verification of the 13 supported ops against a live
/// Ghostty window is the leaf's separate "Done when" item.
@Suite("(modaliser apps ghostty) library")
struct ModaliserAppsGhosttyLibraryTests {
    @Test func importsAndExposesProcedures() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser apps ghostty))")
        // Public surface mirrors wezterm / tmux / zellij — ops live on
        // the façade, not here. Both must bind without error.
        _ = try engine.evaluate("register!")
        _ = try engine.evaluate("backend")
    }

    /// (register!) installs the backend into the façade's registry,
    /// keyed by 'ghostty + bundle-id "com.mitchellh.ghostty". When
    /// the frontmost app is Ghostty, the façade walks the path and
    /// resolves to this backend.
    @Test func registerInstallsGhosttyBackend() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser dsl) (modaliser state-machine)
                  (modaliser apps ghostty) (modaliser terminal))
        """)
        try engine.evaluate("(register!)")

        let pathLen = try engine.evaluate("""
          (parameterize ((current-frontmost-bundle-id
                           (lambda () "com.mitchellh.ghostty")))
            (length (focused-terminal-path)))
        """)
        // Without a running ghostty, detect-fg returns #f and the
        // path stops at the host — length 1.
        #expect(pathLen == .fixnum(1))

        let inChain = try engine.evaluate("""
          (parameterize ((current-frontmost-bundle-id
                           (lambda () "com.mitchellh.ghostty")))
            (in-chain? 'ghostty))
        """)
        #expect(inChain == .true)
    }

    /// (register!) also wires the digit-pick mode so that the façade's
    /// (focus-pane-by-digit) thunk has a tree to (enter-mode!) into.
    @Test func registerInstallsDigitPickTree() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser dsl) (modaliser state-machine)
                  (modaliser apps ghostty))
        """)
        try engine.evaluate("(register!)")
        #expect(try engine.evaluate("(lookup-tree \"ghostty-pane-digit\")") != .false)
    }

    /// Capability matrix: Ghostty is 13/14 — move-pane is the gap, same
    /// shape as WezTerm. (supports-splits?) requires all 12 focus /
    /// split / move ops; with move-pane absent it returns #f. The
    /// other three predicates all return #t.
    @Test func backendCapabilityMatrix() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser apps ghostty) (modaliser terminal))
        """)
        #expect(try engine.evaluate("(terminal-backend? backend)") == .true)
        try engine.evaluate("(register-backend! backend)")

        // splits? requires all four move-pane ops; Ghostty has none,
        // so the predicate is #f.
        #expect(try engine.evaluate("""
          (parameterize ((current-frontmost-bundle-id
                           (lambda () "com.mitchellh.ghostty")))
            (supports-splits?))
        """) == .false)

        // move-pane? is the explicit gap.
        #expect(try engine.evaluate("""
          (parameterize ((current-frontmost-bundle-id
                           (lambda () "com.mitchellh.ghostty")))
            (supports-move-pane?))
        """) == .false)

        // digit-jump and zoom both supported.
        #expect(try engine.evaluate("""
          (parameterize ((current-frontmost-bundle-id
                           (lambda () "com.mitchellh.ghostty")))
            (supports-digit-jump?))
        """) == .true)
        #expect(try engine.evaluate("""
          (parameterize ((current-frontmost-bundle-id
                           (lambda () "com.mitchellh.ghostty")))
            (supports-zoom?))
        """) == .true)

        // supports? for an individual op confirms granularity: focus
        // and split ops report #t, move-pane ops report #f.
        for op in ["focus-pane-left", "split-pane-right", "toggle-pane-zoom"] {
            #expect(try engine.evaluate("""
              (parameterize ((current-frontmost-bundle-id
                               (lambda () "com.mitchellh.ghostty")))
                (supports? '\(op)))
            """) == .true, "expected (supports? '\(op)) ⇒ #t")
        }
        for op in ["move-pane-left", "move-pane-down"] {
            #expect(try engine.evaluate("""
              (parameterize ((current-frontmost-bundle-id
                               (lambda () "com.mitchellh.ghostty")))
                (supports? '\(op)))
            """) == .false, "expected (supports? '\(op)) ⇒ #f")
        }
    }
}
