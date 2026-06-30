;; (modaliser display-actions) — display-management panel block.
;;
;; The sibling of (modaliser window-actions). Users embed (display:display-list-
;; block 'chips? #t) in a window-management sub-screen alongside (window:list-
;; block 'chips? #t): round display chips (top-right) light up next to the
;; square window chips (top-left).
;;
;;   (import (modaliser dsl)
;;           (prefix (modaliser display-actions) display:))
;;
;;   (open "w" "Windows"
;;     (window:list-block 'chips? #t)
;;     (display:display-list-block 'chips? #t))
;;
;; Interaction: per display label, two dispatch keys are lifted to the block's
;; 'block-children — the plain letter moves the focused window to that display
;; (preserving its size/position as a fraction of the display, see remap-frame),
;; and the uppercase (Shift) letter focuses that display. Default labels
;; h j k l n o; override with 'labels. Surplus labels (more labels than
;; displays) are inert no-ops, exactly as the window-list digit range binds all
;; ten digits regardless of window count.

(define-library (modaliser display-actions)
  (export display-list-block
          move-focused-window-to-display
          ;; Exported for unit testing the proportional remap + source pick.
          remap-frame
          display-containing-point)
  (import (scheme base)
          (scheme char)
          (modaliser dsl)
          (modaliser util)
          (modaliser window)
          (modaliser blocks display-list))
  (begin

    ;; ─── Proportional remap (pure) ─────────────────────────────────
    ;;
    ;; Preserve the window's size and position as a FRACTION of each display's
    ;; visible frame, scaling x and y independently so a ⅓-width window stays
    ;; ⅓-width across displays of differing size/aspect. newW/newH are clamped
    ;; so the window stays within the target (mirrors move-window's
    ;; min(width, 1 - x) clamp). win/src/tgt are alists carrying x y w h.
    (define (remap-frame win src tgt)
      (let* ((wx (cdr (assoc 'x win))) (wy (cdr (assoc 'y win)))
             (ww (cdr (assoc 'w win))) (wh (cdr (assoc 'h win)))
             (sx (cdr (assoc 'x src))) (sy (cdr (assoc 'y src)))
             (sw (cdr (assoc 'w src))) (sh (cdr (assoc 'h src)))
             (tx (cdr (assoc 'x tgt))) (ty (cdr (assoc 'y tgt)))
             (tw (cdr (assoc 'w tgt))) (th (cdr (assoc 'h tgt)))
             (fx (/ (- wx sx) sw))
             (fy (/ (- wy sy) sh))
             (fw (/ ww sw))
             (fh (/ wh sh))
             (cfw (min fw (- 1 fx)))
             (cfh (min fh (- 1 fy)))
             (nx (+ tx (* fx tw)))
             (ny (+ ty (* fy th)))
             (nw (* cfw tw))
             (nh (* cfh th)))
        (list nx ny nw nh)))

    ;; ─── Source-display selection (pure) ───────────────────────────

    (define (point-in-display? d px py)
      (let ((x (cdr (assoc 'x d))) (y (cdr (assoc 'y d)))
            (w (cdr (assoc 'w d))) (h (cdr (assoc 'h d))))
        (and (>= px x) (< px (+ x w))
             (>= py y) (< py (+ y h)))))

    ;; First display whose visible frame contains (px, py), or #f.
    (define (display-containing-point displays px py)
      (let loop ((ds displays))
        (cond
          ((null? ds) #f)
          ((point-in-display? (car ds) px py) (car ds))
          (else (loop (cdr ds))))))

    (define (primary-display displays)
      (let loop ((ds displays))
        (cond
          ((null? ds) (and (pair? displays) (car displays)))
          ((cdr (assoc 'is-primary (car ds))) (car ds))
          (else (loop (cdr ds))))))

    (define (display-by-id displays id)
      (let loop ((ds displays))
        (cond
          ((null? ds) #f)
          ((= (cdr (assoc 'id (car ds))) id) (car ds))
          (else (loop (cdr ds))))))

    ;; ─── Move (impure: reads focused-window, writes the frame) ─────

    ;; Move the focused window to display `id`, preserving its position/size as
    ;; a fraction of each display's visible frame. Source = the display whose
    ;; visible frame contains the window's centre (fall back to primary).
    (define (move-focused-window-to-display id)
      (let ((fw (focused-window))
            (displays (list-displays)))
        (when (and fw (pair? displays))
          (let* ((cx (+ (cdr (assoc 'x fw)) (/ (cdr (assoc 'w fw)) 2)))
                 (cy (+ (cdr (assoc 'y fw)) (/ (cdr (assoc 'h fw)) 2)))
                 (src (or (display-containing-point displays cx cy)
                          (primary-display displays)))
                 (tgt (display-by-id displays id)))
            (when (and src tgt)
              (let ((r (remap-frame fw src tgt)))
                (set-focused-window-frame (car r) (cadr r)
                                          (caddr r) (cadddr r))))))))

    ;; ─── Dispatch (resolve a pressed label to the live display) ────

    (define (move-by-label label)
      (let ((entry (assoc label (display-list-current-targets))))
        (when entry
          (move-focused-window-to-display (cdr (assoc 'id (cdr entry)))))))

    (define (focus-by-label label)
      (let ((entry (assoc label (display-list-current-targets))))
        (when entry
          (focus-display (cdr (assoc 'id (cdr entry)))))))

    ;; Uppercase a single-char label string for the Shift focus binding.
    (define (label-shift label)
      (string (char-upcase (string-ref label 0))))

    ;; Two hidden dispatch keys per label: plain → move, Shift → focus. Marked
    ;; 'hidden so the loose region doesn't surface them as rows — the block's
    ;; own JS rows already show the label→display map and the Shift hint.
    (define (display-dispatch-keys labels)
      (let loop ((ls labels) (acc '()))
        (if (null? ls)
          (reverse acc)
          (let ((label (car ls)))
            (loop (cdr ls)
                  (cons (cons (cons 'hidden #t)
                              (key (label-shift label)
                                   (string-append "Focus " label)
                                   (lambda () (focus-by-label label))))
                        (cons (cons (cons 'hidden #t)
                                    (key label
                                         (string-append "Move to " label)
                                         (lambda () (move-by-label label))))
                              acc)))))))

    ;; (display-list-block . opts) → display-list block spec with dispatch keys.
    ;; Wraps make-display-list-block and lifts the move/focus keys for the whole
    ;; configured label set. Opts ('chips?, 'labels, 'corner) flow through.
    (define (display-list-block . opts)
      (let* ((base   (apply make-display-list-block opts))
             (alist  (apply props->alist opts))
             (labels (alist-ref alist 'labels default-display-labels)))
        (append base
                (list (cons 'block-children (display-dispatch-keys labels))))))

    ))
