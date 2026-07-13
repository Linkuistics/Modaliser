import Foundation
import Testing
@testable import Modaliser

/// Tests for `(modaliser dialogs)` — the slim async AppleScript dialog
/// library (ADR-0014, leaf error-dialogs-async-k3).
///
/// Every test routes through `current-dialog-runner`, the library's single
/// test seam, so no test spawns osascript
/// (feedback_no_live_env_mutation_in_tests): a stubbed runner either
/// captures the exact assembled shell command (escaping tests) or invokes
/// the callback synchronously with a canned (exit-code stdout stderr)
/// (confirm/cancel plumbing tests).
@Suite("(modaliser dialogs) library")
struct ModaliserDialogsLibraryTests {
    @Test func importsAndExposesProcedures() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dialogs))")
        _ = try engine.evaluate("dialog-confirm")
        _ = try engine.evaluate("dialog-info")
        _ = try engine.evaluate("current-dialog-runner")
        _ = try engine.evaluate("sq-escape")
    }

    /// The POSIX single-quote idiom directly: each ' becomes '\'' (close
    /// the quote, emit an escaped literal ', reopen). Exported so callers
    /// with their own shell-quoting need (herdr.sld's branch-name
    /// interpolation) share this instead of a local copy.
    @Test func sqEscapeAppliesThePosixIdiom() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dialogs))")
        #expect(try engine.evaluate(#"(sq-escape "a'b")"#) == .string(#"a'\''b"#))
        #expect(try engine.evaluate(#"(sq-escape "no quotes here")"#)
                == .string("no quotes here"))
    }

    /// dialog-confirm with no options: default "OK" label, no title, no
    /// icon. Verifies the exact command assembled and fired through the
    /// seam — the shell wrapper (`osascript -e '...' 2>/dev/null`) and the
    /// AppleScript payload (`button returned of (display dialog ...)`, a
    /// Cancel/OK button pair, `cancel button "Cancel"` so Escape/Cancel
    /// raises rather than returning a value).
    @Test func dialogConfirmDefaultsBuildExpectedCommand() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dialogs))")
        try engine.evaluate("""
          (define captured #f)
          (parameterize ((current-dialog-runner (lambda (cmd cb) (set! captured cmd))))
            (dialog-confirm "Proceed?" (lambda (ok?) ok?)))
        """)
        #expect(try engine.evaluate("captured") == .string(
            #"osascript -e 'button returned of (display dialog "Proceed?" buttons {"Cancel", "OK"} default button "Cancel" cancel button "Cancel")' 2>/dev/null"#))
    }

    /// 'title / 'ok-label / 'icon options all splice into the AppleScript
    /// payload — the shape the iTerm/Kitty/Alacritty configure-confirm
    /// call sites depend on to preserve their existing title/button-
    /// wording/caution-icon UX through the shared library.
    @Test func dialogConfirmOptionsBuildExpectedCommand() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dialogs))")
        try engine.evaluate("""
          (define captured #f)
          (parameterize ((current-dialog-runner (lambda (cmd cb) (set! captured cmd))))
            (dialog-confirm "Configure X?" (lambda (ok?) ok?)
              'title "Configure iTerm" 'ok-label "Continue" 'icon "caution"))
        """)
        #expect(try engine.evaluate("captured") == .string(
            #"osascript -e 'button returned of (display dialog "Configure X?" with title "Configure iTerm" buttons {"Cancel", "Continue"} default button "Cancel" cancel button "Cancel" with icon caution)' 2>/dev/null"#))
    }

    /// An apostrophe in the message exercises sq-escape over the WHOLE
    /// assembled script (the shell single-quote wrap), not just the
    /// message substring — the same apostrophe-in-message bug the iTerm
    /// backend's original hand-rolled escaping was written to avoid.
    @Test func dialogConfirmEscapesApostropheInMessage() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dialogs))")
        try engine.evaluate("""
          (define captured #f)
          (parameterize ((current-dialog-runner (lambda (cmd cb) (set! captured cmd))))
            (dialog-confirm "it's here" (lambda (ok?) ok?)))
        """)
        #expect(try engine.evaluate("captured") == .string(
            #"osascript -e 'button returned of (display dialog "it'\''s here" buttons {"Cancel", "OK"} default button "Cancel" cancel button "Cancel")' 2>/dev/null"#))
    }

    /// A backslash and an embedded double-quote in the message exercise
    /// as-escape (the AppleScript double-quoted-literal escaping applied
    /// before the whole script is sq-escape'd for the shell).
    @Test func dialogConfirmEscapesBackslashAndQuoteInMessage() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dialogs))")
        try engine.evaluate(#"""
          (define captured #f)
          (parameterize ((current-dialog-runner (lambda (cmd cb) (set! captured cmd))))
            (dialog-confirm "say \"hi\" \\ ok" (lambda (ok?) ok?)))
          """#)
        #expect(try engine.evaluate("captured") == .string(
            #"osascript -e 'button returned of (display dialog "say \"hi\" \\ ok" buttons {"Cancel", "OK"} default button "Cancel" cancel button "Cancel")' 2>/dev/null"#))
    }

    /// Confirm/cancel plumbing (the continuation, not the escaping): a
    /// stub runner invokes the callback synchronously with canned
    /// (exit-code stdout stderr), mirroring what a real "OK" click, a
    /// "Cancel" click, and a cancelled/errored osascript call each look
    /// like on the wire.
    @Test func dialogConfirmPlumbsConfirmAndCancel() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dialogs))")

        // "OK" clicked → #t.
        #expect(try engine.evaluate("""
          (let ((result 'unset))
            (parameterize ((current-dialog-runner (lambda (cmd cb) (cb 0 "OK\\n" ""))))
              (dialog-confirm "Proceed?" (lambda (ok?) (set! result ok?))))
            result)
        """) == .true)

        // Cancel raises AppleScript -128 → empty stdout, non-zero exit → #f.
        #expect(try engine.evaluate("""
          (let ((result 'unset))
            (parameterize ((current-dialog-runner (lambda (cmd cb) (cb -1 "" "some error"))))
              (dialog-confirm "Proceed?" (lambda (ok?) (set! result ok?))))
            result)
        """) == .false)

        // A custom ok-label must match exactly — "Cancel" returned (no
        // error path taken) still reads as declined.
        #expect(try engine.evaluate("""
          (let ((result 'unset))
            (parameterize ((current-dialog-runner (lambda (cmd cb) (cb 0 "Continue\\n" ""))))
              (dialog-confirm "Proceed?" (lambda (ok?) (set! result ok?)) 'ok-label "Continue"))
            result)
        """) == .true)
        #expect(try engine.evaluate("""
          (let ((result 'unset))
            (parameterize ((current-dialog-runner (lambda (cmd cb) (cb 0 "Cancel\\n" ""))))
              (dialog-confirm "Proceed?" (lambda (ok?) (set! result ok?)) 'ok-label "Continue"))
            result)
        """) == .false)
    }

    /// dialog-info: single-button alert, no "button returned of" wrapper,
    /// no cancel button (there is nothing to decline). The optional
    /// continuation is a plain 0-arg callback, invoked with no result.
    @Test func dialogInfoBuildsExpectedCommandAndFiresContinuation() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dialogs))")
        try engine.evaluate("""
          (define captured #f)
          (parameterize ((current-dialog-runner (lambda (cmd cb) (set! captured cmd) (cb 0 "" ""))))
            (dialog-info "It's done"))
        """)
        #expect(try engine.evaluate("captured") == .string(
            #"osascript -e 'display dialog "It'\''s done" buttons {"OK"} default button "OK"' 2>/dev/null"#))

        // With a continuation, it fires once the dialog is dismissed.
        #expect(try engine.evaluate("""
          (let ((fired? #f))
            (parameterize ((current-dialog-runner (lambda (cmd cb) (cb 0 "" ""))))
              (dialog-info "Done!" (lambda () (set! fired? #t))))
            fired?)
        """) == .true)
    }

    /// Omitting the continuation must not raise — the common case for a
    /// fire-and-forget info alert with no follow-on work.
    @Test func dialogInfoWithoutContinuationDoesNotRaise() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dialogs))")
        try engine.evaluate("""
          (parameterize ((current-dialog-runner (lambda (cmd cb) (cb 0 "" ""))))
            (dialog-info "Done!"))
        """)
    }
}
