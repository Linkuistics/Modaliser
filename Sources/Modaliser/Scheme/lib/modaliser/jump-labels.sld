;; (modaliser jump-labels) — general parameterised jump-label assignment
;; (jump-labels-k4).
;;
;; Pure function: ordered targets in, prefix-free one- or two-key lowercase
;; labels out. First consumer is the herdr jump space
;; (docs/specs/herdr-jump-navigation.md) — axis priority (panes → spaces →
;; agents → tabs) becomes the caller's target order; this library knows
;; nothing about axes, only positions in a list.
;;
;; Three constraint parameters, each an ordered list of distinct one-char
;; strings, honoured as a PRIORITY order (never re-sorted, same convention
;; as axis priority / visual order elsewhere in this codebase):
;;   - single-alphabet — candidates for a one-key label, tried first.
;;   - leader-alphabet — candidates for the first key of a two-key label,
;;     escalated into only as needed, in the order given.
;;   - second-alphabet — candidates for the second key of a two-key label.
;; single-alphabet and leader-alphabet may overlap (the common case: a
;; restricted single alphabet, e.g. home-row-only, doubles as the leader
;; preference order) or be disjoint (dedicated leader-only keys that never
;; cost a single slot) — both are handled correctly.
;;
;; Escalation: if there are more targets than single-alphabet has capacity
;; for, leaders are promoted from leader-alphabet, IN ORDER, until capacity
;; (remaining singles + promoted-leaders × second-alphabet) covers every
;; target or leader-alphabet is exhausted. Promoting a leader that is ALSO
;; a single-alphabet member removes it from the single pool (prefix-freedom:
;; "a" would prefix "ab"); promoting a leader that ISN'T a single-alphabet
;; member costs nothing. A leader is skipped (never promoted) when doing so
;; cannot possibly help — e.g. a one-member second-alphabet promoting an
;; already-single leader nets zero capacity — so escalation only ever uses
;; the minimum leaders that each strictly add capacity, honouring the
;; caller's given order rather than re-sorting for a global optimum.
;;
;; Exhaustion: once both pools run dry, remaining targets get label #f —
;; the unlabelled tail. Output is always the same length as the input
;; target list, in the same order, so a caller can zip labels back onto
;; targets positionally.
;;
;; Determinism: no hidden state, no cross-invocation persistence — same
;; targets in the same order with the same three alphabets always produce
;; the same labels.
;;
;; Portable: imports only (scheme base) and (modaliser util) — no host
;; LispKit bindings, so check-portable-surface.sh stays green.

(define-library (modaliser jump-labels)
  (export jump-labels-assign)
  (import (scheme base)
          (modaliser util))
  (begin

    ;; Decide which PREFIX of leader-alphabet to promote to two-key duty, in
    ;; the order given. Returns (used-leaders . remaining-singles):
    ;;   used-leaders     — the promoted leaders, in leader-alphabet order.
    ;;   remaining-singles — single-alphabet with any promoted overlaps
    ;;                       removed, order preserved.
    ;; Stops as soon as capacity (remaining singles + used-leaders ×
    ;; second-count) covers targets-count, leader-alphabet runs out, or
    ;; second-alphabet is empty (no two-key label is ever possible, so
    ;; escalating would only ever waste a single slot).
    (define (compute-escalation targets-count single leaders seconds)
      (let ((second-count (length seconds)))
        (let loop ((remaining leaders)
                   (used '())
                   (avail-singles single)
                   (capacity (length single)))
          (cond
            ((or (>= capacity targets-count)
                 (null? remaining)
                 (zero? second-count))
             (cons (reverse used) avail-singles))
            (else
              (let* ((next (car remaining))
                     (was-single? (if (member next avail-singles) #t #f))
                     (delta (- second-count (if was-single? 1 0))))
                (if (> delta 0)
                  (loop (cdr remaining)
                        (cons next used)
                        (if was-single?
                          (remove (lambda (s) (string=? s next)) avail-singles)
                          avail-singles)
                        (+ capacity delta))
                  ;; Not beneficial (e.g. a single-member leader with a
                  ;; one-key second-alphabet) — skip it, keep scanning.
                  (loop (cdr remaining) used avail-singles capacity))))))))

    ;; All two-key labels reachable from the promoted leaders, in order:
    ;; every second-alphabet key under the first leader, then the second, …
    (define (two-key-pool leaders seconds)
      (apply append
             (map (lambda (l) (map (lambda (s) (string-append l s)) seconds))
                  leaders)))

    ;; Assign TARGETS (order = priority) labels drawn from SINGLE-ALPHABET,
    ;; escalating into LEADER-ALPHABET × SECOND-ALPHABET only as needed.
    ;; Returns a list of (label . target) pairs, same length and order as
    ;; TARGETS; label is #f for any target past the exhausted label pool.
    (define (jump-labels-assign targets single-alphabet leader-alphabet second-alphabet)
      (let* ((escalation (compute-escalation (length targets)
                                              single-alphabet
                                              leader-alphabet
                                              second-alphabet))
             (used-leaders (car escalation))
             (avail-singles (cdr escalation))
             (pool (append avail-singles (two-key-pool used-leaders second-alphabet))))
        (let loop ((ts targets) (ps pool) (acc '()))
          (if (null? ts)
            (reverse acc)
            (loop (cdr ts)
                  (if (null? ps) '() (cdr ps))
                  (cons (cons (if (null? ps) #f (car ps)) (car ts)) acc))))))))
