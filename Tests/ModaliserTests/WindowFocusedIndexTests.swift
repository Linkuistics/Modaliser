import Foundation
import Testing
@testable import Modaliser

/// Unit tests for `focused-row-index`, the pure matcher that seeds the
/// global Windows overlay's selection cursor to the focused window
/// (list-cursor-window-focus-k28 / focused-window-seed-k29).
///
/// The matcher is the only branching part of `window-focused-index`; the
/// live thunk just feeds it `(focused-window)` and
/// `(window-list-current-targets)`. Exercising it with stubbed alists keeps
/// the decision logic testable without a live window server.
///
/// Targets shape mirrors `window-list-current-targets`:
///   ((label . window-alist) ...), each window-alist carrying
///   windowId / ownerPid / x / y.
@Suite("window focused-row-index matcher")
struct WindowFocusedIndexTests {

    private func engine() throws -> SchemeEngine {
        let e = try SchemeEngine()
        try e.evaluate("(import (modaliser window-actions))")
        return e
    }

    // Strategy 1 — focused windowId ≠ 0 matches the row with the same id.
    // This is the trustworthy AX-id-vs-AX-id path (same _AXUIElementGetWindow
    // source on both sides), so the id alone settles it even when several
    // rows share the pid.
    @Test func windowIdHitWins() throws {
        let e = try engine()
        try e.evaluate("""
          (define focused '((ownerPid . 7) (windowId . 42) (x . 10) (y . 20)))
          (define targets
            (list
              (cons "1" '((windowId . 11) (ownerPid . 3) (x . 0) (y . 0)))
              (cons "2" '((windowId . 42) (ownerPid . 7) (x . 10) (y . 20)))
              (cons "3" '((windowId . 99) (ownerPid . 7) (x . 5) (y . 5)))))
        """)
        #expect(try e.evaluate("(focused-row-index focused targets)") == .fixnum(1))
    }

    // Strategy 2 — windowId unresolved (0): match owner pid AND exact frame
    // origin. The residual _AXUIElementGetWindow→0 case.
    @Test func idZeroFallsBackToPidAndOrigin() throws {
        let e = try engine()
        try e.evaluate("""
          (define focused '((ownerPid . 7) (windowId . 0) (x . 300) (y . 400)))
          (define targets
            (list
              (cons "1" '((windowId . 11) (ownerPid . 3) (x . 0) (y . 0)))
              (cons "2" '((windowId . 0) (ownerPid . 7) (x . 300) (y . 400)))))
        """)
        #expect(try e.evaluate("(focused-row-index focused targets)") == .fixnum(1))
    }

    // Strategy 2 must not match on pid alone when the origin differs and the
    // pid is ambiguous — a multi-window app at the wrong origin is no match.
    @Test func idZeroPidMatchButWrongOriginAndAmbiguous() throws {
        let e = try engine()
        try e.evaluate("""
          (define focused '((ownerPid . 7) (windowId . 0) (x . 999) (y . 999)))
          (define targets
            (list
              (cons "1" '((windowId . 0) (ownerPid . 7) (x . 1) (y . 1)))
              (cons "2" '((windowId . 0) (ownerPid . 7) (x . 2) (y . 2)))))
        """)
        #expect(try e.evaluate("(focused-row-index focused targets)") == .false)
    }

    // Strategy 3 — windowId 0, origin mismatch, but exactly one row owns the
    // pid (a single-window app): pid alone disambiguates, so seed to it.
    @Test func idZeroSingleWindowAppMatchesOnPidAlone() throws {
        let e = try engine()
        try e.evaluate("""
          (define focused '((ownerPid . 7) (windowId . 0) (x . 999) (y . 999)))
          (define targets
            (list
              (cons "1" '((windowId . 11) (ownerPid . 3) (x . 0) (y . 0)))
              (cons "2" '((windowId . 0) (ownerPid . 7) (x . 300) (y . 400)))))
        """)
        #expect(try e.evaluate("(focused-row-index focused targets)") == .fixnum(1))
    }

    // No-match — focused windowId ≠ 0 but no row carries it: degrade to #f so
    // the caller seeds the cursor to row 0 (never worse than today). The id≠0
    // branch does not fall through to pid matching.
    @Test func noMatchYieldsFalse() throws {
        let e = try engine()
        try e.evaluate("""
          (define focused '((ownerPid . 7) (windowId . 42) (x . 10) (y . 20)))
          (define targets
            (list
              (cons "1" '((windowId . 11) (ownerPid . 3) (x . 0) (y . 0)))))
        """)
        #expect(try e.evaluate("(focused-row-index focused targets)") == .false)
    }

    // Empty target list — nothing to match, #f.
    @Test func emptyTargetsYieldsFalse() throws {
        let e = try engine()
        try e.evaluate("(define focused '((ownerPid . 7) (windowId . 42) (x . 10) (y . 20)))")
        #expect(try e.evaluate("(focused-row-index focused '())") == .false)
    }
}
