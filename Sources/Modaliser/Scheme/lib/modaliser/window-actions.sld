;; (modaliser window-actions) — windows-overlay block constructors.
;;
;; Provides the high-level block wrappers users compose with the
;; generic (overlay …) constructor from (modaliser dsl):
;;
;;   (import (modaliser dsl)
;;           (modaliser blocks which-key)               ; make-which-key-block
;;           (prefix (modaliser window-actions) window:))
;;
;;   (define-tree 'global
;;     (overlay 'key "w" 'label "Windows"
;;       (window:default-layout-block)
;;       (make-which-key-block
;;         (selector "n" "Named…" 'prompt "Select window…"
;;                                 'source list-windows
;;                                 'on-select focus-window)
;;         (key "r" "Restore" (lambda () (restore-window))))
;;       (window:list-block 'show-chips #t)))
;;
;; Each block carries its dispatch keys as 'block-children; overlay
;; lifts them onto the group's 'children so the state machine routes
;; keys correctly. The window-list block (with 'show-chips #t) also
;; carries its own 'on-leave-fn that calls (hints-hide) — chip cleanup
;; lives with the block that paints chips, not at the overlay level.

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

    ;; (layout-block . panel-pairs) → block spec
    ;; Each panel-pair is (panel-spec key-list) as returned by
    ;; `divisions` or `center-panel`. Combines them into a single
    ;; window-diagram block and attaches the union of all panel keys as
    ;; 'block-children so overlay can lift them for dispatch.
    (define (layout-block . panel-pairs)
      (let* ((panel-specs (map car panel-pairs))
             (panel-keys  (apply append (map cadr panel-pairs)))
             (base (make-window-diagram-block panel-specs)))
        (append base (list (cons 'block-children panel-keys)))))

    ;; Default 6-panel layout matching the v19 mockup:
    ;;   Row 1: full thirds (d/f/g), half thirds (D/F/G over C/V/B),
    ;;          two two-thirds spans (e and t).
    ;;   Row 2: maximise fill (m), centre (c).
    (define (default-divisions)
      (list
        (divisions '(("d" "f" "g")))           ; full thirds
        (divisions '(("D" "F" "G")
                     ("C" "V" "B")))           ; half thirds
        (divisions '(("e" "e" #f)))            ; left two-thirds
        (divisions '((#f "t" "t")))            ; right two-thirds
        (divisions '(("m")))                   ; maximise
        (center-panel "c")))                   ; centre

    (define (default-layout-block)
      (apply layout-block (default-divisions)))

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

    ;; Dynamic window-range for 1.. — marked 'hidden so neither the
    ;; default list renderer nor the which-key block surfaces the
    ;; "1.. → Window <n>" row; the windows-list block at the bottom
    ;; already shows the digit-to-window mapping per row.
    (define (window-range)
      (cons (cons 'hidden #t)
            (key-range "1.." "Window <n>"
              default-window-labels
              (lambda (k) (focus-by-digit k)))))

    ;; (list-block . opts) → window-list block spec with dispatch keys.
    ;; Wraps make-window-list-block and bundles the 1.. range so
    ;; digits resolve to focus-by-digit at the group level.
    ;;
    ;; Opts forwarded to make-window-list-block: 'show-chips, 'chip-options.
    (define (list-block . opts)
      (let ((base (apply make-window-list-block opts)))
        (append base (list (cons 'block-children
                                 (list (window-range)))))))

    ))
