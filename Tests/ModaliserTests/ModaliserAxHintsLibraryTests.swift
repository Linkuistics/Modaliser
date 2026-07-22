import Foundation
import Testing
@testable import Modaliser

@Suite("(modaliser ax-hints) library")
struct ModaliserAxHintsLibraryTests {
    @Test func labelPairsTruncatesAtMinLength() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser ax-hints))")
        try engine.evaluate("(define ps (label-pairs '(\"a\" \"b\" \"c\") '(1 2)))")
        #expect(try engine.evaluate("(= (length ps) 2)") == .true)
        #expect(try engine.evaluate("(equal? (car (car ps)) \"a\")") == .true)
        #expect(try engine.evaluate("(= (cdr (car ps)) 1)") == .true)
    }

    @Test func axTargetHintsHandlesEmpty() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser ax-hints))")
        #expect(try engine.evaluate("(null? (ax-target-hints '() '()))") == .true)
    }

    @Test func defaultHintOptionsIsAlist() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser ax-hints))")
        #expect(try engine.evaluate("(list? default-hint-options)") == .true)
        // Probe one expected key.
        #expect(try engine.evaluate("(equal? (cdr (assoc 'font-size default-hint-options)) 24)") == .true)
    }

    // MARK: - Per-char narrowing styling (narrowing-dim-state-k30)

    /// Absent (or non-positive) 'consumed — every caller before this key
    /// existed — omits BOTH 'consumed and 'dim-color from the built entry
    /// entirely, so HintsLibrary.swift's makeHintPanel takes the plain
    /// single-colour path unchanged (output is byte-identical to before
    /// this key existed).
    @Test func axTargetHintsOmitsConsumedByDefault() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser ax-hints))")
        try engine.evaluate(#"""
          (define h (car (ax-target-hints
                            (list (cons "a" (list (cons 'handle #f) (cons 'x 0) (cons 'y 0))))
                            '())))
        """#)
        #expect(try engine.evaluate("(assoc 'consumed h)") == .false)
        #expect(try engine.evaluate("(assoc 'dim-color h)") == .false)
    }

    /// A positive 'consumed in opts stamps BOTH 'consumed and the given
    /// 'dim-color onto every built entry — the call-wide override
    /// narrowing's surviving chip group uses (one shared value per call,
    /// not threaded per-entry — see (modaliser blocks herdr-list)'s
    /// herdr-paint-chip-targets!).
    @Test func axTargetHintsStampsConsumedAndDimColorWhenProvided() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser ax-hints))")
        try engine.evaluate(#"""
          (define h (car (ax-target-hints
                            (list (cons "a" (list (cons 'handle #f) (cons 'x 0) (cons 'y 0))))
                            (list (cons 'consumed 1) (cons 'dim-color "#123456")))))
        """#)
        #expect(try engine.evaluate("(= (cdr (assoc 'consumed h)) 1)") == .true)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'dim-color h)) \"#123456\")") == .true)
    }

    /// consumed with no explicit dim-color falls back to the entry's own
    /// resolved 'color — mirrors border-color's existing color fallback in
    /// the same function.
    @Test func axTargetHintsDimColorDefaultsToColorWhenOmitted() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser ax-hints))")
        try engine.evaluate(#"""
          (define h (car (ax-target-hints
                            (list (cons "a" (list (cons 'handle #f) (cons 'x 0) (cons 'y 0))))
                            (list (cons 'consumed 1) (cons 'color "#abcdef")))))
        """#)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'dim-color h)) \"#abcdef\")") == .true)
    }

    // MARK: - Anchor corner (mini-chip-size-and-label-anchor-k38)

    /// Absent 'anchor — every caller before this key existed, including an
    /// entry with no 'w at all — places the chip top-left + padding
    /// unchanged (output is byte-identical to before this key existed).
    @Test func axTargetHintsDefaultsToTopLeftAnchorWithNoWKey() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser ax-hints) (modaliser theming))")
        try engine.evaluate(#"""
          (define h (car (ax-target-hints
                            (list (cons "a" (list (cons 'handle #f) (cons 'x 100) (cons 'y 50))))
                            (list (cons 'font-size 10) (cons 'padding 2)))))
        """#)
        // chip-size = 10 + 2*2 = 14; host-pad is theming's chip-host-padding.
        try engine.evaluate("(define expected-x (+ 100 (chip-host-padding)))")
        #expect(try engine.evaluate("(= (cdr (assoc 'x h)) expected-x)") == .true)
    }

    /// 'anchor 'right, element tall enough that the requested chip-size
    /// isn't clamped: reads the element's own 'w to place the chip flush
    /// with its right edge (a small fixed inset, not chip-host-padding —
    /// see ax-target-hints' own header), and vertically centres it within
    /// the element's 'h instead of top-anchoring.
    @Test func axTargetHintsRightAnchorPositionsAtEdgeWhenUnclamped() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser ax-hints))")
        try engine.evaluate(#"""
          (define h (car (ax-target-hints
                            (list (cons "a" (list (cons 'handle #f) (cons 'x 100) (cons 'y 50)
                                                   (cons 'w 200) (cons 'h 100))))
                            (list (cons 'font-size 10) (cons 'padding 2) (cons 'anchor 'right)))))
        """#)
        // requested chip-size = 10 + 2*2 = 14, well under the element's h=100
        // so it's unclamped. Right edge = 100+200 = 300, minus chip-size(14),
        // minus the 'right-only 2px edge inset = 284. Vertically centred in
        // h=100: 50 + (100-14)/2 = 93. font-size unchanged at 10.
        #expect(try engine.evaluate("(= (cdr (assoc 'x h)) 284)") == .true)
        #expect(try engine.evaluate("(= (cdr (assoc 'y h)) 93)") == .true)
        #expect(try engine.evaluate("(= (cdr (assoc 'w h)) 14)") == .true)
        #expect(try engine.evaluate("(= (cdr (assoc 'font-size h)) 10)") == .true)
    }

    /// 'anchor 'right, element SHORTER than the requested chip-size: the
    /// chip clamps down to the element's own 'h MINUS a small margin —
    /// never overflows a short sidebar row/tab title regardless of the
    /// requested ceiling, and never fills the row edge-to-edge either
    /// (two elements packed with zero gap in cell-space would otherwise
    /// paint chips touching exactly, which reads as "colliding" even
    /// though it's mathematically not an overlap —
    /// mini-chip-size-and-label-anchor-k38 live dogfooding). font-size
    /// re-derives from the clamped size rather than staying at the (now
    /// too-large) requested value.
    @Test func axTargetHintsRightAnchorClampsToElementHeightMinusMargin() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser ax-hints))")
        try engine.evaluate(#"""
          (define h (car (ax-target-hints
                            (list (cons "a" (list (cons 'handle #f) (cons 'x 100) (cons 'y 50)
                                                   (cons 'w 200) (cons 'h 10))))
                            (list (cons 'font-size 10) (cons 'padding 2) (cons 'anchor 'right)))))
        """#)
        // requested chip-size = 14 > h=10, so chip-size clamps to
        // max(1, 10 - row-margin(4)) = 6.
        // font-size re-derives: max(1, 6 - 2*2) = 2.
        // x = 100+200-6-2 = 292; y = 50 + (10-6)/2 = 52 (2px margin above/below).
        #expect(try engine.evaluate("(= (cdr (assoc 'w h)) 6)") == .true)
        #expect(try engine.evaluate("(= (cdr (assoc 'font-size h)) 2)") == .true)
        #expect(try engine.evaluate("(= (cdr (assoc 'x h)) 292)") == .true)
        #expect(try engine.evaluate("(= (cdr (assoc 'y h)) 52)") == .true)
    }

    /// Two elements that touch exactly (zero gap in element-space, the live
    /// sidebar's own common case once ui-layout-chip-entries' boundary fix
    /// makes touching rows genuinely touch in pixel-space too) must still
    /// get a VISIBLE gap between their painted chips, not just a
    /// non-overlapping one — two 36px chips meeting edge-to-edge reads as
    /// "colliding" to the eye. Uses production-shaped inputs (36px request,
    /// the mini-chip default) so this exercises the exact clamp path real
    /// sidebar painting hits.
    @Test func axTargetHintsRightAnchorLeavesGapBetweenTouchingElements() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser ax-hints))")
        try engine.evaluate(#"""
          (define hs (ax-target-hints
                       (list (cons "a" (list (cons 'handle #f) (cons 'x 0) (cons 'y 0)
                                              (cons 'w 50) (cons 'h 36)))
                             (cons "b" (list (cons 'handle #f) (cons 'x 0) (cons 'y 36)
                                              (cons 'w 50) (cons 'h 36))))
                       (list (cons 'font-size 24) (cons 'padding 6) (cons 'anchor 'right))))
          (define a (car hs))
          (define b (cadr hs))
          (define gap (- (cdr (assoc 'y b)) (+ (cdr (assoc 'y a)) (cdr (assoc 'h a)))))
        """#)
        #expect(try engine.evaluate("(> gap 0)") == .true)
    }
}
