import Foundation
import Testing
@testable import Modaliser

// Unit tests for the (modaliser list-cursor) library — the portable cursor
// state machine that backs the selection cursor on embedded live lists
// (list-cursor-k6). It holds the active list's targets accessor and a clamped
// selected index, with a per-render-pass first-wins claim so the first live
// list in a screen owns the cursor (multi-list ownership, design spec §12).
@Suite("(modaliser list-cursor) library")
struct ListCursorLibraryTests {

    private func loaded() throws -> SchemeEngine {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser list-cursor))")
        return engine
    }

    // A render pass that offers a non-empty targets accessor makes the cursor
    // active and seeds the selection at the first row.
    @Test func offerActivatesCursorAtIndexZero() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (define tf (lambda () (list (cons "1" 'a) (cons "2" 'b) (cons "3" 'c))))
          (list-cursor-begin-pass!)
          (list-cursor-offer! tf)
          (list-cursor-end-pass!)
        """)
        #expect(try engine.evaluate("(list-cursor-active?)") == .true)
        #expect(try engine.evaluate("(list-cursor-index)") == .fixnum(0))
        #expect(try engine.evaluate("(list-cursor-count)") == .fixnum(3))
        #expect(try engine.evaluate("(list-cursor-has-selection?)") == .true)
    }

    // A pass with no offer (a screen with no live list) clears the cursor.
    @Test func passWithoutOfferClearsCursor() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (define tf (lambda () (list (cons "1" 'a))))
          (list-cursor-begin-pass!) (list-cursor-offer! tf) (list-cursor-end-pass!)
          (list-cursor-begin-pass!) (list-cursor-end-pass!)
        """)
        #expect(try engine.evaluate("(list-cursor-active?)") == .false)
        #expect(try engine.evaluate("(list-cursor-has-selection?)") == .false)
    }

    // move! shifts the selection and clamps at both ends (no wrap — mirrors the
    // chooser's clamp-on-arrow behaviour).
    @Test func moveClampsAtBothEnds() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (define tf (lambda () (list (cons "1" 'a) (cons "2" 'b) (cons "3" 'c))))
          (list-cursor-begin-pass!) (list-cursor-offer! tf) (list-cursor-end-pass!)
        """)
        #expect(try engine.evaluate("(list-cursor-move! 1)") == .fixnum(1))
        #expect(try engine.evaluate("(list-cursor-move! 1)") == .fixnum(2))
        // Clamp at the bottom.
        #expect(try engine.evaluate("(list-cursor-move! 1)") == .fixnum(2))
        #expect(try engine.evaluate("(list-cursor-move! -1)") == .fixnum(1))
        #expect(try engine.evaluate("(list-cursor-move! -1)") == .fixnum(0))
        // Clamp at the top.
        #expect(try engine.evaluate("(list-cursor-move! -1)") == .fixnum(0))
    }

    // The selected label is the digit (car) of the index-th (label . target)
    // pair — the same digit the immediate selectors dispatch, so ⏎ activation
    // can reuse the existing digit-range dispatch.
    @Test func selectedLabelTracksIndex() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (define tf (lambda () (list (cons "1" 'a) (cons "2" 'b) (cons "3" 'c))))
          (list-cursor-begin-pass!) (list-cursor-offer! tf) (list-cursor-end-pass!)
        """)
        #expect(try engine.evaluate("(list-cursor-selected-label)") == .makeString("1"))
        try engine.evaluate("(list-cursor-move! 1)")
        #expect(try engine.evaluate("(list-cursor-selected-label)") == .makeString("2"))
    }

    // Re-offering the SAME targets accessor across render passes preserves the
    // index — a cursor move's own re-render must not snap the cursor back to the
    // top. Offering a DIFFERENT accessor (a screen change) resets to 0.
    @Test func reofferSameTargetsPreservesIndexDifferentResets() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (define tf-a (lambda () (list (cons "1" 'a) (cons "2" 'b) (cons "3" 'c))))
          (define tf-b (lambda () (list (cons "1" 'x) (cons "2" 'y))))
          (list-cursor-begin-pass!) (list-cursor-offer! tf-a) (list-cursor-end-pass!)
          (list-cursor-move! 2)
        """)
        #expect(try engine.evaluate("(list-cursor-index)") == .fixnum(2))
        // Same accessor re-offered: index preserved.
        try engine.evaluate("(begin (list-cursor-begin-pass!) (list-cursor-offer! tf-a) (list-cursor-end-pass!))")
        #expect(try engine.evaluate("(list-cursor-index)") == .fixnum(2))
        // Different accessor: index resets.
        try engine.evaluate("(begin (list-cursor-begin-pass!) (list-cursor-offer! tf-b) (list-cursor-end-pass!))")
        #expect(try engine.evaluate("(list-cursor-index)") == .fixnum(0))
    }

    // Within one render pass the FIRST offer wins, so the first live-list panel
    // in declaration order owns the cursor (spec §12: multi-list ownership).
    @Test func firstOfferOfPassWins() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (define tf-first  (lambda () (list (cons "1" 'a) (cons "2" 'b))))
          (define tf-second (lambda () (list (cons "1" 'x))))
          (list-cursor-begin-pass!)
          (list-cursor-offer! tf-first)
          (list-cursor-offer! tf-second)
          (list-cursor-end-pass!)
        """)
        #expect(try engine.evaluate("(eq? (list-cursor-active-targets-fn) tf-first)") == .true)
        #expect(try engine.evaluate("(list-cursor-count)") == .fixnum(2))
    }

    // A stored index that is now out of range (the live list shrank between
    // renders — e.g. a window closed) is clamped on read, never crashes.
    @Test func indexClampsWhenTargetsShrink() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (define rows (list (cons "1" 'a) (cons "2" 'b) (cons "3" 'c)))
          (define tf (lambda () rows))
          (list-cursor-begin-pass!) (list-cursor-offer! tf) (list-cursor-end-pass!)
          (list-cursor-move! 2)
          (set! rows (list (cons "1" 'a)))
        """)
        #expect(try engine.evaluate("(list-cursor-index)") == .fixnum(0))
        #expect(try engine.evaluate("(list-cursor-selected-label)") == .makeString("1"))
    }

    // clear! drops the active controller; move!/selected-label go inert.
    @Test func clearDeactivates() throws {
        let engine = try loaded()
        try engine.evaluate("""
          (define tf (lambda () (list (cons "1" 'a))))
          (list-cursor-begin-pass!) (list-cursor-offer! tf) (list-cursor-end-pass!)
          (list-cursor-clear!)
        """)
        #expect(try engine.evaluate("(list-cursor-active?)") == .false)
        #expect(try engine.evaluate("(list-cursor-move! 1)") == .fixnum(0))
        #expect(try engine.evaluate("(list-cursor-selected-label)") == .false)
    }
}
