;; (modaliser window-actions) — window-management binding builder.
;;
;; Builds the Windows group as a diagrammatic panel: each direction key
;; sits at the screen region it targets (declared via a matrix of key
;; strings), plus Center (inward arrows) and Maximise (filled), plus
;; text entries for the Named selector (n), numbered window picker
;; (1..), and Restore (r).
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
          (modaliser diagram-panel))
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
    ;; (for the diagram renderer) and the list of key nodes (for the
    ;; group's children).
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

    ;; Per-launch state: the current set of window alists the chip
    ;; digits map to. Set by paint-window-chips! on every leader press;
    ;; read by the focus action.
    (define current-window-targets '())

    (define default-window-labels
      (list "1" "2" "3" "4" "5" "6" "7" "8" "9" "0"))

    ;; (paint-window-chips!) → ()
    ;; Side-effect: paints a chip on each current-space window at its
    ;; top-left corner and updates current-window-targets so the focus
    ;; action can look up the window alist by digit.
    (define (paint-window-chips!)
      (let* ((ws (list-current-space-windows))
             (labels (let loop ((lbls default-window-labels) (xs ws) (acc '()))
                       (cond
                         ((or (null? lbls) (null? xs)) (reverse acc))
                         (else (loop (cdr lbls) (cdr xs)
                                     (cons (cons (car lbls) (car xs)) acc))))))
             (chips (map
                      (lambda (lw)
                        (let* ((lbl (car lw))
                               (w (cdr lw))
                               (x (cdr (assoc 'x w)))
                               (y (cdr (assoc 'y w))))
                          (list (cons 'label lbl)
                                (cons 'x x) (cons 'y y)
                                (cons 'w 52) (cons 'h 52)
                                (cons 'color "white")
                                (cons 'background "dodgerblue")
                                (cons 'font-size 32)
                                (cons 'padding 10)
                                (cons 'corner-radius 6)
                                (cons 'border-width 1)
                                (cons 'border-color "black"))))
                      labels)))
        (set! current-window-targets labels)
        (hints-show chips)))

    (define (hide-window-chips!)
      (hints-hide))

    ;; (focus-by-digit digit-str) → ()
    ;; Look up the window for the given label and call focus-window.
    (define (focus-by-digit d)
      (let ((entry (assoc d current-window-targets)))
        (when entry
          (focus-window (cdr entry)))))

    ;; Dynamic window-range for 1.. — paint-window-chips! refreshes
    ;; current-window-targets on every leader press into the group, so
    ;; the same digit labels map to whichever windows are visible now.
    (define (window-range)
      (key-range "1.." "Window <n>"
        default-window-labels
        (lambda (k) (focus-by-digit k))))

    ;; (actions . opts) → group node with 'renderer 'diagram
    (define (actions . opts)
      (let* ((alist        (apply props->alist opts))
             (group-key    (alist-ref alist 'key "w"))
             (group-label  (alist-ref alist 'label "Windows"))
             (custom-panels (alist-ref alist 'panels #f))
             (panels        (or custom-panels (default-panels)))
             (panel-specs   (map panel-spec-of panels))
             (panel-keys    (apply append (map panel-keys-of panels)))
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
               'renderer 'diagram
               'panels panel-specs
               'on-enter (lambda () (paint-window-chips!))
               'on-leave (lambda () (hide-window-chips!))
               children)))

    (define (register! . opts)
      (let* ((alist (apply props->alist opts))
             (scope (alist-ref alist 'tree-scope 'global)))
        (define-tree scope (apply actions opts))))))
