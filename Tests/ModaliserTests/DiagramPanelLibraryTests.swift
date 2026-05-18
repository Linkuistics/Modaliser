import Foundation
import Testing
@testable import Modaliser

@Suite("(modaliser diagram-panel) library")
struct DiagramPanelLibraryTests {

    @Test func gridPanelSpecHasTypeAndDimensions() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser diagram-panel))")
        try engine.evaluate("""
          (define p (make-grid-panel-spec 3 2 '(((key . "D") (col . 1) (row . 1) (col-span . 1) (row-span . 1)))))
        """)
        #expect(try engine.evaluate("(eq? (cdr (assoc 'type p)) 'grid)") == .true)
        #expect(try engine.evaluate("(= (cdr (assoc 'cols p)) 3)") == .true)
        #expect(try engine.evaluate("(= (cdr (assoc 'rows p)) 2)") == .true)
    }

    @Test func centerPanelSpecCarriesKey() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser diagram-panel))")
        try engine.evaluate("(define p (make-center-panel-spec \"c\"))")
        #expect(try engine.evaluate("(eq? (cdr (assoc 'type p)) 'center)") == .true)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'key p)) \"c\")") == .true)
    }

    @Test func fillPanelSpecCarriesKey() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser diagram-panel))")
        try engine.evaluate("(define p (make-fill-panel-spec \"m\"))")
        #expect(try engine.evaluate("(eq? (cdr (assoc 'type p)) 'fill)") == .true)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'key p)) \"m\")") == .true)
    }

    @Test func parseMatrixSimpleThirds() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser diagram-panel))")
        try engine.evaluate("""
          (define cells (parse-matrix '(("d" "f" "g"))))
          ;; cells is a list of alists with (key col row col-span row-span)
          (define d (car cells))
        """)
        #expect(try engine.evaluate("(= (length cells) 3)") == .true)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'key d)) \"d\")") == .true)
        #expect(try engine.evaluate("(= (cdr (assoc 'col d)) 1)") == .true)
        #expect(try engine.evaluate("(= (cdr (assoc 'row d)) 1)") == .true)
        #expect(try engine.evaluate("(= (cdr (assoc 'col-span d)) 1)") == .true)
    }

    @Test func parseMatrixOneDimensionalSpan() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser diagram-panel))")
        try engine.evaluate("""
          (define cells (parse-matrix '(("e" "e" #f))))
          (define e (car cells))
        """)
        #expect(try engine.evaluate("(= (length cells) 1)") == .true)
        #expect(try engine.evaluate("(equal? (cdr (assoc 'key e)) \"e\")") == .true)
        #expect(try engine.evaluate("(= (cdr (assoc 'col e)) 1)") == .true)
        #expect(try engine.evaluate("(= (cdr (assoc 'col-span e)) 2)") == .true)
    }

    @Test func parseMatrixTwoDimensionalSpan() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser diagram-panel))")
        try engine.evaluate("""
          (define cells (parse-matrix '(("x" "x" "y")
                                        ("x" "x" "y"))))
        """)
        #expect(try engine.evaluate("(= (length cells) 2)") == .true)
        try engine.evaluate("""
          (define x-cell
            (let loop ((cs cells))
              (if (equal? (cdr (assoc 'key (car cs))) "x") (car cs) (loop (cdr cs)))))
        """)
        #expect(try engine.evaluate("(= (cdr (assoc 'col-span x-cell)) 2)") == .true)
        #expect(try engine.evaluate("(= (cdr (assoc 'row-span x-cell)) 2)") == .true)
    }

    @Test func parseMatrixRejectsNonRectangularKey() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser diagram-panel))")
        // x's bounding box is rows 1-2 × cols 1-2 but cell (2,2) is #f → invalid
        do {
            try engine.evaluate("(parse-matrix '((\"x\" \"x\" \"y\") (\"x\" #f \"y\")))")
            Issue.record("parse-matrix should have thrown on non-rectangular key x")
        } catch {
            // Expected.
        }
    }

    @Test func parseMatrixRejectsUnevenRowLengths() throws {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser diagram-panel))")
        do {
            try engine.evaluate("(parse-matrix '((\"a\" \"b\") (\"c\")))")
            Issue.record("parse-matrix should have thrown on uneven row lengths")
        } catch {
            // Expected.
        }
    }
}
