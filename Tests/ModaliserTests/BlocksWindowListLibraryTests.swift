import Foundation
import Testing
@testable import Modaliser

@Suite("(modaliser blocks window-list) library")
struct BlocksWindowListLibraryTests {

    @Test func makeWindowListBlockWithoutChipsHasNoChipHooks() throws {
        // Absent 'chips? → block renders the row list only, no
        // on-render-fn (chip painting) and no on-leave-fn (cleanup).
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser blocks window-list))")
        try engine.evaluate("(define b (make-window-list-block))")
        #expect(try engine.evaluate("(eq? (cdr (assoc 'type b)) 'window-list)") == .true)
        #expect(try engine.evaluate("(not (assoc 'on-render-fn b))") == .true)
        #expect(try engine.evaluate("(not (assoc 'on-leave-fn b))") == .true)
    }

    @Test func makeWindowListBlockWithChipsEnablesChips() throws {
        // 'chips? #t enables chip painting; chip styling itself comes
        // from (current-chip-theme) — see (modaliser theming).
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser blocks window-list))")
        try engine.evaluate("(define b (make-window-list-block 'chips? #t))")
        #expect(try engine.evaluate("(procedure? (cdr (assoc 'on-render-fn b)))") == .true)
        #expect(try engine.evaluate("(procedure? (cdr (assoc 'on-leave-fn b)))") == .true)
    }

    @Test func makeWindowListBlockLegacyChipOptionsRaises() throws {
        // The old 'chip-options keyword was removed in the chip-theming
        // refactor. Passing it should fail loudly with a migration
        // message pointing at the new .chip CSS surface.
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser blocks window-list))")
        #expect(throws: (any Error).self) {
            try engine.evaluate("(make-window-list-block 'chip-options '())")
        }
    }

    @Test func windowListPayloadCarriesEmptyWindowsByDefault() throws {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else { Issue.record("scheme path"); return }
        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser state-machine))")
        try engine.evaluate("(import (modaliser event-dispatch) (modaliser dsl) (modaliser dom))")
        try engine.evaluateFile(schemePath + "/ui/css.scm")
        try engine.evaluateFile(schemePath + "/ui/overlay.scm")
        try engine.evaluate("(import (modaliser blocks window-list))")
        try engine.evaluate("""
          (define grp (group "w" "Win" 'renderer 'blocks
                        'blocks (list (make-window-list-block))))
          (define html (render-overlay-html grp '("Root") '()))
        """)
        let html = try engine.evaluate("html").asString()
        #expect(html.contains("\"type\":\"window-list\""))
        #expect(html.contains("\"windows\":[]"))
    }

    @Test func windowListRegistersJsAndCss() throws {
        let engine = try SchemeEngine()
        guard let schemePath = engine.schemeDirectoryPath else { Issue.record("scheme path"); return }
        try engine.evaluate("(import (modaliser util) (modaliser keymap) (modaliser state-machine))")
        try engine.evaluate("(import (modaliser event-dispatch) (modaliser dsl) (modaliser dom))")
        try engine.evaluateFile(schemePath + "/ui/css.scm")
        try engine.evaluateFile(schemePath + "/ui/overlay.scm")
        try engine.evaluate("(import (modaliser blocks window-list))")
        try engine.evaluate("""
          (define grp (group "w" "Win" 'renderer 'blocks
                        'blocks (list (make-window-list-block))))
          (define html (render-overlay-html grp '("Root") '()))
        """)
        let html = try engine.evaluate("html").asString()
        #expect(html.contains("overlayBlockRenderers['window-list']"))
        #expect(html.contains(".block-window-list"))
    }
}

/// Grove `window-chips-overlap-same-app-windows`, leaf 020/020 — Stage B:
/// the cross-chip no-overlap invariant + slot-lattice cascade.
///
/// These drive the REAL Scheme `assign-chips` (exported for testing) through
/// the `SchemeEngine`, so the pure placement logic that ships is what's under
/// test — not a mirror. The strong invariant has two parts (see CONTEXT.md):
/// no two chips overlap, and every listed window keeps exactly one chip.
///
/// `assign-chips` consumes annotated entries `(list visible? chip nat-x nat-y)`
/// in label order and returns the placed chips in label order. Chips are
/// 88×88 (the real size); the lattice step is chip-side + host-pad = 100.
@Suite("(modaliser blocks window-list) Stage-B placement invariant (grove 020/020)")
struct WindowListStageBPlacementTests {

