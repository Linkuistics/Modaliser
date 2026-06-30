import Foundation
import Testing
@testable import Modaliser

@Suite("(modaliser display-actions) library")
struct ModaliserDisplayActionsLibraryTests {

    private func booted() throws -> SchemeEngine {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser dsl) (prefix (modaliser display-actions) display:))")
        return engine
    }

    // ── Pure remap math ────────────────────────────────────────────

    @Test func remapLeftThirdStaysLeftThirdAcrossSizes() throws {
        // Window = left third of a 1200x900 source. Target 3000x2000 of a
        // different aspect. Independent x/y scaling: still the left third of T.
        let engine = try booted()
        try engine.evaluate("""
          (define src (list (cons 'x 0) (cons 'y 0) (cons 'w 1200) (cons 'h 900)))
          (define tgt (list (cons 'x 0) (cons 'y 0) (cons 'w 3000) (cons 'h 2000)))
          (define win (list (cons 'x 0) (cons 'y 0) (cons 'w 400) (cons 'h 900)))
          (define r (display:remap-frame win src tgt))
        """)
        #expect(try engine.evaluate("(= (car r) 0)") == .true)        // newX
        #expect(try engine.evaluate("(= (cadr r) 0)") == .true)       // newY
        #expect(try engine.evaluate("(= (caddr r) 1000)") == .true)   // newW = (1/3)*3000
        #expect(try engine.evaluate("(= (cadddr r) 2000)") == .true)  // newH = 1*2000
    }

    @Test func remapTranslatesTargetOrigin() throws {
        // A target whose origin isn't (0,0): the offset is preserved.
        let engine = try booted()
        try engine.evaluate("""
          (define src (list (cons 'x 0) (cons 'y 0) (cons 'w 1000) (cons 'h 1000)))
          (define tgt (list (cons 'x 2000) (cons 'y 100) (cons 'w 1000) (cons 'h 1000)))
          (define win (list (cons 'x 500) (cons 'y 500) (cons 'w 250) (cons 'h 250)))
          (define r (display:remap-frame win src tgt))
        """)
        #expect(try engine.evaluate("(= (car r) 2500)") == .true)    // 2000 + 0.5*1000
        #expect(try engine.evaluate("(= (cadr r) 600)") == .true)    // 100 + 0.5*1000
        #expect(try engine.evaluate("(= (caddr r) 250)") == .true)
        #expect(try engine.evaluate("(= (cadddr r) 250)") == .true)
    }

    @Test func remapIdentityOnSameDisplay() throws {
        // Remapping onto the display the window already occupies is identity.
        let engine = try booted()
        try engine.evaluate("""
          (define d (list (cons 'x 0) (cons 'y 0) (cons 'w 1440) (cons 'h 900)))
          (define win (list (cons 'x 120) (cons 'y 80) (cons 'w 600) (cons 'h 400)))
          (define r (display:remap-frame win d d))
        """)
        #expect(try engine.evaluate("(= (car r) 120)") == .true)
        #expect(try engine.evaluate("(= (cadr r) 80)") == .true)
        #expect(try engine.evaluate("(= (caddr r) 600)") == .true)
        #expect(try engine.evaluate("(= (cadddr r) 400)") == .true)
    }

    @Test func remapClampsOversizeWithinTarget() throws {
        // A window wider than its fraction allows on T is clamped to stay in T
        // (mirrors move-window's min(width, 1 - x) clamp). Window at x=0.5 of S
        // spanning to the right edge → on a narrower T it must not exceed T.
        let engine = try booted()
        try engine.evaluate("""
          (define src (list (cons 'x 0) (cons 'y 0) (cons 'w 1000) (cons 'h 1000)))
          (define tgt (list (cons 'x 0) (cons 'y 0) (cons 'w 600) (cons 'h 600)))
          (define win (list (cons 'x 500) (cons 'y 0) (cons 'w 500) (cons 'h 1000)))
          (define r (display:remap-frame win src tgt))
        """)
        // fx = 0.5 → newX = 300 ; clamped fw = min(0.5, 0.5) = 0.5 → newW = 300,
        // and newX + newW = 600 = right edge of T (stays within bounds).
        #expect(try engine.evaluate("(= (car r) 300)") == .true)
        #expect(try engine.evaluate("(= (caddr r) 300)") == .true)
        #expect(try engine.evaluate("(<= (+ (car r) (caddr r)) 600)") == .true)
    }

    // ── Source-display selection ───────────────────────────────────

    @Test func displayContainingPointPicksByCentre() throws {
        let engine = try booted()
        try engine.evaluate("""
          (define ds (list (list (cons 'id 1) (cons 'x 0) (cons 'y 0)
                                 (cons 'w 1000) (cons 'h 800))
                           (list (cons 'id 2) (cons 'x 1000) (cons 'y 0)
                                 (cons 'w 1000) (cons 'h 800))))
          (define hit (display:display-containing-point ds 1500 400))
        """)
        #expect(try engine.evaluate("(= (cdr (assoc 'id hit)) 2)") == .true)
        #expect(try engine.evaluate("(eq? #f (display:display-containing-point ds 5000 5000))") == .true)
    }

    // ── Dispatch-key lift ──────────────────────────────────────────

    @Test func displayListBlockLiftsTwoKeysPerLabel() throws {
        // Default 6 labels → 12 block-children: a move key (lowercase) and a
        // focus key (uppercase) per display, all hidden (the rows show the map).
        let engine = try booted()
        try engine.evaluate("""
          (define b (display:display-list-block 'chips? #t))
          (define bc (cdr (assoc 'block-children b)))
        """)
        #expect(try engine.evaluate("(= (length bc) 12)") == .true)
        // First two children are h (move) then H (focus), both hidden.
        #expect(try engine.evaluate("(equal? (cdr (assoc 'key (car bc))) \"h\")") == .true)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'hidden (car bc))) #t)") == .true)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'key (cadr bc))) \"H\")") == .true)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'hidden (cadr bc))) #t)") == .true)
    }

    @Test func displayListBlockHonoursCustomLabels() throws {
        let engine = try booted()
        try engine.evaluate("""
          (define b (display:display-list-block 'chips? #t 'labels '("a" "b")))
          (define bc (cdr (assoc 'block-children b)))
        """)
        #expect(try engine.evaluate("(= (length bc) 4)") == .true)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'key (car bc))) \"a\")") == .true)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'key (cadr bc))) \"A\")") == .true)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'key (caddr bc))) \"b\")") == .true)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'key (cadddr bc))) \"B\")") == .true)
    }
}
