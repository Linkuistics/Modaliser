;; (modaliser list-cursor) — selection-cursor state for embedded live lists.
;;
;; A which-key panel can embed a live list (window-list / iterm-panes /
;; iterm-tabs). Alongside the immediate digit selectors (1–9/0, dispatched by a
;; hidden key-range), the list carries a movable SELECTION CURSOR: ↑↓ / k j move
;; a highlighted row, ⏎ activates it. This library holds that cursor's state —
;; which list owns it and the clamped selected index — kept out of the state
;; machine and the renderer so both can read it without either owning it.
;;
;; The cursor pivots on the list's existing `*-current-targets` alist (the
;; ((label . target) …) snapshot the digit dispatch already consults): the
;; cursor is a movable pointer into that list, and its "label" at any index is
;; the very digit the immediate selector would fire — so ⏎ activation reuses the
;; digit-range dispatch verbatim (see modal-list-cursor-activate! in the state
;; machine). The list block hands us a *targets accessor* (a thunk returning the
;; live alist), never the data — so a move always sees the current snapshot.
;;
;; Ownership across a render: a screen's renderer serializes its panels in
;; declaration order, each list block OFFERING its accessor during that pass.
;; The FIRST offer of the pass wins (design spec §12: the first live-list panel
;; owns the cursor; Tab-cycling between lists is a non-goal). A pass with no
;; offer — a screen with no live list — clears the cursor so its keys go inert.
;;
;; Portable: imports only (scheme base) — no host LispKit libraries, so
;; check-portable-surface.sh stays green.

(define-library (modaliser list-cursor)
  (export list-cursor-begin-pass! list-cursor-end-pass! list-cursor-offer!
          list-cursor-active? list-cursor-active-targets-fn
          list-cursor-index list-cursor-count list-cursor-has-selection?
          list-cursor-move! list-cursor-selected-label
          list-cursor-clear!)
  (import (scheme base))
  (begin

    ;; The active list's targets accessor — a thunk returning the live
    ;; ((label . target) …) alist — or #f when no list owns the cursor.
    (define active-targets-fn #f)
    ;; Selected row, an index into (active-targets-fn). Read through
    ;; list-cursor-index, which clamps it against the live count.
    (define selected-index 0)
    ;; Per render-pass first-wins guard. begin-pass! clears it; the first
    ;; offer! of the pass sets it; end-pass! reads it to decide whether the
    ;; screen had any list at all.
    (define claimed-this-pass? #f)

    ;; Start a render pass — call once before serializing a screen body.
    (define (list-cursor-begin-pass!)
      (set! claimed-this-pass? #f))

    ;; A list block presents its targets accessor as a cursor candidate. The
    ;; first offer of the pass wins (first declared list owns the cursor). When
    ;; the winning list differs from the previously active one (a screen
    ;; change), the selection resets to the top; re-offering the SAME accessor
    ;; across re-renders preserves the index, so a cursor move's own re-render
    ;; doesn't snap the cursor back to row 0.
    (define (list-cursor-offer! targets-fn)
      (unless claimed-this-pass?
        (set! claimed-this-pass? #t)
        (unless (eq? targets-fn active-targets-fn)
          (set! active-targets-fn targets-fn)
          (set! selected-index 0))))

    ;; Finish a render pass — call once after serializing a screen body. If no
    ;; list claimed the cursor this pass, the current screen has no live list,
    ;; so drop the controller and its keys go inert.
    (define (list-cursor-end-pass!)
      (unless claimed-this-pass?
        (list-cursor-clear!)))

    (define (list-cursor-clear!)
      (set! active-targets-fn #f)
      (set! selected-index 0))

    (define (list-cursor-active?) (and active-targets-fn #t))
    (define (list-cursor-active-targets-fn) active-targets-fn)

    (define (list-cursor-count)
      (if active-targets-fn (length (active-targets-fn)) 0))

    (define (list-cursor-has-selection?)
      (> (list-cursor-count) 0))

    ;; Clamp on read: the live targets list can shrink between renders (a
    ;; window closed, a pane merged), so a stored index may now be out of range.
    (define (list-cursor-index)
      (let ((n (list-cursor-count)))
        (cond ((<= n 0) 0)
              ((>= selected-index n) (- n 1))
              ((< selected-index 0) 0)
              (else selected-index))))

    ;; Shift the selection by DELTA, clamped to [0, count-1] (no wrap — mirrors
    ;; the chooser's clamp-on-arrow). Returns the new index; a no-op when no
    ;; list is active (returns 0).
    (define (list-cursor-move! delta)
      (let ((n (list-cursor-count)))
        (if (<= n 0)
          0
          (let* ((cur (list-cursor-index))
                 (nxt (+ cur delta))
                 (clamped (cond ((< nxt 0) 0)
                                ((>= nxt n) (- n 1))
                                (else nxt))))
            (set! selected-index clamped)
            clamped))))

    ;; The label (digit string) of the row under the cursor — the car of the
    ;; index-th (label . target) pair — or #f when no list / empty. ⏎ activation
    ;; dispatches this label through the normal digit-range path.
    (define (list-cursor-selected-label)
      (if (list-cursor-has-selection?)
        (car (list-ref (active-targets-fn) (list-cursor-index)))
        #f))))
