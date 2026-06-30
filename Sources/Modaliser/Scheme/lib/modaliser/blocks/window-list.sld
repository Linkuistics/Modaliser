;; (modaliser blocks window-list) — block constructor for the
;; window-list block. Lifts the labelled windows-list section from
;; the old diagram renderer, plus the chip-painting side-effect.
;;
;; (make-window-list-block . opts) → block-spec alist
;;
;; Opts:
;;   'chips?  BOOL — default #f. When #t, the block's on-render-fn
;;                   computes chip positions, runs window-visible-at?
;;                   probes, and forwards to hints-show. The block's
;;                   payload also carries the current windows list so
;;                   the rendered rows mirror the chip placement.
;;
;; Chip styling is no longer threaded through this constructor. The
;; per-chip alist is built at paint time from (current-chip-theme), which
;; reads the resolved .chip / .chip.faded CSS rules from base.css plus
;; the user's ~/.config/modaliser/theme.css. See (modaliser theming).
;;
;; The current window snapshot is exposed via window-list-current-labels
;; so the parent group can build a (key-range …) that dispatches
;; per-digit window focus.

(define-library (modaliser blocks window-list)
  (export make-window-list-block
          window-list-current-labels
          window-list-current-targets
          ;; Exported for unit testing the Stage-B placement invariant
          ;; (see SameAppChipCollisionTests / window-list tests).
          assign-chips
          chips-overlap?
          ;; Exported for unit testing the multi-display bounding box that
          ;; lets chips land on non-primary displays (see window-list tests).
          displays-bounding-box
          shift-chip-xy)
  (import (scheme base)
          (modaliser util)
          (modaliser window)
          (modaliser hints)
          (modaliser ax-hints)
          (modaliser overlay-assets)
          (modaliser theming))
  (begin

    ;; Per-render state — refreshed by the on-render effect every render.
    ;; The parent group's focus-by-digit binding reads from these.
    (define current-window-targets '())   ;; ((label . window-alist) ...)
    (define current-windows-data '())     ;; ((label . app . title . visible) shape, see build-row)

    (define (window-list-current-targets) current-window-targets)
    (define (window-list-current-labels)
      (map car current-window-targets))

    (define default-window-labels
      (list "1" "2" "3" "4" "5" "6" "7" "8" "9" "0"))

    ;; ─── Chip placement helpers — lifted from window-actions.sld ────
    ;; Kept private to this library so it owns chip painting end-to-end.
    ;;
    ;; The clearance between a chip and its host's top-left, between a
    ;; chip and any occluding window edge, and between two chips that
    ;; dodge each other are all the same value: `(chip-host-padding)`
    ;; from (modaliser theming). See its docstring for the rationale.

    (define (chips-overlap? a b)
      (let ((ax (cdr (assoc 'x a))) (ay (cdr (assoc 'y a)))
            (aw (cdr (assoc 'w a))) (ah (cdr (assoc 'h a)))
            (bx (cdr (assoc 'x b))) (by (cdr (assoc 'y b)))
            (bw (cdr (assoc 'w b))) (bh (cdr (assoc 'h b))))
        (and (< ax (+ bx bw))
             (< bx (+ ax aw))
             (< ay (+ by bh))
             (< by (+ ay ah)))))

    (define (chip-with-position c nx ny)
      (map (lambda (entry)
             (cond
               ((eq? (car entry) 'x) (cons 'x nx))
               ((eq? (car entry) 'y) (cons 'y ny))
               (else entry)))
           c))

    (define (clamp-chip-to-screen c sw sh)
      (let* ((cx (cdr (assoc 'x c))) (cy (cdr (assoc 'y c)))
             (cw (cdr (assoc 'w c))) (ch (cdr (assoc 'h c)))
             (nx (max 0 (min cx (- sw cw))))
             (ny (max 0 (min cy (- sh ch)))))
        (chip-with-position c nx ny)))

    (define (find-overlapping placed c)
      (cond
        ((null? placed) #f)
        ((chips-overlap? c (car placed)) (car placed))
        (else (find-overlapping (cdr placed) c))))

    ;; Like find-overlapping, but treats `c` as inflated by `gap` on every
    ;; side, so a cell is rejected unless its chip clears every committed
    ;; chip by at least `gap`. This is what keeps the inter-chip padding
    ;; around cascaded chips — not merely non-overlap — so two chips on
    ;; misaligned grids (e.g. an on-window chip and a lattice slot) never
    ;; touch. Because adjacent same-lattice cells sit exactly `gap` apart
    ;; (step = chip + gap) and the test is strict, same-lattice neighbours
    ;; still pass: the gap only bites against off-grid committed chips.
    (define (find-too-close placed c gap)
      (let ((cx (- (cdr (assoc 'x c)) gap))
            (cy (- (cdr (assoc 'y c)) gap))
            (cw (+ (cdr (assoc 'w c)) (* 2 gap)))
            (ch (+ (cdr (assoc 'h c)) (* 2 gap))))
        (let loop ((placed placed))
          (cond
            ((null? placed) #f)
            (else
              (let* ((p (car placed))
                     (px (cdr (assoc 'x p))) (py (cdr (assoc 'y p)))
                     (pw (cdr (assoc 'w p))) (ph (cdr (assoc 'h p))))
                (if (and (< cx (+ px pw)) (< px (+ cx cw))
                         (< cy (+ py ph)) (< py (+ cy ch)))
                  p
                  (loop (cdr placed)))))))))

    (define (chip-with-background chip new-bg)
      (map (lambda (entry)
             (if (eq? (car entry) 'background)
               (cons 'background new-bg)
               entry))
           chip))

    (define (window-chip-for digit win opts)
      (let* ((wx (cdr (assoc 'x win))) (wy (cdr (assoc 'y win)))
             (font-size (cdr (assoc 'font-size opts)))
             (padding (cdr (assoc 'padding opts)))
             (host-pad (chip-host-padding))
             (chip-x (+ wx host-pad))
             (chip-y (+ wy host-pad))
             (chip-size (+ font-size (* 2 padding))))
        (list (cons 'label digit)
              (cons 'x chip-x) (cons 'y chip-y)
              (cons 'w chip-size) (cons 'h chip-size)
              (cons 'font-size font-size)
              (cons 'padding padding)
              (cons 'corner-radius (cdr (assoc 'corner-radius opts)))
              (cons 'color (cdr (assoc 'color opts)))
              (cons 'background (cdr (assoc 'background opts)))
              (cons 'border-width (cdr (assoc 'border-width opts)))
              (cons 'border-color (cdr (assoc 'border-color opts))))))

    ;; ─── Stage B — cross-chip invariant + slot-lattice cascade ──────
    ;; A single assignment pass over ALL chips that guarantees the
    ;; strong invariant (no two chips overlap; every window keeps one
    ;; chip). Replaces the old visible/occluded split and the
    ;; attempt-bounded dodge — the guarantee is now structural, leaning
    ;; on the ≤10-chip cap (default-window-labels). See
    ;; docs/specs/window-chip-placement-design.md §"Stage B".

    (define (floor-div a b)
      (exact (floor (/ a b))))

    ;; The slot lattice — a screen-covering tiling of chip-sized cells.
    ;; step = chip side + inter-chip padding, so adjacent cells' chips
    ;; stay disjoint (gap = padding). Degenerate guard: if a pathological
    ;; tiny screen yields fewer than `min-cells` cells, drop the padding
    ;; (step → chip side) so more cells exist — chips may then touch
    ;; edges but never overlap (chips-overlap? is strict). This cannot
    ;; arise on any supported display; it only keeps the proof total.
    (define (build-lattice sw sh chip-w chip-h min-cells)
      (let* ((pad (chip-host-padding))
             (step-full (+ chip-w pad))
             (cells-full (* (max 1 (floor-div sw step-full))
                            (max 1 (floor-div sh step-full))))
             (step (if (>= cells-full min-cells) step-full chip-w)))
        (let loop-j ((j 0) (acc '()))
          (let ((y (* j step)))
            (if (> (+ y chip-h) sh)
              (if (null? acc)
                ;; Screen smaller than one chip — a single clamped cell.
                (list (cons (max 0 (- sw chip-w)) (max 0 (- sh chip-h))))
                (reverse acc))
              (let loop-i ((i 0) (acc acc))
                (let ((x (* i step)))
                  (if (> (+ x chip-w) sw)
                    (loop-j (+ j 1) acc)
                    (loop-i (+ i 1) (cons (cons x y) acc))))))))))

    ;; Tile the on-screen part of a window's rect into chip-sized cells,
    ;; anchored at the window's *natural chip corner* (origin + padding),
    ;; not its raw origin. On-window chips sit at that natural corner, so
    ;; aligning the lattice there lets cascade chips pack flush against the
    ;; same grid and keep a full padding gap from the front chip (anchoring
    ;; at the raw origin offsets the grid by a pad, leaving the nearest
    ;; cells touching the front chip). step = chip side + inter-chip
    ;; padding — the same as the screen lattice, so a cascade chip that
    ;; must spill from here still respects the clearance check against
    ;; committed chips. Unlike `build-lattice` there is no degenerate
    ;; min-cells guard: this lattice is allowed to be small or empty — a
    ;; window too small to host a free cell simply falls through to the
    ;; screen lattice (the overflow spill). The region is clipped to the
    ;; screen so a window straddling an edge cannot yield an off-screen cell.
    (define (window-cells wx wy ww wh sw sh chip-w chip-h)
      (let* ((pad (chip-host-padding))
             (step (+ chip-w pad))
             (x0 (max 0 (+ wx pad))) (y0 (max 0 (+ wy pad)))
             (x1 (min sw (+ wx ww))) (y1 (min sh (+ wy wh))))
        (let loop-j ((j 0) (acc '()))
          (let ((y (+ y0 (* j step))))
            (if (> (+ y chip-h) y1)
              (reverse acc)
              (let loop-i ((i 0) (acc acc))
                (let ((x (+ x0 (* i step))))
                  (if (> (+ x chip-w) x1)
                    (loop-j (+ j 1) acc)
                    (loop-i (+ i 1) (cons (cons x y) acc))))))))))

    ;; Nearest free lattice cell (by cell-centre distance) to `anchor`
    ;; — the chip's own window natural corner — skipping cells whose chip
    ;; comes within a padding gap of any already-committed chip (so chips
    ;; never touch, not merely never overlap). Returns a (x . y) cell
    ;; origin, or #f if every cell is blocked (cannot happen with ≤10 chips
    ;; on a real screen lattice — see the spec's counting proof).
    (define (nearest-free-cell lattice committed chip
                               anchor-x anchor-y chip-w chip-h)
      (let loop ((cells lattice) (best #f) (best-d #f))
        (cond
          ((null? cells) best)
          (else
            (let* ((cell (car cells))
                   (cand (chip-with-position chip (car cell) (cdr cell))))
              (if (find-too-close committed cand (chip-host-padding))
                (loop (cdr cells) best best-d)
                (let* ((ccx (+ (car cell) (/ chip-w 2)))
                       (ccy (+ (cdr cell) (/ chip-h 2)))
                       (dx (- ccx anchor-x)) (dy (- ccy anchor-y))
                       (d (+ (* dx dx) (* dy dy))))
                  (if (or (not best-d) (< d best-d))
                    (loop (cdr cells) cell d)
                    (loop (cdr cells) best best-d)))))))))

    ;; assign-chips: the Stage-B pass. `annotated` is a list, in label
    ;; order, of entries (list visible? chip nat-x nat-y wx wy ww wh) where:
    ;;   visible? — #t if Stage A gave the chip an on-window position,
    ;;              #f if the window has no usable area (cascade);
    ;;   chip     — the chip alist at its Stage-A position (visible) or
    ;;              its faded natural position (occluded);
    ;;   nat-x,
    ;;   nat-y    — the chip's own window natural corner (lattice anchor);
    ;;   wx,wy,
    ;;   ww,wh    — the owning window's rect, used to build an in-bounds
    ;;              lattice so a cascaded chip stays over its own window.
    ;; Returns the placed chips in label order, pairwise non-overlapping.
    (define (assign-chips annotated sw sh)
      (if (null? annotated)
        '()
        (let* ((n (length annotated))
               (chip0 (cadr (car annotated)))
               (chip-w (cdr (assoc 'w chip0)))
               (chip-h (cdr (assoc 'h chip0)))
               (lattice (build-lattice sw sh chip-w chip-h n))
               (indexed
                 (let loop ((es annotated) (i 0) (acc '()))
                   (if (null? es) (reverse acc)
                     (loop (cdr es) (+ i 1) (cons (cons i (car es)) acc))))))
          ;; Pass 1 — on-window chips: commit at the Stage-A position iff
          ;; clear of all prior commits; otherwise demote to the cascade
          ;; pool. Occluded chips (Stage-A #f) go straight to the pool.
          (let pass1 ((items indexed) (committed '()) (results '()) (deferred '()))
            (cond
              ((null? items)
               ;; Pass 2 — cascade + demoted chips: each takes the nearest
               ;; free slot to its own window natural corner, preferring a
               ;; cell inside its own window's bounds (window-cells) so the
               ;; chip stays over its window; only when no in-bounds cell is
               ;; free does it spill to the screen-covering lattice.
               (let pass2 ((ds (reverse deferred)) (committed committed) (results results))
                 (cond
                   ((null? ds)
                    (let reasm ((i 0) (acc '()))
                      (if (>= i n) (reverse acc)
                        (reasm (+ i 1) (cons (cdr (assoc i results)) acc)))))
                   (else
                     (let* ((d (car ds))
                            (idx (car d))
                            (entry (cdr d))
                            (chip (car (cdr entry)))
                            (nat-x (list-ref entry 2))
                            (nat-y (list-ref entry 3))
                            (win-x (list-ref entry 4))
                            (win-y (list-ref entry 5))
                            (win-w (list-ref entry 6))
                            (win-h (list-ref entry 7))
                            (anchor-x (+ nat-x (/ chip-w 2)))
                            (anchor-y (+ nat-y (/ chip-h 2)))
                            (in-cells (window-cells win-x win-y win-w win-h
                                                    sw sh chip-w chip-h))
                            (cell (or (nearest-free-cell in-cells committed chip
                                                         anchor-x anchor-y chip-w chip-h)
                                      (nearest-free-cell lattice committed chip
                                                         anchor-x anchor-y chip-w chip-h)))
                            (placed (clamp-chip-to-screen
                                      (if cell
                                        (chip-with-position chip (car cell) (cdr cell))
                                        chip)
                                      sw sh)))
                       (pass2 (cdr ds)
                              (cons placed committed)
                              (cons (cons idx placed) results)))))))
              (else
                (let* ((item (car items))
                       (idx (car item))
                       (entry (cdr item))
                       (visible? (car entry))
                       (chip (cadr entry))
                       (clamped (clamp-chip-to-screen chip sw sh)))
                  (if (and visible? (not (find-overlapping committed clamped)))
                    (pass1 (cdr items)
                           (cons clamped committed)
                           (cons (cons idx clamped) results)
                           deferred)
                    (pass1 (cdr items) committed results
                           (cons item deferred))))))))))

    ;; ─── Multi-display chip placement (desktop bounding box) ───────
    ;; The Stage-B lattice + clamp work in a single (0,0)-(w,h) rect.
    ;; (primary-screen-size) is the PRIMARY display only, so on a
    ;; multi-display desktop every chip got clamped onto the primary —
    ;; a window on a second display had its chip pinned to the primary's
    ;; edge. Instead we run Stage B in the DESKTOP BOUNDING BOX (the
    ;; union of every display's AX-visible frame), translating chip /
    ;; window coords into box-relative space (origin → 0,0) for the
    ;; placement pass and back afterwards. A chip's natural position is
    ;; always on a real display (inside the box), so it keeps that
    ;; position; only genuine cascade overflow is clamped — now to the
    ;; whole desktop, not the primary.

    ;; Pure: bounding box (list ox oy w h) of a display alist list, each
    ;; ((x . X) (y . Y) (w . W) (h . H) …). Empty → (0 0 0 0).
    (define (displays-bounding-box ds)
      (if (null? ds)
        (list 0 0 0 0)
        (let loop ((rest ds) (ox #f) (oy #f) (mx #f) (my #f))
          (if (null? rest)
            (list ox oy (- mx ox) (- my oy))
            (let* ((d (car rest))
                   (x (cdr (assoc 'x d))) (y (cdr (assoc 'y d)))
                   (w (cdr (assoc 'w d))) (h (cdr (assoc 'h d))))
              (loop (cdr rest)
                    (if ox (min ox x) x)
                    (if oy (min oy y) y)
                    (if mx (max mx (+ x w)) (+ x w))
                    (if my (max my (+ y h)) (+ y h))))))))

    ;; Live desktop bounding box; falls back to the primary screen size
    ;; when no displays are reported.
    (define (desktop-bounds)
      (let ((ds (list-displays)))
        (if (pair? ds)
          (displays-bounding-box ds)
          (let ((s (primary-screen-size)))
            (list 0 0 (cdr (assoc 'w s)) (cdr (assoc 'h s)))))))

    ;; Translate a chip alist's x/y by (dx,dy); other entries untouched.
    (define (shift-chip-xy c dx dy)
      (map (lambda (e)
             (cond ((eq? (car e) 'x) (cons 'x (+ (cdr e) dx)))
                   ((eq? (car e) 'y) (cons 'y (+ (cdr e) dy)))
                   (else e)))
           c))

    ;; Translate one annotated entry (visible? chip nat-x nat-y wx wy ww wh)
    ;; into box-relative space by (dx,dy): chip alist, natural corner, and
    ;; window origin shift; the window size does not.
    (define (shift-annotated-entry entry dx dy)
      (list (list-ref entry 0)
            (shift-chip-xy (list-ref entry 1) dx dy)
            (+ (list-ref entry 2) dx)
            (+ (list-ref entry 3) dy)
            (+ (list-ref entry 4) dx)
            (+ (list-ref entry 5) dy)
            (list-ref entry 6)
            (list-ref entry 7)))

    ;; ─── on-render side-effect ─────────────────────────────────────
    ;; Reads chip styling from (current-chip-theme) at paint time so
    ;; users theme chips by editing CSS, not by passing options through
    ;; the block constructor. The 'normal variant feeds the chip
    ;; geometry + appearance; the 'faded variant contributes only its
    ;; background, swapped in for chips whose window is occluded.
    (define (paint-and-snapshot!)
      (let* ((normal-theme (current-chip-theme 'normal))
             (faded-theme  (current-chip-theme 'faded))
             (faded-bg     (cdr (assoc 'background faded-theme)))
             (ws (list-current-space-windows))
             (labelled (label-pairs default-window-labels ws))
             (raw-chips
               (map (lambda (lw)
                      (window-chip-for (car lw) (cdr lw) normal-theme))
                    labelled))
             ;; Ask the window system for the best chip placement on
             ;; each window: find-chip-position walks the on-screen
             ;; z-order, subtracts front-er-window rects from the target
             ;; rect, and either honours the natural top-left (when its
             ;; padded chip rect fits cleanly in some fragment) or
             ;; relocates the chip to the top-left of the next clear
             ;; fragment. #f means no fragment can host the chip — the
             ;; chip keeps its natural position, gets faded styling, and
             ;; is routed to the slot-lattice cascade by `assign-chips`
             ;; (Stage B) downstream.
             ;;
             ;; Each annotated entry is
             ;; (list visible? chip nat-x nat-y wx wy ww wh):
             ;; nat-x/nat-y are the chip's natural corner (captured before
             ;; relocation) — Stage B uses them as the lattice anchor; the
             ;; window rect wx/wy/ww/wh lets Stage B build an in-bounds
             ;; lattice so a cascaded chip stays over its own window.
             (annotated
               (map (lambda (lw chip)
                      (let* ((win (cdr lw))
                             (wid (cdr (assoc 'windowId win)))
                             (pid (cdr (assoc 'ownerPid win)))
                             (wx (cdr (assoc 'x win))) (wy (cdr (assoc 'y win)))
                             (ww (cdr (assoc 'w win))) (wh (cdr (assoc 'h win)))
                             (nat-x (cdr (assoc 'x chip)))
                             (nat-y (cdr (assoc 'y chip)))
                             (cx nat-x) (cy nat-y)
                             (cw (cdr (assoc 'w chip))) (ch (cdr (assoc 'h chip)))
                             (placement
                               (find-chip-position wid pid wx wy ww wh
                                                   cx cy cw ch (chip-host-padding))))
                        (cond
                          (placement
                            (let ((nx (cdr (assoc 'x placement)))
                                  (ny (cdr (assoc 'y placement))))
                              (list #t (chip-with-position chip nx ny)
                                    nat-x nat-y wx wy ww wh)))
                          (else
                            (list #f (chip-with-background chip faded-bg)
                                  nat-x nat-y wx wy ww wh)))))
                    labelled raw-chips))
             (windows-data
               (map (lambda (lw vc)
                      (let* ((win (cdr lw))
                             (label (car lw))
                             (visible? (car vc)))
                        (list (cons 'label label)
                              (cons 'app (cdr (assoc 'subText win)))
                              (cons 'title (cdr (assoc 'text win)))
                              (cons 'visible visible?))))
                    labelled annotated))
             ;; Stage B over the whole desktop bounding box, not just the
             ;; primary, so chips on non-primary displays aren't clamped home.
             (bbox (desktop-bounds))
             (ox (car bbox)) (oy (cadr bbox))
             (bw (caddr bbox)) (bh (cadddr bbox))
             (shifted (map (lambda (e) (shift-annotated-entry e (- 0 ox) (- 0 oy)))
                           annotated))
             (placed (assign-chips shifted bw bh))
             (chips (map (lambda (c) (shift-chip-xy c ox oy)) placed)))
        (set! current-window-targets labelled)
        (set! current-windows-data windows-data)
        (hints-show chips)))

    ;; Constructor.
    ;; A block spec is an alist; we tuck the (live!) windows-data into
    ;; 'windows so the JS renderer sees the current snapshot every render.
    ;; alist->json reads the cell at serialization time, so set! between
    ;; render() and the spec being built isn't a race — block-list-
    ;; payload-json calls on-render-fn FIRST, then serializes.
    ;; on-render-fn protocol:
    ;;   The block-list renderer (ui/overlay.scm) calls (fn) before
    ;;   serializing each block. The return value — if a pair/alist —
    ;;   is merged into the block's JSON, overriding any spec-level
    ;;   entries with the same key. For pure side-effect thunks the
    ;;   return value is ignored.
    ;;
    ;;   We use this to splice the current windows snapshot into the
    ;;   block payload at serialize time. LispKit doesn't expose
    ;;   set-cdr!, so live in-place mutation isn't an option — the
    ;;   thunk-resolver pattern is the documented fallback.
    (define (make-window-list-block . opts)
      ;; 'chips? #t enables on-screen chips; absence (or #f) means the
      ;; block just renders the row list with no chip painting. The old
      ;; 'chip-options keyword has been removed — chip styling lives in
      ;; CSS now. Catch users still passing it with a one-line migration
      ;; error pointing at the new authoring surface.
      (let* ((alist (apply props->alist opts)))
        (when (assoc 'chip-options alist)
          (error
            "make-window-list-block: 'chip-options removed — edit .chip in ~/.config/modaliser/theme.css instead"))
        (cond
          ((alist-ref alist 'chips? #f)
            ;; The block owns the chip lifecycle end-to-end:
            ;;   on-render-fn paints chips and snapshots windows-data
            ;;   on-leave-fn  clears the chips when the overlay closes
            (list (cons 'type 'window-list)
                  (cons 'on-render-fn
                    (lambda ()
                      (paint-and-snapshot!)
                      (list (cons 'windows current-windows-data))))
                  (cons 'on-leave-fn
                    (lambda () (hints-hide)))))
          (else
            (list (cons 'type 'window-list)
                  (cons 'windows '()))))))

    (add-overlay-asset-file! 'css "lib/modaliser/blocks/window-list.css")
    (add-overlay-asset-file! 'js  "lib/modaliser/blocks/window-list.js")))
