;; (modaliser blocks display-list) — block constructor for the display-list
;; block. The sibling of (modaliser blocks window-list): it paints one round
;; "display chip" per display (top-right by default) and renders one overlay
;; row per display, exposing a label→display target map the action layer
;; resolves a pressed chip letter against.
;;
;; (make-display-list-block . opts) → block-spec alist
;;
;; Opts:
;;   'chips?  BOOL  — default #f. When #t the block's on-render-fn paints the
;;                    display chips (into the 'displays hint group) and snapshots
;;                    the displays list so the rendered rows mirror the chips.
;;   'labels  LIST  — default default-display-labels. Single-char strings, one
;;                    per display in left-to-right order; truncated to the
;;                    display count by label-pairs.
;;   'corner  SYM   — default 'top-right. One of top-left / top-right /
;;                    bottom-left / bottom-right — which corner of each display's
;;                    visible frame the chip is inset into.
;;
;; Chip styling is read at paint time from (current-chip-theme 'display), which
;; resolves the .chip + .chip.display CSS rules (see modaliser theming). The
;; round corner is computed here (corner-radius = floor(size / 2)), not from CSS.
;;
;; Display chips never overlap (a handful of displays, one per distinct corner),
;; so there is no occlusion search or slot-lattice cascade — placement is direct.

(define-library (modaliser blocks display-list)
  (export make-display-list-block
          display-list-current-labels
          display-list-current-targets
          default-display-labels
          ;; Exported for unit-testing the pure chip geometry.
          display-chip-for)
  (import (scheme base)
          (modaliser util)
          (modaliser window)
          (modaliser hints)
          (modaliser ax-hints)
          (modaliser overlay-assets)
          (modaliser theming))
  (begin

    ;; Per-render state — refreshed by the on-render effect every render. The
    ;; action layer's move/focus dispatch reads from these.
    (define current-display-targets '())   ;; ((label . display-alist) ...)
    (define current-displays-data '())     ;; ((label name primary) row shape)

    (define (display-list-current-targets) current-display-targets)
    (define (display-list-current-labels)
      (map car current-display-targets))

    ;; Default chip letters, left-to-right. hjkl are the user's movement keys;
    ;; n/o extend past four displays. Override with 'labels.
    (define default-display-labels
      (list "h" "j" "k" "l" "n" "o"))

    (define (floor-div a b)
      (exact (floor (/ a b))))

    ;; (display-chip-for label disp theme corner) → chip alist for hints-show-in.
    ;; Round (corner-radius = floor(size/2)) and inset (chip-host-padding) from
    ;; the chosen corner of the display's visible frame.
    (define (display-chip-for label disp theme corner)
      (let* ((dx (cdr (assoc 'x disp))) (dy (cdr (assoc 'y disp)))
             (dw (cdr (assoc 'w disp))) (dh (cdr (assoc 'h disp)))
             (font-size (cdr (assoc 'font-size theme)))
             (padding   (cdr (assoc 'padding theme)))
             (host-pad  (chip-host-padding))
             (size      (+ font-size (* 2 padding)))
             (right?    (or (eq? corner 'top-right) (eq? corner 'bottom-right)))
             (bottom?   (or (eq? corner 'bottom-left) (eq? corner 'bottom-right)))
             (chip-x    (if right?  (- (+ dx dw) size host-pad) (+ dx host-pad)))
             (chip-y    (if bottom? (- (+ dy dh) size host-pad) (+ dy host-pad)))
             (radius    (floor-div size 2)))
        (list (cons 'label label)
              (cons 'x chip-x) (cons 'y chip-y)
              (cons 'w size) (cons 'h size)
              (cons 'font-size font-size)
              (cons 'padding padding)
              (cons 'corner-radius radius)
              (cons 'color (cdr (assoc 'color theme)))
              (cons 'background (cdr (assoc 'background theme)))
              (cons 'border-width (cdr (assoc 'border-width theme)))
              (cons 'border-color (cdr (assoc 'border-color theme))))))

    ;; on-render side-effect: paint the display chips into the 'displays group
    ;; (so they coexist with the window chips in the default group) and snapshot
    ;; the rows. Reads the 'display chip theme at paint time.
    (define (paint-and-snapshot! labels corner)
      (let* ((theme    (current-chip-theme 'display))
             (displays (list-displays))
             (labelled (label-pairs labels displays))
             (chips    (map (lambda (ld)
                              (display-chip-for (car ld) (cdr ld) theme corner))
                            labelled))
             (rows (let loop ((ls labelled) (i 1) (acc '()))
                     (if (null? ls)
                       (reverse acc)
                       (let ((label (car (car ls)))
                             (d     (cdr (car ls))))
                         (loop (cdr ls) (+ i 1)
                               (cons (list (cons 'label label)
                                           (cons 'name (string-append
                                                         "Display " (number->string i)))
                                           (cons 'primary (cdr (assoc 'is-primary d))))
                                     acc)))))))
        (set! current-display-targets labelled)
        (set! current-displays-data rows)
        (hints-show-in 'displays chips)))

    ;; Constructor. Mirrors make-window-list-block: 'chips? #t installs the
    ;; on-render paint + snapshot and an on-leave that clears ALL hint groups
    ;; (hints-hide) when the overlay closes — display chips and window chips
    ;; clear together. Absence (or #f) yields a static block with no chips.
    (define (make-display-list-block . opts)
      (let* ((alist  (apply props->alist opts))
             (labels (alist-ref alist 'labels default-display-labels))
             (corner (alist-ref alist 'corner 'top-right)))
        (cond
          ((alist-ref alist 'chips? #f)
            (list (cons 'type 'display-list)
                  (cons 'on-render-fn
                    (lambda ()
                      (paint-and-snapshot! labels corner)
                      (list (cons 'displays current-displays-data))))
                  (cons 'on-leave-fn
                    (lambda () (hints-hide)))))
          (else
            (list (cons 'type 'display-list)
                  (cons 'displays '()))))))

    (add-overlay-asset-file! 'css "lib/modaliser/blocks/display-list.css")
    (add-overlay-asset-file! 'js  "lib/modaliser/blocks/display-list.js")))
