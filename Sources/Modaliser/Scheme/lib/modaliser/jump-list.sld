;; (modaliser jump-list) — lowering a jump-label assignment onto the FSM
;; (jump-list-k4).
;;
;; Pure function over an assignment: `jump-labels-assign`'s own
;; ((label . target) …) shape in, one **Edge provider result** out —
;; 'edges and 'states, ready for a provided state's provider slot.
;;
;; This is the half of a labelled listing that is NOT about what is being
;; listed. Gathering the rows, joining them against a live enumeration and
;; choosing the alphabets all happen in the caller; what happens here is the
;; part that is subtle in the same way for every caller:
;;
;;   - a single-key label becomes a direct edge to a Terminal state;
;;   - a two-key label is grouped under its leader, and each leader becomes
;;     ONE edge to a narrowing PREFIX state that re-mints its own group;
;;   - a label with nothing behind it is dropped from the edge set and from
;;     nothing else, so the listing still shows the row.
;;
;; Extracted from (modaliser wms paneru)'s strip-provider, which was its
;; first caller and now composes it. The extraction was deliberate rather
;; than tidy-up: this machinery fails SILENTLY when it is wrong — a
;; mis-shaped prefix-state id garbles a breadcrumb, a missing re-mint makes
;; a second key resolve to a state nobody minted, an absent payload narrows
;; into a blank screen — and a second copy of it would drift without
;; anything going red. Presentation duplicated between two listings is
;; visible; this is not, which is why this is shared and the row renderers
;; are not.
;;
;; ─── What the caller injects ────────────────────────────────────────
;;
;; Three functions, and nothing else about the domain crosses the boundary:
;;
;;   'state-id  TARGET → STRING. A Terminal dispatch state's id. Free-form
;;              but must be collision-free across live targets; namespace it
;;              per caller so two listings alive at once cannot collide.
;;   'action    TARGET → THUNK, or #f. What pressing this target's label
;;              does. Returning #f means "nothing to do", which is also how
;;              a caller says a row is not actionable — the two are the same
;;              question, so they are one function (see below).
;;   'block     PAIRS → BLOCK-SPEC. The narrowed listing's block, given the
;;              ((second-key . target) …) survivors of one leader. Its own
;;              'type is read back out to reference it from the panel, so a
;;              caller never restates the type it just constructed.
;;
;; **Why 'action folds in the focusability predicate.** The first caller
;; carried a separate `strip-target-focusable?`, and a second caller would
;; have carried its own — two predicates that each had to agree with their
;; own action function about which targets are live. Folding them makes that
;; agreement structural: the target with no action IS the target with no
;; edge, because it is the same call.
;;
;; ─── Portable, and free of decisions ────────────────────────────────
;;
;; Imports only (scheme base), (modaliser util) and two FSM primitives, so
;; the portable surface stays clean. No key, label or alphabet is authored
;; here: the labels arrive already assigned, and PANEL-LABEL rides in from
;; the user (ADR-0021) exactly as it did in paneru.

