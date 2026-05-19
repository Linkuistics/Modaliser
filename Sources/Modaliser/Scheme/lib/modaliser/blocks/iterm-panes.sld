;; (modaliser blocks iterm-panes) — block constructor for the iTerm
;; panes list. Mirrors (modaliser blocks window-list) but tailored to
;; iTerm pane discovery: AX gives pane frames + reading-order index,
;; AppleScript gives session UUIDs in matching enumeration order, and
;; the N-th frame binds to the N-th UUID.
;;
;; (make-iterm-panes-block . opts) → block-spec alist
;;
;; Opts:
;;   'chips? BOOL — default #f. When #t, the block's on-render-fn paints
;;                  pane chips (via hints-show) AND snapshots the current
;;                  labelled panes. When #f the block renders just the
;;                  row list with no chips.
;;
;; The block exposes (iterm-panes-current-targets) → ((label . uuid) ...)
;; so the parent group can build a (key-range "1.." ...) that dispatches
;; per-digit pane focus by UUID — race-free, no event injection.
;;
;; Chip appearance lives in CSS (.chip rule, base.css + theme.css). See
;; (modaliser theming).

(define-library (modaliser blocks iterm-panes)
  (export make-iterm-panes-block
          iterm-panes-current-targets
          iterm-panes-current-labels)
  (import (scheme base)
          (modaliser dsl)
          (modaliser util)
          (modaliser shell)
          (modaliser hints)
          (modaliser ax-hints)
          (modaliser overlay-assets)
          (modaliser theming))
  (begin

    (define default-pane-labels
      (list "1" "2" "3" "4" "5" "6" "7" "8" "9" "0"))

    ;; Per-render state — refreshed by on-render-fn every render. The
    ;; parent group's digit key-range reads from here on key press, so
    ;; whichever pane carried that label at paint time is the one
    ;; focused.
    (define current-pane-targets '())   ;; ((label . uuid) ...)
    (define current-panes-data '())     ;; ((label . title) shape, see paint-and-snapshot!)

    (define (iterm-panes-current-targets) current-pane-targets)
    (define (iterm-panes-current-labels)
      (map car current-pane-targets))

    ;; Query iTerm for the UUIDs of every session in the focused window's
    ;; current tab. Returns '() when iTerm isn't running. UUIDs don't
    ;; contain commas, so the comma-space split is safe.
    (define (iterm-list-session-ids)
      (let* ((out (run-shell
                    (string-append
                      "osascript -e 'tell application \"iTerm\" to "
                      "id of every session of current tab of current window' "
                      "2>/dev/null")))
             (trimmed (string-trim out)))
        (if (string=? trimmed "")
          '()
          (let loop ((parts (string-split trimmed ",")) (acc '()))
            (cond
              ((null? parts) (reverse acc))
              (else
                (let ((s (string-trim (car parts))))
                  (loop (cdr parts)
                        (if (string=? s "") acc (cons s acc))))))))))

    ;; ─── on-render side-effect ─────────────────────────────────────
    ;; Discover the current pane layout, snapshot label→UUID, and paint
    ;; chips. AX provides the frames + a 0-based 'idx; AppleScript's
    ;; enumeration order matches (NSView subview-tree DFS), so the
    ;; N-th frame's UUID is (list-ref session-ids idx).
    (define (paint-and-snapshot! labels)
      (let* ((raw-panes    (ax-find-elements-named
                             "com.googlecode.iterm2" "AXScrollArea" "AXStaticText"))
             (panes        (label-pairs labels raw-panes))
             (session-ids  (iterm-list-session-ids))
             (sid-count    (length session-ids)))
        (let loop ((ps panes) (targets '()) (rows '()))
          (cond
            ((null? ps)
             (set! current-pane-targets (reverse targets))
             (set! current-panes-data   (reverse rows))
             (hints-show (ax-target-hints panes (current-chip-theme 'normal))))
            (else
             (let* ((entry (car ps))
                    (label (car entry))
                    (pane  (cdr entry))
                    (idx   (cdr (assoc 'idx pane)))
                    (name  (let ((p (assoc 'name pane)))
                             (if p (cdr p) "")))
                    (sid   (and (< idx sid-count)
                                (list-ref session-ids idx)))
                    (row   (list (cons 'label label)
                                 (cons 'title name))))
               (loop (cdr ps)
                     (if sid (cons (cons label sid) targets) targets)
                     (cons row rows))))))))

    ;; Constructor. See window-list.sld for the on-render-fn protocol:
    ;; the block-list renderer calls (fn) before serialising; any pair/
    ;; alist returned merges into the block JSON. We use this to splice
    ;; the freshly-captured panes-data so the rendered rows match the
    ;; chips painted on the same render pass.
    (define (make-iterm-panes-block . opts)
      (let* ((alist  (apply props->alist opts))
             (labels (alist-ref alist 'pane-labels default-pane-labels)))
        (cond
          ((alist-ref alist 'chips? #f)
            (list (cons 'type 'iterm-panes)
                  (cons 'on-render-fn
                    (lambda ()
                      (paint-and-snapshot! labels)
                      (list (cons 'panes current-panes-data))))
                  (cons 'on-leave-fn
                    (lambda () (hints-hide)))))
          (else
            (list (cons 'type 'iterm-panes)
                  (cons 'panes '()))))))

    (add-overlay-asset-file! 'css "lib/modaliser/blocks/iterm-panes.css")
    (add-overlay-asset-file! 'js  "lib/modaliser/blocks/iterm-panes.js")))