    /// Boots an engine with the library imported and Scheme test helpers:
    ///   (mk-chip x y)        — an 88×88 chip alist at (x,y)
    ///   (entry* vis x y wx wy ww wh)
    ///                        — an annotated entry: chip natural corner (x,y),
    ///                          owning-window rect (wx,wy,ww,wh).
    ///   (entry vis x y)      — convenience: a generous 600×400 window whose
    ///                          top-left sits a host-pad (12) above/left of the
    ///                          chip's natural corner (matches paint-and-snapshot:
    ///                          nat = win-origin + host-pad). Big enough that the
    ///                          in-bounds lattice always has room.
    ///   (any-overlap? cs)    — #t iff some pair of chips in `cs` overlaps
    ///                          (using the library's own exported `chips-overlap?`)
    ///   (within? c wx wy ww wh)        — chip c fully inside the window rect
    ///   (all-within? cs wx wy ww wh)   — every chip in cs inside the rect
    ///   (count-outside cs wx wy ww wh) — how many chips fall outside the rect
    private func bootedEngine() throws -> SchemeEngine {
        let engine = try SchemeEngine()
        try engine.evaluate("(import (modaliser blocks window-list))")
        try engine.evaluate("""
          (define (mk-chip x y)
            (list (cons 'label "x") (cons 'x x) (cons 'y y)
                  (cons 'w 88) (cons 'h 88) (cons 'background "n")))
          (define (entry* vis x y wx wy ww wh)
            (list vis (mk-chip x y) x y wx wy ww wh))
          (define (entry vis x y)
            (entry* vis x y (- x 12) (- y 12) 600 400))
          (define (any-overlap? cs)
            (let outer ((cs cs))
              (cond
                ((null? cs) #f)
                (else
                  (let inner ((rest (cdr cs)))
                    (cond
                      ((null? rest) (outer (cdr cs)))
                      ((chips-overlap? (car cs) (car rest)) #t)
                      (else (inner (cdr rest)))))))))
          (define (within? c wx wy ww wh)
            (and (>= (cdr (assoc 'x c)) wx)
                 (>= (cdr (assoc 'y c)) wy)
                 (<= (+ (cdr (assoc 'x c)) (cdr (assoc 'w c))) (+ wx ww))
                 (<= (+ (cdr (assoc 'y c)) (cdr (assoc 'h c))) (+ wy wh))))
          (define (all-within? cs wx wy ww wh)
            (cond ((null? cs) #t)
                  ((within? (car cs) wx wy ww wh)
                   (all-within? (cdr cs) wx wy ww wh))
                  (else #f)))
          (define (count-outside cs wx wy ww wh)
            (let loop ((cs cs) (n 0))
              (cond ((null? cs) n)
                    ((within? (car cs) wx wy ww wh) (loop (cdr cs) n))
                    (else (loop (cdr cs) (+ n 1))))))
          ;; #t iff some pair of chips sits closer than `gap` apart (i.e.
          ;; the gap between their edges is < gap). Inflating one chip by
          ;; `gap` and testing overlap with the other detects exactly that;
          ;; chips exactly `gap` apart pass (strict inequality).
          (define (inflate c g)
            (list (cons 'x (- (cdr (assoc 'x c)) g))
                  (cons 'y (- (cdr (assoc 'y c)) g))
                  (cons 'w (+ (cdr (assoc 'w c)) (* 2 g)))
                  (cons 'h (+ (cdr (assoc 'h c)) (* 2 g)))))
          (define (any-too-close? cs gap)
            (let outer ((cs cs))
              (cond
                ((null? cs) #f)
                (else
                  (let inner ((rest (cdr cs)))
                    (cond
                      ((null? rest) (outer (cdr cs)))
                      ((chips-overlap? (inflate (car cs) gap) (car rest)) #t)
                      (else (inner (cdr rest)))))))))
        """)
        return engine
    }

