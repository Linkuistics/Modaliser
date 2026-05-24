import Foundation
import Testing
@testable import Modaliser

/// Tests for `(modaliser apps kitty)` — the Kitty host backend behind
/// the (modaliser terminal) façade.
///
/// These tests run without Kitty being installed or running. The
/// shell-out helpers cleanly return #f / empty in that case, which is
/// the contract the façade expects, so we can verify wiring,
/// registration, configure-entry shape, and the capability matrix
/// end-to-end without a real session. Hand-verification of the 13
/// supported ops + chip rendering against a live Kitty window is the
/// leaf's separate "Done when" item.
@Suite("(modaliser apps kitty) library")
struct ModaliserAppsKittyLibraryTests {
    @Test func importsAndExposesProcedures() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser apps kitty))")
        // Public surface mirrors wezterm plus configure-entry / probe.
        // ADR-0003: ops live on the façade; this module just exports
        // the registration and configure plumbing.
        _ = try engine.evaluate("register!")
        _ = try engine.evaluate("backend")
        _ = try engine.evaluate("configure-entry")
        _ = try engine.evaluate("kitty-configured?")
    }

    /// (register!) installs the backend into the façade's registry,
    /// keyed by 'kitty + bundle-id "net.kovidgoyal.kitty". When the
    /// frontmost app is Kitty, the façade walks the path and resolves
    /// to this backend.
    @Test func registerInstallsKittyBackend() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser dsl) (modaliser state-machine)
                  (modaliser apps kitty) (modaliser terminal))
        """)
        try engine.evaluate("(register!)")

        let pathLen = try engine.evaluate("""
          (parameterize ((current-frontmost-bundle-id
                           (lambda () "net.kovidgoyal.kitty")))
            (length (focused-terminal-path)))
        """)
        // Without a running kitty, detect-fg returns #f and the path
        // stops at the host — length 1.
        #expect(pathLen == .fixnum(1))

        let inChain = try engine.evaluate("""
          (parameterize ((current-frontmost-bundle-id
                           (lambda () "net.kovidgoyal.kitty")))
            (in-chain? 'kitty))
        """)
        #expect(inChain == .true)
    }

    /// (register!) also wires the digit-pick mode so that the façade's
    /// (focus-pane-by-digit) thunk has a tree to (enter-mode!) into.
    @Test func registerInstallsDigitPickTree() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser dsl) (modaliser state-machine)
                  (modaliser apps kitty))
        """)
        try engine.evaluate("(register!)")
        #expect(try engine.evaluate("(lookup-tree \"kitty-pane-digit\")") != .false)
    }

    /// Capability matrix: Kitty is 13/14 — zoom is the gap (ADR-0007,
    /// Kitty has no native single-pane zoom). (supports-zoom?) returns
    /// #f; the other three predicates all return #t once configure-
    /// entry has run.
    ///
    /// In this test no kitty.conf exists (or none with the marker), so
    /// `kitty-configured?` is #f and *all* capability predicates short-
    /// circuit on the configured? AND. That's the provisioning-gate
    /// behaviour (ADR-0004). To exercise the matrix shape we register
    /// a stub-host backend with the same kind/match-key whose
    /// configured? is constant #t and re-run.
    @Test func backendCapabilityMatrix() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("""
          (import (modaliser apps kitty) (modaliser terminal))
        """)
        #expect(try engine.evaluate("(terminal-backend? backend)") == .true)
        try engine.evaluate("(register-backend! backend)")

        // Pre-configure-entry: configured? is #f, so EVERY capability
        // predicate returns #f. This is the provisioning gate.
        for predicate in [
            "(supports-splits?)",
            "(supports-move-pane?)",
            "(supports-digit-jump?)",
            "(supports-zoom?)"
        ] {
            #expect(try engine.evaluate("""
              (parameterize ((current-frontmost-bundle-id
                               (lambda () "net.kovidgoyal.kitty")))
                \(predicate))
            """) == .false, "expected \(predicate) ⇒ #f pre-configure")
        }

        // Stub a constant-configured? backend at the same key so the
        // matrix shape (zoom #f, others #t) is testable without a
        // real kitty.conf on disk.
        try engine.evaluate("""
          (define ops (lambda () 'x))
          (define stub
            (make-terminal-backend
              'kitty "Kitty" 'host "net.kovidgoyal.kitty"
              (lambda () #f) (lambda () #f)
              ops ops ops ops
              ops ops ops ops
              ops ops ops ops
              ops
              #f                ;; toggle-pane-zoom — the Kitty gap
              (lambda () #t)))
          (register-backend! stub)
        """)

        // splits / move-pane / digit-jump: present.
        for predicate in [
            "(supports-splits?)",
            "(supports-move-pane?)",
            "(supports-digit-jump?)"
        ] {
            #expect(try engine.evaluate("""
              (parameterize ((current-frontmost-bundle-id
                               (lambda () "net.kovidgoyal.kitty")))
                \(predicate))
            """) == .true, "expected \(predicate) ⇒ #t with stub backend")
        }

        // zoom: the explicit Kitty gap. ADR-0007 documents why this is
        // the only splitting-backend capability predicate that's #f
        // in v1.
        #expect(try engine.evaluate("""
          (parameterize ((current-frontmost-bundle-id
                           (lambda () "net.kovidgoyal.kitty")))
            (supports-zoom?))
        """) == .false)

        // Granular (supports? '<op>): focus / split / move report #t,
        // toggle-pane-zoom reports #f.
        for op in ["focus-pane-left", "split-pane-right", "move-pane-up", "focus-pane-by-digit"] {
            #expect(try engine.evaluate("""
              (parameterize ((current-frontmost-bundle-id
                               (lambda () "net.kovidgoyal.kitty")))
                (supports? '\(op)))
            """) == .true, "expected (supports? '\(op)) ⇒ #t")
        }
        #expect(try engine.evaluate("""
          (parameterize ((current-frontmost-bundle-id
                           (lambda () "net.kovidgoyal.kitty")))
            (supports? 'toggle-pane-zoom))
        """) == .false)
    }
}
