;; (modaliser diagram-panel) — renderer assets + panel-spec constructors
;; for the diagrammatic overlay renderer.
;;
;; Three panel types (all alists):
;;
;;   'grid    — N×M grid of cells. Each cell carries (key, col, row,
;;              col-span, row-span). Empty cells (#f in matrices) are
;;              omitted from the cells list — they're inferred from the
;;              gaps when JS renders the grid.
;;   'center  — outer frame, inner filled rectangle at fractional
;;              bounds, four inward arrows. Carries just the key.
;;   'fill    — single white-filled rectangle covering the whole
;;              panel. Carries just the key. (Equivalent to a 1×1 grid
;;              but kept as an explicit type for clarity.)
;;
;; (parse-matrix matrix) walks an array-of-arrays of key strings (or #f
;; for empty cells), validates rectangular row lengths and rectangular
;; key bounding boxes, and emits a list of cell alists. Used by
;; window-actions.sld to derive both keybindings (via move-window
;; computed from grid position) and the matching panel-spec.
;;
;; The .js and .css that render these panels are registered with the
;; overlay at library-load time via (add-overlay-asset! …).

(define-library (modaliser diagram-panel)
  (export make-grid-panel-spec
          make-center-panel-spec
          make-fill-panel-spec
          parse-matrix)
  (import (scheme base)
          (scheme cxr))
  (begin

    ;; ─── Panel-spec constructors ───────────────────────────────

    (define (make-grid-panel-spec cols rows cells)
      (list (cons 'type 'grid)
            (cons 'cols cols)
            (cons 'rows rows)
            (cons 'cells cells)))

    (define (make-center-panel-spec key)
      (list (cons 'type 'center)
            (cons 'key key)))

    (define (make-fill-panel-spec key)
      (list (cons 'type 'fill)
            (cons 'key key)))

    ;; ─── Matrix parser ─────────────────────────────────────────

    ;; Validate matrix shape: non-empty list of equal-length rows.
    (define (validate-matrix-shape matrix)
      (when (null? matrix)
        (error "parse-matrix: matrix must have at least one row"))
      (let ((cols (length (car matrix))))
        (when (zero? cols)
          (error "parse-matrix: rows must be non-empty"))
        (for-each
          (lambda (row)
            (unless (= (length row) cols)
              (error "parse-matrix: rows must all be the same length"
                     'expected cols 'got (length row))))
          matrix)))

    ;; Find bounding box of every cell holding the given key.
    ;; Returns (min-col max-col min-row max-row).
    (define (bounding-box matrix key)
      (let loop ((rows matrix) (r 1) (min-c #f) (max-c #f) (min-r #f) (max-r #f))
        (if (null? rows)
          (list min-c max-c min-r max-r)
          (let inner ((cells (car rows)) (c 1) (min-c min-c) (max-c max-c) (min-r min-r) (max-r max-r))
            (cond
              ((null? cells)
                (loop (cdr rows) (+ r 1) min-c max-c min-r max-r))
              ((equal? (car cells) key)
                (inner (cdr cells) (+ c 1)
                       (if (or (not min-c) (< c min-c)) c min-c)
                       (if (or (not max-c) (> c max-c)) c max-c)
                       (if (or (not min-r) (< r min-r)) r min-r)
                       (if (or (not max-r) (> r max-r)) r max-r)))
              (else
                (inner (cdr cells) (+ c 1) min-c max-c min-r max-r)))))))

    ;; Walk each cell in the bounding box and confirm every one is the
    ;; expected key (no #f holes, no other keys interspersed).
    (define (validate-rectangular matrix key bbox)
      (let ((min-c (car bbox)) (max-c (cadr bbox))
            (min-r (caddr bbox)) (max-r (cadddr bbox)))
        (let row-loop ((r min-r))
          (when (<= r max-r)
            (let* ((row (list-ref matrix (- r 1))))
              (let col-loop ((c min-c))
                (when (<= c max-c)
                  (let ((cell (list-ref row (- c 1))))
                    (unless (equal? cell key)
                      (error "parse-matrix: key not rectangular"
                             'key key 'at-row r 'at-col c 'got cell))
                    (col-loop (+ c 1)))))
              (row-loop (+ r 1)))))))

    ;; Collect every unique non-#f key, preserving first-seen order.
    (define (unique-keys matrix)
      (let row-loop ((rows matrix) (seen '()))
        (if (null? rows)
          (reverse seen)
          (let col-loop ((cells (car rows)) (seen seen))
            (cond
              ((null? cells) (row-loop (cdr rows) seen))
              ((not (car cells)) (col-loop (cdr cells) seen))
              ((member (car cells) seen) (col-loop (cdr cells) seen))
              (else (col-loop (cdr cells) (cons (car cells) seen))))))))

    ;; (parse-matrix matrix) → list of cell alists
    (define (parse-matrix matrix)
      (validate-matrix-shape matrix)
      (let ((keys (unique-keys matrix)))
        (map
          (lambda (k)
            (let* ((bbox (bounding-box matrix k))
                   (min-c (car bbox)) (max-c (cadr bbox))
                   (min-r (caddr bbox)) (max-r (cadddr bbox)))
              (validate-rectangular matrix k bbox)
              (list (cons 'key k)
                    (cons 'col min-c)
                    (cons 'row min-r)
                    (cons 'col-span (+ (- max-c min-c) 1))
                    (cons 'row-span (+ (- max-r min-r) 1)))))
          keys)))))
