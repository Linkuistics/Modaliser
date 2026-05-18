;; (modaliser blocks window-list) — block constructor for the
;; window-list block. Lifts the labelled windows-list section from
;; the old diagram renderer, plus the chip-painting side-effect.
;;
;; (make-window-list-block . opts) → block-spec alist
;;
;; Opts:
;;   'show-chips    BOOL  — default #f. When true, the block's
;;                          on-render-fn computes chip positions,
;;                          runs window-visible-at? probes, and forwards
;;                          to hints-show. The block's payload also
;;                          carries the current windows list so the
;;                          rendered rows mirror the chip placement.
;;   'chip-options  ALIST — chip styling overrides; merged with
;;                          default-window-chip-options.
;;
;; The current window snapshot is exposed via window-list-current-labels
;; so the parent group can build a (key-range …) that dispatches
;; per-digit window focus.

(define-library (modaliser blocks window-list)
  (export make-window-list-block
          window-list-current-labels
          window-list-current-targets)
  (import (scheme base)
          (modaliser util)
          (modaliser window)
          (modaliser hints)
          (modaliser overlay-assets))
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

    (define default-chip-options
      (list (cons 'offset-x-frac 0.02)
            (cons 'offset-y-frac 0.02)
            (cons 'font-size 56)
            (cons 'padding 16)
            (cons 'corner-radius 8)
            (cons 'color "white")
            (cons 'background "dodgerblue")
            (cons 'faded-background "#6f8baa")
            (cons 'border-width 1)
            (cons 'border-color "black")))

    (define (merge-chip-options overrides)
      (let loop ((rest default-chip-options) (acc '()))
        (cond
          ((null? rest) (append (reverse acc) overrides))
          ((assoc (car (car rest)) overrides)
           (loop (cdr rest) acc))
          (else (loop (cdr rest) (cons (car rest) acc))))))

    ;; ─── Chip placement helpers — lifted from window-actions.sld ────
    ;; Kept private to this library so it owns chip painting end-to-end.

    (define chip-overlap-gap 4)
    (define chip-resolve-max-attempts 64)

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

    (define (chip-with-background chip new-bg)
      (map (lambda (entry)
             (if (eq? (car entry) 'background)
               (cons 'background new-bg)
               entry))
           chip))

    (define (window-chip-for digit win opts)
      (let* ((wx (cdr (assoc 'x win))) (wy (cdr (assoc 'y win)))
             (ww (cdr (assoc 'w win))) (wh (cdr (assoc 'h win)))
             (font-size (cdr (assoc 'font-size opts)))
             (padding (cdr (assoc 'padding opts)))
             (offx (cdr (assoc 'offset-x-frac opts)))
             (offy (cdr (assoc 'offset-y-frac opts)))
             (chip-x (+ wx (exact (round (* ww offx)))))
             (chip-y (+ wy (exact (round (* wh offy)))))
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

    (define (resolve-occluded-against-visible chips initial-placed sw sh)
      (let outer ((rest chips)
                  (placed (let r ((xs initial-placed) (a '()))
                            (if (null? xs) a (r (cdr xs) (cons (car xs) a)))))
                  (new-count 0))
        (cond
          ((null? rest)
            (let collect ((p placed) (remaining new-count) (acc '()))
              (cond
                ((zero? remaining) acc)
                (else (collect (cdr p) (- remaining 1) (cons (car p) acc))))))
          (else
            (let* ((c0 (clamp-chip-to-screen (car rest) sw sh))
                   (natural-y (cdr (assoc 'y c0))))
              (let inner ((c c0) (attempts 0))
                (cond
                  ((>= attempts chip-resolve-max-attempts)
                   (outer (cdr rest) (cons c placed) (+ new-count 1)))
                  (else
                    (let ((conflict (find-overlapping placed c)))
                      (cond
                        ((not conflict)
                         (outer (cdr rest) (cons c placed) (+ new-count 1)))
                        (else
                          (let* ((cw (cdr (assoc 'w c))) (ch (cdr (assoc 'h c)))
                                 (cx (cdr (assoc 'x c)))
                                 (cf-x (cdr (assoc 'x conflict)))
                                 (cf-y (cdr (assoc 'y conflict)))
                                 (cf-w (cdr (assoc 'w conflict)))
                                 (cf-h (cdr (assoc 'h conflict)))
                                 (try-y (+ cf-y cf-h chip-overlap-gap))
                                 (try-x-right (+ cf-x cf-w chip-overlap-gap))
                                 (new-c
                                   (cond
                                     ((<= (+ try-y ch) sh)
                                      (chip-with-position c cx try-y))
                                     ((<= (+ try-x-right cw) sw)
                                      (chip-with-position c try-x-right natural-y))
                                     (else c))))
                            (inner new-c (+ attempts 1))))))))))))))

    (define (resolve-chips-with-visibility annotated sw sh)
      (let split ((rest annotated) (visible-rev '()) (occluded-rev '()))
        (cond
          ((null? rest)
            (let* ((visible-chips (reverse visible-rev))
                   (occluded-chips (reverse occluded-rev))
                   (occluded-resolved (resolve-occluded-against-visible
                                        occluded-chips visible-chips sw sh)))
              (let reassemble ((src annotated)
                               (vp visible-chips)
                               (op occluded-resolved)
                               (acc '()))
                (cond
                  ((null? src) (reverse acc))
                  ((car (car src))
                   (reassemble (cdr src) (cdr vp) op (cons (car vp) acc)))
                  (else
                   (reassemble (cdr src) vp (cdr op) (cons (car op) acc)))))))
          ((car (car rest))
            (split (cdr rest)
                   (cons (clamp-chip-to-screen (cdr (car rest)) sw sh) visible-rev)
                   occluded-rev))
          (else
            (split (cdr rest)
                   visible-rev
                   (cons (cdr (car rest)) occluded-rev))))))

    ;; ─── on-render side-effect ─────────────────────────────────────
    (define (paint-and-snapshot! opts)
      (let* ((ws (list-current-space-windows))
             (labelled (label-pairs default-window-labels ws))
             (raw-chips
               (map (lambda (lw)
                      (window-chip-for (car lw) (cdr lw) opts))
                    labelled))
             (faded-bg (cdr (assoc 'faded-background opts)))
             (annotated
               (map (lambda (lw chip)
                      (let* ((win (cdr lw))
                             (wid (cdr (assoc 'windowId win)))
                             (pid (cdr (assoc 'ownerPid win)))
                             (cx (cdr (assoc 'x chip))) (cy (cdr (assoc 'y chip)))
                             (cw (cdr (assoc 'w chip))) (ch (cdr (assoc 'h chip)))
                             (test-x (+ cx (quotient cw 2)))
                             (test-y (+ cy (quotient ch 2)))
                             (visible? (window-visible-at? wid pid test-x test-y))
                             (styled (if visible?
                                       chip
                                       (chip-with-background chip faded-bg))))
                        (cons visible? styled)))
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
             (screen (primary-screen-size))
             (chips (resolve-chips-with-visibility
                      annotated
                      (cdr (assoc 'w screen))
                      (cdr (assoc 'h screen)))))
        (set! current-window-targets labelled)
        (set! current-windows-data windows-data)
        (hints-show chips)))

    ;; Constructor.
    ;; A block spec is an alist; we tuck the (live!) windows-data into
    ;; 'windows so the JS renderer sees the current snapshot every render.
    ;; alist->json reads the cell at serialization time, so set! between
    ;; render() and the spec being built isn't a race — block-list-
    ;; payload-json calls on-render-fn FIRST, then serializes.
    (define (make-window-list-block . opts)
      (let* ((alist (apply props->alist opts))
             (show-chips? (alist-ref alist 'show-chips #f))
             (chip-overrides (alist-ref alist 'chip-options '()))
             (chip-opts (merge-chip-options chip-overrides)))
        (let ((base
                (list (cons 'type 'window-list)
                      ;; Carry windows as a thunk-resolved value. We can't
                      ;; bake the snapshot into the spec since the spec is
                      ;; constructed once at group-build time. Instead the
                      ;; on-render-fn updates current-windows-data and the
                      ;; serializer pulls it via assoc each render — but
                      ;; alist->json reads the cell value as of serialize
                      ;; time, so we use a wrapper that resolves at JSON
                      ;; build time. The simplest mechanism: list a sentinel
                      ;; key 'windows-resolver and have block-list-payload-
                      ;; json call it. To avoid extending the protocol we
                      ;; instead keep the on-render-fn pattern: when
                      ;; show-chips, on-render-fn mutates the spec's
                      ;; 'windows entry in place via set-cdr!.
                      (cons 'windows '()))))
          (cond
            (show-chips?
              ;; Build an effect closure that captures the mutable spec
              ;; for in-place update. The closure refreshes 'windows on
              ;; every render so the JS payload matches what was just
              ;; painted on screen.
              (let ((spec base))
                (define (effect)
                  (paint-and-snapshot! chip-opts)
                  (let ((win-entry (assoc 'windows spec)))
                    (set-cdr! win-entry current-windows-data)))
                (append spec
                        (list (cons 'on-render-fn effect)))))
            (else base)))))

    (add-overlay-asset-file! 'css "lib/modaliser/blocks/window-list.css")
    (add-overlay-asset-file! 'js  "lib/modaliser/blocks/window-list.js")))