    /// WORST CASE FROM THE SPEC. Ten same-app windows fully stacked at one
    /// corner: the frontmost is visible at its natural corner, the other nine
    /// are occluded (Stage-A nil) and share the same natural anchor. Stage B
    /// must emit ten chips, all present and pairwise non-overlapping — the
    /// counting argument (≤10 chips, ~96 lattice cells) made concrete.
    @Test func tenFullyStackedSameApp_allDistinctAllPresent() throws {
        let engine = try bootedEngine()
        try engine.evaluate("""
          (define annotated
            (cons (entry #t 312 262)            ; frontmost: on-window chip
                  (let loop ((k 9) (acc '()))   ; nine occluded behind it
                    (if (zero? k) acc
                      (loop (- k 1) (cons (entry #f 312 262) acc))))))
          (define placed (assign-chips annotated 1280 800))
        """)
        #expect(try engine.evaluate("(= (length placed) 10)") == .true)
        #expect(try engine.evaluate("(any-overlap? placed)") == .false)
    }

    /// THE ORIGINAL TWO-iTERM SYMPTOM (Cause 2 guard). Two *visible* chips
    /// landing on the identical natural corner — the exact collision the old
    /// dodge never fixed, because it only de-collided occluded chips. The
    /// cross-chip guard now demotes the second to a lattice slot.
    @Test func twoVisibleChipsSameCorner_deCollided() throws {
        let engine = try bootedEngine()
        try engine.evaluate("""
          (define annotated (list (entry #t 212 162) (entry #t 212 162)))
          (define placed (assign-chips annotated 1280 800))
        """)
        #expect(try engine.evaluate("(= (length placed) 2)") == .true)
        #expect(try engine.evaluate("(any-overlap? placed)") == .false)
        // First (priority) chip keeps its on-window position; second moved.
        #expect(try engine.evaluate("(= (cdr (assoc 'x (car placed))) 212)") == .true)
        #expect(try engine.evaluate("(= (cdr (assoc 'y (car placed))) 162)") == .true)
        #expect(try engine.evaluate("""
          (not (and (= (cdr (assoc 'x (cadr placed))) 212)
                    (= (cdr (assoc 'y (cadr placed))) 162)))
        """) == .true)
    }

    /// NO NEEDLESS MOVEMENT. Already-distinct visible chips pass through
    /// unchanged — Stage B only relocates chips that must move.
    @Test func distinctVisibleChips_passThroughUnchanged() throws {
        let engine = try bootedEngine()
        try engine.evaluate("""
          (define annotated (list (entry #t 100 100) (entry #t 400 400)))
          (define placed (assign-chips annotated 1280 800))
        """)
        #expect(try engine.evaluate("(any-overlap? placed)") == .false)
        #expect(try engine.evaluate("(= (cdr (assoc 'x (car placed))) 100)") == .true)
        #expect(try engine.evaluate("(= (cdr (assoc 'x (cadr placed))) 400)") == .true)
    }

    /// EMPTY INPUT is total — no windows, no chips, no crash.
    @Test func emptyAnnotated_yieldsNoChips() throws {
        let engine = try bootedEngine()
        #expect(try engine.evaluate("(null? (assign-chips '() 1280 800))") == .true)
    }

    /// MIXED CLUSTERS. Two separate same-app clusters, each a visible front
    /// plus occluded backs, plus one lone visible window. All eight chips
    /// present and pairwise distinct; cascaded chips anchor near their own
    /// cluster (a regression check that the anchor is per-window, not global).
    @Test func mixedClusters_allDistinct() throws {
        let engine = try bootedEngine()
        try engine.evaluate("""
          (define annotated
            (list (entry #t 100 100) (entry #f 100 100) (entry #f 100 100)
                  (entry #t 900 600) (entry #f 900 600) (entry #f 900 600)
                  (entry #f 900 600) (entry #t 500 100)))
          (define placed (assign-chips annotated 1280 800))
        """)
        #expect(try engine.evaluate("(= (length placed) 8)") == .true)
        #expect(try engine.evaluate("(any-overlap? placed)") == .false)
    }

    /// IN-BOUNDS CASCADE (grove 040). A fully-occluded window's cascade chip
    /// must land *inside its own window rect*, not flung to free screen space.
    /// The window's origin (130,130) is OFF the screen lattice's 100-grid, so
    /// the screen lattice's nearest free cell to the corner straddles/sits
    /// above the window (outside it) — only an in-bounds lattice anchored at
    /// the window origin keeps the chip within bounds. This test fails on the
    /// pre-040 screen-only cascade and passes after.
    @Test func occludedChipStaysWithinWindowBounds() throws {
        let engine = try bootedEngine()
        try engine.evaluate("""
          ;; window (130,130,260,260); front visible at its natural corner,
          ;; one occluded back sharing the same rect.
          (define annotated
            (list (entry* #t 142 142 130 130 260 260)
                  (entry* #f 142 142 130 130 260 260)))
          (define placed (assign-chips annotated 1280 800))
        """)
        #expect(try engine.evaluate("(= (length placed) 2)") == .true)
        #expect(try engine.evaluate("(any-overlap? placed)") == .false)
        // The occluded back chip (second) sits inside the window rect.
        #expect(try engine.evaluate("(within? (cadr placed) 130 130 260 260)") == .true)
        // …and keeps a full padding gap from the front chip — never touching.
        #expect(try engine.evaluate("(any-too-close? placed 12)") == .false)
    }

    /// IN-BOUNDS CLUSTER PACKING (grove 040). A visible front plus four
    /// occluded backs all sharing one comfortably-large window: every chip —
    /// including all cascaded ones — packs inside that window's bounds, none
    /// spilling to screen space. Window origin is again off the 100-grid to
    /// defeat the screen lattice.
    @Test func occludedClusterPacksWithinLargeWindow() throws {
        let engine = try bootedEngine()
        try engine.evaluate("""
          ;; window (130,130,600,500); 1 visible + 4 occluded, all same rect.
          (define annotated
            (list (entry* #t 142 142 130 130 600 500)
                  (entry* #f 142 142 130 130 600 500)
                  (entry* #f 142 142 130 130 600 500)
                  (entry* #f 142 142 130 130 600 500)
                  (entry* #f 142 142 130 130 600 500)))
          (define placed (assign-chips annotated 1280 800))
        """)
        #expect(try engine.evaluate("(= (length placed) 5)") == .true)
        #expect(try engine.evaluate("(any-overlap? placed)") == .false)
        #expect(try engine.evaluate("(all-within? placed 130 130 600 500)") == .true)
    }

    /// OVERFLOW SPILL (grove 040). When more windows are fully stacked than a
    /// small shared window can host non-overlapping chips, the surplus spills
    /// to the screen lattice — placement stays total (all present) and the
    /// invariant holds (no overlap). The small window (0,0,200,200) holds at
    /// most ~4 chip cells, so eight stacked windows force a spill.
    @Test func smallStackedOverflowSpillsOffWindow() throws {
        let engine = try bootedEngine()
        try engine.evaluate("""
          (define annotated
            (cons (entry* #t 12 12 0 0 200 200)        ; frontmost on-window
                  (let loop ((k 7) (acc '()))          ; seven occluded behind
                    (if (zero? k) acc
                      (loop (- k 1) (cons (entry* #f 12 12 0 0 200 200) acc))))))
          (define placed (assign-chips annotated 1280 800))
        """)
        #expect(try engine.evaluate("(= (length placed) 8)") == .true)
        #expect(try engine.evaluate("(any-overlap? placed)") == .false)
        // The small window cannot host all eight, so at least one spilled.
        #expect(try engine.evaluate("(> (count-outside placed 0 0 200 200) 0)") == .true)
    }

    /// PADDING MAINTAINED (grove 040). Cascade chips must keep the inter-chip
    /// padding gap from every committed chip — never merely "not overlapping".
    /// Ten same-app windows fully stacked: the frontmost is on-window at its
    /// natural corner, the nine occluded cascade around it. Before the
    /// natural-corner anchoring + clearance check, the first cascade cell sat
    /// flush against the front chip (zero gap — touching); now every pair is
    /// at least a padding (12) apart.
    @Test func stackedCascadeChipsMaintainPadding() throws {
        let engine = try bootedEngine()
        try engine.evaluate("""
          (define annotated
            (cons (entry #t 312 262)
                  (let loop ((k 9) (acc '()))
                    (if (zero? k) acc
                      (loop (- k 1) (cons (entry #f 312 262) acc))))))
          (define placed (assign-chips annotated 1280 800))
        """)
        #expect(try engine.evaluate("(= (length placed) 10)") == .true)
        #expect(try engine.evaluate("(any-overlap? placed)") == .false)
        #expect(try engine.evaluate("(any-too-close? placed 12)") == .false)
    }
}
