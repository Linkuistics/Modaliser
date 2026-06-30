import Foundation
import Testing
@testable import Modaliser

@Suite("(modaliser blocks display-list) library")
struct BlocksDisplayListLibraryTests {

    @Test func makeDisplayListBlockWithoutChipsHasNoChipHooks() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser blocks display-list))")
        try engine.evaluate("(define b (make-display-list-block))")
        #expect(try engine.evaluate("(eq? (cdr (assoc 'type b)) 'display-list)") == .true)
        #expect(try engine.evaluate("(not (assoc 'on-render-fn b))") == .true)
        #expect(try engine.evaluate("(not (assoc 'on-leave-fn b))") == .true)
    }

    @Test func makeDisplayListBlockWithChipsEnablesChips() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser blocks display-list))")
        try engine.evaluate("(define b (make-display-list-block 'chips? #t))")
        #expect(try engine.evaluate("(procedure? (cdr (assoc 'on-render-fn b)))") == .true)
        #expect(try engine.evaluate("(procedure? (cdr (assoc 'on-leave-fn b)))") == .true)
    }

    @Test func defaultDisplayLabelsAreHJKLNO() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser blocks display-list))")
        #expect(try engine.evaluate(
            "(equal? default-display-labels '(\"h\" \"j\" \"k\" \"l\" \"n\" \"o\"))") == .true)
    }

    @Test func displayChipForIsRoundAndTopRight() throws {
        // Synthetic display + theme — pure geometry, no native call. A 1440x900
        // display at origin (0,0); theme font-size 56, padding 16 → size 88,
        // host-pad 12. Round: corner-radius = floor(88/2) = 44. Top-right:
        // x = 0 + 1440 - 88 - 12 = 1340 ; y = 0 + 12 = 12.
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser blocks display-list))")
        try engine.evaluate("""
          (define disp (list (cons 'id 1) (cons 'x 0) (cons 'y 0)
                             (cons 'w 1440) (cons 'h 900) (cons 'is-primary #t)))
          (define theme (list (cons 'color "#fff") (cons 'background "#2ca58d")
                              (cons 'font-size 56) (cons 'padding 16)
                              (cons 'corner-radius 8) (cons 'border-width 1)
                              (cons 'border-color "#000")))
          (define c (display-chip-for "h" disp theme 'top-right))
        """)
        #expect(try engine.evaluate("(= (cdr (assoc 'w c)) 88)") == .true)
        #expect(try engine.evaluate("(= (cdr (assoc 'h c)) 88)") == .true)
        #expect(try engine.evaluate("(= (cdr (assoc 'corner-radius c)) 44)") == .true)
        #expect(try engine.evaluate("(= (cdr (assoc 'x c)) 1340)") == .true)
        #expect(try engine.evaluate("(= (cdr (assoc 'y c)) 12)") == .true)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'label c)) \"h\")") == .true)
    }

    @Test func displayChipForTopLeftCorner() throws {
        // Same display/theme; 'top-left → x = 0 + 12 = 12, y = 0 + 12 = 12.
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser blocks display-list))")
        try engine.evaluate("""
          (define disp (list (cons 'id 1) (cons 'x 0) (cons 'y 0)
                             (cons 'w 1440) (cons 'h 900) (cons 'is-primary #t)))
          (define theme (list (cons 'color "#fff") (cons 'background "#2ca58d")
                              (cons 'font-size 56) (cons 'padding 16)
                              (cons 'corner-radius 8) (cons 'border-width 1)
                              (cons 'border-color "#000")))
          (define c (display-chip-for "h" disp theme 'top-left))
        """)
        #expect(try engine.evaluate("(= (cdr (assoc 'x c)) 12)") == .true)
        #expect(try engine.evaluate("(= (cdr (assoc 'y c)) 12)") == .true)
    }
}
