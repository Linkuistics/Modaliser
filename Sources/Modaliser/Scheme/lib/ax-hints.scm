;; lib/ax-hints.scm — AX-based hint flows for any app
;;
;; Compose these primitives in your config to wire up "see a chip, type a
;; letter, focus that thing" UX over any app's accessible elements:
;;
;;   1. ax-find-labelled  — query AX for elements of a role in an app's
;;                          focused window; pair them with labels in
;;                          reading order. Returns ((label . elem) ...).
;;   2. ax-target-bindings — convert that list into (key ...) bindings
;;                           that fire your action with the AX handle.
;;   3. ax-target-hints   — convert that list into the hint-list shape
;;                          (modaliser hints) hints-show consumes.
;;
;; Wire (2) into a tree's children and (3) into its on-enter / on-leave
;; hooks. See default-config.scm's iTerm tree for an end-to-end example.

;; ─── Hint chip appearance ──────────────────────────────────────────
;;
;; Sensible smallish defaults. Override per-tree by passing your own opts
;; alist to ax-target-hints — see the iTerm tree in default-config.scm
;; for one tuned for very large pane chips.
;;
;; Keys (all optional):
;;   offset-x-frac, offset-y-frac  — chip top-left as fraction of element size
;;   font-size, padding, corner-radius, border-width  — pixels
;;   color, background, border-color  — CSS hex strings
(define default-hint-options
  (list (cons 'offset-x-frac 0.02)
        (cons 'offset-y-frac 0.02)
        (cons 'font-size 24)
        (cons 'padding 6)
        (cons 'corner-radius 6)
        (cons 'color "#000000")
        (cons 'background "#ffffff")
        (cons 'border-width 1)
        (cons 'border-color "#000000")))

;; ─── Helpers ──────────────────────────────────────────────────────

;; (label-pairs labels elements) → ((label . elem) ...)
;; Truncates at min length: extra labels or extra elements are dropped.
(define (label-pairs labels elements)
  (let loop ((ls labels) (es elements) (acc '()))
    (cond
      ((or (null? ls) (null? es)) (reverse acc))
      (else (loop (cdr ls) (cdr es)
                  (cons (cons (car ls) (car es)) acc))))))

(define (hint-opt opts key default)
  (let ((p (assoc key opts)))
    (if p (cdr p) default)))

;; ─── Public API ───────────────────────────────────────────────────

;; (ax-find-labelled bundle-id role labels) → ((label . elem-alist) ...)
;;
;; Probe AX for elements of `role` inside the focused window of `bundle-id`,
;; then pair them with the supplied label list in reading order
;; (top-to-bottom, left-to-right). Returns '() if the app isn't running
;; or has no matching elements. Truncates at min(len(labels), len(elements)).
(define (ax-find-labelled bundle-id role labels)
  (label-pairs labels (ax-find-elements bundle-id role)))

;; (ax-target-bindings labelled-elements label-prefix action-fn) → (key ...)
;;
;; For each (label . elem) pair, produce a (key label display-label thunk)
;; entry suitable for splicing into a tree's children. The thunk calls
;; (action-fn handle) where handle is the AX handle from the elem alist.
;; display-label = label-prefix ++ label (e.g. "Pane a", "Tab f").
(define (ax-target-bindings labelled-elements label-prefix action-fn)
  (let loop ((ps labelled-elements) (acc '()))
    (if (null? ps)
      (reverse acc)
      (let* ((entry (car ps))
             (label (car entry))
             (elem  (cdr entry))
             (handle (cdr (assoc 'handle elem))))
        (loop (cdr ps)
              (cons (key label
                         (string-append label-prefix label)
                         (lambda () (action-fn handle)))
                    acc))))))

;; (ax-target-hints labelled-elements opts) → list ready for hints-show
;;
;; Each chip is sized to (font-size + 2*padding) square and positioned at
;; the configured fractional offset from the element's top-left corner.
(define (ax-target-hints labelled-elements opts)
  (let* ((offx-frac (hint-opt opts 'offset-x-frac 0.02))
         (offy-frac (hint-opt opts 'offset-y-frac 0.02))
         (font-size (hint-opt opts 'font-size 24))
         (padding   (hint-opt opts 'padding 6))
         (corner    (hint-opt opts 'corner-radius 6))
         (color     (hint-opt opts 'color "#000000"))
         (background (hint-opt opts 'background "#ffffff"))
         (border-width (hint-opt opts 'border-width 0))
         (border-color (hint-opt opts 'border-color color))
         (chip-size (+ font-size (* 2 padding))))
    (let loop ((ps labelled-elements) (acc '()))
      (if (null? ps)
        (reverse acc)
        (let* ((entry (car ps))
               (label (car entry))
               (elem  (cdr entry))
               (px (cdr (assoc 'x elem)))
               (py (cdr (assoc 'y elem)))
               (pw (cdr (assoc 'w elem)))
               (ph (cdr (assoc 'h elem)))
               (hx (+ px (exact (round (* pw offx-frac)))))
               (hy (+ py (exact (round (* ph offy-frac))))))
          (loop (cdr ps)
                (cons (list (cons 'label label)
                            (cons 'x hx) (cons 'y hy)
                            (cons 'w chip-size) (cons 'h chip-size)
                            (cons 'color color)
                            (cons 'background background)
                            (cons 'font-size font-size)
                            (cons 'padding padding)
                            (cons 'corner-radius corner)
                            (cons 'border-width border-width)
                            (cons 'border-color border-color))
                      acc)))))))
