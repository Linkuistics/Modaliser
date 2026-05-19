import Foundation
import Testing
@testable import Modaliser

@Suite("(modaliser theming) library")
struct ModaliserThemingLibraryTests {

    @Test func currentChipThemeReturnsSeedDefaultsBeforeProbe() throws {
        // Before the boot-time probe runs (which it never does in unit
        // tests — root.scm isn't loaded), current-chip-theme returns
        // seeded defaults mirroring the .chip declarations in base.css
        // so callers always see usable values.
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser theming))")
        try engine.evaluate("(define t (current-chip-theme))")
        #expect(try engine.evaluate("(equal? (cdr (assoc 'color t)) \"#ffffff\")") == .true)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'background t)) \"#1e90ff\")") == .true)
        #expect(try engine.evaluate("(= (cdr (assoc 'font-size t)) 56)") == .true)
        #expect(try engine.evaluate("(= (cdr (assoc 'padding t)) 16)") == .true)
        #expect(try engine.evaluate("(= (cdr (assoc 'corner-radius t)) 8)") == .true)
        #expect(try engine.evaluate("(= (cdr (assoc 'border-width t)) 1)") == .true)
    }

    @Test func currentChipThemeFadedReturnsFadedBackground() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser theming))")
        try engine.evaluate("(define t (current-chip-theme 'faded))")
        // The .chip.faded rule overrides only background; the rest
        // inherits from .chip — same shape as 'normal.
        #expect(try engine.evaluate("(equal? (cdr (assoc 'background t)) \"#6f8baa\")") == .true)
        #expect(try engine.evaluate("(= (cdr (assoc 'font-size t)) 56)") == .true)
    }

    @Test func currentChipThemeUnknownVariantRaises() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser theming))")
        #expect(throws: (any Error).self) {
            try engine.evaluate("(current-chip-theme 'rainbow)")
        }
    }

    // Coerce keys are the ones HintsLibrary.swift's lookupFixnum will
    // ultimately read out of the chip alist — they MUST be Scheme exact
    // integers (LispKit .fixnum). JS parseFloat emits doubles for any
    // non-integer CSS value (e.g. "56.5px" from a user's theme.css);
    // those would arrive as .flonum without this coercion and silently
    // break chip painting downstream.

    @Test func coerceChipAlistRoundsFontSize() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser theming))")
        try engine.evaluate("""
          (define result (coerce-chip-alist
                          (list (cons 'font-size 56.5)
                                (cons 'padding 16.0)
                                (cons 'corner-radius 8.0)
                                (cons 'border-width 1.0))))
        """)
        // exact (round 56.5) → 56 (banker's rounding rounds .5 to even)
        // or 57 depending on the rounding mode. Accept either as long
        // as the result is an exact integer the painter can consume.
        #expect(try engine.evaluate("(exact? (cdr (assoc 'font-size result)))") == .true)
        #expect(try engine.evaluate("(exact? (cdr (assoc 'padding result)))") == .true)
        #expect(try engine.evaluate("(exact? (cdr (assoc 'corner-radius result)))") == .true)
        #expect(try engine.evaluate("(exact? (cdr (assoc 'border-width result)))") == .true)
        #expect(try engine.evaluate("(= (cdr (assoc 'padding result)) 16)") == .true)
    }

    @Test func coerceChipAlistLeavesColorStringsAlone() throws {
        // Non-integer keys (notably colours, which are strings) pass
        // through unchanged — coerce-chip-alist only touches the
        // integer-typed keys consumed by lookupFixnum.
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser theming))")
        try engine.evaluate("""
          (define result (coerce-chip-alist
                          (list (cons 'color "#ff0000")
                                (cons 'background "#00ff00"))))
        """)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'color result)) \"#ff0000\")") == .true)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'background result)) \"#00ff00\")") == .true)
    }
}
