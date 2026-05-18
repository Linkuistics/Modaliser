;; (modaliser window-actions) — window-management binding builder.
;;
;; Builds the Windows group as a block-list overlay: a window-diagram
;; block (panel grid), a which-key block (text-entry strip), and a
;; window-list block (per-window labelled rows with on-screen chips).
;;
;; Compose with other groups in your config:
;;
;;   (import (modaliser dsl) (prefix (modaliser window-actions) window:))
;;   (define-tree 'global
;;     (window:actions)
;;     (key "i" "iTerm" (lambda () (launch-app "iTerm"))))
;;
;; Override the default layout by passing your own panels:
;;
;;   (window:actions
;;     'panels (list (window:divisions '(("h" "l")))      ; halves
;;                   (window:divisions '(("a" "s" "d" "f"))))) ; quarters

(define-library (modaliser window-actions)
  (export actions
          register!
          divisions
          center-panel)
  (import (scheme base)
          (modaliser dsl)
          (modaliser util)
          (modaliser window)
          (modaliser hints)
          (modaliser diagram-panel)
          (modaliser blocks window-diagram)
          (modaliser blocks which-key)
          (modaliser blocks window-list))
  (begin

    ;; JS-friendly key conversion for grid cells: parse-matrix returns
    ;; col-span / row-span (Scheme/kebab) but diagram-panel.js reads
    ;; colSpan / rowSpan (JS/camel). Convert before emitting so the
    ;; renderer sees the expected payload shape.
    (define (js-cell cell)
      (list (cons 'key      (cdr (assoc 'key cell)))
            (cons 'col      (cdr (assoc 'col cell)))
            (cons 'row      (cdr (assoc 'row cell)))
            (cons 'colSpan  (cdr (assoc 'col-span cell)))
            (cons 'rowSpan  (cdr (assoc 'row-span cell)))))

    ;; (divisions matrix) → (panel-spec key-node-list)
    ;; Parse the matrix, compute (move-window x y w h) for each unique
    ;; key from its bounding box, and produce both the grid panel-spec
    ;; (for the window-diagram block) and the list of key nodes (for
    ;; the group's children).
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

    ;; Helpers to unpack the (panel-spec keys) pair.
    (define (panel-spec-of p) (car p))
    (define (panel-keys-of p) (cadr p))

    ;; Default panel layout matching the v19 mockup:
    ;;   Row 1: full thirds (d/f/g), half thirds (D/F/G over C/V/B),
    ;;          two-thirds spans (e and t — two separate panels).
    ;;   Row 2: maximise fill (m), center (c), text-entries (n/1../r).
    (define (default-panels)
      (list
        (divisions '(("d" "f" "g")))                ; full thirds
        (divisions '(("D" "F" "G")
                     ("C" "V" "B")))                ; half thirds
        (divisions '(("e" "e" #f)))                 ; first two-thirds
        (divisions '((#f "t" "t")))                 ; last two-thirds
        (divisions '(("m")))                        ; maximise (single cell)
        (center-panel "c")))                        ; center

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

    ;; Dynamic window-range for 1.. — marked 'hidden so the which-key
    ;; strip omits the "1.. → Window <n>" row: the windows-list block
    ;; at the bottom of the overlay already shows the digit-to-window
    ;; mapping per-row, and the redundant range entry would just add
    ;; noise. Binding still works — the state machine reads the node
    ;; from children regardless of the hidden flag.
    (define (window-range)
      (cons (cons 'hidden #t)
            (key-range "1.." "Window <n>"
              default-window-labels
              (lambda (k) (focus-by-digit k)))))

    ;; (actions . opts) → group node with 'renderer 'blocks
    ;;
    ;; Options:
    ;;   'key           — leader key char (default "w")
    ;;   'label         — group label (default "Windows")
    ;;   'panels        — list of panel-spec pairs (default = default-panels)
    ;;   'chip-options  — alist of chip overrides; forwarded to the
    ;;                    window-list block, which merges them with its
    ;;                    own defaults (font-size, padding, color,
    ;;                    background, faded-background, offset-x-frac,
    ;;                    etc.).
    (define (actions . opts)
      (let* ((alist        (apply props->alist opts))
             (group-key    (alist-ref alist 'key "w"))
             (group-label  (alist-ref alist 'label "Windows"))
             (custom-panels (alist-ref alist 'panels #f))
             (panels        (or custom-panels (default-panels)))
             (panel-specs   (map panel-spec-of panels))
             (panel-keys    (apply append (map panel-keys-of panels)))
             (chip-overrides (alist-ref alist 'chip-options '()))
             (wd-block (make-window-diagram-block panel-specs))
             (wk-block (make-which-key-block))
             (wl-block (make-window-list-block 'show-chips #t
                                               'chip-options chip-overrides))
             (text-entries
               (list
                 (selector "n" "Named…"
                   'prompt "Select window…"
                   'source list-windows
                   'on-select focus-window
                   'actions
                     (list
                       (action "Focus" 'description "Select window" 'key 'primary
                         'run (lambda (c) (focus-window c)))))
                 (window-range)
                 (key "r" "Restore" (lambda () (restore-window)))))
             (children (append panel-keys text-entries)))
        (apply group group-key group-label
               'renderer 'blocks
               'blocks (list wd-block wk-block wl-block)
               'on-leave (lambda () (hints-hide))
               children)))

    (define (register! . opts)
      (let* ((alist (apply props->alist opts))
             (scope (alist-ref alist 'tree-scope 'global)))
        (define-tree scope (apply actions opts))))))
