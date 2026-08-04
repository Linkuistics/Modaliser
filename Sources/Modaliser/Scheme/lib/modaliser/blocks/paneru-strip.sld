;; (modaliser blocks paneru-strip) — block constructor for the **Strip
;; listing** (paneru-strip-list-k7, docs/specs/paneru-window-management.md
;; decision 1): one overlay row per window on paneru's active virtual
;; workspace, in strip order — jump label, app name, window title, and a
;; `.current` marker on the focused row.
;;
;; (make-paneru-strip-block . opts) → block-spec
;;
;; Opts:
;;   'assigned-fn  THUNK — zero-arg, returns the **Strip snapshot**:
;;                 jump-labels-assign's own ((label . target) …) shape, the
;;                 target being a **Strip target** alist ('app 'title
;;                 'focused …). Threaded in rather than imported — this
;;                 block stays a generic UI component that knows nothing of
;;                 paneru, and the dependency runs one way only: (modaliser
;;                 wms paneru) composes this block, never the reverse.
;;                 Default: a thunk returning '() (an empty listing).
;;
;; **This block never queries.** Its render hook reads a cell; the gather,
;; the join and the label assignment all happened in the strip Edge provider
;; at come-to-rest, before any render. That inversion of blocks/window-list's
;; contract (whose on-render-fn IS its data source) is the largest of the
;; four reasons this is a new block rather than a parameterised window-list —
;; the others being that the Strip listing paints no **Chip** (and chip
;; placement is the great majority of window-list's substance), that three
;; independent axes differ (source, labels, row shape), and that one block
;; per renderer is the established convention here.
;;
;; Display-only, mirroring (modaliser blocks herdr-jump-legend): it
;; dispatches nothing and mutates nothing. The jump labels reach the keyboard
;; as provider edges, not as a block key-range — so a label rendered here is
;; a picture of an edge that already exists.
;;
;; Unlike herdr-jump-legend, an UNLABELLED (#f) entry is NOT dropped: it
;; renders with a blank key and no dispatch, the existing list-block
;; convention for a tail past the label pools' exhaustion (spec "Degradation").
;; The listing is a picture of the strip, and a strip row that outran the
;; alphabet is still on the strip.

(define-library (modaliser blocks paneru-strip)
  (export make-paneru-strip-block
          ;; Pure Strip snapshot → row payload, exported for unit tests
          ;; (test seam 7, docs/specs/paneru-window-management.md
          ;; "Test seams") — fed a canned assignment, no live paneru needed.
          paneru-strip-rows)
  (import (scheme base)
          (modaliser util)
          (modaliser overlay-assets))
  (begin

    ;; ASSIGNED — ((label . target) …), already in strip order — → row
    ;; payload ((label app title focused) …), same length and order.
    ;;
    ;; Order is preserved unconditionally and nothing is filtered: the rows
    ;; ARE the strip, so dropping one would misrepresent it. A #f label
    ;; (past both pools) renders blank; an unmatched target (no 'owner-pid)
    ;; renders identically to a matched one and simply has no edge behind
    ;; its label (ADR-0024 Consequences) — which is deliberate, because
    ;; skipping unmatched rows during ASSIGNMENT would renumber every label
    ;; below a transient join miss, and the labels are muscle memory.
    (define (paneru-strip-rows assigned)
      (map (lambda (entry)
             (let ((label  (car entry))
                   (target (cdr entry)))
               (list (cons 'label (if (string? label) label ""))
                     (cons 'app     (or (alist-ref target 'app) ""))
                     (cons 'title   (or (alist-ref target 'title) ""))
                     (cons 'focused (if (alist-ref target 'focused) #t #f)))))
           assigned))

    ;; Constructor. Non-interactive: no 'cursor-targets-fn, no
    ;; 'block-children digit range — dispatch lives in the provider edges
    ;; (modaliser wms paneru)'s strip-provider mints, so the label here is
    ;; display-only.
    (define (make-paneru-strip-block . opts)
      (let* ((alist       (apply props->alist opts))
             (assigned-fn (alist-ref alist 'assigned-fn (lambda () '()))))
        (list (cons 'type 'paneru-strip)
              (cons 'on-render-fn
                    (lambda ()
                      (list (cons 'rows (paneru-strip-rows (assigned-fn)))))))))

    (add-overlay-asset-file! 'css "lib/modaliser/blocks/paneru-strip.css")
    (add-overlay-asset-file! 'js  "lib/modaliser/blocks/paneru-strip.js")))
