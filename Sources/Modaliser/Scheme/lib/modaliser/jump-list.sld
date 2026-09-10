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
          jump-list-prefix-state-id

          ;; ── Composing several panels onto one 'provider slot ──────
          ;;      (vscode-part-panels-k7, docs/specs/vscode-window-parts.md
          ;;      decision 7)
          ;;
          ;; (jump-list-compose-providers NAME PROVIDER NAME PROVIDER …)
          ;;   → one Edge provider. Calls each contributor with the owner
          ;;   id it was handed, appends their 'edges and 'states in
          ;;   argument order, and RAISES on a collision the engine would
          ;;   otherwise resolve silently.
          jump-list-compose-providers
          ;; The pure, raising half — every fact as data, no graph
          ;; installed. This is the seam: all four collision cases are
          ;; tested here by direct call.
          ;;
          ;; (jump-list-validate-composition RESULTS NAMES OWNER-EDGES
          ;;                                 REGISTERED-STATE-IDS)
          ;;   → the merged ((edges . …) (states . …)), or raises.
          jump-list-validate-composition)
  (import (scheme base)
          (modaliser util)
          ;; edge / provided-state: the FSM primitives an assignment is
          ;; lowered onto. Both portable — (modaliser fsm) imports only
          ;; (scheme base) (scheme write) (modaliser util).
          ;;
          ;; fsm-state-edges / fsm-state-ids are the two questions the
          ;; composer asks the graph ITSELF (decision 7) — deliberately
          ;; not arguments a caller could replace, because a user's
          ;; config is Scheme and could then hand in two empty readers
          ;; and turn the collision check off while still looking
          ;; composed. Edges are plain alists, so reading a trigger
          ;; needs no accessor export.
          (only (modaliser fsm)
                edge provided-state fsm-state-edges fsm-state-ids)
          ;; block-ref-id — the SAME accessor the overlay's panel→block
          ;; resolution uses (display-dsl.sld resolve-block-ref), so the
          ;; reference a narrowing prefix state mints and the lookup that
          ;; resolves it provably agree. Reading 'type directly was right
          ;; while every caller's block had a unique type, and became a
          ;; blank narrowed panel the moment two panels shared one block
          ;; type and disambiguated with explicit 'id entries. Portable:
          ;; display-dsl imports only (scheme …) and (modaliser …).
          (only (modaliser display-dsl) block-ref-id))
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
    ;; The panel references the block by the id the caller's own block spec
    ;; answers to — `block-ref-id`, which is the block's explicit 'id when it
    ;; has one and its 'type otherwise, and is the very accessor the overlay's
    ;; own panel→block resolution uses. Restating it here would be a second
    ;; place for it to be wrong, and the failure is a blank panel. Reading
    ;; 'type directly would be the same failure one step further away: two
    ;; panels sharing one block type must give each block an explicit 'id to
    ;; be resolvable at all, and a type-keyed reference then names nothing.
    ;;
    ;; PANEL-LABEL rides in from the user (ADR-0021): a label authored in a
    ;; library file sits inside the decision-free contract's spirit even where
    ;; check-decision-free.sh's grep cannot see it.
    (define (prefix-state owner-id panel-label leader pairs
                          state-id-fn action-fn block-fn)
      (let* ((block        (block-fn pairs))
             (block-type   (block-ref-id block))
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
                            target)))))))))

    ;; ─── Composing several panels onto one 'provider slot ───────────
    ;;
    ;; A state has ONE 'provider slot, and a screen that wants two
    ;; labelled panels on it has to merge two Edge provider results into
    ;; one. Appending them is mechanically fine and silently wrong when
    ;; it is not, because NOTHING in the engine checks — verified in
    ;; fsm.sld rather than assumed:
    ;;
    ;;   - a provider's edges are folded in with the owner state's own by
    ;;     plain append, with no duplicate check over the result;
    ;;   - a key is resolved by finding the FIRST matching live edge, so a
    ;;     duplicate trigger dispatches to whichever contributor came
    ;;     first;
    ;;   - provided states are installed into a table keyed by id, so a
    ;;     duplicate state id is last-wins;
    ;;   - the duplicate-edge check inside `provided-state` covers ONE
    ;;     state's own edges and nothing across two results.
    ;;
    ;; So the merge checks, and RAISES. Raising rather than dropping,
    ;; because a dropped edge is a dead key with no diagnostic: the key
    ;; still works, bound to whichever panel contributed first, so the
    ;; user presses a terminal's label and focuses a project. A silent
    ;; wrong dispatch is the exact failure this exists to prevent.
    ;;
    ;; ── The surface the validation has to cover is WIDER than the
    ;; provider results, and this is where the first design fell short.
    ;; Two collision sources the engine has, that checking only the
    ;; results leaves uncovered:
    ;;
    ;;   THE OWNER STATE'S OWN STATIC EDGES. A promoted leader that
    ;;   happens to equal a screen key dispatches to the static edge and
    ;;   the row's label silently does the wrong thing. This is MORE
    ;;   likely than a panel-panel collision, because the screen's own
    ;;   keys are already spoken for.
    ;;
    ;;   PERMANENTLY REGISTERED STATES. A provided state shadows a
    ;;   permanent state of the same id, first-lookup-wins.
    ;;
    ;; ── And why the public operation takes no readers for those two.
    ;; An earlier draft passed them in as optional arguments so a test
    ;; could supply them — which meant a user's config, which is Scheme
    ;; calling the same exported procedure, could hand in two empty
    ;; readers and turn the check off while still appearing to compose
    ;; safely. A check with a documented off-switch is discipline
    ;; wearing a check's clothes. So the surface splits at the PURITY
    ;; line instead: the validator below takes every fact as data and is
    ;; where all four cases are tested, and the wrapper that asks the
    ;; graph the two questions has nothing in it worth a seam.
    ;;
    ;; ── When it raises. At come-to-rest, on the dispatch path, which
    ;; is deliberate: a panel's edges are one per surviving single-key
    ;; label PLUS one per promoted leader, and leader promotion is
    ;; DATA-DEPENDENT — two panels can share a leader key and coexist
    ;; happily until one of them grows past its single alphabet. At
    ;; config-load there is no row count to check against.
    ;;
    ;; A raise here releases the keyboard on both dispatch paths and
    ;; tears the modal down on both: the leader path never registers or
    ;; shows anything, and the catch-all path applies modal-abort! after
    ;; releasing the keys (docs/reference/state-machine.md, "When a
    ;; keypress raises"). So the screen just closes; the error text goes
    ;; to the system log and nowhere the user is looking.

    ;; An edge's trigger. Edges are plain alists, so this needs no
    ;; accessor from (modaliser fsm) — and it must stay in step with
    ;; fsm.sld's own `edge-trigger`, which reads the same key.
    (define (edge-trigger-of e) (alist-ref e 'trigger))

    ;; A provided state's id, off the alist `provided-state` returns.
    (define (state-id-of s) (alist-ref s 'id))

    ;; Both comparisons are `equal?` and neither normalises, which
    ;; matches the engine exactly: the graph's edge table and the
    ;; visit's provided-state table are both plain equal?-keyed hash
    ;; tables, so the string "foo" and the symbol foo are two different
    ;; states there and must be two different states here.
    ;;
    ;; Triggers are compared whole rather than filtered to key strings.
    ;; 'up and 'auto collide by the same first-match rule a key does,
    ;; and no current contributor emits either — so including them can
    ;; only catch a real collision, never invent one.

    ;; NAMES is parallel to RESULTS. A contributor's name is the
    ;; CALLER's — the panel's own, out of the user's config — because an
    ;; ordinal cannot repair a configuration: "Editors and Terminals
    ;; both claim j" is a repair, "provider 1 and provider 2" is a
    ;; puzzle. The names being the caller's is also what keeps this
    ;; library free of authored labels (ADR-0021).
    (define (name-at names i)
      (if (< i (length names)) (list-ref names i) "?"))

    (define (compose-error what a b detail)
      (error (string-append "jump-list-compose-providers: " a " and " b
                            " both " what " " detail)))

    ;; (jump-list-validate-composition RESULTS NAMES OWNER-EDGES
    ;;                                 REGISTERED-STATE-IDS)
    ;;   → ((edges . …) (states . …)), or raises.
    ;;
    ;; RESULTS is the contributors' results in argument order; NAMES is
    ;; parallel to it. OWNER-EDGES is the owner state's own declared
    ;; edge list and REGISTERED-STATE-IDS the permanently registered
    ;; ids — both as data, so this is pure and testable from synthetic
    ;; input with no graph installed.
    ;;
    ;; Four raises, in the order a reader meets them: a contributor
    ;; against the owner's static edges, a contributor against a
    ;; registered state id, then contributor against contributor on a
    ;; trigger and on a state id. The owner checks come first because
    ;; they are the likelier collision.
    (define (jump-list-validate-composition results names owner-edges
                                            registered-state-ids)
      (let ((owner-triggers (map edge-trigger-of owner-edges)))
        ;; Contributor vs. the owner and the permanent graph.
        (let loop ((rest results) (i 0))
          (unless (null? rest)
            (let ((who (name-at names i)))
              (for-each
                (lambda (e)
                  (let ((trigger (edge-trigger-of e)))
                    (when (member trigger owner-triggers)
                      (compose-error "claim the key" who "the screen itself"
                                     (trigger->text trigger)))))
                (alist-ref (car rest) 'edges '()))
              (for-each
                (lambda (s)
                  (let ((id (state-id-of s)))
                    (when (member id registered-state-ids)
                      (compose-error "claim the state id" who
                                     "a permanently registered state"
                                     (id->text id)))))
                (alist-ref (car rest) 'states '())))
            (loop (cdr rest) (+ i 1))))
        ;; Contributor vs. contributor, and vs. itself — a contributor
        ;; need not be one of ours, so a result that collides internally
        ;; is a real defect and is reported against its own name.
        (let loop ((rest results) (i 0)
                   (seen-triggers '()) (seen-ids '())
                   (edges '()) (states '()))
          (if (null? rest)
              (list (cons 'edges (reverse edges))
                    (cons 'states (reverse states)))
              (let* ((who   (name-at names i))
                     (my-es (alist-ref (car rest) 'edges '()))
                     (my-ss (alist-ref (car rest) 'states '())))
                (let ((seen-triggers
                        (fold-checked seen-triggers my-es edge-trigger-of who
                                      "claim the key" trigger->text))
                      (seen-ids
                        (fold-checked seen-ids my-ss state-id-of who
                                      "claim the state id" id->text)))
                  (loop (cdr rest) (+ i 1) seen-triggers seen-ids
                        (append (reverse my-es) edges)
                        (append (reverse my-ss) states))))))))

    ;; SEEN is ((value . owner-name) …). Adds each of ITEMS' keys,
    ;; raising against the earlier owner if one is already there.
    (define (fold-checked seen items key-of who what render)
      (let loop ((rest items) (seen seen))
        (if (null? rest)
            seen
            (let* ((k   (key-of (car rest)))
                   (hit (assoc k seen)))
              (when hit (compose-error what (cdr hit) who (render k)))
              (loop (cdr rest) (cons (cons k who) seen))))))

    ;; Rendering a trigger or an id for the message. Both may be a
    ;; string or a symbol; neither is quoted, because the message is
    ;; read by a human repairing a config, not parsed.
    (define (trigger->text t)
      (if (string? t) (string-append "\"" t "\"") (any->text t)))

    (define (id->text id) (any->text id))

    (define (any->text x)
      (cond ((string? x) x)
            ((symbol? x) (symbol->string x))
            ((number? x) (number->string x))
            (else "?")))

    ;; (jump-list-compose-providers NAME PROVIDER NAME PROVIDER …)
    ;;   → a 1-arg procedure for a state's 'provider slot.
    ;;
    ;; The thin impure wrapper: call the contributors with the owner id
    ;; the engine handed over, ask the graph the two questions the
    ;; validator cannot ask for itself, hand the lot to the validator.
    ;; Nothing in here is worth a seam of its own, which is the point —
    ;; everything that can be wrong is in the pure half above.
    ;;
    ;; An owner id naming no registered state contributes no static
    ;; edges (`fsm-state-edges` is total), so a screen built entirely
    ;; from provided states is not a special case — it is simply the
    ;; empty-owner-edges one. Note the consequence honestly: when the
    ;; owner is ITSELF a provided state, its edges are invisible to the
    ;; permanent graph and this check under-covers rather than
    ;; over-covers. No caller composes at that depth today.
    (define (jump-list-compose-providers . pairs)
      (let loop ((rest pairs) (names '()) (providers '()))
        (cond
          ((null? rest)
           (let ((names     (reverse names))
                 (providers (reverse providers)))
             (lambda (owner-id)
               (jump-list-validate-composition
                 (map (lambda (p) (p owner-id)) providers)
                 names
                 (fsm-state-edges owner-id)
                 (fsm-state-ids)))))
          ((null? (cdr rest))
           (error "jump-list-compose-providers: NAME with no provider after it"
                  (car rest)))
          (else
            (loop (cddr rest)
                  (cons (car rest) names)
                  (cons (cadr rest) providers))))))
)) 
