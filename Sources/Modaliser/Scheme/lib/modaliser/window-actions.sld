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
          center-panel)
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

    ;; (list-block . opts) → window-list block spec with dispatch keys.
    ;; Wraps make-window-list-block and bundles the 1.. range so digits resolve
    ;; to focus-by-digit at the group level. When the block is LIVE (it has an
    ;; on-render-fn that refreshes window-list-current-targets every render — the
    ;; 'chips? path), it also carries 'cursor-targets-fn so the selection cursor
    ;; (list-cursor-k6) moves over those live rows; ⏎ then dispatches the
    ;; highlighted row's digit through the very same range. A static (no-chips)
    ;; block never refreshes its targets, so it omits the accessor — the cursor
    ;; must not attach to a list with no live data.
    ;;
    ;; Opts forwarded to make-window-list-block (currently just 'chips?).
    (define (list-block . opts)
      (let* ((base  (apply make-window-list-block opts))
             (live? (and (assoc 'on-render-fn base) #t)))
        (append base
                (if live?
                  (list (cons 'cursor-targets-fn window-list-current-targets))
                  '())
                (list (cons 'block-children (list (window-range)))))))

    ))
