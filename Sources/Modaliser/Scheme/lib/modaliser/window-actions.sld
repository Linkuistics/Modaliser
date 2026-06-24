;; (modaliser window-actions) — window-management panel blocks.
;;
;; Provides the high-level block wrappers users embed in the panels of a
;; window-management sub-screen — idiomatically an (open …) drill-down:
;;
;;   (import (modaliser dsl)
;;           (prefix (modaliser window-actions) window:))
;;
;;   (open "w" "Windows"
;;     (panel "Layout"
;;       (window:default-layout-block))
;;     (panel "Select"
;;       (key "n" "Named…"
;;         (selector 'prompt "Select window…"
;;                   'source list-windows
;;                   'on-select focus-window))
;;       (key "r" "Restore" (lambda () (restore-window))))
;;     (panel "Windows"
;;       (window:list-block 'chips? #t)))
;;
;; Each block carries its dispatch keys as 'block-children; the panel
;; lifts them onto its 'children so the state machine routes keys
;; correctly. The window-list block (with 'chips? #t) also carries
;; its own 'on-leave-fn that calls (hints-hide) — chip cleanup lives
;; with the block that paints chips, not at the panel level.

(define-library (modaliser window-actions)
  (export layout-block
          default-layout-block
          list-block
          divisions
          center-panel
          ;; Exported for unit testing the cursor-seed matcher
          ;; (list-cursor-window-focus-k28). The live thunk
          ;; window-focused-index just feeds it (focused-window) and the
          ;; current targets; the branching lives here.
          focused-row-index)
  (import (scheme base)
          (modaliser dsl)
          (modaliser util)
          (modaliser window)
          (modaliser diagram-panel)
          (modaliser blocks window-diagram)
          (modaliser blocks window-list))
  (begin

    ;; ─── Panel data helpers ────────────────────────────────────

    ;; JS-friendly key conversion for grid cells: parse-matrix returns
    ;; col-span / row-span (Scheme/kebab) but the window-diagram JS
    ;; reads colSpan / rowSpan (JS/camel). Convert before emitting.
    (define (js-cell cell)
      (list (cons 'key      (cdr (assoc 'key cell)))
            (cons 'col      (cdr (assoc 'col cell)))
            (cons 'row      (cdr (assoc 'row cell)))
            (cons 'colSpan  (cdr (assoc 'col-span cell)))
            (cons 'rowSpan  (cdr (assoc 'row-span cell)))))

    ;; (divisions matrix) → (panel-spec key-node-list)
    ;; Parse the matrix, compute (move-window x y w h) for each unique
    ;; key from its bounding box, and produce both the grid panel-spec
    ;; (for the window-diagram block) and the matching key bindings.
    (define (divisions matrix)
      (let* ((rows (length matrix))
             (cols (length (car matrix)))
             (cells (parse-matrix matrix))
             (spec (make-grid-panel-spec cols rows (map js-cell cells)))
             (keys (map (lambda (cell)
                          (let* ((k (cdr (assoc 'key cell)))
                                 (c (cdr (assoc 'col cell)))
                                 (r (cdr (assoc 'row cell)))
                                 (cs (cdr (assoc 'col-span cell)))
                                 (rs (cdr (assoc 'row-span cell)))
                                 (x  (/ (- c 1) cols))
                                 (y  (/ (- r 1) rows))
                                 (w  (/ cs cols))
                                 (h  (/ rs rows)))
                            (key k k
                              (lambda () (move-window x y w h)))))
                        cells)))
        (list spec keys)))

    ;; (center-panel key) → (panel-spec key-node-list-of-one)
    ;; Distinct from divisions because center-window doesn't fit a grid.
    (define (center-panel k)
      (list (make-center-panel-spec k)
            (list (key k "Center" (lambda () (center-window))))))

    ;; ─── Block constructors ────────────────────────────────────

    ;; (layout-block form ...) → block spec
    ;;
    ;; Macro that quasiquotes each form so config authors can write
    ;; matrices and (center K) directly without explicit quoting:
    ;;
    ;;   (layout-block
    ;;     (("d" "f" "g"))                ; full thirds — matrix arg
    ;;     (("D" "F" "G") ("C" "V" "B"))  ; half thirds — matrix arg
    ;;     (center "c"))                  ; centre panel — head symbol
    ;;
    ;; Each form is dispatched at runtime by layout-form->pair:
    ;;   - (center K)  → (center-panel K) — outer frame + inward arrows
    ;;   - any other   → (divisions form) — interpreted as a matrix
    ;;
    ;; Forms are quasiquoted, so `,expr` injects a dynamic value:
    ;;   (layout-block (center ,(my-centre-key)))
    (define-syntax layout-block
      (syntax-rules ()
        ((_ form ...)
         (compose-layout-block (list `form ...)))))

    ;; Runtime helper invoked by the layout-block macro. Dispatches
    ;; each form, combines the results into one window-diagram block
    ;; with the matching dispatch keys lifted to 'block-children.
    ;;
    ;; The keys are marked 'hidden: the diagram itself draws each cell's
    ;; key, so the lifted bindings are dispatch-only. When this block is
    ;; embedded in a panel (panel-grid layout DSL) that would otherwise
    ;; render the panel's dispatch children as text rows, the marker keeps
    ;; them from duplicating the diagram — exactly as the list blocks hide
    ;; their 1.. digit range. Dispatch is unaffected: find-child ignores
    ;; 'hidden (the old block-list overlay never rendered them as rows
    ;; either, so this is invisible there).
    (define (compose-layout-block forms)
      (let* ((pairs (map layout-form->pair forms))
             (panel-specs (map car pairs))
             (panel-keys  (map (lambda (k) (cons (cons 'hidden #t) k))
                               (apply append (map cadr pairs))))
             (base (make-window-diagram-block panel-specs)))
        (append base (list (cons 'block-children panel-keys)))))

    (define (layout-form->pair form)
      (cond
        ((and (pair? form) (eq? (car form) 'center))
         (center-panel (cadr form)))
        ((pair? form)
         (divisions form))
        (else
         (error "layout-block: unrecognised form" form))))

    ;; Default 6-panel layout matching the v19 mockup:
    ;;   Row 1: full thirds (d/f/g), half thirds (D/F/G over C/V/B),
    ;;          two two-thirds spans (e and t).
    ;;   Row 2: maximise fill (m), centre (c).
    (define (default-layout-block)
      (layout-block
        (("d" "f" "g"))                ; full thirds
        (("D" "F" "G")
         ("C" "V" "B"))                ; half thirds
        (("e" "e" #f))                 ; left two-thirds
        ((#f "t" "t"))                 ; right two-thirds
        (("m"))                        ; maximise (full cell)
        (center "c")))                 ; centre (inward arrows)

    ;; ─── Numbered window dispatch ──────────────────────────────

    (define default-window-labels
      (list "1" "2" "3" "4" "5" "6" "7" "8" "9" "0"))

    ;; (focus-by-digit digit-str) → ()
    ;; Look up the window for the pressed digit and focus it. The
    ;; window-list block refreshes its target alist on every render, so
    ;; the same digit press resolves to whichever window had that label
    ;; at paint time.
    (define (focus-by-digit d)
      (let ((entry (assoc d (window-list-current-targets))))
        (when entry
          (focus-window (cdr entry)))))

    ;; Dynamic window-range for 1.. — marked 'hidden so the renderer
    ;; doesn't surface the "1.. → Window <n>" row; the windows-list
    ;; block at the bottom already shows the digit-to-window mapping
    ;; per row.
    (define (window-range)
      (cons (cons 'hidden #t)
            (key-range "1.." "Window <n>"
              default-window-labels
              (lambda (k) (focus-by-digit k)))))

    ;; ─── Cursor seed — focused-window index ────────────────────
    ;;
    ;; focused-row-index: the pure matcher. Given the focused window's
    ;; identity alist (from the focused-window primitive) and the live target
    ;; rows ((label . window-alist) ...), return the 0-based index of the row
    ;; that IS the focused window, or #f. cursor-initial-index-fn reads #f as
    ;; "seed row 0", so a miss is never worse than the spatial default. Match
    ;; strategy (list-cursor-window-focus-k28):
    ;;
    ;;   1. focused windowId ≠ 0 → first row whose windowId equals it. This is
    ;;      an AX-id-vs-AX-id compare: both ids come from the same
    ;;      _AXUIElementGetWindow source (the list rows via WindowEnumerator,
    ;;      the focused id via the focused-window primitive), so they agree by
    ;;      construction — unlike window-visible-at?'s AX-id-vs-CGWindowList
    ;;      cross-source compare. That self-consistency is why the id alone is
    ;;      trusted here even when several rows share the pid.
    ;;   2. windowId = 0 (the residual _AXUIElementGetWindow→0 case) → first
    ;;      row with matching ownerPid AND exact frame origin (x,y); both
    ;;      snapshots come from the same on-render instant, so origins agree.
    ;;   3. still nothing, but exactly one row shares the pid (single-window
    ;;      app) → that row; pid alone disambiguates only when unambiguous.
    ;;   4. otherwise #f.
    (define (focused-row-index focused targets)
      (let ((fwid (cdr (assoc 'windowId focused)))
            (fpid (cdr (assoc 'ownerPid focused)))
            (fx   (cdr (assoc 'x focused)))
            (fy   (cdr (assoc 'y focused))))
        (if (not (zero? fwid))
          (target-index targets
            (lambda (win) (= (cdr (assoc 'windowId win)) fwid)))
          (or (target-index targets
                (lambda (win)
                  (and (= (cdr (assoc 'ownerPid win)) fpid)
                       (= (cdr (assoc 'x win)) fx)
                       (= (cdr (assoc 'y win)) fy))))
              (unique-pid-index targets fpid)))))

    ;; First 0-based row index whose window-alist (the cdr of the row)
    ;; satisfies pred, or #f.
    (define (target-index targets pred)
      (let loop ((ts targets) (i 0))
        (cond
          ((null? ts) #f)
          ((pred (cdr (car ts))) i)
          (else (loop (cdr ts) (+ i 1))))))

    ;; Index of the sole row owned by pid, or #f when zero or several rows
    ;; match (pid alone identifies a window only for a single-window app).
    (define (unique-pid-index targets pid)
      (let loop ((ts targets) (i 0) (found #f))
        (cond
          ((null? ts) found)
          ((= (cdr (assoc 'ownerPid (cdr (car ts)))) pid)
           (if found #f (loop (cdr ts) (+ i 1) i)))
          (else (loop (cdr ts) (+ i 1) found)))))

    ;; Live thunk wired into list-block as cursor-initial-index-fn. Consulted
    ;; once when the window list first claims the cursor (overlay open). The
    ;; on-render snapshot has already refreshed window-list-current-targets by
    ;; the time block-json offers the cursor, so the rows read here are current
    ;; and their frame origins are consistent with the focused frame. #f →
    ;; cursor seeds row 0. Mirrors apps/iterm.sld pane-focused-index.
    (define (window-focused-index)
      (let ((fw (focused-window)))
        (and fw (focused-row-index fw (window-list-current-targets)))))

    ;; (list-block . opts) → window-list block spec with dispatch keys.
    ;; Wraps make-window-list-block and bundles the 1.. range so digits resolve
    ;; to focus-by-digit at the group level. When the block is LIVE (it has an
    ;; on-render-fn that refreshes window-list-current-targets every render — the
    ;; 'chips? path), it also carries 'cursor-targets-fn so the selection cursor
    ;; (list-cursor-k6) moves over those live rows; ⏎ then dispatches the
    ;; highlighted row's digit through the very same range. A live block also
    ;; carries 'cursor-initial-index-fn so the cursor opens on the focused
    ;; window rather than spatial row 0 (list-cursor-window-focus-k28). A static
    ;; (no-chips) block never refreshes its targets, so it omits both accessors —
    ;; the cursor must not attach to a list with no live data.
    ;;
    ;; Opts forwarded to make-window-list-block (currently just 'chips?).
    (define (list-block . opts)
      (let* ((base  (apply make-window-list-block opts))
             (live? (and (assoc 'on-render-fn base) #t)))
        (append base
                (if live?
                  (list (cons 'cursor-targets-fn window-list-current-targets)
                        (cons 'cursor-initial-index-fn window-focused-index))
                  '())
                (list (cons 'block-children (list (window-range)))))))

    ))