(define-library (modaliser jump-list)
  (export ;; (jump-list-provider-result ASSIGNED OWNER-ID PANEL-LABEL
          ;;                            'state-id FN 'action FN 'block FN)
          ;;   → ((edges . …) (states . …))
          ;; The whole surface. Pure — it constructs states and edges and
          ;; fires nothing, which is why a test can assert its shape by
          ;; direct call with no seam underneath.
          jump-list-provider-result
          ;; A narrowing prefix state's id, OWNER-ID + "/" + LEADER.
          ;; Exported because the shape is load-bearing rather than free
          ;; (see below) and a caller's test may need to name one.
          jump-list-prefix-state-id)
  (import (scheme base)
          (modaliser util)
          ;; edge / provided-state: the FSM primitives an assignment is
          ;; lowered onto. Both portable — (modaliser fsm) imports only
          ;; (scheme base) (scheme write) (modaliser util).
          (only (modaliser fsm) edge provided-state))
  (begin

    ;; ─── Ids ────────────────────────────────────────────────────────
    ;;
    ;; A narrowing prefix state's id — OWNER-ID + "/" + leader, the
    ;; convention permanent child states use (fsm-child-id). This shape is
    ;; NOT free: a resting provided state survives as a Visit owner across
    ;; keystrokes, so the presentation façade reads it the way it reads a
    ;; permanent state, and modal-current-path's strip-id-prefix `substring`s
    ;; the parent's id off the child's to derive a breadcrumb segment. Any
    ;; other shape yields a garbled segment or raises outright.
    ;;
    ;; A TARGET's Terminal state id, by contrast, is free-form and therefore
    ;; the caller's ('state-id): a Terminal state deactivates before any
    ;; presentation code consults a state id's shape, so it needs
    ;; collision-freedom across live targets and nothing else.
    (define (jump-list-prefix-state-id owner-id leader)
      (string-append owner-id "/" leader))

    ;; ─── One target's Terminal state ────────────────────────────────
    ;;
    ;; Entry runs the caller's action, no edges — Terminal, so firing it
    ;; halts the engine and the modal exits, which is what a jump means.
    ;; 'payload '() (an empty alist, not the default #f) is never read here
    ;; — a Terminal state deactivates first — but it keeps the shape uniform
    ;; with the prefix state below, where the payload very much does matter.
    (define (terminal-state state-id-fn action-fn target)
      (provided-state (state-id-fn target)
        'payload '()
        'entry (action-fn target)))

    ;; ─── Leader grouping ────────────────────────────────────────────
    ;;
    ;; Merge (LEADER SECOND . TARGET) into BY-LEADER — an alist of
    ;; leader → ((second . target) …), preserving first-seen leader order and
    ;; each leader's own second-key order. Listings are small, so the append
    ;; buys ordering simplicity over a smarter accumulator.
    (define (merge-leader-group by-leader leader second target)
      (if (assoc leader by-leader)
          (map (lambda (kv)
                 (if (string=? (car kv) leader)
                     (cons leader (append (cdr kv) (list (cons second target))))
                     kv))
               by-leader)
          (append by-leader (list (cons leader (list (cons second target)))))))

    ;; ─── One leader's narrowing PREFIX (resting) state ──────────────
    ;;
    ;; Four things about it are load-bearing, and every one of them fails
    ;; silently if guessed at:
    ;;
    ;;  - its id is OWNER-ID + "/" + leader (see jump-list-prefix-state-id);
    ;;  - its 'up edge targets OWNER-ID, or backspace does not un-narrow and
    ;;    ancestors-within-tree stops the climb early;
    ;;  - its 'payload carries the two-layer node shape `screen` lowers a
    ;;    registered root's payload into — a 'children list holding the block,
    ;;    plus a 'display clause with one panel referencing it by type.
    ;;    fsm-resolved-payload hands this alist to the façade as
    ;;    modal-current-node, and the panel-grid renderer resolves 'children +
    ;;    'display off whatever that is (ADR-0011), so the UNCHANGED renderer
    ;;    draws the narrowed listing. A payload-less prefix state narrows into
    ;;    a blank screen with no indication of which second keys are live;
    ;;  - it carries its OWN 'provider, re-minting exactly the Terminal states
    ;;    its own second-key edges target. Not an optimisation: provided
    ;;    states are Visit-scoped, and stepping into this state BEGINS a new
    ;;    Visit whose provided table holds only what this state's provider
    ;;    returns. Without it the second key resolves to a state nobody minted.
    ;;
    ;; PAIRS is the ((second . target) …) survivor list the owner's provider
    ;; already computed, so the re-mint and the narrowed block are both closed
    ;; over it — no second gather, no re-narrowing, and the narrowed rows are
    ;; provably the same targets the second-key edges dispatch to.
    ;;
    ;; The panel references the block by the 'type the caller's own block
    ;; spec declares, read back out of it. Restating the type here would be a
    ;; second place for it to be wrong, and the failure is a blank panel.
    ;;
    ;; PANEL-LABEL rides in from the user (ADR-0021): a label authored in a
    ;; library file sits inside the decision-free contract's spirit even where
    ;; check-decision-free.sh's grep cannot see it.
    (define (prefix-state owner-id panel-label leader pairs
                          state-id-fn action-fn block-fn)
      (let* ((block        (block-fn pairs))
             (block-type   (alist-ref block 'type))
             (second-edges (map (lambda (p)
                                  (edge (car p) (state-id-fn (cdr p))))
                                pairs)))
        (apply provided-state (jump-list-prefix-state-id owner-id leader)
          'payload (list (cons 'children (list block))
                         (cons 'display
                               (list (cons 'panels
                                           (list (list (cons 'label panel-label)
                                                       (cons 'span 'wide)
                                                       (cons 'rows (list (cons 'block block-type)))))))))
          ;; This state's OWN id is handed in as the provider argument and
          ;; ignored: every state re-minted here is Terminal, so none of them
          ;; needs a parent id.
          'provider (lambda (own-id)
                      (list (cons 'states
                                  (map (lambda (p)
                                         (terminal-state state-id-fn action-fn (cdr p)))
                                       pairs))))
          (edge 'up owner-id)
          second-edges)))

    ;; ─── The result ─────────────────────────────────────────────────
    ;;
    ;; ASSIGNED ((label . target) …) → this Visit's provider result: 'edges
    ;; (one direct edge per single-key label, one per USED leader) and
    ;; 'states (one Terminal state per single-key target, one prefix state
    ;; per leader — a leader's own targets' Terminal states live in the
    ;; PREFIX state's provider, not here; see prefix-state).
    ;;
    ;; Two kinds of target are dropped from the edge set and from nothing
    ;; else — both still render as rows:
    ;;   - UNLABELLED (#f): past both label pools' exhaustion.
    ;;   - INERT: the caller's 'action answered #f, so there is nothing to
    ;;     fire. (paneru's case: the join found no owner-pid to focus.)
    ;; Dropping an inert target here rather than during ASSIGNMENT is the
    ;; deliberate choice: skipping it earlier would renumber every label below
    ;; it on a single transient miss, and the labels are muscle memory. A miss
    ;; costs one dead key.
    ;;
    ;; A leader whose every second key is dropped therefore contributes no
    ;; group at all, so the leader key itself stays dead rather than narrowing
    ;; into an empty listing.
    (define (jump-list-provider-result assigned owner-id panel-label . opts)
      (let* ((alist       (apply props->alist opts))
             (state-id-fn (alist-ref alist 'state-id))
             (action-fn   (alist-ref alist 'action))
             (block-fn    (alist-ref alist 'block)))
        (let loop ((rest assigned) (edges '()) (states '()) (by-leader '()))
          (if (null? rest)
              (let ((leader-edges
                      (map (lambda (kv)
                             (edge (car kv) (jump-list-prefix-state-id owner-id (car kv))))
                           by-leader))
                    (prefix-states
                      (map (lambda (kv)
                             (prefix-state owner-id panel-label (car kv) (cdr kv)
                                           state-id-fn action-fn block-fn))
                           by-leader)))
                (list (cons 'edges (append (reverse edges) leader-edges))
                      (cons 'states (append (reverse states) prefix-states))))
              (let* ((entry  (car rest))
                     (label  (car entry))
                     (target (cdr entry)))
                (cond
                  ((or (not label) (not (action-fn target)))
                   (loop (cdr rest) edges states by-leader))
                  ((= (string-length label) 1)
                   (loop (cdr rest)
                         (cons (edge label (state-id-fn target)) edges)
                         (cons (terminal-state state-id-fn action-fn target) states)
                         by-leader))
                  (else
                    (loop (cdr rest) edges states
                          (merge-leader-group
                            by-leader
                            (substring label 0 1)
                            (substring label 1 (string-length label))
                            target))))))))))) 
