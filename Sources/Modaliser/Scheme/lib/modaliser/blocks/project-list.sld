;; (modaliser blocks project-list) — block constructor for a **Project
;; listing** (vscode-project-panel-k4): one overlay row per open project,
;; in listing order — jump label and the project's name, nothing else.
;;
;; (make-project-list-block . opts) → block-spec
;;
;; Opts:
;;   'assigned-fn  THUNK — zero-arg, returns the assignment:
;;                 jump-labels-assign's own ((label . target) …) shape, the
;;                 target being any alist carrying 'text (the name to draw).
;;                 Threaded in rather than imported — this block stays a
;;                 generic UI component that knows nothing of VSCode, and
;;                 the dependency runs one way only: (modaliser apps vscode)
;;                 composes this block, never the reverse.
;;                 Default: a thunk returning '() (an empty listing).
;;
;; **This block never queries.** Its render hook reads a cell; the gather
;; and the label assignment both happened in the Edge provider at
;; come-to-rest, before any render — the same inversion blocks/paneru-strip
;; describes, and for the same reason: the rows drawn must be the exact
;; assignment the keypress dispatches through.
;;
;; Display-only, mirroring blocks/paneru-strip and blocks/herdr-jump-legend:
;; it dispatches nothing and mutates nothing. The jump labels reach the
;; keyboard as provider edges, not as a block key-range — so a label
;; rendered here is a picture of an edge that already exists.
;;
;; An UNLABELLED (#f) entry is NOT dropped: it renders with a blank key and
;; no dispatch, the list-block convention for a tail past the label pools'
;; exhaustion. The listing is a picture of what is open, and a project that
;; outran the alphabet is still open.
;;
;; ─── Why this is not blocks/paneru-strip ────────────────────────────
;;
;; The two are close and were weighed against each other when this was
;; written (jump-list-k4). What they share is the SUBTLE half — grouping,
;; prefix states, re-minting — and that half is shared, in
;; (modaliser jump-list), by both callers. What is duplicated here is
;; presentation: a row grid and forty lines of DOM building.
;;
;; The asymmetry is deliberate. Duplicated machinery drifts silently — a
;; prefix state minted the wrong way narrows into a blank screen and no
;; test goes red. Duplicated presentation drifts VISIBLY: you are looking
;; at it. So the machinery is shared and the renderers are not, which also
;; keeps paneru's shipped block, spec and DOM class names untouched rather
;; than renaming them for a caller that renders different content anyway.
;;
;; The content really is different. A Strip row is app name plus window
;; title in four columns; a Project row is ONE long name — the human's
;; worktree folders run past forty characters — which wants the full width
;; and an ellipsis, not a 1fr column with a title competing for the rest.

(define-library (modaliser blocks project-list)
  (export make-project-list-block
          ;; Pure assignment → row payload, exported so a unit test can feed
          ;; it a canned assignment with no live editor under it.
          project-list-rows)
  (import (scheme base)
          (modaliser util)
          (modaliser overlay-assets))
  (begin

    ;; ASSIGNED — ((label . target) …), already in listing order — → row
    ;; payload ((label name) …), same length and order.
    ;;
    ;; Order is preserved unconditionally and nothing is filtered: the rows
    ;; ARE the listing, so dropping one would misrepresent it. A #f label
    ;; (past both pools) renders blank; an INERT target — one the provider
    ;; found nothing to do with — renders identically to a live one and
    ;; simply has no edge behind its label, because skipping such a row
    ;; during ASSIGNMENT would renumber every label below it on a transient
    ;; miss, and the labels are muscle memory.
    (define (project-list-rows assigned)
      (map (lambda (entry)
             (let ((label  (car entry))
                   (target (cdr entry)))
               (list (cons 'label (if (string? label) label ""))
                     (cons 'name  (or (alist-ref target 'text) "")))))
           assigned))

    ;; Constructor. Non-interactive: no 'cursor-targets-fn, no
    ;; 'block-children digit range — dispatch lives in the provider edges
    ;; (modaliser jump-list) mints, so the label here is display-only.
    (define (make-project-list-block . opts)
      (let* ((alist       (apply props->alist opts))
             (assigned-fn (alist-ref alist 'assigned-fn (lambda () '()))))
        (list (cons 'type 'project-list)
              (cons 'on-render-fn
                    (lambda ()
                      (list (cons 'rows (project-list-rows (assigned-fn)))))))))

    (add-overlay-asset-file! 'css "lib/modaliser/blocks/project-list.css")
    (add-overlay-asset-file! 'js  "lib/modaliser/blocks/project-list.js")))
