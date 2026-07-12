import Foundation
import Testing
import LispKit
@testable import Modaliser

@Suite("(modaliser terminal) library")
struct ModaliserTerminalLibraryTests {
    @Test func importsAndExposesProcedures() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser terminal))")
        // Each exported name must be bound (no exception on evaluation).
        // modaliser-tool-path is a string, the rest are procedures or
        // a parameter; both evaluate fine as bare identifiers.
        for name in [
            // Legacy detection
            "focused-iterm-tty",
            "tty-foreground-command",
            "focused-terminal-foreground-command",
            "list-nvim-sockets",
            "nvim-server-focused?",
            "focused-nvim-socket",
            "nvim-remote-send",
            "nvim-remote-expr",
            "modaliser-tool-path",
            // Façade machinery
            "make-terminal-backend",
            "terminal-backend?",
            "register-backend!",
            "current-frontmost-bundle-id",
            "active-backend",
            "focused-terminal-path",
            "in-chain?",
            // Op shims
            "focus-pane-left",  "focus-pane-right",  "focus-pane-up",  "focus-pane-down",
            "split-pane-left",  "split-pane-right",  "split-pane-up",  "split-pane-down",
            "move-pane-left",   "move-pane-right",   "move-pane-up",   "move-pane-down",
            "focus-pane-by-digit",
            "toggle-pane-zoom",
            // Capability predicates
            "supports-splits?",
            "supports-move-pane?",
            "supports-digit-jump?",
            "supports-zoom?",
            "supports?",
            // Multi-session helper
            "correlate-mux-client-to-host-tty"
        ] {
            _ = try engine.evaluate(name)
        }
    }

    /// A stub host backend with canned values exercises the registry,
    /// path-walk, dispatch, and predicates end-to-end without depending
    /// on AppleScript / shell-out.
    @Test func stubHostBackendDrivesPathAndDispatch() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser terminal))")
        try engine.evaluate("""
          (define host
            (make-terminal-backend
              'stub-host "Stub Host" 'host "test.bundle"
              (lambda () "vim")               ; detect-foreground-command
              (lambda () "host-pane-1")       ; focused-pane-id
              (lambda () 'fpl) (lambda () 'fpr) (lambda () 'fpu) (lambda () 'fpd)
              (lambda () 'spl) (lambda () 'spr) (lambda () 'spu) (lambda () 'spd)
              (lambda () 'mpl) (lambda () 'mpr) (lambda () 'mpu) (lambda () 'mpd)
              'digit (lambda () 'zoom)        ; focus-pane-by-digit: a plain
                                               ; symbol, not a thunk (ADR-0015)
              (lambda () #t)))                ; configured?
          (register-backend! host)
          """)

        // Path has exactly one frame keyed by the stub's symbol, with
        // canned pane-id and fg fields. Extracting by accessor keeps the
        // assertion robust to printed-form quirks.
        let pathLen = try engine.evaluate(stubbed("(length (focused-terminal-path))"))
        #expect(pathLen == .fixnum(1))

        let frame = try engine.evaluate(stubbed(
            "(cdr (assq 'stub-host (focused-terminal-path)))"))
        // frame is #(pane "host-pane-1" fg "vim")
        if case .vector(let collection) = frame {
            let elems = collection.exprs
            #expect(elems.count == 4)
            #expect(elems[1] == .makeString("host-pane-1"))
            #expect(elems[3] == .makeString("vim"))
        } else {
            Issue.record("expected vector frame, got \(frame)")
        }

        // Capability predicates: fully-configured stub reports support.
        for predicate in [
            "(supports-splits?)",
            "(supports-move-pane?)",
            "(supports-digit-jump?)",
            "(supports-zoom?)",
            "(supports? 'focus-pane-left)",
            "(supports? 'toggle-pane-zoom)"
        ] {
            #expect(try engine.evaluate(stubbed(predicate)) == .true,
                    "expected \(predicate) ⇒ #t")
        }

        // (supports? 'no-such-op) is #f.
        #expect(try engine.evaluate(stubbed("(supports? 'no-such-op)")) == .false)

        // Op shims dispatch to the backend's thunks and return their
        // sentinel symbols.
        for (call, expected) in [
            ("(focus-pane-left)",   "fpl"),
            ("(focus-pane-right)",  "fpr"),
            ("(split-pane-up)",     "spu"),
            ("(move-pane-down)",    "mpd"),
            ("(focus-pane-by-digit)","digit"),
            ("(toggle-pane-zoom)",  "zoom")
        ] {
            let got = try engine.evaluate(stubbed(call))
            let expectedExpr = Expr.symbol(engine.context.symbols.intern(expected))
            #expect(got == expectedExpr, "\(call) ⇒ \(got), expected \(expectedExpr)")
        }
    }

    /// Host with a mux inside: the path has both frames, active-backend
    /// is the leaf (mux), and `(in-chain? 'mux-sym)` is true.
    @Test func muxInsideHostExtendsPath() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser terminal))")
        try engine.evaluate("""
          (define host
            (make-terminal-backend
              'stub-host "Stub Host" 'host "test.bundle"
              (lambda () "stubmux")           ; descends into the mux below
              (lambda () "host-pane-1")
              (lambda () 'fpl) (lambda () 'fpr) (lambda () 'fpu) (lambda () 'fpd)
              (lambda () 'spl) (lambda () 'spr) (lambda () 'spu) (lambda () 'spd)
              (lambda () 'mpl) (lambda () 'mpr) (lambda () 'mpu) (lambda () 'mpd)
              'host-digit (lambda () 'host-zoom)
              (lambda () #t)))
          (define mux
            (make-terminal-backend
              'stub-mux "Stub Mux" 'mux "stubmux"
              (lambda () "lazygit")           ; leaf — no further descent
              (lambda () "mux-pane-3")
              (lambda () 'mux-fpl) (lambda () 'mux-fpr) (lambda () 'mux-fpu) (lambda () 'mux-fpd)
              (lambda () 'mux-spl) (lambda () 'mux-spr) (lambda () 'mux-spu) (lambda () 'mux-spd)
              (lambda () 'mux-mpl) (lambda () 'mux-mpr) (lambda () 'mux-mpu) (lambda () 'mux-mpd)
              'mux-digit (lambda () 'mux-zoom)
              (lambda () #t)))
          (register-backend! host)
          (register-backend! mux)
          """)

        // Path has both frames.
        let pathLen = try engine.evaluate(stubbed("(length (focused-terminal-path))"))
        #expect(pathLen == .fixnum(2))

        // active-backend is the leaf (mux): focus-pane-left dispatches
        // to the mux's mux-fpl, not the host's fpl.
        let dispatch = try engine.evaluate(stubbed("(focus-pane-left)"))
        #expect(dispatch == Expr.symbol(engine.context.symbols.intern("mux-fpl")))

        // in-chain? sees both layers; unrelated symbols return #f.
        #expect(try engine.evaluate(stubbed("(in-chain? 'stub-host)")) == .true)
        #expect(try engine.evaluate(stubbed("(in-chain? 'stub-mux)"))  == .true)
        #expect(try engine.evaluate(stubbed("(in-chain? 'zellij)"))    == .false)

        // The leaf frame's fg drives focused-terminal-foreground-command.
        #expect(try engine.evaluate(stubbed("(focused-terminal-foreground-command)"))
                == .makeString("lazygit"))
    }

    /// `configured?` returns #f → predicates report unsupported even when
    /// the op fields are populated. Models WezTerm pre-configure-entry.
    @Test func unconfiguredBackendDoesNotReportSupport() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser terminal))")
        try engine.evaluate("""
          (define host
            (make-terminal-backend
              'stub-host "Stub" 'host "test.bundle"
              (lambda () "vim") (lambda () "p")
              (lambda () 'x) (lambda () 'x) (lambda () 'x) (lambda () 'x)
              (lambda () 'x) (lambda () 'x) (lambda () 'x) (lambda () 'x)
              (lambda () 'x) (lambda () 'x) (lambda () 'x) (lambda () 'x)
              'x (lambda () 'x)
              (lambda () #f)))                ; NOT configured
          (register-backend! host)
          """)

        #expect(try engine.evaluate(stubbed("(supports-splits?)"))    == .false)
        #expect(try engine.evaluate(stubbed("(supports-move-pane?)")) == .false)
        #expect(try engine.evaluate(stubbed("(supports-zoom?)"))      == .false)
    }

    /// Missing op slot → predicate is #f, dispatch errors. Models
    /// Ghostty 1.3.1 (no `move-pane`).
    @Test func missingOpReportsUnsupportedAndErrorsOnDispatch() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser terminal))")
        try engine.evaluate("""
          (define host
            (make-terminal-backend
              'stub-host "Stub" 'host "test.bundle"
              (lambda () "vim") (lambda () "p")
              (lambda () 'fpl) (lambda () 'fpr) (lambda () 'fpu) (lambda () 'fpd)
              (lambda () 'spl) (lambda () 'spr) (lambda () 'spu) (lambda () 'spd)
              #f #f #f #f                     ; move-pane unsupported
              'digit (lambda () 'zoom)
              (lambda () #t)))
          (register-backend! host)
          """)

        #expect(try engine.evaluate(stubbed("(supports-move-pane?)")) == .false)
        // Other ops still dispatch — they're populated.
        #expect(try engine.evaluate(stubbed("(focus-pane-left)"))
                == Expr.symbol(engine.context.symbols.intern("fpl")))

        // Calling an unsupported op raises.
        do {
            _ = try engine.evaluate(stubbed("(move-pane-left)"))
            Issue.record("expected (move-pane-left) to raise")
        } catch {
            // Expected.
        }
    }

    /// With no backend registered for the frontmost app, the path is
    /// empty, predicates are #f, and ops error cleanly.
    @Test func noBackendRegisteredErrorsCleanly() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser terminal))")

        let path = try engine.evaluate(
            "(parameterize ((current-frontmost-bundle-id (lambda () \"unregistered.bundle\"))) " +
            "  (focused-terminal-path))"
        )
        #expect(path == .null, "expected empty alist, got \(path)")

        let supports = try engine.evaluate(
            "(parameterize ((current-frontmost-bundle-id (lambda () \"unregistered.bundle\"))) " +
            "  (supports-splits?))"
        )
        #expect(supports == .false)

        do {
            _ = try engine.evaluate(
                "(parameterize ((current-frontmost-bundle-id (lambda () \"unregistered.bundle\"))) " +
                "  (focus-pane-left))"
            )
            Issue.record("expected (focus-pane-left) to raise with no backend")
        } catch {
            // Expected.
        }
    }

    /// `focus-pane-by-digit` is a fire-time resolver, not a dispatch-
    /// and-call op shim (ADR-0015 Context item 3): no active backend, or
    /// an active backend whose slot is #f (unsupported), resolves to #f
    /// rather than raising — the fail-safe a procedure-valued `'next`
    /// edge relies on.
    @Test func focusPaneByDigitResolvesOrFailsSafe() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser terminal))")
        try engine.evaluate("""
          (define host
            (make-terminal-backend
              'stub-host "Stub" 'host "test.bundle"
              (lambda () "vim") (lambda () "p")
              (lambda () 'x) (lambda () 'x) (lambda () 'x) (lambda () 'x)
              (lambda () 'x) (lambda () 'x) (lambda () 'x) (lambda () 'x)
              (lambda () 'x) (lambda () 'x) (lambda () 'x) (lambda () 'x)
              #f (lambda () 'zoom)            ; focus-pane-by-digit unsupported
              (lambda () #t)))
          (register-backend! host)
          """)

        #expect(try engine.evaluate(stubbed("(focus-pane-by-digit)")) == .false)

        let noBackend = try engine.evaluate(
            "(parameterize ((current-frontmost-bundle-id (lambda () \"unregistered.bundle\"))) " +
            "  (focus-pane-by-digit))"
        )
        #expect(noBackend == .false)
    }

    /// Wraps the given form in a parameterize that overrides the
    /// frontmost-bundle-id source. The stub backends in these tests
    /// register against "test.bundle"; this hook makes the OS query
    /// irrelevant in CI.
    private func stubbed(_ form: String) -> String {
        return "(parameterize ((current-frontmost-bundle-id (lambda () \"test.bundle\"))) " +
               "  \(form))"
    }
}
