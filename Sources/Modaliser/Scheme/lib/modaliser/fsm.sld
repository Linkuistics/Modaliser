;; (modaliser fsm) — The explicit FSM graph: data model, construction DSL,
;; the step engine that runs it, and the modal façade over it.
;;
;; Modal dispatch's core (ADR-0015, docs/specs/fsm-graph.md): states and
;; labelled edges as first-class, printable s-expression data. The file
;; has three parts: the GRAPH MODEL (construction, validation, the
;; print/query surface a renderer or tooling would use — graph-model-k8),
;; the STEP ENGINE (configuration, activation, `step!`, visits,
;; gates/providers, the return stack — step-engine-k9, "─── Step engine
;; ───" below), and the MODAL FAÇADE (the pure lower function, the node
;; predicates/accessors the overlay renders through, the modal-* layer
;; deriving presentation state from the engine, and the overlay/chooser
;; hooks — consolidated from (modaliser state-machine) at
;; cutover-contract-k13; that library survives as a re-export shim slated
;; for docs-sweep removal). The graph model never executes a state's
;; behaviour; the step engine does.
;;
;; The graph is a first-class VALUE (closed-graph-lowering-k7): a
;; <fsm-graph> record bundling the state/edge tables and the tree-root
;; set. It is built by the PURE lower — lower-configuration below — from
;; the Configuration value (ADR-0018) via the graph-directed constructors
;; (fsm-graph-state!/fsm-graph-edge!) and validated CLOSED over its
;; authored references (fsm-graph-check-closed: every non-procedure edge
;; target must name a state, as a load-time error). The open path
;; (fsm-state!/fsm-edge!/fsm-entry! accumulating into the installed graph
;; as config loaded) retired with the registration model
;; (cutover-contract-k13); the entry table retired with it — activation
;; resolves outside the graph ((modaliser activation)). The step engine
;; consumes only the installed graph (fsm-install-graph! /
;; fsm-installed-graph); it never reaches around it.
;;
;; Two ways to attach an edge to a state build the identical graph:
;;
;;   inline:     (fsm-graph-state! g 'a 'label "A" (edge "x" 'b))
;;   standalone: (fsm-graph-state! g 'a 'label "A")
;;               (fsm-graph-edge! g 'a "x" 'b)
;;
;; Because graph structure (a state's outgoing edges) can grow after the
;; state itself is created, it cannot live as an immutable field inside the
;; state's own alist — LispKit has no set-car!/set-cdr! to splice a new
;; edge into an existing list in place. Edges instead
;; live in their own mutable hashtable INSIDE the graph value, keyed by
;; state id; the state's alist holds only what's fixed at
;; creation (label, payload, the four action slots, the provider). A
;; pure build mutates only the fresh graph value it returns — nothing
;; observable outside it.

(define-library (modaliser fsm)
  (export
    ;; The graph value (closed-graph-lowering-k7): fresh-graph
    ;; construction, the graph-directed constructors, the closure
    ;; check the pure lowering runs, and the engine's install point.
    fsm-make-graph fsm-graph?
    fsm-graph-state! fsm-graph-edge!
    fsm-graph-check-closed
    fsm-install-graph! fsm-installed-graph
    ;; Construction values: the edge-spec constructor and the
    ;; visit-scoped synthetic state a provider mints.
    edge named provided-state
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
    ;; (resolve-state-def). The modal façade's payload/up-edge derivation
    ;; needs this — the plain queries above only ever see the permanent
    ;; graph, so a provided RESTING state (e.g. a jump-label narrowing
    ;; prefix state) is invisible to them mid-Visit.
    fsm-resolve-state fsm-resolved-payload fsm-resolved-up-edge
    fsm-resolved-state-class
    ;; Printable / queryable whole-graph view
    fsm-graph->alist fsm-print
    ;; Step engine — activation
    fsm-activate!
    ;; Step engine — dispatch
    fsm-step! fsm-step-back! fsm-halt!
    ;; Step engine — configuration queries
    fsm-active? fsm-current-state fsm-return-stack
    fsm-visit-generation fsm-visit-displayed? fsm-live-edges
    ;; Step engine — host-injected hooks (the engine stays portable; a host
    ;; installs these at boot)
    fsm-mark-displayed! set-fsm-accepts-arg!
    ;; ── The modal façade (consolidated from (modaliser state-machine),
    ;; cutover-contract-k13) ──
    ;; The pure lower function (ADR-0018): Configuration value → closed
    ;; FSM graph value.
    lower-configuration
    ;; Node predicates
    command? group? selector? range-command?
    splice? expand-splices dispatch-children
    ;; Node accessors
    node-key node-label node-action node-children node-range-keys
    node-on-enter node-on-leave node-provider node-entry node-exit
    node-exit-on-unknown?
    node-display-name node-next node-walk?
    ;; The two-layer node model (ADR-0011): extract / replace a node's
    ;; attached display value without touching dispatch structure, and
    ;; read one entry of it.
    node-display node-with-display node-display-ref
    run-on-enter run-on-leave
    find-child navigate-to-path
    ;; Path helpers
    any-on-path?
    ;; Modal state
    modal-active? modal-current-node modal-root-node modal-current-path
    modal-leader-keycode modal-overlay-generation modal-overlay-delay
    modal-root-segments set-modal-root-segments! modal-stack modal-stack-empty?
    ;; Modal lifecycle
    modal-activate! modal-exit modal-step-back modal-handle-key
    modal-show-overlay-now modal-show-overlay-delayed
    modal-list-cursor-move! modal-list-cursor-activate!
    set-overlay-delay!
    ;; Key handler hook (installed by event-dispatch after it defines modal-key-handler)
    set-modal-key-handler!
    ;; On-leave arity predicate hook (installed by the host at boot)
    set-on-leave-accepts-reason!
    ;; Overlay/chooser hooks
    overlay-open? show-overlay update-overlay hide-overlay open-chooser
    open-chooser-prompt
    set-overlay-open! set-show-overlay! set-update-overlay!
    set-hide-overlay! set-open-chooser! set-open-chooser-prompt!
    chooser-open? set-chooser-open! close-chooser set-close-chooser!
    ;; Breadcrumb
    resolve-app-segments compute-root-segments compute-tree-root-segments)
  (import (scheme base)
          (scheme write)
          (modaliser util)
          (modaliser app)
          (modaliser keyboard)
          (modaliser lifecycle)
          (modaliser list-cursor)
          (modaliser configuration)
          ;; The press stopwatch (measure-hot-scan-k2). Two spans, and they
          ;; answer two different questions: `run-on-enter` is where a
          ;; provider gathers and chips are painted (the herdr symptom), and
          ;; `show-overlay` is where the renderer payload is built and pushed
          ;; (the "slows down with a lot of windows" symptom). A report fires
          ;; after the delayed show as well as after the press, because on
          ;; the delayed path this work runs on a timer callback and is NOT
          ;; inside the leader handler's own epoch.
          (only (modaliser instrument) instrument-span instrument-report!))
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

;; ─── The graph value ─────────────────────────────────────────────
;;
;; One <fsm-graph> record bundles everything a graph holds: the state
;; table (id -> alist: id, label, payload, entry, exit, show, hide,
;; provider — deliberately no 'edges; see the file header note), the
;; edge table (from-id -> edge alists), and the tree-root set (the state
;; ids lower-configuration lowered a tree of the value under — the
;; boundaries the breadcrumb derivation stops at). The record's tables
;; are mutable so a build can grow the value it is constructing; a pure
;; build mutates only the fresh value it returns.

(define-record-type <fsm-graph>
  (%make-fsm-graph states state-order edges roots)
  fsm-graph?
  (states        %graph-states)
  (state-order   %graph-state-order   %set-graph-state-order!)
  (edges         %graph-edges)
  (roots         %graph-roots         %set-graph-roots!))

;; (fsm-make-graph) → a fresh, empty graph value.
(define (fsm-make-graph)
  (%make-fsm-graph (make-hash-table) '() (make-hash-table) '()))

;; The graph's tree-root set — recorded by lower-configuration, one id
;; per lowered tree, in lowering order.
(define (graph-add-root! g id)
  (%set-graph-roots! g (append (%graph-roots g) (list id))))

(define (graph-roots g) (%graph-roots g))

;; The INSTALLED graph — the one the step engine consumes, every
;; single-graph query below reads, and the open construction surface
;; accumulates into. Starts empty and open; the handoff
;; (modaliser:start!, a later increment) will install a lowered,
;; closed graph here instead.
(define %fsm-graph (fsm-make-graph))

(define (fsm-installed-graph) %fsm-graph)

;; (fsm-install-graph! g) → g — replace the installed graph wholesale.
;; Deactivates the step engine first (without firing any exit/hide
;; hooks — the runtime configuration cannot outlive the graph it points
;; into, and firing the OLD graph's hooks mid-swap is not a defined
;; visit end). One-shot enforcement is the Handoff's business, not
;; this primitive's.
(define (fsm-install-graph! g)
  (unless (fsm-graph? g)
    (error "fsm-install-graph!: not a graph value" g))
  (full-deactivate!)
  (set! %fsm-graph g)
  g)

;; ─── States ──────────────────────────────────────────────────────

(define (readable-id? id) (or (symbol? id) (string? id)))

(define (graph-state-ref g id)
  (hash-table-ref/default (%graph-states g) id #f))

(define (graph-state-ids g) (reverse (%graph-state-order g)))

(define (graph-register-state! g id label payload entry exit show hide provider exit-on-unknown)
  (unless (readable-id? id)
    (error "fsm-graph-state!: id must be a symbol or string" id))
  (when (graph-state-ref g id)
    (error "fsm-graph-state!: duplicate state id" id))
  (for-each
    (lambda (name slot)
      (unless (valid-behavior? slot)
        (error (string-append "fsm-graph-state!: " name
                              " must be #f, a procedure, or (named …)")
               slot)))
    '("entry" "exit" "show" "hide" "provider")
    (list entry exit show hide provider))
  (hash-table-set! (%graph-states g) id
    (list (cons 'id id) (cons 'label label) (cons 'payload payload)
          (cons 'entry entry) (cons 'exit exit)
          (cons 'show show) (cons 'hide hide)
          (cons 'provider provider)
          (cons 'exit-on-unknown exit-on-unknown)))
  (%set-graph-state-order! g (cons id (%graph-state-order g))))

;; Shared keyword-parsing loop for both fsm-graph-state! (registers into
;; a graph value) and provided-state (below — builds an unregistered,
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

;; (fsm-graph-state! g id [keyword value]... edge...) → id
;;
;; Registers a state into graph G. Keywords: 'label, 'payload, 'entry,
;; 'exit, 'show, 'hide, 'provider, 'exit-on-unknown — each a behaviour
;; slot (#f, a procedure, or a `named` wrapper) except 'label (a string),
;; 'payload (opaque, renderer-owned) and 'exit-on-unknown (boolean — the
;; step engine's per-state unknown-key policy; #f/absent is the forgiving
;; default, swallowing an unrecognised key instead of halting). Trailing
;; positional args are edge specs built by `edge` — the INLINE declaration
;; surface; registered as this state's outgoing edges exactly as
;; `fsm-graph-edge!` would (see the file header — the two surfaces
;; converge on the same graph-register-edge!).
(define (fsm-graph-state! g id . rest)
  (call-with-values (lambda () (parse-state-args "fsm-graph-state!" rest))
    (lambda (label payload entry exit show hide provider exit-on-unknown edges)
      (graph-register-state! g id label payload entry exit show hide provider exit-on-unknown)
      (for-each (lambda (e) (graph-register-edge! g id e)) edges)
      id)))

(define (fsm-state-ids) (graph-state-ids %fsm-graph))

(define (fsm-state-ref id) (graph-state-ref %fsm-graph id))

(define (graph-state-field g id key)
  (let ((s (graph-state-ref g id)))
    (and s (cdr (assoc key s)))))

(define (state-field id key) (graph-state-field %fsm-graph id key))

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
;; declaration order — held in the graph value's edge table. A trigger
;; is a key string, or the symbol 'up (backspace) or 'auto (post-action).

(define (key-trigger? trigger) (string? trigger))

(define (edge-trigger e) (cdr (assoc 'trigger e)))
(define (edge-target  e) (cdr (assoc 'target  e)))
(define (edge-gate    e) (cdr (assoc 'gate    e)))
(define (edge-call    e) (cdr (assoc 'call    e)))

;; (edge trigger target [keyword value]...) → edge-spec alist (pure data —
;; no source state; the source is implied by where the spec is used: an
;; inline child of `fsm-graph-state!`, or the `from` argument to
;; `fsm-graph-edge!`).
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
;; (fsm-graph-edge!/fsm-graph-state!'s inline edges — accumulating into a
;; graph value's edge table — AND provided-state's one-shot edge list
;; below):
;;   - key-edges-xor-auto-edge — a state may not carry both a key-triggered
;;     edge and an 'auto edge (it cannot be simultaneously resting and
;;     transient)
;;   - at most one 'auto edge, at most one 'up edge
;;   - no two edges from the same state share a key trigger
;; Dangling targets are NOT checked here — the closure check runs on the
;; whole graph after lowering (fsm-graph-check-closed).
(define (check-new-edge! from spec existing)
  (unless (valid-behavior? (edge-gate spec))
    (error "fsm-graph-edge!: gate must be #f, a procedure, or (named …)" (edge-gate spec)))
  (let ((trigger (edge-trigger spec)))
    (cond
      ((and (key-trigger? trigger)
            (find (lambda (e) (eq? (edge-trigger e) 'auto)) existing))
       (error "fsm-graph-edge!: state already has an auto edge; cannot add a key edge (key-edges-xor-auto-edge)" from))
      ((and (eq? trigger 'auto)
            (find (lambda (e) (key-trigger? (edge-trigger e))) existing))
       (error "fsm-graph-edge!: state already has key edges; cannot add an auto edge (key-edges-xor-auto-edge)" from))
      ((and (eq? trigger 'auto)
            (find (lambda (e) (eq? (edge-trigger e) 'auto)) existing))
       (error "fsm-graph-edge!: state already has an auto edge" from))
      ((and (eq? trigger 'up)
            (find (lambda (e) (eq? (edge-trigger e) 'up)) existing))
       (error "fsm-graph-edge!: state already has an up edge" from))
      ((and (key-trigger? trigger)
            (find (lambda (e) (and (key-trigger? (edge-trigger e))
                                   (equal? (edge-trigger e) trigger)))
                  existing))
       (error "fsm-graph-edge!: duplicate key trigger for state" from trigger))
      (else #t))))

(define (graph-state-edges g id)
  (hash-table-ref/default (%graph-edges g) id '()))

(define (graph-register-edge! g from spec)
  (unless (readable-id? from)
    (error "fsm-graph-edge!: from must be a symbol or string" from))
  (let ((existing (graph-state-edges g from)))
    (check-new-edge! from spec existing)
    (hash-table-set! (%graph-edges g) from (append existing (list spec)))))

;; (fsm-graph-edge! g from trigger target [keyword value]...) → from
;; The standalone declaration surface, graph-directed — see the file
;; header.
(define (fsm-graph-edge! g from trigger target . opts)
  (graph-register-edge! g from (apply edge trigger target opts))
  from)

(define (fsm-state-edges id) (graph-state-edges %fsm-graph id))

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
(define (graph-state-class g id)
  (let ((edges (graph-state-edges g id)))
    (cond
      ((find (lambda (e) (eq? (edge-trigger e) 'auto)) edges) 'transient)
      ((find (lambda (e) (key-trigger? (edge-trigger e))) edges) 'resting)
      (else 'terminal))))

(define (fsm-state-class id) (graph-state-class %fsm-graph id))

;; ─── Provided (visit-scoped) states ────────────────────────────────
;;
;; (provided-state id [keyword value]... edge...) → state-spec alist
;;
;; A resting state's provider (step engine, below) returns extra edges and
;; SYNTHETIC STATES for the visit — jump-label targets, narrowing prefix
;; states (CONTEXT.md "Edge provider"). A provided state is built by this
;; constructor instead of fsm-graph-state!: it is never registered into the
;; permanent graph, so it needs no duplicate-id check and nothing to
;; accumulate into later — it is fully specified in one call, valid only
;; for the visit that produced it. Same keyword surface as fsm-graph-state!
;; (plus the shared parse-state-args helper), but the trailing edge specs
;; become this spec's fixed 'edges field directly rather than a
;; hashtable slot — unlike a permanent state, nothing ever adds to a
;; provided state's edges after this call returns, so the mutable-pairs
;; workaround the graph's edge table needs (file header) doesn't apply
;; here.
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

;; ─── Whole-graph print / query view ──────────────────────────────

(define (edge->alist e)
  (list (cons 'trigger (edge-trigger e))
        (cons 'target  (edge-target e))
        (cons 'gate    (behavior-repr (edge-gate e)))
        (cons 'call    (edge-call e))))

(define (state->alist g id)
  (list (cons 'id id)
        (cons 'label (graph-state-field g id 'label))
        (cons 'payload (graph-state-field g id 'payload))
        (cons 'entry (behavior-repr (graph-state-field g id 'entry)))
        (cons 'exit (behavior-repr (graph-state-field g id 'exit)))
        (cons 'show (behavior-repr (graph-state-field g id 'show)))
        (cons 'hide (behavior-repr (graph-state-field g id 'hide)))
        (cons 'provider (behavior-repr (graph-state-field g id 'provider)))
        (cons 'exit-on-unknown (graph-state-field g id 'exit-on-unknown))
        (cons 'class (graph-state-class g id))
        (cons 'edges (map edge->alist (graph-state-edges g id)))))

;; (fsm-graph->alist [g]) → graph G (default: the installed graph) as
;; printable data: every state (structure + behaviour names; only
;; closure bodies are opaque) and the tree-root set. What a renderer or
;; debugging tool would walk — and how a test inspects a purely lowered
;; graph value without installing it.
(define (fsm-graph->alist . opt)
  (let ((g (if (pair? opt) (car opt) %fsm-graph)))
    (list (cons 'states (map (lambda (id) (state->alist g id)) (graph-state-ids g)))
          (cons 'roots  (graph-roots g)))))

;; (fsm-print [g]) — write the whole graph to the current output port.
(define (fsm-print . opt)
  (write (apply fsm-graph->alist opt))
  (newline))

;; ─── Closure check ───────────────────────────────────────────────
;;
;; (fsm-graph-check-closed g) → g, or a load-time error.
;;
;; The pure lowering's validation gate (ADR-0018 / docs/specs/
;; configuration-value.md "Lowering and validation"): every statically
;; declared edge target in G — key edges, 'up edges, 'auto cross/call
;; ids — must name a state in G. A procedure-valued target (a dynamic
;; 'next resolver, resolved at fire time) is deliberately outside static
;; closure, as are providers' visit-scoped synthetic states (a provider
;; is never invoked here — closure is checked on the graph's own
;; structure only). A violation raises a decodable error whose irritants
;; name the offending source state, trigger, and target:
;; (dangling-edge-target <from-id> <trigger> <target>).
(define (fsm-graph-check-closed g)
  (for-each
    (lambda (id)
      (for-each
        (lambda (e)
          (let ((target (edge-target e)))
            (unless (or (procedure? target)
                        (graph-state-ref g target))
              (error "fsm-graph-check-closed: edge target does not name a state in the graph"
                     'dangling-edge-target id (edge-trigger e) target))))
        (graph-state-edges g id)))
    (graph-state-ids g))
  g)

;; ─── Step engine ────────────────────────────────────────────────
;;
;; Runs the INSTALLED graph (%fsm-graph — every read below goes through
;; the single-graph query wrappers, which resolve against it).
;; Configuration is (current state, return stack) — an RTN
;; (docs/specs/fsm-graph.md "Runtime semantics"). A VISIT spans from
;; coming to rest in a resting state until the machine rests elsewhere
;; or halts (CONTEXT.md "Visit"); it is the unit gates, providers, and
;; show/hide belong to. The runtime configuration is global mutable
;; module state, matching the modal façade's existing modal-*
;; style — it is the engine's residual mutable state behind the handoff
;; (ADR-0018), deliberately NOT part of the graph value.
;;
;; A STATE-DEF, as used throughout this section, is the normalized alist
;; resolve-state-def returns: id/label/payload/entry/exit/show/hide/
;; provider/exit-on-unknown/edges — the same shape provided-state builds,
;; so a resting state's own permanent record and a provider's synthetic
;; states are handled by identical code below. Permanent states don't
;; naturally carry 'edges (file header — they live in the graph value's
;; edge table so they can grow incrementally); resolve-state-def folds
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
;; portable procedure-arity introspection, so (like the modal façade's
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
;; (permanent graph only), this is what the modal façade's modal-
;; current-node/modal-root-node need: a provided RESTING state (a
;; narrowing prefix state, say) must present the same way a permanent
;; one does.
(define (fsm-resolved-payload id)
  (let ((def (fsm-resolve-state id))) (and def (def-payload def))))

;; (fsm-resolved-up-edge id) → ID's up edge (permanent or provided), or
;; #f. Unlike fsm-up-edge (permanent graph only), this is what
;; ancestors-within-tree (the modal façade below) needs to climb OUT of a
;; provided RESTING state — its up edge lives only in %fsm-visit-
;; provided, never the permanent graph's edge table.
(define (fsm-resolved-up-edge id)
  (let ((def (fsm-resolve-state id)))
    (and def (find (lambda (e) (eq? (edge-trigger e) 'up)) (def-edges def)))))

;; (fsm-resolved-state-class id) → 'resting | 'transient | 'terminal, or #f
;; if ID names neither a permanent nor a provided state. Unlike
;; fsm-state-class (permanent graph only, via its edge table), this
;; reads DEF's own 'edges field through fsm-resolve-state — a provided
;; state's edges (e.g. a jump-label narrowing prefix state's second-key
;; edges) live only there, never in the graph, so fsm-state-class always
;; reads a provided RESTING state back as zero-edges 'terminal. That's what
;; the modal façade's fsm-key-target-class needs before a step even runs:
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
;;
;; A provider is called with ONE argument: the id of the state it is
;; lowered onto (CONTEXT.md "Edge provider"). A provider that mints a
;; provided RESTING state — a narrowing prefix state — cannot be written
;; without it: that state's id must read `<owner-id>/<key>` and its 'up
;; edge must target `<owner-id>`, or strip-id-prefix garbles the
;; breadcrumb and ancestors-within-tree stops the climb early. The value
;; is right here (resolve-state-def stamps 'id on every def, provided or
;; permanent), and %fsm-visit-owner is NOT a substitute — it is still the
;; PREVIOUS owner at this point (set below, after the snapshot). Unlike
;; entry/exit, the argument is unconditional rather than arity-dispatched:
;; fsm-accepts-arg?'s portable default is always-#f, so a provider that
;; genuinely needs its owner would silently receive nothing under any host
;; that never installed the predicate.
(define (classify-and-snapshot def)
  (let* ((static-edges (def-edges def))
         (auto (find (lambda (e) (eq? (edge-trigger e) 'auto)) static-edges)))
    (if auto
      (values 'transient (list auto) '())
      (let* ((provider (def-provider def))
             (result (if provider ((fsm-behavior-proc provider) (def-id def)) '()))
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
;; (the modal façade's modal-exit does the same).
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
;; end-old-visit!'s own hide/exit lookup, both the modal façade and
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

;; (fsm-activate! state-id [seeded-stack]) — direct activation (config's
;; "direct activation by state id"): resets to a clean slate, then lands
;; on state-id exactly as any other move would. The optional SEEDED-STACK
;; (a list of state ids, in pop order — the frame backspace pops first at
;; the head) becomes the return stack before the landing move: how
;; activation seeds one outward frame per outer context from the
;; detection chain (ADR-0013 / resolve-activation, docs/specs/
;; configuration-value.md "Activation"), so backspace at the landing root
;; pops outward exactly as any call-pushed frame would. Seeded ids are
;; not validated here — like any open-graph edge target, a dangling frame
;; surfaces at step time; frames from resolve-activation name trees of
;; the same value the graph was lowered from, so they always resolve.
(define (fsm-activate! state-id . opt)
  (full-deactivate!)
  (when (pair? opt)
    (unless (list? (car opt))
      (error "fsm-activate!: seeded stack must be a list of state ids" (car opt)))
    (set! %fsm-return-stack (car opt)))
  (move-to! state-id #f))

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

;; ═══ The modal façade ══════════════════════════════════════════════════
;;
;; Consolidated from (modaliser state-machine) at cutover-contract-k13:
;; the pure lower function, the node predicates/accessors (the overlay's
;; and chooser's read-only rendering contract over the ORIGINAL alist
;; tree), the modal-* presentation layer derived from the step engine's
;; configuration, and the overlay/chooser hook cells. The (modaliser
;; state-machine) re-export shim was removed at docs-sweep-k15 — import
;; (modaliser fsm) directly.


;; Modal navigation is not tree-walking: modal-handle-key /
;; modal-step-back / modal-activate! / modal-exit drive the step
;; engine (fsm-step! / fsm-step-back! / fsm-activate! / fsm-halt!) and derive
;; every observable modal-* value from its configuration afterward. The node
;; predicates/accessors and find-child/navigate-to-path/any-on-path? below
;; remain — they are the overlay's (and the chooser's) read-only rendering
;; contract over the ORIGINAL alist tree, unrelated to how dispatch itself
;; runs.

;; ─── Lowering (the pure lower function, ADR-0018) ───────────────────────
;;
;; Lowers operational trees into states + edges. The lowered graph IS what
;; dispatch runs on (fsm-step!/fsm-step-back!, driven from
;; modal-handle-key/modal-step-back below).
;;
;; ONE lowering, ONE caller (cutover-contract-k13): lower-node! is
;; graph-directed — it emits into whatever graph value it is handed — and
;; lower-configuration below is its sole caller, building a fresh, closed
;; graph from a whole Configuration value. The open path (register-tree!,
;; accumulating trees into the installed graph as config loaded) is
;; retired.
;;
;; State ids are region + key-path strings (graph-model-k8's readable-id
;; rule): a tree's root state is its scope string; each descendant appends
;; "/" + its own dispatch key (a literal key, or a range-command's display
;; key).

(define (fsm-child-id parent-id child) (string-append parent-id "/" (node-key child)))

;; Every distinct key-trigger string reachable from a flat dispatch
;; children list: a literal (key …) leaf's own key, plus every key a
;; range-command covers. One edge is built per distinct string (below),
;; the WINNER of find-child's literal-shadows-range / first-range-wins
;; precedence (ADR-0015) resolved once here at lowering, not live on
;; every keypress.
(define (add-keys-once keys acc)
  (let loop ((ks keys) (acc acc))
    (cond
      ((null? ks) acc)
      ((member (car ks) acc) (loop (cdr ks) acc))
      (else (loop (cdr ks) (cons (car ks) acc))))))

(define (dispatch-key-triggers flat)
  (let loop ((rest flat) (acc '()))
    (cond
      ((null? rest) (reverse acc))
      ((range-command? (car rest))
       (loop (cdr rest) (add-keys-once (node-range-keys (car rest)) acc)))
      (else
       (loop (cdr rest) (add-keys-once (list (node-key (car rest))) acc))))))

;; A leaf's 'next (ADR-0015) becomes its one 'auto edge: 'self is a cyclic
;; edge back to the nearest enclosing group (no push — a Walk's own
;; latch); any other symbol or dynamic resolver is a cross/call edge
;; (enter-mode!'s old semantics — cross edges always push a return frame,
;; whether the target was static or resolved at fire time — CONTEXT.md
;; "Call edge / Return stack"). Symbols are normalized to strings to match
;; this file's scope-string-keyed state ids; a dynamic resolver is passed
;; through as-is (it may itself return a bare mode-id symbol; resolve-next-
;; symbol handles that at fire time — see below).
(define (resolve-next-symbol-or-string v)
  (cond
    ((string? v) v)
    ((symbol? v) (symbol->string v))
    (else v)))

(define (fsm-auto-edge-for next parent-id)
  (cond
    ((eq? next 'self)  (edge 'auto parent-id))
    ((procedure? next) (edge 'auto (lambda () (resolve-next-symbol-or-string (next))) 'call #t))
    (else              (edge 'auto (resolve-next-symbol-or-string next) 'call #t))))

;; ─── Pending-teardown: pre-action overlay/keyboard release ordering ────
;;
;; A Terminal leaf (no 'next) must release modal capture — on-leave (if the
;; overlay was visible), the catch-all key handler, the overlay itself —
;; BEFORE its action runs, so the action may freely hand the keyboard
;; elsewhere (a dialog, an external prompt; CONTEXT.md "Terminal"). The FSM
;; engine fires a Terminal state's entry (the action) synchronously INSIDE
;; move-to!, after it has already deactivated the engine but before move-to!
;; (and so fsm-step!) returns control to modal-handle-key below — so the
;; façade cannot simply diff before/after state to decide when to release;
;; by the time it observes "now inactive", the action has already run.
;;
;; Instead: modal-handle-key ARMS this cell with the presentation state to
;; tear down, right before calling fsm-step!. A Terminal leaf's lowered
;; entry is WRAPPED (below) to fire the teardown itself, first, before the
;; user's action — reproducing the old modal-exit-before-action order
;; exactly. If nothing consumes it that way (unknown key + exit-on-unknown,
;; or a transient's dynamic-#f fail-safe halt — see fire-transient-leaf!),
;; modal-handle-key fires it itself right after fsm-step! returns.
(define %pending-teardown-armed? #f)
(define %pending-teardown-node #f)
(define %pending-teardown-overlay-open? #f)
(define %pending-teardown-reason 'exit)

(define (arm-pending-teardown! node overlay-open? reason)
  (set! %pending-teardown-armed? #t)
  (set! %pending-teardown-node node)
  (set! %pending-teardown-overlay-open? overlay-open?)
  (set! %pending-teardown-reason reason))

(define (disarm-pending-teardown!) (set! %pending-teardown-armed? #f))

(define (teardown-modal-presentation! node overlay-open? reason)
  (when (and node overlay-open?)
    (run-on-leave node reason))
  (set! modal-overlay-generation (+ modal-overlay-generation 1))
  (unregister-all-keys!)
  (hide-overlay))

(define (fire-pending-teardown-if-armed!)
  (when %pending-teardown-armed?
    (teardown-modal-presentation! %pending-teardown-node
                                  %pending-teardown-overlay-open?
                                  %pending-teardown-reason)
    (set! %pending-teardown-armed? #f)))

;; The matched key for a Terminal range-command's wrapped entry (below) —
;; captured by fire-terminal-leaf! right before fsm-step!, read by the
;; wrapper instead of relying on fire-entry!'s host-injected arity dispatch
;; (set-fsm-accepts-arg!), which a great many tests never install. Wrapping
;; ALWAYS as a 0-arg closure sidesteps that entirely: a 0-arg procedure's
;; arity always reads as "doesn't accept an arg", wired predicate or not.
(define %current-dispatch-key #f)

;; (wrap-terminal-command-entry action) / (wrap-terminal-range-entry action)
;; → a Terminal leaf's real 'entry slot: fire the pending teardown (a no-op
;; if modal-handle-key's own pending-teardown check already fired it — see
;; fire-terminal-leaf!) THEN run the leaf's actual action. Both wrappers are
;; 0-arg on purpose (see %current-dispatch-key above); the range-command
;; variant forwards the matched key from that cell instead of an argument.
(define (wrap-terminal-command-entry action)
  (lambda ()
    (fire-pending-teardown-if-armed!)
    (action)))

(define (wrap-terminal-range-entry action)
  (lambda ()
    (fire-pending-teardown-if-armed!)
    (action %current-dispatch-key)))

;; (lower-node! g id node parent-id inherited-exit-unknown?) — registers
;; NODE (and, for a group, everything reachable from it) as fsm state(s)
;; under ID, into graph value G (see the section comment — the one
;; lowering both authoring paths share). PARENT-ID is the enclosing
;; group's fsm id, or #f at a tree root (a
;; root gets no up edge — backspace at depth 0 is the return-stack /
;; walk-root rule, not a graph edge). INHERITED-EXIT-UNKNOWN? is already
;; OR'd down from every ancestor group, so it is stamped on this state
;; directly instead of walked live at dispatch time (fsm-graph.md
;; "Lowering and the façade").
;;
;; Every state's payload is the ORIGINAL node alist — its flat children
;; and its whole 'display entry ride along for free, satisfying
;; "renderer payloads ride the state's presentation payload" with no
;; per-key special-casing, AND giving modal-root-node/modal-
;; current-node (below) their carried-presentation-node values for free.
(define (lower-node! g id node parent-id inherited-exit-unknown?)
  (let ((exit-unknown? (or inherited-exit-unknown? (node-exit-on-unknown? node))))
    (cond
      ;; Selectors are always Terminal (CONTEXT.md "Dialog command" family):
      ;; opening the chooser IS this state's entry action — wrapped so
      ;; capture releases before the chooser opens, exactly as a plain
      ;; Terminal command's action does.
      ((selector? node)
       (fsm-graph-state! g id 'label (node-label node) 'payload node
         'exit-on-unknown exit-unknown?
         'entry (wrap-terminal-command-entry (lambda () (open-chooser node)))))
      ;; Command / range-command leaves: the body is entry; 'next (if any)
      ;; is the state's one auto edge, making it transient instead of
      ;; Terminal. Terminal leaves get the wrapped, capture-releases-first
      ;; entry (see above); transient leaves keep the raw action — it fires
      ;; with capture still held, and fire-entry!'s host-injected arity
      ;; dispatch decides 0- vs 1-arg (unaffected by this file, unchanged
      ;; since lower-and-shadow-k10).
      ((or (command? node) (range-command? node))
       (let ((next (node-next node)))
         (if next
           (fsm-graph-state! g id 'label (node-label node) 'payload node
             'exit-on-unknown exit-unknown? 'entry (node-action node)
             (fsm-auto-edge-for next parent-id))
           (fsm-graph-state! g id 'label (node-label node) 'payload node
             'exit-on-unknown exit-unknown?
             'entry (if (range-command? node)
                      (wrap-terminal-range-entry (node-action node))
                      (wrap-terminal-command-entry (node-action node)))))))
      ;; Groups become resting states: an implicit up edge to their
      ;; lowering parent, one key edge per distinct trigger (literal
      ;; shadows range, first range wins — computed once via find-child),
      ;; and recursion into every flat dispatch child (splices and block
      ;; digit ranges expand via dispatch-children). on-enter/on-leave are
      ;; presentation-gated (fired by the façade only when the overlay is
      ;; open — see fire-group-descent!), so they land on show/hide, not
      ;; entry/exit, which fire unconditionally. The slots carry the
      ;; node's OWN hooks only: block children's hook fns are not
      ;; composed in — run-on-enter/run-on-leave fire them structurally
      ;; from the payload's children.
      ((group? node)
       ;; The display's per-edge embed choice must resolve — embed/drill
       ;; references are load-time errors (docs/specs/configuration-value.md
       ;; "Lowering and validation"): each 'embed key names a key edge of
       ;; THIS node whose target is a group. A section is an intra-tree
       ;; drill target rendered in place (ADR-0011), so a leaf, a step-in
       ;; (cross-tree, no state of its own), or a missing key all reject.
       (let ((embed (node-display-ref node 'embed)))
         (when embed
           (for-each
             (lambda (k)
               (let ((target (find-child node k)))
                 (unless (and target (group? target))
                   (error "lower-node!: 'embed key does not name a group child"
                          id k))))
             embed)))
       (fsm-graph-state! g id 'label (node-label node) 'payload node
         'exit-on-unknown exit-unknown?
         'show (node-on-enter node) 'hide (node-on-leave node)
         'provider (node-provider node)
         'entry (node-entry node) 'exit (node-exit node))
       (when parent-id (fsm-graph-edge! g id 'up parent-id))
       ;; A step-in child (ADR-0013) lowers to a direct, gated key edge to
       ;; an ALREADY-registered tree's root — no state of its own, so it is
       ;; excluded from both the ordinary find-child-resolved key edges
       ;; below (which would otherwise build a dangling fsm-child-id state
       ;; nobody ever registers) and the recursive per-child lowering.
       (let* ((flat     (dispatch-children node))
              (step-ins (filter step-in? flat))
              (rest     (remove step-in? flat)))
         (for-each
           (lambda (c)
             (fsm-graph-edge! g id (node-key c) (node-step-in-target c)
               'gate (node-step-in-gate c)))
           step-ins)
         (for-each
           (lambda (k) (fsm-graph-edge! g id k (fsm-child-id id (find-child node k))))
           (dispatch-key-triggers rest))
         (for-each
           (lambda (c) (lower-node! g (fsm-child-id id c) c id exit-unknown?))
           rest))))))

;; (lower-configuration config) → a closed FSM graph value.
;;
;; The pure lower function (ADR-0018, docs/specs/configuration-value.md
;; "Lowering and validation"): CONFIG is a Configuration value built by
;; `configuration` (the pure merge); the result is a FRESH graph — the
;; installed graph, and every other engine observable, is untouched.
;; Each tree in the value's tree set (contributed AND walk-hoisted)
;; lowers through lower-node!, its root recorded in the graph's root
;; set (what the breadcrumb derivation below recognises as tree
;; boundaries), then fsm-graph-check-closed validates the graph closed
;; over its authored references — key-edge targets, 'next cross/call
;; ids, up-edges — as a load-time error naming the offending ids.
;; Providers' visit-scoped synthetic states and dynamic 'next resolvers
;; stay outside static closure (the two deliberate runtime carve-outs);
;; no provider is invoked here. The graph carries NO entry rows —
;; activation resolves outside the graph (resolve-activation,
;; (modaliser activation)). Installing the result is the Handoff's
;; business (fsm-install-graph!, via modaliser:start!).
(define (lower-configuration config)
  (unless (configuration? config)
    (error "lower-configuration: not a configuration value"
           'invalid-configuration config))
  (let ((g (fsm-make-graph)))
    (for-each
      (lambda (entry)
        (let* ((scope (car entry))
               (scope-str (if (symbol? scope) (symbol->string scope) scope)))
          (lower-node! g scope-str (cdr entry) #f #f)
          (graph-add-root! g scope-str)))
      (configuration-trees config))
    (fsm-graph-check-closed g)))

;; ─── Node Predicates ────────────────────────────────────────────

(define (command? node)
  (and (pair? node)
       (let ((kind (assoc 'kind node)))
         (and kind (eq? (cdr kind) 'command)))))

(define (group? node)
  (and (pair? node)
       (let ((kind (assoc 'kind node)))
         (and kind (eq? (cdr kind) 'group)))))

(define (selector? node)
  (and (pair? node)
       (let ((kind (assoc 'kind node)))
         (and kind (eq? (cdr kind) 'selector)))))

;; Range-command: one node bound to multiple keys, displayed as a single
;; overlay row. Action is a 1-arg function called with the matched key.
(define (range-command? node)
  (and (pair? node)
       (let ((kind (assoc 'kind node)))
         (and kind (eq? (cdr kind) 'range-command)))))

;; Step-in: a gated cross-tree key edge (CONTEXT.md "Edge gate" — "e.g.
;; the `.` step-in edge", ADR-0013). Built by dsl.sld's (step-in …), it
;; carries no children and lowers to a PLAIN key edge straight from its
;; enclosing group to an already-registered tree's root — never a state
;; of its own, unlike a command (contrast node-next's auto-edge cross
;; jump, which always creates an intermediate state and always calls/
;; pushes). See lower-node!'s group branch.
(define (step-in? node)
  (and (pair? node)
       (let ((kind (assoc 'kind node)))
         (and kind (eq? (cdr kind) 'step-in)))))

(define (node-step-in-target node) (cdr (assoc 'target node)))
(define (node-step-in-gate node)   (cdr (assoc 'gate node)))

;; A live-list / diagram block-spec carries 'type and no 'kind — the
;; shape contract shared with dsl.sld / (modaliser display-dsl). A block
;; is a DISPATCH ATOM (ADR-0011): it sits among a node's flat children,
;; contributing its hidden digit key-range ('block-children) to dispatch,
;; while the node's display value places its visual by reference.
(define (block-spec-item? x)
  (and (pair? x) (pair? (car x))
       (assoc 'type x)
       (not (assoc 'kind x))
       #t))

;; (dispatch-children node) → the node's flat DISPATCH view: splice
;; nodes expanded in place (since dsl-purification-k9 they survive
;; construction as data — THIS is where their expansion reaches
;; dispatch), and each block-spec replaced by its hidden
;; 'block-children rows. Anything else that is not a dispatch node
;; (no 'kind) is dropped. Used by find-child, node-walk? and the FSM
;; lowering, so dispatch sees spliced keys and block digit ranges as
;; direct children — and never sees the display layer (the former
;; category tunneling retired with the category node kind, ADR-0011).
(define (dispatch-view children)
  (let loop ((rest children) (acc '()))
    (cond
      ((null? rest) (reverse acc))
      ((splice? (car rest))
       (loop (cdr rest)
             (append (reverse (dispatch-view (node-children (car rest)))) acc)))
      ((block-spec-item? (car rest))
       (let ((e (assoc 'block-children (car rest))))
         (loop (cdr rest)
               (append (reverse (dispatch-view (if e (cdr e) '()))) acc))))
      ((not (and (pair? (car rest)) (assoc 'kind (car rest))))
       (loop (cdr rest) acc))
      (else
       (loop (cdr rest) (cons (car rest) acc))))))

(define (dispatch-children node)
  (dispatch-view (node-children node)))

;; Splice nodes ('kind 'splice) are TRANSPARENT for dispatch. Produced by
;; (walk …) / (splice …) (dsl.sld), they SURVIVE construction as data
;; (dsl-purification-k9) — a walk's splice carries its mode tree under
;; 'tree for the configuration merge to hoist — and are expanded
;; downstream: dispatch-children (dispatch / FSM lowering) and
;; expand-splices (presentation views) hoist their children in place, so
;; the lowered result is identical to writing those children inline.
(define (splice? node)
  (and (pair? node)
       (let ((kind (assoc 'kind node)))
         (and kind (eq? (cdr kind) 'splice)))))

;; (expand-splices children) → children with every splice node replaced
;; in place by its (recursively expanded) children. Non-splice items —
;; including block-specs — pass through untouched (contrast
;; dispatch-children, which swaps a block for its hidden key rows).
(define (expand-splices children)
  (let loop ((rest children) (acc '()))
    (cond
      ((null? rest) (reverse acc))
      ((splice? (car rest))
       (loop (cdr rest)
             (append (reverse (expand-splices (node-children (car rest)))) acc)))
      (else (loop (cdr rest) (cons (car rest) acc))))))

;; List of keys a range-command binds. Empty for non-range nodes.
(define (node-range-keys node)
  (let ((entry (assoc 'keys node)))
    (if entry (cdr entry) '())))

;; ─── Node Helpers ───────────────────────────────────────────────

(define (node-children node)
  (let ((entry (assoc 'children node)))
    (if entry (cdr entry) '())))

(define (node-key node)
  (let ((entry (assoc 'key node)))
    (if entry (cdr entry) "")))

(define (node-label node)
  (let ((entry (assoc 'label node)))
    (if entry (cdr entry) "")))

(define (node-action node)
  (let ((entry (assoc 'action node)))
    (if entry (cdr entry) #f)))

;; Optional lifecycle thunks attached to group nodes. Either may be #f.
;;
;;   on-enter fires the moment the modal navigates *into* this group (the
;;   activation landing on the root, or descending into a child group).
;;   on-leave fires when the modal navigates *out* of this group (step-back,
;;   exit, or descending past it via a child action).
;;
;; They run for their side effects only; return values are ignored.
;; Used by lib/iterm.scm to show pane-hint overlays while the user is in the
;; "Pane" group, and tear them down on exit.
(define (node-on-enter node)
  (let ((entry (assoc 'on-enter node)))
    (if entry (cdr entry) #f)))

(define (node-on-leave node)
  (let ((entry (assoc 'on-leave node)))
    (if entry (cdr entry) #f)))

;; (node-provider node) → procedure or #f
;; A group's optional FSM edge provider (CONTEXT.md "Edge provider"):
;; unlike on-enter/on-leave (presentation-gated, lowered onto show/hide),
;; a provider lowers straight onto the resulting state's 'provider slot —
;; it runs at come-to-rest regardless of whether the overlay ever
;; displays, since the live edge/state set it contributes is what
;; dispatch itself consults. Set via 'provider on (group …) /
;; screen / tree-root.
(define (node-provider node)
  (let ((entry (assoc 'provider node)))
    (if entry (cdr entry) #f)))

;; (node-entry node) / (node-exit node) → procedure or #f
;; A group's optional unconditional action-slot pair (CONTEXT.md "Action
;; slots"): unlike on-enter/on-leave (presentation-gated, lowered onto
;; show/hide), entry/exit lower straight onto the resulting state's
;; 'entry/'exit slots — they fire at Visit come-to-rest / end regardless
;; of whether the overlay ever displays. Set via 'entry/'exit on
;; (group …) / tree-root / screen / open. The escape hatch for a
;; NON-presentation side effect that must not wait out
;; modal-overlay-delay; anything the user sees belongs on the gated pair.
;; The shipped tree has no user — herdr's jump chips were the one, and
;; moved onto on-enter/on-leave at defer-chips-to-overlay-k33
;; (docs/reference/state-machine.md "Unconditional hooks").
(define (node-entry node)
  (let ((e (assoc 'entry node)))
    (if e (cdr e) #f)))

(define (node-exit node)
  (let ((e (assoc 'exit node)))
    (if e (cdr e) #f)))

;; The presentation hook fns of NODE's block children — dispatch atoms
;; carrying 'on-enter-fn / 'on-leave-fn (chip paint/clear), read from
;; the splice-expanded children. Block hooks fire STRUCTURALLY from
;; run-on-enter / run-on-leave, whatever surface authored the node
;; (display-dsl-surface-k23): the sugar composes nothing, so a bare
;; tree-root/group holding a block behaves identically to a screen.
;; They stay presentation-gated with the show/hide pair — never fired
;; from the unconditional entry/exit slots.
(define (node-block-hook-fns node tag)
  (filter-map (lambda (b)
                (let ((e (assoc tag b)))
                  (and e (procedure? (cdr e)) (cdr e))))
              (filter block-spec-item? (expand-splices (node-children node)))))

(define (run-on-enter node)
  (let ((thunk (node-on-enter node)))
    (when thunk (thunk)))
  (for-each (lambda (fn) (fn)) (node-block-hook-fns node 'on-enter-fn)))

;; Run a node's on-leave hook, then its block children's on-leave fns
;; (node-block-hook-fns above). The optional REASON (default 'navigate;
;; 'confirm / 'cancel / 'exit when leaving via modal-exit) is passed to hooks
;; that declare an argument — a hook may ask *why* the modal left it (e.g. to
;; commit vs. cancel an app-side interaction). Zero-arg hooks are unaffected,
;; and block hook fns are always nullary — no reason reaches them.
;;
;; Deciding 1-arg-vs-0-arg needs procedure-arity introspection, which R7RS
;; has no portable primitive for. So — exactly like the overlay/chooser hooks
;; below — the predicate is a host-injected cell: the portable default assumes
;; nullary (the legacy behaviour before reason-aware leave hooks landed), and
;; the host installs the real arity-backed predicate at boot via
;; set-on-leave-accepts-reason!. An uninstalled host still calls every 0-arg
;; hook correctly; only reason-aware hooks need the injected predicate. Read
;; through the on-leave-accepts-reason? procedure (dynamic dispatch) so the
;; mutation is always seen, never snapshotted (same reason overlay-open? is a
;; thunk).
(define on-leave-accepts-reason?-impl (lambda (thunk) #f))
(define (on-leave-accepts-reason? thunk) (on-leave-accepts-reason?-impl thunk))
(define (set-on-leave-accepts-reason! pred) (set! on-leave-accepts-reason?-impl pred))

(define (run-on-leave node . opt)
  (let ((thunk (node-on-leave node))
        (reason (if (pair? opt) (car opt) 'navigate)))
    (when thunk
      (if (on-leave-accepts-reason? thunk)
          (thunk reason)
          (thunk)))
    (for-each (lambda (fn) (fn)) (node-block-hook-fns node 'on-leave-fn))))

;; Does this group declare that unknown keys should exit the modal?
;; Opt-in (default forgiving). Inherited by descendants via path walk;
;; see any-on-path? below (used only by the overlay's rendering contract
;; now — dispatch's own unknown-key policy is stamped per-state at
;; lowering and enforced by the engine, see fire-terminal-leaf!/
;; modal-handle-key's no-live-edge branch).
(define (node-exit-on-unknown? node)
  (let ((entry (assoc 'exit-on-unknown node)))
    (and entry (cdr entry))))

;; (node-display-name node) → string or #f
;; Optional human label for a tree root, used as the breadcrumb scope
;; segment in place of an auto-resolved app name. Set via 'display-name
;; on tree-root / walk / screen, stored in the node's display value
;; (display is where every rendering concern lives — ADR-0011). Returns
;; #f for plain children (only roots use this).
(define (node-display-name node)
  (node-display-ref node 'display-name))

;; (node-next node) → symbol | 'self | procedure | #f
;; A command/range-command leaf's declared post-action transition — the
;; ONLY transition mechanism (ADR-0015): a registered collection's id,
;; the literal 'self (the leaf's own containing group — the cycle case,
;; resolved by the DSL's `walk` at construction time, never computed
;; here), or a 0-arg procedure resolved at fire time (a dynamic edge,
;; e.g. the terminal façade's "whichever backend is frontmost"). Set via
;; 'next on (key …). #f (the property absent) means the leaf is
;; Terminal — dispatch releases modal capture BEFORE running its action.
;; Presence, not resolved value, is what's static: a procedure-valued
;; 'next is never Terminal, even where it resolves to #f at fire time.
;; Drives both runtime behaviour (the FSM auto edge fsm-auto-edge-for
;; builds from it) and overlay rendering (the cell gets a ↻ marker).
(define (node-next node)
  (let ((entry (assoc 'next node)))
    (and entry (cdr entry))))

;; (node-walk? node) → boolean
;; True iff NODE has at least one direct command/range-command child
;; declared 'next 'self — i.e. firing a leaf here re-arms in place
;; rather than exiting. Derived, not declared: a Walk (CONTEXT.md) is a
;; collection whose members cycle, so this is exactly what makes one
;; recognisable structurally, with no group-level flag needed. Used by
;; modal-activate! (immediate- vs delayed-show) and modal-step-back's
;; walk-root exit rule (mirrored in the engine's own walk-root? — see
;; fsm.sld — for the actual step-back decision) and the overlay's
;; container marker.
(define (node-walk? node)
  (let loop ((children (dispatch-children node)))
    (cond
      ((null? children) #f)
      ((and (or (command? (car children)) (range-command? (car children)))
            (eq? (node-next (car children)) 'self))
       #t)
      (else (loop (cdr children))))))

;; (embed-edge? node char) → #t when NODE's display marks CHAR's edge
;; target as an embedded section of NODE's own display root (ADR-0011,
;; CONTEXT.md "Embed"/"Display root"). Firing such an edge moves the
;; Visit WITHIN the display root, so the overlay restyles rather than
;; swapping roots — and the show delay is NOT re-armed (the delay binds
;; to the root's first display; see fire-group-descent!).
(define (embed-edge? node char)
  (let ((em (and node (node-display-ref node 'embed))))
    (and em (member char em) #t)))

;; ─── The two-layer node model (ADR-0011) ────────────────────────
;;
;; Every authored node factors into DISPATCH STRUCTURE (kind, key,
;; children, action, 'next, gates, providers, the action-slot hooks —
;; what the FSM lowering consumes) and an attached DISPLAY VALUE — one
;; disjoint 'display entry holding the pure display-DSL value that says
;; how the node renders (CONTEXT.md "Display value"; shape and
;; resolution: (modaliser display-dsl)). with-display ((modaliser
;; display-dsl)) is the validating authoring attach — the sugar routes
;; through it too; these accessors present the
;; factoring: node-display EXTRACTS the display value whole,
;; node-with-display REPLACES it wholesale — and substituting a display
;; never changes the live key set (the invariant ADR-0011 binds:
;; find-child reads only dispatch entries, via dispatch-children).

;; (node-display node) → the node's attached display value, whole: the
;; cdr of its single 'display entry, or '() when the node carries none.
;; An empty display and an absent one render identically — every child
;; loose, in declaration order — so absence needs no distinct value.
(define (node-display node)
  (let ((e (assoc 'display node)))
    (if e (cdr e) '())))

;; (node-with-display node display) → a node with its display value
;; replaced wholesale by DISPLAY, in one step. Dispatch entries pass
;; through untouched — the children, actions, and every key edge are
;; the very same objects.
(define (node-with-display node display)
  (append (remove (lambda (e) (eq? (car e) 'display)) node)
          (list (cons 'display display))))

;; (node-display-ref node key) → value or #f
;; One entry of the node's display value ('cols, 'order, 'embed,
;; 'display-name, …) — the sparse-alist read every display consumer
;; shares; #f when absent (or when the node carries no display).
(define (node-display-ref node key)
  (let ((e (assoc key (node-display node))))
    (and e (cdr e))))

;; Find the child that handles KEY. Specific bindings (key …) always win
;; over a range-command that lists KEY among its keys — letting a literal
;; binding carve a slot out of an existing range. Range matches are taken
;; in declaration order if multiple ranges include KEY (first wins).
;;
;; Retained for the overlay's (and the chooser's) read-only rendering
;; contract — walking the ORIGINAL alist tree to resolve "current node at
;; path" for breadcrumbs/labels/panel-grid rendering. Dispatch itself no
;; longer calls this (see modal-handle-key below): the FSM graph, not this
;; tree-walk, decides where a keypress goes.
(define (find-child node key)
  (let loop ((children (dispatch-children node)) (range-hit #f))
    (cond
      ((null? children) range-hit)
      ((and (not (range-command? (car children)))
            (equal? (node-key (car children)) key))
       (car children))
      ((and (not range-hit)
            (range-command? (car children))
            (member key (node-range-keys (car children))))
       (loop (cdr children) (car children)))
      (else (loop (cdr children) range-hit)))))

;; ─── Key handler hook ──────────────────────────────────────────
;;
;; modal-key-handler is defined in (modaliser event-dispatch), which
;; depends on this library. Since library-internal bindings are
;; lexically scoped, modal-activate! cannot reference the cross-library
;; name directly. Instead, a mutable cell holds the handler;
;; (modaliser event-dispatch) installs it via (set-modal-key-handler! …)
;; once its own body has run.

(define modal-key-handler-cell (lambda (kc mods) #f))
(define (set-modal-key-handler! h) (set! modal-key-handler-cell h))

;; ─── Overlay/chooser hooks ────────────────────────────────────
;;
;; In the include-based loader, ui/overlay.scm and ui/chooser.scm
;; redefined the stub bindings below to install their real impls.
;; That pattern doesn't survive library encapsulation — a library's
;; define bindings are hermetic.
;; Instead we expose setters so the UI code installs its hooks by
;; mutation. Same runtime effect, library-clean shape.

;; %overlay-open?-flag is the private mutable cell.
;; overlay-open? is exported as a *procedure* (thunk) so that closures
;; compiled in importing scopes (e.g. ui/overlay.scm) always call through
;; and see the live value — LispKit snapshots the value of mutable imports
;; at compile time, but procedure calls are always dynamically dispatched.
;;
;; Rule of thumb for new mutable exports from this library: if a value
;; will be READ inside a closure that lives in a different library or
;; that's compiled by an `(import (modaliser fsm))` consumer,
;; you MUST use this thunk pattern. Bare-variable mutable exports
;; (e.g. modal-active?, modal-stack below) survive only because every
;; read happens at top level in include-spliced .scm files, which use
;; dynamic binding lookup. When in doubt, use the thunk pattern.
(define %overlay-open?-flag #f)
(define (overlay-open?) %overlay-open?-flag)
(define (set-overlay-open! v) (set! %overlay-open?-flag v))

(define show-overlay-impl   (lambda (node path) (if #f #f)))
(define update-overlay-impl (lambda (node path) (if #f #f)))
(define hide-overlay-impl   (lambda ()          (if #f #f)))
(define open-chooser-impl   (lambda (sel)       (if #f #f)))
;; chooser-prompt (herdr-rename-prompt-ownership-k9): a second, narrower
;; entry point into the same host-specific chooser panel — a text-input +
;; closure-continuation mode, not a selector tree-node. Same deferred-hook
;; shape as open-chooser, so a portable-tree library (herdr.sld) can call
;; it without importing ui/chooser.scm directly.
(define open-chooser-prompt-impl (lambda (prompt initial on-submit) (if #f #f)))

(define (show-overlay   node path) (show-overlay-impl node path))
(define (update-overlay node path) (update-overlay-impl node path))
(define (hide-overlay)             (hide-overlay-impl))
(define (open-chooser selector-node) (open-chooser-impl selector-node))
(define (open-chooser-prompt prompt initial-value on-submit)
  (open-chooser-prompt-impl prompt initial-value on-submit))

(define (set-show-overlay!   fn) (set! show-overlay-impl   fn))
(define (set-update-overlay! fn) (set! update-overlay-impl fn))
(define (set-hide-overlay!   fn) (set! hide-overlay-impl   fn))
(define (set-open-chooser!   fn) (set! open-chooser-impl   fn))
(define (set-open-chooser-prompt! fn) (set! open-chooser-prompt-impl fn))

;; %chooser-open?-flag is private; chooser-open? exported as a thunk
;; for the same LispKit-snapshotting reason as overlay-open? above.
(define %chooser-open?-flag #f)
(define (chooser-open?) %chooser-open?-flag)
(define (set-chooser-open! v) (set! %chooser-open?-flag v))

(define close-chooser-impl (lambda () (if #f #f)))
(define (close-chooser) (close-chooser-impl))
(define (set-close-chooser! fn) (set! close-chooser-impl fn))

;; ─── Modal State ────────────────────────────────────────────────
;;
;; Every value below is DERIVED from the FSM engine's configuration
;; (fsm-current-state / fsm-return-stack) by sync-modal-state-from-fsm!,
;; called after every fsm-step!/fsm-step-back!/fsm-activate!/fsm-halt! —
;; see "Modal Navigation" further down. They remain plain mutable
;; top-level bindings (not thunks) because existing callers — including
;; the whole regression suite — read them as bare variables.

(define modal-active? #f)
(define modal-current-node #f)
(define modal-root-node #f)
(define modal-current-path '())
(define modal-leader-keycode #f)
(define modal-overlay-generation 0) ;; generation counter for delayed overlay show
(define modal-overlay-delay 1.0)    ;; seconds before overlay appears (0 = immediate)

;; The leader keycode of the OUTERMOST modal-activate! —
;; modal-leader-keycode derives to this while the return stack is no
;; deeper than the activation's SEEDED baseline (below), and to #f once
;; a call edge pushes past it (every cross-edge-entered mode is
;; leaderless — CONTEXT.md "Call edge / Return stack"), so backing all
;; the way out restores it exactly as modal-apply-context! used to.
(define %modal-root-leader-kc #f)

;; The seeded return-stack depth of the current activation: 0 for a
;; plain landing; the outward-frame count for a chain-seeded
;; modal-activate! landing (resolve-activation, ADR-0013). The seeded
;; frames are part of the leader-entered landing — the leader must
;; still toggle the modal closed there, and anywhere outward of there —
;; so the leaderless rule starts one call PAST the baseline, not at the
;; first non-empty stack.
(define %modal-seeded-depth 0)

;; modal-root-segments is exported as a *procedure* (thunk) for the same reason
;; as overlay-open?: LispKit snapshots '() at compile time in importing scopes.
;; The stored value is recomputed by sync-modal-state-from-fsm! on every
;; ACTIVE sync (see below) — but deliberately LEFT UNTOUCHED on deactivation
;; (a selector's Terminal fire calls modal-exit before opening the chooser,
;; which reads modal-root-segments for its own breadcrumb — clearing it here
;; would lose the scope mid-handoff).
(define %modal-root-segments '())    ;; breadcrumb root: host? + scope segments
(define (modal-root-segments) %modal-root-segments)
(define (set-modal-root-segments! v) (set! %modal-root-segments v))

;; Stack of saved modal contexts — DERIVED from (fsm-return-stack) (a list of
;; state ids, most-recently-pushed first): every real consumer (this file,
;; the overlay, the whole regression suite) only inspects its length /
;; null?-ness, both of which fsm-return-stack already carries with the exact
;; push/pop timing (fsm-core's cross-edge = a call edge = a push; a Walk's
;; own cyclic auto edge never pushes — cyclicSelfEdgeNeverPushesStack).
(define modal-stack '())

;; Functional accessor. Reading `modal-stack` directly from .scm files
;; loaded outside any library captures a stale binding under LispKit;
;; procedures defined inside this library reliably see live mutations.
;; Overlay code uses this to decide if backspace has somewhere to pop to.
(define (modal-stack-empty?) (null? modal-stack))

;; (set-overlay-delay! seconds) — set the overlay delay.
;; 0 shows the overlay immediately; typical values are 0.3–1.0 seconds.
(define (set-overlay-delay! seconds)
  (set! modal-overlay-delay seconds))

;; ─── Deriving façade state from the FSM engine ─────────────────────────
;;
;; Every descendant state carries an up edge to its lowering parent
;; (lower-node! above); a tree's ROOT carries none of its own. The
;; boundary ancestors-within-tree stops the climb at is the nearest
;; ancestor that is itself a tree root — recorded in the graph's root
;; set by lower-configuration — regardless of what lies beyond it. A
;; cross edge (a CALL, tracked by fsm-return-stack) is unrelated to this —
;; it never contributes an up edge. And because a state's own id is built
;; by literally appending "/" + key onto its parent's id (fsm-child-id
;; above), the key at each hop is recoverable by stripping the parent id
;; as a string prefix off the child id — robust even when the ROOT id
;; itself contains "/" (a bundle-id/suffix scope).

(define (last-in-list lst) (if (null? (cdr lst)) (car lst) (last-in-list (cdr lst))))

;; (registered-tree-root? id) → boolean — true iff id is a tree root in
;; the INSTALLED graph's root set (recorded by lower-configuration — the
;; boundary ancestors-within-tree/fsm-tree-root stop at).
(define (registered-tree-root? id)
  (and (member id (graph-roots (fsm-installed-graph))) #t))

;; (ancestors-within-tree id) → ancestor ids from id (exclusive) up to and
;; INCLUDING the nearest registered-tree-root ancestor, nearest first.
;; Mirrors fsm-ancestors' cycle/dangling guards, but additionally stops
;; climbing the moment it reaches a tree root. Uses the RESOLVED
;; (permanent-or-provided) up-edge lookup, not fsm-up-edge's permanent-
;; graph-only one — a provided RESTING state (a jump-label narrowing
;; prefix state) carries its up edge only in the current Visit's
;; provided-state table, never the permanent graph, so id itself may be
;; provided-only even though its target (checked below) always resolves
;; to a real, permanent tree root in every shape this codebase builds.
(define (ancestors-within-tree id)
  (let loop ((current id) (acc '()) (visited (list id)))
    (if (registered-tree-root? current)
      (reverse acc)
      (let* ((up     (fsm-resolved-up-edge current))
             (target (and up (cdr (assoc 'target up)))))
        (cond
          ((not up) (reverse acc))
          ((not (fsm-resolve-state target)) (reverse acc))
          ((member target visited) (reverse acc))
          (else
           (loop target (cons target acc) (cons target visited))))))))

(define (fsm-tree-root id)
  (let ((chain (ancestors-within-tree id)))
    (if (null? chain) id (last-in-list chain))))

(define (strip-id-prefix child parent)
  (substring child (+ 1 (string-length parent)) (string-length child)))

(define (derive-current-path root-id current-id)
  (if (equal? current-id root-id)
    '()
    ;; ancestors-within-tree already ENDS at root-id (it stops the climb
    ;; there, inclusive), so the chain is exactly its reverse plus
    ;; current-id — no separate (cons root-id …), which would double it.
    (let ((chain (append (reverse (ancestors-within-tree current-id)) (list current-id))))
      (let loop ((rest chain) (acc '()))
        (if (null? (cdr rest))
          (reverse acc)
          (loop (cdr rest) (cons (strip-id-prefix (cadr rest) (car rest)) acc)))))))

;; The breadcrumb across every tree on the current call chain, oldest
;; (the outermost activation) first: fsm-return-stack (most-recent-push
;; first) reversed, plus the current state, each mapped to its OWN tree
;; root and that root's compute-tree-root-segments — reproducing the old
;; enter-mode!'s cumulative append (each push appended its tree's segments
;; onto whatever the caller already had) without needing to have stored
;; that history anywhere.
(define (derive-root-segments)
  (let* ((current (fsm-current-state))
         (stack   (fsm-return-stack))
         (roots   (map fsm-tree-root (append (reverse stack) (list current)))))
    (apply append (map (lambda (id) (compute-tree-root-segments (fsm-resolved-payload id))) roots))))

;; Re-derive every modal-* value from the engine's current configuration.
;; Called after every fsm-step!/fsm-step-back!/fsm-activate!/fsm-halt! in
;; modal-activate!/modal-exit/modal-handle-key/modal-step-back below. See the
;; comment on %modal-root-segments above for why root-segments is the one
;; value deliberately NOT touched on deactivation.
(define (sync-modal-state-from-fsm!)
  (set! modal-active? (fsm-active?))
  (if (not modal-active?)
    (begin
      (set! modal-current-node #f)
      (set! modal-root-node #f)
      (set! modal-current-path '())
      (set! modal-leader-keycode #f)
      (set! modal-stack '()))
    (let* ((current (fsm-current-state))
           (root-id (fsm-tree-root current)))
      (set! modal-current-node (fsm-resolved-payload current))
      (set! modal-root-node (fsm-resolved-payload root-id))
      (set! modal-current-path (derive-current-path root-id current))
      (set! modal-leader-keycode
            (if (<= (length (fsm-return-stack)) %modal-seeded-depth)
              %modal-root-leader-kc
              #f))
      (set! modal-stack (fsm-return-stack))
      (set-modal-root-segments! (derive-root-segments)))))

;; ─── Modal Navigation ──────────────────────────────────────────

;; Show overlay immediately, cancelling any pending delayed show.
;; on-enter for the current node fires here, so subscribers see the same
;; "user is now looking at this level" event the overlay represents.
(define (modal-show-overlay-now)
  (set! modal-overlay-generation (+ modal-overlay-generation 1))
  (instrument-span 'show-now/on-enter (lambda () (run-on-enter modal-current-node)))
  (instrument-span 'show-now/show-overlay
    (lambda () (show-overlay modal-root-node modal-current-path))))

;; Schedule overlay to appear after modal-overlay-delay seconds.
;; If a key is pressed before the delay, the show is cancelled — and so are
;; the on-enter hooks. Quick muscle-memory presses produce no UI at all
;; (no overlay, no hint chips, nothing).
(define (modal-show-overlay-delayed)
  (if (<= modal-overlay-delay 0)
    (begin
      (instrument-span 'show-imm/on-enter (lambda () (run-on-enter modal-current-node)))
      (instrument-span 'show-imm/show-overlay
        (lambda () (show-overlay modal-root-node modal-current-path))))
    (let ()
      (set! modal-overlay-generation (+ modal-overlay-generation 1))
      (let ((gen modal-overlay-generation))
        (after-delay modal-overlay-delay
          (lambda ()
            (when (and modal-active? (= gen modal-overlay-generation))
              (instrument-span 'show-delayed/on-enter
                (lambda () (run-on-enter modal-current-node)))
              (instrument-span 'show-delayed/show-overlay
                (lambda () (show-overlay modal-root-node modal-current-path)))
              ;; This body runs on a timer callback, outside the leader
              ;; handler's epoch — so it needs its own dump or its scans
              ;; are counted and never printed.
              (instrument-report! 'delayed-show))))))))

;; (modal-activate! root-id stack leader-kc) — enter modal mode on a
;; resolved LANDING: ROOT-ID and STACK are resolve-activation's root
;; state and seeded return stack (pop order), resolved against the
;; installed configuration value (the handoff's leader path —
;; modaliser:start!, ADR-0018/ADR-0013). The one activation entry:
;; state sync, catch-all key-handler registration, then
;; walk-root-immediate / else-delayed overlay show (a Walk root shows
;; immediately because the overlay is the mode indicator; on-enter in
;; the delayed path fires inside the overlay-show callback, so quick
;; muscle-memory presses produce no UI at all). The landing may sit
;; mid-chain with outward frames already on the return stack, so
;; backspace at the landing root steps outward (CONTEXT.md "Call edge /
;; Return stack"). No on-the-fly lowering: landing ids name trees of
;; the same value the installed graph was lowered from, so an
;; unresolvable id means there is nothing to activate — a silent no-op.
(define (modal-activate! root-id stack leader-kc)
  (when (fsm-resolve-state root-id)
    (set! %modal-root-leader-kc leader-kc)
    (set! %modal-seeded-depth (length stack))
    (fsm-activate! root-id stack)
    (sync-modal-state-from-fsm!)
    (register-all-keys! modal-key-handler-cell)
    (if (and modal-root-node (node-walk? modal-root-node))
      (modal-show-overlay-now)
      (modal-show-overlay-delayed))))

;; Exit modal mode. Deregisters catch-all and hides overlay.
;; Idempotent: a second call after the modal is already inactive is a no-op.
;;
;; on-leave only fires if the overlay was actually visible — paired with
;; on-enter, which only fires when the overlay shows. A modal that exits
;; before the overlay's display delay elapses produces zero hook fires.
;;
;; Optional REASON ('confirm / 'cancel / 'exit) is forwarded to the current
;; node's on-leave hook, so a hook can distinguish a confirming exit (Return)
;; from a cancelling one (Escape). Defaults to 'exit.
(define (modal-exit . opt)
  (let ((reason (if (pair? opt) (car opt) 'exit))
        (node-before modal-current-node)
        (overlay-open-before? (overlay-open?))
        (was-active? (fsm-active?)))
    (fsm-halt! reason)
    (when was-active?
      (teardown-modal-presentation! node-before overlay-open-before? reason))
    (sync-modal-state-from-fsm!)))
;; modal-root-segments is intentionally NOT reset here (see the comment on
;; %modal-root-segments above / sync-modal-state-from-fsm!'s inactive
;; branch) — a selector key calls (modal-exit) before (open-chooser ...),
;; and the chooser reads modal-root-segments to render its breadcrumb.
;; The next activation overwrites it, so staleness can't leak into a new
;; session.

;; (any-on-path? root path pred) → bool
;;
;; Walk from ROOT along PATH; return #t if PRED holds on any visited
;; group (including ROOT and the final current node). Retained for the
;; overlay's rendering contract (the "is this path a Walk" / ancestor-
;; inherited-flag query) — dispatch's own unknown-key policy is now
;; enforced by the engine (each state's exit-on-unknown was stamped,
;; inherited, at lowering).
(define (any-on-path? root path pred)
  (let loop ((node root) (remaining path))
    (cond
      ((pred node) #t)
      ((null? remaining) #f)
      (else
       (let ((child (find-child node (car remaining))))
         (if child
           (loop child (cdr remaining))
           #f))))))

;; ─── List selection cursor ─────────────────────────────────────
;;
;; An embedded live list (window-list / iterm-panes / iterm-tabs) carries a
;; movable selection cursor alongside its immediate digit selectors. The
;; cursor's state lives in (modaliser list-cursor); the renderer registers the
;; owning list each render pass (overlay.scm). These two helpers are the modal's
;; bridge to it: the key path (modal-handle-key for k/j, modal-key-handler for
;; ↑↓/⏎ by keycode) calls them, and they re-render through the overlay so the
;; highlight follows.

;; Move the active list cursor by DELTA and re-render the overlay so the
;; highlighted row updates. Returns #t when a cursor was active (the key is
;; consumed), #f when none is — the caller then handles the key normally.
(define (modal-list-cursor-move! delta)
  (and (list-cursor-active?)
       (begin
         (list-cursor-move! delta)
         (when (overlay-open?)
           (update-overlay modal-root-node modal-current-path))
         #t)))

;; Activate the highlighted list row: dispatch its label (a digit) through the
;; normal range-command path, so the digit action AND its cleanup are reused
;; verbatim — ⏎ on a selection behaves exactly like pressing that digit.
;; Returns #t when it activated (Return is consumed), #f when no
;; list / no selection (the caller falls back to confirm-exit).
(define (modal-list-cursor-activate!)
  (let ((label (and (list-cursor-active?)
                    (list-cursor-has-selection?)
                    (list-cursor-selected-label))))
    (and label (begin (modal-handle-key label) #t))))

;; ─── Key dispatch (fsm-core, dispatch-cutover-k11) ──────────────────────
;;
;; The FSM graph is what decides where a key goes; modal-handle-key's job is
;; to classify the upcoming transition from the GRAPH — not the tree — so it
;; knows which side-effect replay applies, run fsm-step!, then replay
;; exactly the overlay/hook side effects the old tree-walk used to. See the
;; file-level "Pending-teardown" comment above for why a Terminal leaf's
;; capture-release-before-action ordering can't be decided by diffing
;; before/after engine state.
;;
;; Classification is graph-derived (fsm-live-edges + fsm-resolved-state-
;; class), not find-child-derived: a key with no live edge is unknown (the
;; engine's own exit-on-unknown/swallow policy applies); otherwise its
;; target's class — 'terminal / 'transient / 'resting — picks the branch
;; below. A dynamic (procedure-valued) edge target can only ever appear on
;; an AUTO edge (fsm.sld), never a literal key edge, so the class is always
;; resolvable without invoking anything speculatively. fsm-resolved-state-
;; class (not fsm-state-class) is required here: the target may be a
;; PROVIDED resting state (a jump-label narrowing prefix state, say), whose
;; edges live only in this Visit's %fsm-visit-provided, never the permanent
;; graph — fsm-state-class would read it back as zero-edges 'terminal and
;; misroute to fire-terminal-leaf!, which arms a capture-release teardown
;; no Terminal-only entry-slot wrapper ever consumes, deregistering the
;; catch-all and hiding the overlay under a state that's actually still
;; resting and awaiting its next key.

(define (fsm-edge-for-key char)
  (find (lambda (e) (equal? (cdr (assoc 'trigger e)) char)) (fsm-live-edges)))

(define (fsm-key-target-class char)
  (let ((e (fsm-edge-for-key char)))
    (and e
         (let ((target (cdr (assoc 'target e))))
           (and (not (procedure? target)) (fsm-resolved-state-class target))))))

;; A Terminal leaf (command/range-command with no 'next, or a selector):
;; capture releases before the action (via the wrapped entry's pending-
;; teardown — see above); nothing further to replay once fsm-step! returns.
(define (fire-terminal-leaf! char)
  (let ((node-before modal-current-node)
        (overlay-open-before? (overlay-open?)))
    (arm-pending-teardown! node-before overlay-open-before? 'exit)
    (set! %current-dispatch-key char)
    (fsm-step! char)
    (fire-pending-teardown-if-armed!)
    (sync-modal-state-from-fsm!)))

;; A transient leaf (command/range-command WITH 'next): capture stays
;; through the action; afterward the auto edge has already been followed
;; by fsm-step! (cyclic re-arm, cross switch, or the dynamic-target fail-
;; safe halt) — replay the matching presentation side effect by comparing
;; where we ended up to where we started.
(define (fire-transient-leaf! char)
  (let* ((owner-before (fsm-current-state))
         (root-before (fsm-tree-root owner-before))
         (node-before modal-current-node)
         (overlay-open-before? (overlay-open?)))
    (fsm-step! char)
    (sync-modal-state-from-fsm!)
    (cond
      ((not modal-active?)
       (teardown-modal-presentation! node-before overlay-open-before? 'exit))
      ((equal? (fsm-current-state) owner-before)
       ;; Cyclic re-arm: entry/show never refire (CONTEXT.md "Visit"), but
       ;; the overlay still refreshes so provided content stays current.
       (when overlay-open-before?
         (update-overlay modal-root-node modal-current-path)))
      ((equal? (fsm-tree-root (fsm-current-state)) root-before)
       (when overlay-open-before? (run-on-leave node-before))
       (if (overlay-open?)
         (begin (run-on-enter modal-current-node)
                (update-overlay modal-root-node modal-current-path))
         (modal-show-overlay-delayed)))
      (else
       ;; Cross edge: always shows immediately, matching the old enter-
       ;; mode!'s "caller's overlay was up, so no flash of nothing".
       (when overlay-open-before? (run-on-leave node-before))
       (modal-show-overlay-now)))))

;; Descending into a group: hooks pair with overlay visibility — fire
;; transitions only when the user actually sees the change. Fast descent
;; before the overlay shows gets neither leave nor enter; the eventual
;; overlay-show callback fires on-enter for whatever the current node is
;; at that moment.
(define (fire-group-descent! char)
  (let ((node-before modal-current-node)
        (overlay-open-before? (overlay-open?)))
    (when overlay-open-before? (run-on-leave node-before))
    (fsm-step! char)
    (sync-modal-state-from-fsm!)
    (if (overlay-open?)
      (begin (run-on-enter modal-current-node)
             (update-overlay modal-root-node modal-current-path))
      ;; Show/hide and the delay bind to the DISPLAY ROOT (ADR-0011,
      ;; docs/specs/configuration-value.md "The two-layer node model"): a
      ;; descent along an embedded edge stays within the origin node's
      ;; root, so the delay armed for that root's first display keeps its
      ;; original deadline — no re-arm. The pending callback reads the
      ;; live modal state at fire time, so when it fires it shows the
      ;; root with the section already active. A non-embedded descent
      ;; swaps roots and re-arms as before.
      (unless (embed-edge? node-before char)
        (modal-show-overlay-delayed)))))

;; Handle a character key press while modal is active.
;; Side-effecting: directly calls actions, updates overlay, etc.
;;
;; Default keymap is forgiving: unknown keys are swallowed, never drop
;; the modal. Groups can opt back into dismissal by setting
;; 'exit-on-unknown #t — typing a non-binding key then exits the modal,
;; useful for cyclic focus-movement modes (a Walk, e.g. iTerm pane mode)
;; where the user's next typing should reach the underlying app without
;; an explicit Escape first. Both halves of that policy — swallow vs.
;; cancel-halt — are the engine's own (fsm-step!, driven by each state's
;; exit-on-unknown flag stamped at lowering); this function only replays
;; the presentation teardown when the engine reports it became inactive.
(define (modal-handle-key char)
  (let ((class (fsm-key-target-class char)))
    (cond
      ((not class)
       (cond
         ((and (or (string=? char "j") (string=? char "k"))
               (modal-list-cursor-move! (if (string=? char "j") 1 -1)))
          (if #f #f))
         (else
          (let ((node-before modal-current-node)
                (overlay-open-before? (overlay-open?)))
            (fsm-step! char)
            (sync-modal-state-from-fsm!)
            (unless modal-active?
              (teardown-modal-presentation! node-before overlay-open-before? 'cancel))))))
      ((eq? class 'terminal) (fire-terminal-leaf! char))
      ((eq? class 'transient) (fire-transient-leaf! char))
      (else (fire-group-descent! char)))))

;; Step back one level in the navigation path — the engine's one rule
;; (fsm-step-back!, docs/specs/fsm-graph.md "Runtime semantics"): follow
;; the current state's up edge if live, else pop the return stack, else —
;; a Walk root halts, any other root no-ops. This function only replays
;; the matching presentation side effect once fsm-step-back! has decided
;; which of those four happened (detected the same way fire-transient-leaf!
;; does: compare before/after state and return-stack depth).
;;
;;   * became inactive         → walk-root halt: full teardown, reason 'exit.
;;   * same current state      → true no-op (root, not a Walk, empty stack).
;;   * return stack shrank     → popped a caller context: on-leave, then
;;                                (unlike a plain move) show-overlay
;;                                unconditionally, mirroring the old
;;                                enter-mode!-pop's "no flash" guarantee.
;;   * otherwise               → an up-edge move within the same tree.
;; Escape remains the one-shot exit-from-any-depth, regardless of stack —
;; unrelated to this function (see modal-key-handler in event-dispatch).
(define (modal-step-back)
  (let* ((owner-before (fsm-current-state))
         (node-before modal-current-node)
         (overlay-open-before? (overlay-open?))
         (stack-depth-before (length (fsm-return-stack))))
    (fsm-step-back!)
    (cond
      ((not (fsm-active?))
       (teardown-modal-presentation! node-before overlay-open-before? 'exit)
       (sync-modal-state-from-fsm!))
      ((equal? (fsm-current-state) owner-before)
       (if #f #f))
      ((< (length (fsm-return-stack)) stack-depth-before)
       (sync-modal-state-from-fsm!)
       (when overlay-open-before? (run-on-leave node-before))
       (when (overlay-open?)
         (run-on-enter modal-current-node)
         (show-overlay modal-root-node modal-current-path)))
      (else
       (sync-modal-state-from-fsm!)
       (when overlay-open-before? (run-on-leave node-before))
       (when (overlay-open?) (run-on-enter modal-current-node))
       (update-overlay modal-root-node modal-current-path)))))

;; ROOT's own id for the provided-state fallback below: the 'scope a
;; registered tree root carries (tree-root's own 'scope field), or #f
;; for a node with none (a hand-built test fixture, say) — a #f id simply
;; disables the fallback rather than erroring on a bad string-append.
(define (node-tree-id node)
  (let ((entry (assoc 'scope node)))
    (and entry (cdr entry))))

;; Navigate from root following a list of key strings. Retained for the
;; overlay's rendering contract (resolving "current node at path" over the
;; ORIGINAL alist tree) — dispatch itself derives modal-current-path from
;; the engine's own state id (see derive-current-path above), never by
;; walking here.
;;
;; A step with no STATIC child falls back to a live PROVIDED (visit-scoped)
;; state at that id (narrowed-legend-k45): a jump-label narrowing prefix
;; state (docs/specs/herdr-jump-navigation.md "Legend") is never part of
;; the permanent alist tree find-child walks — it exists only for the
;; Visit that minted it — so without this fallback the overlay's body
;; resolves to #f the moment path descends into one, even though
;; fsm-resolved-payload (fsm.sld) already hands back its payload "so a
;; provided RESTING state ... must present the same way a permanent one
;; does" (that function's own doc comment). fsm-child-id's own
;; "parent-id/key" convention is what lets this reconstruct the id a
;; provider minted a state under and read ITS resolved payload; ID threads
;; through the recursion so a chain of steps (static or provided) keeps
;; reconstructing correctly at any depth, though today only one provided
;; level ever exists (a root screen's own narrowing prefix states).
(define (navigate-to-path root path)
  (navigate-to-path-from root path (node-tree-id root)))

(define (navigate-to-path-from root path id)
  (if (null? path)
    root
    (let ((child (find-child root (car path))))
      (if child
        (navigate-to-path-from child (cdr path)
                                (and id (string-append id "/" (car path))))
        (let ((provided (and id (fsm-resolved-payload (string-append id "/" (car path))))))
          (and provided
               (navigate-to-path-from provided (cdr path)
                                       (string-append id "/" (car path)))))))))

;; (resolve-app-segments scope-str) → list of strings
;;
;; Splits a registered scope key into breadcrumb segments by `/`.
;; The first segment is resolved to a display name via app-display-name;
;; if resolution fails, the bare bundle ID is used.  Subsequent
;; segments (variant suffixes like "nvim") are passed through verbatim.
;;
;;   "com.apple.Safari"            → ("Safari")
;;   "com.googlecode.iterm2/nvim"  → ("iTerm" "nvim")
;;   "com.example.unknown"         → ("com.example.unknown")
(define (resolve-app-segments scope-str)
  (let* ((parts (string-split scope-str "/"))
         (bundle-id (car parts))
         (variant   (cdr parts))
         (display   (or (app-display-name bundle-id) bundle-id)))
    (cons display variant)))

;; (compute-root-segments scope-str) → list of strings
;;
;; Builds the breadcrumb root from the scope segments.
;;   global tree              → ("Global")
;;   app-local tree           → (app-name [variant])
(define (compute-root-segments scope-str)
  (if (equal? scope-str "global")
    (list "Global")
    (resolve-app-segments scope-str)))

;; (compute-tree-root-segments tree) → list of strings
;;
;; Like compute-root-segments but uses the tree's 'display-name when set
;; (so registered modes show a human label instead of the raw mode-id).
;; Falls back to scope-string resolution otherwise. Called by modal-activate!,
;; and by derive-root-segments above for every tree on the current call
;; chain.
(define (compute-tree-root-segments tree)
  (let ((display (node-display-name tree)))
    (cond
      (display (list display))
      (else
       (compute-root-segments (or (alist-ref tree 'scope #f) ""))))))

)) ;; end begin / define-library
