;; (modaliser fsm) — The explicit FSM graph: data model, construction DSL,
;; and the step engine that runs it.
;;
;; Modal dispatch's core (ADR-0015, docs/specs/fsm-graph.md): states and
;; labelled edges as first-class, printable s-expression data. The file has
;; two halves: the GRAPH MODEL (construction, validation, the print/query
;; surface a renderer or tooling would use — graph-model-k8) and the STEP
;; ENGINE (configuration, activation, `step!`, visits, gates/providers,
;; the return stack — step-engine-k9, "─── Step engine ───" below). The
;; graph model never executes a state's behaviour; the step engine does.
;;
;; The graph is OPEN: registrations accumulate as config loads, so a state
;; may be created before every edge targeting it exists, and an edge may be
;; declared before its target state is registered (dangling targets are
;; only checked at step time, by the step engine). Entry rows are the one
;; exception — they must name an already-registered state (see fsm-entry!).
;;
;; Two ways to attach an edge to a state build the identical graph:
;;
;;   inline:     (fsm-state! 'a 'label "A" (edge "x" 'b))
;;   standalone: (fsm-state! 'a 'label "A")
;;               (fsm-edge! 'a "x" 'b)
;;
;; Because graph structure (a state's outgoing edges) can grow after the
;; state itself is created, it cannot live as an immutable field inside the
;; state's own alist — LispKit has no set-car!/set-cdr! to splice a new
;; edge into an existing list in place. Edges (and the entry table) instead
;; live in their own mutable hashtables, keyed by state id / entry name;
;; the state's alist holds only what's fixed at creation (label, payload,
;; the four action slots, the provider).

(define-library (modaliser fsm)
  (export
    ;; Construction
    fsm-state! edge fsm-edge! fsm-entry! named provided-state
    ;; Behaviour-slot introspection (a slot is #f, a bare procedure, or a
    ;; `named` wrapper around one — these two accessors see through it)
    fsm-named? fsm-behavior-proc fsm-behavior-name
    ;; State queries
    fsm-state-ids fsm-state-ref
    fsm-state-label fsm-state-payload
    fsm-state-entry fsm-state-exit fsm-state-show fsm-state-hide
    fsm-state-provider fsm-state-exit-on-unknown?
    fsm-state-edges fsm-up-edge fsm-ancestors fsm-state-class
    ;; Visit-scoped state resolution — like the queries above, but seeing
    ;; through to a PROVIDED (visit-scoped) state when one shadows a
    ;; permanent id, exactly as the step engine's own move-to! does
    ;; (resolve-state-def). A host layer presenting the CURRENT
    ;; configuration (state-machine.sld's payload/up-edge derivation)
    ;; needs this — the plain queries above only ever see the permanent
    ;; graph, so a provided RESTING state (e.g. a jump-label narrowing
    ;; prefix state) is invisible to them mid-Visit.
    fsm-resolve-state fsm-resolved-payload fsm-resolved-up-edge
    fsm-resolved-state-class
    ;; Entry-table queries
    fsm-entry-rows fsm-entry-ref fsm-entry-more-specific?
    ;; Printable / queryable whole-graph view
    fsm-graph->alist fsm-print
    ;; Step engine — activation
    fsm-activate! fsm-activate-via-entry-table!
    ;; Step engine — dispatch
    fsm-step! fsm-step-back! fsm-halt!
    ;; Step engine — configuration queries
    fsm-active? fsm-current-state fsm-return-stack
    fsm-visit-generation fsm-visit-displayed? fsm-live-edges
    ;; Step engine — host-injected hooks (the engine stays portable; a host
    ;; installs these at boot, mirroring (modaliser state-machine)'s
    ;; set-on-leave-accepts-reason!)
    fsm-mark-displayed! set-fsm-accepts-arg!)
  (import (scheme base)
          (scheme write)
          (modaliser util))
  (begin

;; ─── The `named` behaviour wrapper ──────────────────────────────
;;
;; Any behaviour slot (entry/exit/show/hide, a provider, a gate) is either
;; #f, a bare procedure, or one of these — a display name attached to a
;; procedure so the graph prints something readable instead of an opaque
;; closure. `fsm-behavior-proc` sees through the wrapper for calling;
;; `fsm-behavior-name` (and the printer, internally) sees through it for
;; display.
(define-record-type <fsm-named>
  (make-fsm-named name proc)
  fsm-named?
  (name fsm-named-name)
  (proc fsm-named-proc))

;; (named symbol-name procedure) → a wrapped behaviour slot value
(define (named name proc)
  (unless (symbol? name)
    (error "named: name must be a symbol" name))
  (unless (procedure? proc)
    (error "named: proc must be a procedure" proc))
  (make-fsm-named name proc))

;; A behaviour slot value is #f, a bare procedure, or a `named` wrapper.
(define (valid-behavior? v)
  (or (not v) (procedure? v) (fsm-named? v)))

(define (fsm-behavior-proc slot)
  (cond
    ((not slot) #f)
    ((fsm-named? slot) (fsm-named-proc slot))
    ((procedure? slot) slot)
    (else (error "fsm-behavior-proc: not a behavior slot" slot))))

(define (fsm-behavior-name slot)
  (cond
    ((not slot) #f)
    ((fsm-named? slot) (fsm-named-name slot))
    ((procedure? slot) #f)
    (else (error "fsm-behavior-name: not a behavior slot" slot))))

;; Printed form of a slot: the given name, `'anonymous-proc` for a bare
;; procedure (structure is printable; a closure's body stays opaque), or
;; #f. Used only by the whole-graph print/query view below.
(define (behavior-repr slot)
  (cond
    ((not slot) #f)
    ((fsm-named? slot) (fsm-named-name slot))
    ((procedure? slot) 'anonymous-proc)
    (else (error "behavior-repr: not a behavior slot" slot))))

;; ─── States ──────────────────────────────────────────────────────
;;
;; id -> alist: id, label, payload, entry, exit, show, hide, provider.
;; Deliberately holds no 'edges — see the file header note.

(define fsm-states (make-hash-table))
(define fsm-state-order '())    ;; ids, declaration order

(define (readable-id? id) (or (symbol? id) (string? id)))

(define (register-state! id label payload entry exit show hide provider exit-on-unknown)
  (unless (readable-id? id)
    (error "fsm-state!: id must be a symbol or string" id))
  (when (fsm-state-ref id)
    (error "fsm-state!: duplicate state id" id))
  (for-each
    (lambda (name slot)
      (unless (valid-behavior? slot)
        (error (string-append "fsm-state!: " name
                              " must be #f, a procedure, or (named …)")
               slot)))
    '("entry" "exit" "show" "hide" "provider")
    (list entry exit show hide provider))
  (hash-table-set! fsm-states id
    (list (cons 'id id) (cons 'label label) (cons 'payload payload)
          (cons 'entry entry) (cons 'exit exit)
          (cons 'show show) (cons 'hide hide)
          (cons 'provider provider)
          (cons 'exit-on-unknown exit-on-unknown)))
  (set! fsm-state-order (cons id fsm-state-order)))

;; Shared keyword-parsing loop for both fsm-state! (registers into the
;; permanent graph) and provided-state (below — builds an unregistered,
;; visit-scoped state-spec). Returns nine values: label payload entry exit
;; show hide provider exit-on-unknown trailing-args (the edge specs after
;; the keyword/value pairs).
(define known-state-keywords '(label payload entry exit show hide provider exit-on-unknown))

(define (parse-state-args who rest)
  (let loop ((args rest) (label #f) (payload #f)
             (entry #f) (exit #f) (show #f) (hide #f) (provider #f)
             (exit-on-unknown #f))
    (cond
      ((and (pair? args) (symbol? (car args)))
       (unless (memq (car args) known-state-keywords)
         (error (string-append who ": unknown keyword") (car args)))
       (when (null? (cdr args))
         (error (string-append who ": missing value after keyword") (car args)))
       (case (car args)
         ((label)    (loop (cddr args) (cadr args) payload entry exit show hide provider exit-on-unknown))
         ((payload)  (loop (cddr args) label (cadr args) entry exit show hide provider exit-on-unknown))
         ((entry)    (loop (cddr args) label payload (cadr args) exit show hide provider exit-on-unknown))
         ((exit)     (loop (cddr args) label payload entry (cadr args) show hide provider exit-on-unknown))
         ((show)     (loop (cddr args) label payload entry exit (cadr args) hide provider exit-on-unknown))
         ((hide)     (loop (cddr args) label payload entry exit show (cadr args) provider exit-on-unknown))
         ((provider) (loop (cddr args) label payload entry exit show hide (cadr args) exit-on-unknown))
         ((exit-on-unknown) (loop (cddr args) label payload entry exit show hide provider (cadr args)))))
      (else
       (values label payload entry exit show hide provider exit-on-unknown args)))))

;; (fsm-state! id [keyword value]... edge...) → id
;;
;; Registers a state. Keywords: 'label, 'payload, 'entry, 'exit, 'show,
;; 'hide, 'provider, 'exit-on-unknown — each a behaviour slot (#f, a
;; procedure, or a `named` wrapper) except 'label (a string), 'payload
;; (opaque, renderer-owned) and 'exit-on-unknown (boolean — the step
;; engine's per-state unknown-key policy; #f/absent is the forgiving
;; default, swallowing an unrecognised key instead of halting). Trailing
;; positional args are edge specs built by `edge` — the INLINE declaration
;; surface; registered as this state's outgoing edges exactly as
;; `fsm-edge!` would (see the file header — the two surfaces converge on
;; the same register-edge!).
(define (fsm-state! id . rest)
  (call-with-values (lambda () (parse-state-args "fsm-state!" rest))
    (lambda (label payload entry exit show hide provider exit-on-unknown edges)
      (register-state! id label payload entry exit show hide provider exit-on-unknown)
      (for-each (lambda (e) (register-edge! id e)) edges)
      id)))

(define (fsm-state-ids) (reverse fsm-state-order))

(define (fsm-state-ref id) (hash-table-ref/default fsm-states id #f))

(define (state-field id key)
  (let ((s (fsm-state-ref id)))
    (and s (cdr (assoc key s)))))

(define (fsm-state-label id)    (state-field id 'label))
(define (fsm-state-payload id)  (state-field id 'payload))
(define (fsm-state-entry id)    (state-field id 'entry))
(define (fsm-state-exit id)     (state-field id 'exit))
(define (fsm-state-show id)     (state-field id 'show))
(define (fsm-state-hide id)     (state-field id 'hide))
(define (fsm-state-provider id) (state-field id 'provider))
(define (fsm-state-exit-on-unknown? id) (state-field id 'exit-on-unknown))

;; ─── Edges ───────────────────────────────────────────────────────
;;
;; from-id -> list of edge alists (trigger, target, gate, call), in
;; declaration order. A trigger is a key string, or the symbol 'up
;; (backspace) or 'auto (post-action).

(define fsm-edges (make-hash-table))

(define (key-trigger? trigger) (string? trigger))

(define (edge-trigger e) (cdr (assoc 'trigger e)))
(define (edge-target  e) (cdr (assoc 'target  e)))
(define (edge-gate    e) (cdr (assoc 'gate    e)))
(define (edge-call    e) (cdr (assoc 'call    e)))

;; (edge trigger target [keyword value]...) → edge-spec alist (pure data —
;; no source state; the source is implied by where the spec is used: an
;; inline child of `fsm-state!`, or the `from` argument to `fsm-edge!`).
;;
;;   trigger : a key string, or 'up, or 'auto
;;   target  : the destination state's id — need not exist yet
;;   'gate PROCEDURE — optional 0-arg predicate; the edge is only live
;;                     when it holds (checked at step time, not here)
;;   'call BOOLEAN   — marks a call edge (pushes a return frame at step
;;                     time); defaults to #f
(define (edge trigger target . opts)
  (unless (or (string? trigger) (eq? trigger 'up) (eq? trigger 'auto))
    (error "edge: trigger must be a key string, 'up, or 'auto" trigger))
  (let loop ((rest opts) (gate #f) (call #f))
    (cond
      ((null? rest)
       (list (cons 'trigger trigger) (cons 'target target)
             (cons 'gate gate) (cons 'call call)))
      ((or (null? (cdr rest)) (not (symbol? (car rest))))
       (error "edge: expected trailing keyword/value pairs" rest))
      ((eq? (car rest) 'gate) (loop (cddr rest) (cadr rest) call))
      ((eq? (car rest) 'call) (loop (cddr rest) gate (cadr rest)))
      (else (error "edge: unknown keyword" (car rest))))))

;; Construction-time validation, shared by both declaration surfaces
;; (fsm-edge!/fsm-state!'s inline edges — accumulating into the permanent
;; fsm-edges hashtable — AND provided-state's one-shot edge list below):
;;   - key-edges-xor-auto-edge — a state may not carry both a key-triggered
;;     edge and an 'auto edge (it cannot be simultaneously resting and
;;     transient)
;;   - at most one 'auto edge, at most one 'up edge
;;   - no two edges from the same state share a key trigger
;; Dangling targets are NOT checked here — the graph is open (file header).
(define (check-new-edge! from spec existing)
  (unless (valid-behavior? (edge-gate spec))
    (error "fsm-edge!: gate must be #f, a procedure, or (named …)" (edge-gate spec)))
  (let ((trigger (edge-trigger spec)))
    (cond
      ((and (key-trigger? trigger)
            (find (lambda (e) (eq? (edge-trigger e) 'auto)) existing))
       (error "fsm-edge!: state already has an auto edge; cannot add a key edge (key-edges-xor-auto-edge)" from))
      ((and (eq? trigger 'auto)
            (find (lambda (e) (key-trigger? (edge-trigger e))) existing))
       (error "fsm-edge!: state already has key edges; cannot add an auto edge (key-edges-xor-auto-edge)" from))
      ((and (eq? trigger 'auto)
            (find (lambda (e) (eq? (edge-trigger e) 'auto)) existing))
       (error "fsm-edge!: state already has an auto edge" from))
      ((and (eq? trigger 'up)
            (find (lambda (e) (eq? (edge-trigger e) 'up)) existing))
       (error "fsm-edge!: state already has an up edge" from))
      ((and (key-trigger? trigger)
            (find (lambda (e) (and (key-trigger? (edge-trigger e))
                                   (equal? (edge-trigger e) trigger)))
                  existing))
       (error "fsm-edge!: duplicate key trigger for state" from trigger))
      (else #t))))

(define (register-edge! from spec)
  (unless (readable-id? from)
    (error "fsm-edge!: from must be a symbol or string" from))
  (let ((existing (hash-table-ref/default fsm-edges from '())))
    (check-new-edge! from spec existing)
    (hash-table-set! fsm-edges from (append existing (list spec)))))

;; (fsm-edge! from trigger target [keyword value]...) → from
;; The standalone declaration surface — see the file header.
(define (fsm-edge! from trigger target . opts)
  (register-edge! from (apply edge trigger target opts))
  from)

(define (fsm-state-edges id) (hash-table-ref/default fsm-edges id '()))

(define (fsm-up-edge id)
  (find (lambda (e) (eq? (edge-trigger e) 'up)) (fsm-state-edges id)))

;; (fsm-ancestors id) → list of ancestor ids, walking 'up edges outward,
;; nearest first. Stops (rather than erroring) at a dangling up-edge
;; target — the graph is open and may still be under construction — and
;; guards against an authored cycle.
(define (fsm-ancestors id)
  (let loop ((current id) (acc '()) (visited (list id)))
    (let ((up (fsm-up-edge current)))
      (cond
        ((not up) (reverse acc))
        ((not (fsm-state-ref (edge-target up))) (reverse acc))
        ((member (edge-target up) visited) (reverse acc))
        (else
         (loop (edge-target up)
               (cons (edge-target up) acc)
               (cons (edge-target up) visited)))))))

;; (fsm-state-class id) → 'resting | 'transient | 'terminal — derived,
;; never declared (CONTEXT.md "State class"): an 'auto edge is transient;
;; failing that, any key edge is resting; none of either is terminal. An
;; 'up edge does not itself affect class — backspace is orthogonal to
;; whether a state awaits further input.
(define (fsm-state-class id)
  (let ((edges (fsm-state-edges id)))
    (cond
      ((find (lambda (e) (eq? (edge-trigger e) 'auto)) edges) 'transient)
      ((find (lambda (e) (key-trigger? (edge-trigger e))) edges) 'resting)
      (else 'terminal))))

;; ─── Provided (visit-scoped) states ────────────────────────────────
;;
;; (provided-state id [keyword value]... edge...) → state-spec alist
;;
;; A resting state's provider (step engine, below) returns extra edges and
;; SYNTHETIC STATES for the visit — jump-label targets, narrowing prefix
;; states (CONTEXT.md "Edge provider"). A provided state is built by this
;; constructor instead of fsm-state!: it is never registered into the
;; permanent graph, so it needs no duplicate-id check and nothing to
;; accumulate into later — it is fully specified in one call, valid only
;; for the visit that produced it. Same keyword surface as fsm-state!
;; (plus the shared parse-state-args helper), but the trailing edge specs
;; become this spec's fixed 'edges field directly rather than a
;; hashtable slot — unlike a permanent state, nothing ever adds to a
;; provided state's edges after this call returns, so the mutable-pairs
;; workaround fsm-state!/fsm-edge! need (file header) doesn't apply here.
(define (provided-state id . rest)
  (unless (readable-id? id)
    (error "provided-state: id must be a symbol or string" id))
  (call-with-values (lambda () (parse-state-args "provided-state" rest))
    (lambda (label payload entry exit show hide provider exit-on-unknown edges)
      (for-each
        (lambda (name slot)
          (unless (valid-behavior? slot)
            (error (string-append "provided-state: " name
                                  " must be #f, a procedure, or (named …)")
                   slot)))
        '("entry" "exit" "show" "hide" "provider")
        (list entry exit show hide provider))
      (let loop ((rest edges) (checked '()))
        (unless (null? rest)
          (check-new-edge! id (car rest) checked)
          (loop (cdr rest) (append checked (list (car rest))))))
      (list (cons 'id id) (cons 'label label) (cons 'payload payload)
            (cons 'entry entry) (cons 'exit exit)
            (cons 'show show) (cons 'hide hide)
            (cons 'provider provider)
            (cons 'exit-on-unknown exit-on-unknown)
            (cons 'edges edges)))))

;; ─── Entry table ─────────────────────────────────────────────────
;;
;; name -> alist: name, target (a state id), gate, refines, order. The
;; entry table maps activation names to states (CONTEXT.md "Entry table");
;; unlike edges, a target MUST already be a registered state (below).

(define fsm-entries (make-hash-table))
(define fsm-entry-order '())    ;; names, declaration order
(define fsm-entry-counter 0)

;; (fsm-entry! name state-id [keyword value]...) → name
;;
;;   'gate PROCEDURE — optional 0-arg detection predicate
;;   'refines OTHER-NAME — stamps this entry as a scope-refinement of an
;;                         already-registered entry (a bundle/suffix
;;                         variant outranking its base) — see
;;                         fsm-entry-more-specific?
(define (fsm-entry! name state-id . opts)
  (unless (readable-id? name)
    (error "fsm-entry!: name must be a symbol or string" name))
  (when (fsm-entry-ref name)
    (error "fsm-entry!: duplicate entry name" name))
  (unless (fsm-state-ref state-id)
    (error "fsm-entry!: unknown state" state-id))
  (let loop ((rest opts) (gate #f) (refines #f))
    (cond
      ((null? rest)
       (when refines
         (unless (fsm-entry-ref refines)
           (error "fsm-entry!: refines names an unknown entry" refines)))
       (unless (valid-behavior? gate)
         (error "fsm-entry!: gate must be #f, a procedure, or (named …)" gate))
       (hash-table-set! fsm-entries name
         (list (cons 'name name) (cons 'target state-id)
               (cons 'gate gate) (cons 'refines refines)
               (cons 'order fsm-entry-counter)))
       (set! fsm-entry-counter (+ fsm-entry-counter 1))
       (set! fsm-entry-order (append fsm-entry-order (list name)))
       name)
      ((or (null? (cdr rest)) (not (symbol? (car rest))))
       (error "fsm-entry!: expected trailing keyword/value pairs" rest))
      ((eq? (car rest) 'gate)    (loop (cddr rest) (cadr rest) refines))
      ((eq? (car rest) 'refines) (loop (cddr rest) gate (cadr rest)))
      (else (error "fsm-entry!: unknown keyword" (car rest))))))

(define (fsm-entry-ref name) (hash-table-ref/default fsm-entries name #f))

(define (fsm-entry-rows) (map fsm-entry-ref fsm-entry-order))

(define (entry-field name key)
  (let ((e (fsm-entry-ref name)))
    (and e (cdr (assoc key e)))))

;; (fsm-entry-more-specific? name-a name-b) → boolean
;;
;; The derived ranking a leader activation (step engine, later) would use
;; to pick among passing entries (CONTEXT.md "Entry table" / "Entry
;; point"): an explicit 'refines stamp wins outright; failing that, the
;; entry whose target state is nested inside the other's (reachable via
;; `fsm-ancestors`) wins; failing that, earlier declaration wins. This is
;; a pure structural comparison — it never calls a gate; deciding which
;; passing entries are live is the step engine's job.
(define (fsm-entry-more-specific? name-a name-b)
  (unless (fsm-entry-ref name-a) (error "fsm-entry-more-specific?: unknown entry" name-a))
  (unless (fsm-entry-ref name-b) (error "fsm-entry-more-specific?: unknown entry" name-b))
  (cond
    ((equal? (entry-field name-a 'refines) name-b) #t)
    ((equal? (entry-field name-b 'refines) name-a) #f)
    ((member (entry-field name-b 'target) (fsm-ancestors (entry-field name-a 'target))) #t)
    ((member (entry-field name-a 'target) (fsm-ancestors (entry-field name-b 'target))) #f)
    (else (< (entry-field name-a 'order) (entry-field name-b 'order)))))

;; ─── Whole-graph print / query view ──────────────────────────────

(define (edge->alist e)
  (list (cons 'trigger (edge-trigger e))
        (cons 'target  (edge-target e))
        (cons 'gate    (behavior-repr (edge-gate e)))
        (cons 'call    (edge-call e))))

(define (state->alist id)
  (list (cons 'id id)
        (cons 'label (fsm-state-label id))
        (cons 'payload (fsm-state-payload id))
        (cons 'entry (behavior-repr (fsm-state-entry id)))
        (cons 'exit (behavior-repr (fsm-state-exit id)))
        (cons 'show (behavior-repr (fsm-state-show id)))
        (cons 'hide (behavior-repr (fsm-state-hide id)))
        (cons 'provider (behavior-repr (fsm-state-provider id)))
        (cons 'exit-on-unknown (fsm-state-exit-on-unknown? id))
        (cons 'class (fsm-state-class id))
        (cons 'edges (map edge->alist (fsm-state-edges id)))))

(define (entry->alist name)
  (list (cons 'name name)
        (cons 'target (entry-field name 'target))
        (cons 'gate (behavior-repr (entry-field name 'gate)))
        (cons 'refines (entry-field name 'refines))
        (cons 'order (entry-field name 'order))))

;; (fsm-graph->alist) → the whole graph as printable data: every state
;; (structure + behaviour names; only closure bodies are opaque) and every
;; entry row. What a renderer or debugging tool would walk.
(define (fsm-graph->alist)
  (list (cons 'states  (map state->alist (fsm-state-ids)))
        (cons 'entries (map entry->alist fsm-entry-order))))

;; (fsm-print) — write the whole graph to the current output port.
(define (fsm-print)
  (write (fsm-graph->alist))
  (newline))

;; ─── Step engine ────────────────────────────────────────────────
;;
;; Runs the graph built above. Configuration is (current state, return
;; stack) — an RTN (docs/specs/fsm-graph.md "Runtime semantics"). A
;; VISIT spans from coming to rest in a resting state until the machine
;; rests elsewhere or halts (CONTEXT.md "Visit"); it is the unit gates,
;; providers, and show/hide belong to. Global mutable module state,
;; matching (modaliser state-machine)'s existing modal-* style — the
;; graph itself is already a global singleton (fsm-states/fsm-edges/
;; fsm-entries above), so a second, per-visit global for the runtime
;; configuration is consistent, not a new pattern.
;;
;; A STATE-DEF, as used throughout this section, is the normalized alist
;; resolve-state-def returns: id/label/payload/entry/exit/show/hide/
;; provider/exit-on-unknown/edges — the same shape provided-state builds,
;; so a resting state's own permanent record and a provider's synthetic
;; states are handled by identical code below. Permanent states don't
;; naturally carry 'edges (file header — they live in the fsm-edges
;; hashtable so they can grow incrementally); resolve-state-def folds
;; fsm-state-edges in to normalize.

(define %fsm-current #f)          ;; current state id, or #f (inactive)
(define %fsm-visit-owner #f)      ;; the resting state owning the active visit, or #f
(define %fsm-return-stack '())    ;; state ids, most-recently-pushed first
(define %fsm-visit-generation 0)  ;; bumped when a NEW visit begins (not on cyclic re-arm)
(define %fsm-visit-displayed? #f) ;; has `show` fired for the active visit?
(define %fsm-visit-live-edges '())        ;; the visit owner's gate-filtered + provider edges
(define %fsm-visit-exit-on-unknown? #f)   ;; the visit owner's unknown-key policy
(define %fsm-visit-provided (make-hash-table))  ;; id -> provided-state alist, this visit only

(define fsm-max-auto-chain 1000)  ;; step-limit guard — see the file's Notes

;; ─── Host-injected arity hook ──────────────────────────────────
;;
;; Whether `entry` receives the arriving key (a shared provided target's
;; entry action distinguishing which key led to it) and whether `exit`
;; receives the leaving reason both need 1-vs-0-arg dispatch — R7RS has no
;; portable procedure-arity introspection, so (like state-machine.sld's
;; on-leave-accepts-reason?) the real check is a host-injected predicate;
;; the portable default assumes nullary. One predicate serves both slots —
;; it is a pure arity check, indifferent to which slot it is guarding.
(define fsm-accepts-arg?-impl (lambda (proc) #f))
(define (fsm-accepts-arg? proc) (fsm-accepts-arg?-impl proc))
(define (set-fsm-accepts-arg! pred) (set! fsm-accepts-arg?-impl pred))

;; ─── Normalizing state lookup ───────────────────────────────────

(define (def-id def)              (cdr (assoc 'id def)))
(define (def-payload def)         (cdr (assoc 'payload def)))
(define (def-entry def)           (cdr (assoc 'entry def)))
(define (def-exit def)            (cdr (assoc 'exit def)))
(define (def-show def)            (cdr (assoc 'show def)))
(define (def-hide def)            (cdr (assoc 'hide def)))
(define (def-provider def)        (cdr (assoc 'provider def)))
(define (def-exit-on-unknown? def) (cdr (assoc 'exit-on-unknown def)))
(define (def-edges def)           (cdr (assoc 'edges def)))

;; (resolve-state-def id) → normalized state-def alist, or #f
;;
;; A provided (visit-scoped) state shadows a permanent one of the same
;; id — checked first, since it only exists while a provider that just
;; ran chose to mint it. Falls back to the permanent graph, folding its
;; edges (a separate hashtable — file header) into the same 'edges key a
;; provided-state alist already carries, so every caller below reads
;; through one shape regardless of origin.
(define (resolve-state-def id)
  (or (hash-table-ref/default %fsm-visit-provided id #f)
      (and (fsm-state-ref id)
           (list (cons 'id id)
                 (cons 'label (fsm-state-label id))
                 (cons 'payload (fsm-state-payload id))
                 (cons 'entry (fsm-state-entry id))
                 (cons 'exit (fsm-state-exit id))
                 (cons 'show (fsm-state-show id))
                 (cons 'hide (fsm-state-hide id))
                 (cons 'provider (fsm-state-provider id))
                 (cons 'exit-on-unknown (fsm-state-exit-on-unknown? id))
                 (cons 'edges (fsm-state-edges id))))))

;; (fsm-resolve-state id) → the PUBLIC name for resolve-state-def above —
;; a host layer's read-only window onto "whatever the step engine would
;; land on for ID right now", permanent or provided.
(define (fsm-resolve-state id) (resolve-state-def id))

;; (fsm-resolved-payload id) → ID's payload, permanent or provided (see
;; fsm-resolve-state) — #f if ID names neither. Unlike fsm-state-payload
;; (permanent graph only), this is what state-machine.sld's modal-
;; current-node/modal-root-node need: a provided RESTING state (a
;; narrowing prefix state, say) must present the same way a permanent
;; one does.
(define (fsm-resolved-payload id)
  (let ((def (fsm-resolve-state id))) (and def (def-payload def))))

;; (fsm-resolved-up-edge id) → ID's up edge (permanent or provided), or
;; #f. Unlike fsm-up-edge (permanent graph only), this is what
;; ancestors-within-tree (state-machine.sld) needs to climb OUT of a
;; provided RESTING state — its up edge lives only in %fsm-visit-
;; provided, never the permanent fsm-edges hashtable.
(define (fsm-resolved-up-edge id)
  (let ((def (fsm-resolve-state id)))
    (and def (find (lambda (e) (eq? (edge-trigger e) 'up)) (def-edges def)))))

;; (fsm-resolved-state-class id) → 'resting | 'transient | 'terminal, or #f
;; if ID names neither a permanent nor a provided state. Unlike
;; fsm-state-class (permanent graph only, via the fsm-edges hashtable), this
;; reads DEF's own 'edges field through fsm-resolve-state — a provided
;; state's edges (e.g. a jump-label narrowing prefix state's second-key
;; edges) live only there, never in fsm-edges, so fsm-state-class always
;; reads a provided RESTING state back as zero-edges 'terminal. That's what
;; state-machine.sld's fsm-key-target-class needs before a step even runs:
;; pre-classifying a key's target has to agree with what classify-and-
;; snapshot (the step engine's own live classification) will find, for any
;; origin.
(define (fsm-resolved-state-class id)
  (let ((def (fsm-resolve-state id)))
    (and def
         (let ((edges (def-edges def)))
           (cond
             ((find (lambda (e) (eq? (edge-trigger e) 'auto)) edges) 'transient)
             ((find (lambda (e) (key-trigger? (edge-trigger e))) edges) 'resting)
             (else 'terminal))))))

;; (resolve-target t) → concrete id, or #f
;; An edge's target is either a concrete id or a 0-arg dynamic resolver
;; (a fire-time procedure — the terminal façade's "whichever backend is
;; frontmost", ported from the old model's 'next). #f means declined —
;; the fail-safe halt-after-action direction (file Notes).
(define (resolve-target t) (if (procedure? t) (t) t))

;; (edge-live? e) → boolean — does e's gate (if any) currently pass?
(define (edge-live? e)
  (let ((g (edge-gate e)))
    (or (not g) ((fsm-behavior-proc g)))))

;; (provider-result-edges/-states result) — a provider returns an alist
;; with optional 'edges and 'states keys (both default '()); 'edges are
;; folded into the owning state's live set, 'states are minted as
;; visit-scoped provided-state specs (built by `provided-state`, above).
(define (provider-result-edges result)
  (let ((e (assoc 'edges result))) (if e (cdr e) '())))
(define (provider-result-states result)
  (let ((e (assoc 'states result))) (if e (cdr e) '())))

;; (classify-and-snapshot def) → (values class live-edges provided-states)
;;
;; The "come to rest" snapshot (CONTEXT.md "Edge gate" / "Edge provider"):
;; run once for any target a step lands on, BEFORE the engine knows its
;; class — an auto edge makes it transient outright (providers are a
;; resting state's per-visit edge source, so a transient target's
;; provider — it shouldn't have one — is never invoked, keeping "once
;; per come-to-rest" true even for a bare transient hop); otherwise the
;; provider (if any) runs exactly once, its edges are folded in with the
;; state's own, the combined set is gate-filtered, and the target is
;; resting if any key edge survives, terminal otherwise. Auto edges are
;; never gate-filtered — an auto edge is unconditional once its state is
;; entered; its only dynamic aspect is resolve-target on its target.
(define (classify-and-snapshot def)
  (let* ((static-edges (def-edges def))
         (auto (find (lambda (e) (eq? (edge-trigger e) 'auto)) static-edges)))
    (if auto
      (values 'transient (list auto) '())
      (let* ((provider (def-provider def))
             (result (if provider ((fsm-behavior-proc provider)) '()))
             (extra-edges (provider-result-edges result))
             (extra-states (provider-result-states result))
             (live (filter edge-live? (append static-edges extra-edges))))
        (if (find (lambda (e) (key-trigger? (edge-trigger e))) live)
          (values 'resting live extra-states)
          (values 'terminal live extra-states))))))

;; ─── Firing action slots ────────────────────────────────────────
;; entry/exit are unconditional at a visit's boundaries; show/hide are
;; presentation-paired (fsm-mark-displayed!, below). entry may receive
;; the arriving key, exit the leaving reason — both via the shared
;; host-injected arity predicate; #f means "call with no args".

(define (fire-slot! slot arg)
  (when slot
    (let ((proc (fsm-behavior-proc slot)))
      (if (fsm-accepts-arg? proc) (proc arg) (proc)))))

(define (fire-entry! def key) (fire-slot! (def-entry def) key))
(define (fire-exit! def reason) (fire-slot! (def-exit def) reason))
(define (fire-show! def) (when (def-show def) ((fsm-behavior-proc (def-show def)))))
(define (fire-hide! def) (when (def-hide def) ((fsm-behavior-proc (def-hide def)))))

;; ─── Visit bookkeeping ──────────────────────────────────────────

(define (push-return-frame!)
  (set! %fsm-return-stack (cons %fsm-visit-owner %fsm-return-stack)))

(define (install-provided-states! extra-states)
  (let ((t (make-hash-table)))
    (for-each (lambda (s) (hash-table-set! t (def-id s) s)) extra-states)
    (set! %fsm-visit-provided t)))

;; End whatever visit is currently active — hide (if it fired), then exit,
;; unwinding in the reverse order they were acquired. A no-op when nothing
;; is active, so callers never need to guard the very first activation.
(define (end-old-visit! reason)
  (when %fsm-visit-owner
    (let ((def (resolve-state-def %fsm-visit-owner)))
      (when %fsm-visit-displayed? (fire-hide! def))
      (fire-exit! def reason))))

;; Fully deactivate: HALT (CONTEXT.md "State class"). Idempotent — a
;; second call while already inactive changes nothing, mirroring
;; modal-exit's idempotency. Clears the return stack unconditionally —
;; a terminal fire or Escape is a full teardown regardless of call depth
;; (state-machine.sld's modal-exit does the same).
(define (full-deactivate!)
  (set! %fsm-current #f)
  (set! %fsm-visit-owner #f)
  (set! %fsm-return-stack '())
  (set! %fsm-visit-live-edges '())
  (set! %fsm-visit-exit-on-unknown? #f)
  (set! %fsm-visit-displayed? #f)
  (set! %fsm-visit-provided (make-hash-table)))

;; Begin a genuinely new visit at id (def already resolved, live/extra
;; already snapshotted by classify-and-snapshot). Bumps the generation —
;; the guard fsm-mark-displayed! uses to reject a stale host callback.
;; Installs DEF alongside EXTRA — not just EXTRA — so the new owner
;; itself stays resolvable via resolve-state-def for as long as it
;; remains the visit owner: a PERMANENT owner is already resolvable
;; without this (resolve-state-def falls back to the permanent graph
;; regardless), but a PROVIDED owner (a jump-label narrowing prefix
;; state, say) exists ONLY in this table, and install-provided-states!
;; below REPLACES it wholesale — without DEF riding along, the owner
;; would vanish from its own visit-scoped lookup the moment it began,
;; breaking any caller resolving it by id (ancestors-within-tree /
;; end-old-visit!'s own hide/exit lookup, both state-machine.sld and
;; this file).
(define (begin-new-visit! id def live extra)
  (set! %fsm-visit-generation (+ %fsm-visit-generation 1))
  (set! %fsm-visit-owner id)
  (set! %fsm-visit-live-edges live)
  (set! %fsm-visit-exit-on-unknown? (def-exit-on-unknown? def))
  (set! %fsm-visit-displayed? #f)
  (install-provided-states! (cons def extra)))

;; Cyclic re-arm: the machine returned to the SAME resting state via an
;; auto-edge chain. entry/show do NOT refire (CONTEXT.md "Visit") — only
;; the snapshot refreshes, so provided edges track live content and gates
;; re-evaluate. DEF rides along with EXTRA for the same self-resolution
;; reason begin-new-visit! above needs it.
(define (refresh-visit-snapshot! def live extra)
  (set! %fsm-visit-live-edges live)
  (install-provided-states! (cons def extra)))

;; (walk-root? owner-id) → boolean — does owner-id have a live key edge
;; into a transient state whose own auto edge cycles back to owner-id?
;; Derived, never declared (CONTEXT.md "Walk"); only ever asked of the
;; current visit owner, so its own edges are already snapshotted. A
;; dynamic (procedure-valued) auto-edge target is never resolved here —
;; that would speculatively invoke a resolver meant only for actual fire
;; time — so a cyclic leaf reached that way simply isn't detected as
;; making its owner a walk root.
(define (walk-root? owner-id)
  (and (find
         (lambda (e)
           (and (key-trigger? (edge-trigger e))
                (let ((tdef (resolve-state-def (edge-target e))))
                  (and tdef
                       (let ((auto (find (lambda (a) (eq? (edge-trigger a) 'auto))
                                          (def-edges tdef))))
                         (and auto (equal? (edge-target auto) owner-id)))))))
         %fsm-visit-live-edges)
       #t))

;; ─── The step: move-to! ─────────────────────────────────────────
;;
;; move-to! is the one place that lands on a state and reacts to its
;; class (docs/specs/fsm-graph.md "Runtime semantics"). It is a trampoline,
;; not unbounded recursion, so a mis-constructed auto-edge cycle raises
;; instead of looping forever — dynamic resolvers make static loop
;; detection impossible (file Notes), so this is a runtime guard, not a
;; construction-time validation.
(define (move-to! target-id arriving-key)
  (let loop ((id target-id) (key arriving-key) (n 0))
    (when (> n fsm-max-auto-chain)
      (error "fsm: auto-edge chain exceeded the step limit (possible construction loop)" id))
    (let ((def (resolve-state-def id)))
      (unless def
        (error "fsm: step target is not a registered or provided state" id))
      (call-with-values
        (lambda () (classify-and-snapshot def))
        (lambda (class live extra)
          (case class
            ((transient)
             (set! %fsm-current id)
             (fire-entry! def key)
             (let* ((auto (car live))
                    (target (resolve-target (edge-target auto))))
               (if (not target)
                 ;; dynamic-#f: the fail-safe halt AFTER the action already ran.
                 (begin (end-old-visit! 'exit) (full-deactivate!))
                 (begin
                   (when (edge-call auto) (push-return-frame!))
                   (loop target #f (+ n 1))))))
            ((terminal)
             ;; Halt BEFORE entry — capture releases so the action may hand
             ;; the keyboard elsewhere (CONTEXT.md "Terminal").
             (end-old-visit! 'exit)
             (full-deactivate!)
             (fire-entry! def key))
            ((resting)
             (if (equal? id %fsm-visit-owner)
               (begin (set! %fsm-current id) (refresh-visit-snapshot! def live extra))
               (begin
                 (end-old-visit! 'navigate)
                 (set! %fsm-current id)
                 (begin-new-visit! id def live extra)
                 (fire-entry! def key))))))))))

;; ─── Public entry points ────────────────────────────────────────

;; (fsm-activate! state-id) — direct activation (config's "direct
;; activation by state id"): resets to a clean slate, then lands on
;; state-id exactly as any other move would.
(define (fsm-activate! state-id)
  (full-deactivate!)
  (move-to! state-id #f))

;; (fsm-activate-via-entry-table!) → the winning entry name, or #f
;;
;; Leader activation (CONTEXT.md "Entry table"/"Entry point"): among
;; entries whose gate currently passes, the most specific wins
;; (fsm-entry-more-specific?, already derived above); ties fall to
;; declaration order via that same predicate. #f (no-op, engine stays
;; inactive) when nothing passes.
(define (entry-passing? name)
  (let ((gate (entry-field name 'gate)))
    (or (not gate) ((fsm-behavior-proc gate)))))

(define (most-specific-entry names)
  (let loop ((rest (cdr names)) (best (car names)))
    (if (null? rest)
      best
      (loop (cdr rest)
            (if (fsm-entry-more-specific? (car rest) best) (car rest) best)))))

(define (fsm-activate-via-entry-table!)
  (let ((passing (filter entry-passing? fsm-entry-order)))
    (if (null? passing)
      #f
      (let ((winner (most-specific-entry passing)))
        (fsm-activate! (entry-field winner 'target))
        winner))))

;; (fsm-step! key) — ordinary key dispatch. key is a string; a matching
;; live edge is followed (resolve-target first — a declined dynamic
;; target falls through to the unknown-key policy exactly like a missing
;; edge); otherwise the visit owner's exit-on-unknown flag decides
;; between a cancel-halt and the forgiving swallow-default.
(define (fsm-step! key)
  (unless (fsm-active?) (error "fsm-step!: engine is not active"))
  (let* ((e (find (lambda (edge)
                     (and (key-trigger? (edge-trigger edge))
                          (equal? (edge-trigger edge) key)))
                  %fsm-visit-live-edges))
         (target (and e (resolve-target (edge-target e)))))
    (cond
      (target
       (when (edge-call e) (push-return-frame!))
       (move-to! target key))
      (%fsm-visit-exit-on-unknown? (fsm-halt! 'cancel))
      (else (if #f #f)))))

;; (fsm-step-back!) — backspace, one rule (CONTEXT.md "Up-edge" / "Call
;; edge / Return stack"): the visit owner's up edge if live, else pop the
;; return stack, else — a Walk root halts (it always has a conceptual
;; "outside"), any other root no-ops (nothing to back into).
(define (fsm-step-back!)
  (unless (fsm-active?) (error "fsm-step-back!: engine is not active"))
  (let* ((up (find (lambda (e) (eq? (edge-trigger e) 'up)) %fsm-visit-live-edges))
         (target (and up (resolve-target (edge-target up)))))
    (cond
      (target
       (when (edge-call up) (push-return-frame!))
       (move-to! target #f))
      ((not (null? %fsm-return-stack))
       (let ((popped (car %fsm-return-stack)))
         (set! %fsm-return-stack (cdr %fsm-return-stack))
         (move-to! popped #f)))
      ((walk-root? %fsm-visit-owner) (fsm-halt! 'exit))
      (else (if #f #f)))))

;; (fsm-halt! [reason]) — global halt (Escape, leader-toggle-off, Return):
;; end whatever visit is active and fully deactivate. Idempotent.
(define (fsm-halt! . opt)
  (when (fsm-active?)
    (end-old-visit! (if (pair? opt) (car opt) 'exit))
    (full-deactivate!)))

;; ─── Host-injected display signal ───────────────────────────────
;;
;; The engine stays portable — it never talks to the overlay directly
;; (file Goal). show/hide are presentation-paired: a host decides WHEN
;; the overlay actually displays the visit owner (immediately, or after
;; its own delay) and signals back via this one call. generation guards
;; a stale delayed callback from firing show on a visit that has since
;; ended or been superseded — the host captures (fsm-visit-generation) at
;; schedule time and passes it back here.
(define (fsm-mark-displayed! generation)
  (cond
    ((not (fsm-active?)) #f)
    ((not (equal? generation %fsm-visit-generation)) #f)
    (%fsm-visit-displayed? #f)
    (else
     (set! %fsm-visit-displayed? #t)
     (fire-show! (resolve-state-def %fsm-visit-owner))
     #t)))

;; ─── Configuration queries ──────────────────────────────────────

(define (fsm-active?) (and %fsm-current #t))
(define (fsm-current-state) %fsm-current)
(define (fsm-return-stack) %fsm-return-stack)
(define (fsm-visit-generation) %fsm-visit-generation)
(define (fsm-visit-displayed?) %fsm-visit-displayed?)
(define (fsm-live-edges) %fsm-visit-live-edges)

)) ;; end begin / define-library
