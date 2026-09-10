;; (modaliser blocks part-list) — block constructor for a **window part**
;; listing (vscode-part-panels-k7, docs/specs/vscode-window-parts.md
;; decision 6): one overlay row per part of the frontmost window, in
;; listing order — jump label, arrow, the part's name, and a dimmed
;; trailing detail.
;;
;; (make-part-list-block . opts) → block-spec
;;
;; Opts:
;;   'assigned-fn  THUNK — zero-arg, returns the assignment:
;;                 jump-labels-assign's own ((label . target) …) shape, the
;;                 target being any alist carrying 'text (the name), and
;;                 optionally 'detail, 'current, 'dirty and 'inert.
;;                 Threaded in rather than imported — this block stays a
;;                 generic UI component that knows nothing of VSCode, and
;;                 the dependency runs one way only: (modaliser apps
;;                 vscode) composes this block, never the reverse.
;;                 Default: a thunk returning '() (an empty listing).
;;   'id           SYMBOL — the id a panel references this block by, which
;;                 is `block-ref-id`'s explicit case. **Give one when two
;;                 part listings are alive on the same screen**, which is
;;                 the ordinary case here: a panel reference resolves by
;;                 'id when there is one and by 'type otherwise, and two
;;                 blocks answering to `part-list` are ambiguous.
;;                 Default: none, so the block answers to its 'type.
;;
;; **This block never queries.** Its render hook reads a cell; the gather
;; and the label assignment both happened in the Edge provider at
;; come-to-rest, before any render — the same inversion blocks/paneru-strip
;; and blocks/project-list describe, and for the same reason: the rows
;; drawn must be the exact assignment the keypress dispatches through.
;;
;; Display-only, mirroring its two peers: it dispatches nothing and mutates
;; nothing. The jump labels reach the keyboard as provider edges, not as a
;; block key-range — so a label rendered here is a picture of an edge that
;; already exists.
;;
;; ─── Why ONE block for two panels ───────────────────────────────────
;;
;; k4 recorded the rule this follows: **share machinery, duplicate
;; presentation** — duplicated machinery drifts silently, duplicated
;; presentation drifts visibly. That rule bought blocks/project-list its
;; own existence beside blocks/paneru-strip, because a Project row is one
;; long name in the full width and a Strip row is four competing columns.
;;
;; It buys the opposite here, and for the same reason read the other way: a
;; **Terminal listing** row is a short name plus a cwd, and an **Editor
;; listing** row is a filename plus a workspace-relative path. That is not
;; two presentations, it is one presentation with two callers — so writing
;; it twice would be duplicating presentation that is not different, which
;; the rule never asked for. What each panel supplies is the CONTENT of
;; `text` and `detail`; the grid is the same grid.
;;
;; It is closer to blocks/paneru-strip's four-column shape than to
;; blocks/project-list's full-width one, which decision 6 predicted, and it
;; is a separate block rather than a parameterisation of paneru's because
;; paneru's spec, DOM class names and shipped CSS are its own and renaming
;; them for a caller that renders different content is churn.
;;
;; ─── Two kinds of row that render and do not dispatch ───────────────
;;
;; An UNLABELLED (#f) entry is NOT dropped: it renders with a blank key and
;; no arrow, the list-block convention for a tail past the label pools'
;; exhaustion. The listing is a picture of what is open, and a part that
;; outran the alphabet is still open.
;;
;; An INERT entry — 'inert true — is the case this block has that its peers
;; do not, and it is normal use rather than a race: a tab of a kind with no
;; specified activation is listed with no token at all (spec decision 1), so
;; it has a label and nothing behind it. It renders with its label and
;; without an arrow, exactly as an unlabelled row does, because an arrow
;; pointing out of a keycap that does nothing is the one thing worse than
;; no arrow. Listing it and refusing to act is honest; omitting it would
;; make the panel disagree with the tab strip the user is looking at, and
;; would renumber every label below it.

(define-library (modaliser blocks part-list)
  (export make-part-list-block
          ;; Pure assignment → row payload, exported so a unit test can feed
          ;; it a canned assignment with no live editor under it.
          part-list-rows)
  (import (scheme base)
          (modaliser util)
          (modaliser overlay-assets))
  (begin

    ;; ASSIGNED — ((label . target) …), already in listing order — → row
    ;; payload ((label name detail current dirty inert) …), same length and
    ;; order.
    ;;
    ;; Order is preserved unconditionally and nothing is filtered: the rows
    ;; ARE the listing, so dropping one would misrepresent it. Both of the
    ;; non-dispatching cases above render like any other row apart from the
    ;; arrow, because skipping either during ASSIGNMENT would renumber every
    ;; label below it, and the labels are muscle memory.
    (define (part-list-rows assigned)
      (map (lambda (entry)
             (let ((label  (car entry))
                   (target (cdr entry)))
               (list (cons 'label   (if (string? label) label ""))
                     (cons 'name    (or (alist-ref target 'text) ""))
                     (cons 'detail  (or (alist-ref target 'detail) ""))
                     (cons 'current (if (alist-ref target 'current) #t #f))
                     (cons 'dirty   (if (alist-ref target 'dirty) #t #f))
                     (cons 'inert   (if (alist-ref target 'inert) #t #f)))))
           assigned))

    ;; Constructor. Non-interactive: no 'cursor-targets-fn, no
    ;; 'block-children digit range — dispatch lives in the provider edges
    ;; (modaliser jump-list) mints, so the label here is display-only.
    ;;
    ;; The 'id entry is emitted only when one was asked for: `block-ref-id`
    ;; prefers 'id over 'type, so a block carrying an empty or absent id
    ;; must not carry the key at all.
    (define (make-part-list-block . opts)
      (let* ((alist       (apply props->alist opts))
             (assigned-fn (alist-ref alist 'assigned-fn (lambda () '())))
             (id          (alist-ref alist 'id))
             (base        (list (cons 'type 'part-list)
                                (cons 'on-render-fn
                                      (lambda ()
                                        (list (cons 'rows (part-list-rows (assigned-fn)))))))))
        (if id (cons (cons 'id id) base) base)))

    (add-overlay-asset-file! 'css "lib/modaliser/blocks/part-list.css")
    (add-overlay-asset-file! 'js  "lib/modaliser/blocks/part-list.js")))
