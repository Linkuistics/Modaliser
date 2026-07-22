;; (modaliser state-machine) — Modal navigation, now a DERIVED FAÇADE over
;; (modaliser fsm)'s step engine (dispatch-cutover-k11, docs/specs/fsm-graph.md
;; "Lowering and the façade"). register-tree! lowers every tree into the FSM
;; graph (fsm-core, lower-and-shadow-k10); dispatch itself — modal-handle-key,
;; modal-step-back, modal-enter, modal-exit — now runs on fsm-step!/
;; fsm-step-back!/fsm-activate!/fsm-halt!. The exported names, and the
;; overlay's (node, path) contract (modal-root-node / modal-current-path /
;; modal-current-node), are unchanged: they are DERIVED from the engine's
;; configuration (current state id + return stack) after every step, rather
;; than mutated by hand-rolled tree-walking.
;;
;; Hosts the tree registry, modal-* state, and the overlay/chooser hook
;; setters (see Task 4 for why setters instead of define-redefinition).

(define-library (modaliser state-machine)
  (export
    ;; Tree registry
    register-tree! lookup-tree register-tree-entry!
    ;; Node predicates
    command? group? selector? range-command? category? flatten-categories
    splice? expand-splices
    ;; Node accessors
    node-key node-label node-action node-children node-range-keys
    node-on-enter node-on-leave node-provider node-entry node-exit
    node-exit-on-unknown?
    node-display-name node-next node-walk?
    node-renderer node-renderer-payload
    run-on-enter run-on-leave
    find-child navigate-to-path
    ;; Path helpers
    any-on-path?
    ;; Modal state
    modal-active? modal-current-node modal-root-node modal-current-path
    modal-leader-keycode modal-overlay-generation modal-overlay-delay
    modal-root-segments set-modal-root-segments! modal-stack modal-stack-empty?
    modal-current-context modal-apply-context!
    ;; Modal lifecycle
    modal-enter modal-exit modal-step-back modal-handle-key
    modal-show-overlay-now modal-show-overlay-delayed
    modal-list-cursor-move! modal-list-cursor-activate!
    set-overlay-delay!
    ;; Key handler hook (installed by event-dispatch after it defines modal-key-handler)
    set-modal-key-handler!
    ;; On-leave arity predicate hook (installed by the host at boot)
    set-on-leave-accepts-reason!
    ;; Local-context-suffix hook (installed by event-dispatch — see the
    ;; FSM shadow-lowering section) + the entry-table resolver it feeds
    set-local-context-suffix-hook! resolve-entry-for-bundle
    ;; Nested-context entry points (ADR-0013): the outward up edge + the
    ;; directly-gated entry-table row a genuinely nested scope needs
    ;; instead of the suffix-hook/'refines heuristic register-tree-entry!
    ;; derives automatically.
    register-tree-up-edge! register-tree-entry-gated!
    ;; Overlay/chooser hooks
    overlay-open? show-overlay update-overlay hide-overlay open-chooser
    open-chooser-prompt
    set-overlay-open! set-show-overlay! set-update-overlay!
    set-hide-overlay! set-open-chooser! set-open-chooser-prompt!
    chooser-open? set-chooser-open! close-chooser set-close-chooser!
    ;; Breadcrumb
    resolve-app-segments compute-root-segments compute-tree-root-segments)
  (import (scheme base)
          (modaliser util)
          (modaliser app)
          (modaliser keyboard)
          (modaliser lifecycle)
          (modaliser list-cursor)
          (modaliser fsm))
  (begin

;; Manages command tree registration, lookup, and modal navigation.
;; All trees are stored in a hash table keyed by scope string.
;;
;; Modal navigation ITSELF is no longer tree-walking: modal-handle-key /
;; modal-step-back / modal-enter / modal-exit drive (modaliser fsm)'s step
;; engine (fsm-step! / fsm-step-back! / fsm-activate! / fsm-halt!) and derive
;; every observable modal-* value from its configuration afterward. The node
;; predicates/accessors and find-child/navigate-to-path/any-on-path? below
;; remain — they are the overlay's (and the chooser's) read-only rendering
;; contract over the ORIGINAL alist tree, unrelated to how dispatch itself
;; now runs.

;; ─── Tree Registry ──────────────────────────────────────────────

;; SRFI 69's make-hash-table takes (equality hash) — opposite order
;; to LispKit's make-hashtable, which took (hash equality). Easy to miss.
(define tree-registry (make-hash-table string=? string-hash))

;; Register a command tree for a scope.
;; scope: symbol or string (e.g. 'global or "com.apple.Safari")
;; rest:  optional leading keyword/value pairs followed by child nodes.
;;
;; Recognized keywords (mirror the (group ...) DSL):
;;   'on-enter THUNK     — runs when the modal navigates into this tree
;;   'on-leave THUNK     — runs when the modal navigates out of this tree
;;   'exit-on-unknown BOOL — unrecognised keys dismiss the modal instead
;;                         of being swallowed. Inherited by descendants:
;;                         if any group on the current path has it, an
;;                         unknown key exits. Useful for cyclic focus-
;;                         movement modes (a Walk, e.g. iTerm pane navigation)
;;                         where typing a non-binding key should hand
;;                         control back to the underlying app instead of
;;                         forcing an explicit Escape.
;;   'display-name STR   — overrides the breadcrumb scope segment. For
;;                         non-bundle-ID scopes (mode IDs) the auto-resolution
;;                         in resolve-app-segments would otherwise surface
;;                         the raw scope string.
;;   'entry THUNK / 'exit THUNK — the unconditional action-slot pair
;;                         (CONTEXT.md "Action slots"), lowered straight
;;                         onto the root state's 'entry/'exit slots
;;                         (fire at Visit come-to-rest / end regardless of
;;                         overlay display), distinct from 'on-enter/
;;                         'on-leave which lower onto the presentation-
;;                         gated show/hide pair. See `group`'s docstring
;;                         (dsl.sld) for the full contract.
;;
;; Children are alist nodes produced by (key ...), (group ...), (selector ...).
;; Disambiguation: a child node's car is a pair; a keyword is a bare symbol.
;;
;; The root node carries 'scope (the raw key string) instead of a label;
;; the breadcrumb is computed at modal-enter time via compute-root-segments,
;; not from a baked-in root label.
(define (register-tree! scope . rest)
  (let ((scope-str (if (symbol? scope) (symbol->string scope) scope)))
    (let loop ((args rest)
               (on-enter #f) (on-leave #f)
               (display-name #f) (exit-unk #f)
               (provider #f)
               (entry #f) (exit #f)
               (extras '()))     ; reverse-accumulated opaque kw/val pairs
      (cond
        ((and (pair? args) (symbol? (car args)) (pair? (cdr args)))
         (case (car args)
           ((on-enter)        (loop (cddr args) (cadr args) on-leave display-name exit-unk provider entry exit extras))
           ((on-leave)        (loop (cddr args) on-enter (cadr args) display-name exit-unk provider entry exit extras))
           ((display-name)    (loop (cddr args) on-enter on-leave (cadr args) exit-unk provider entry exit extras))
           ((exit-on-unknown) (loop (cddr args) on-enter on-leave display-name (cadr args) provider entry exit extras))
           ((provider)        (loop (cddr args) on-enter on-leave display-name exit-unk (cadr args) entry exit extras))
           ((entry)           (loop (cddr args) on-enter on-leave display-name exit-unk provider (cadr args) exit extras))
           ((exit)            (loop (cddr args) on-enter on-leave display-name exit-unk provider entry (cadr args) extras))
           (else
             ;; Unknown keyword — pass through as opaque alist entry on the
             ;; registered group. Mirrors `group`'s extras pattern; used by
             ;; screen / open to carry 'renderer 'panel-grid (+ 'cols N) at
             ;; the root, so the top-level overlay renders as a panel grid.
             (loop (cddr args) on-enter on-leave display-name exit-unk provider entry exit
                   (cons (cons (car args) (cadr args)) extras)))))
        (else
          (let* ((acc (list (cons 'kind 'group)
                            (cons 'key "")
                            (cons 'scope scope-str)
                            (cons 'children (expand-splices args))))
                 (acc (if on-leave     (cons (cons 'on-leave on-leave)         acc) acc))
                 (acc (if on-enter     (cons (cons 'on-enter on-enter)         acc) acc))
                 (acc (if provider     (cons (cons 'provider provider)         acc) acc))
                 (acc (if entry        (cons (cons 'entry entry)               acc) acc))
                 (acc (if exit         (cons (cons 'exit exit)                 acc) acc))
                 (acc (if exit-unk     (cons (cons 'exit-on-unknown #t)        acc) acc))
                 (acc (if display-name (cons (cons 'display-name display-name) acc) acc))
                 (acc (append (reverse extras) acc))
                 ;; register-tree! is safe to call more than once for the SAME
                 ;; scope (rebuild-tree!, mux register!, config reload) — the
                 ;; tree itself is last-write-wins, but (modaliser fsm) has no
                 ;; delete/replace primitive, so re-lowering would raise on a
                 ;; duplicate state id. Only the FIRST registration of a scope
                 ;; is mirrored into the FSM graph; a later rebuild leaves the
                 ;; graph stale — harmless for the same reason it always was:
                 ;; rebuild-tree!/mux register! rebuild internal, non-entry-
                 ;; point trees (walk/muxes), never a re-entered root.
                 (fresh? (not (hash-table-ref/default tree-registry scope-str #f))))
            (hash-table-set! tree-registry scope-str acc)
            (when fresh? (lower-tree->fsm! scope-str acc))))))))

;; ─── FSM lowering (fsm-core, lower-and-shadow-k10 / dispatch-cutover-k11) ──
;;
;; Lowers the operational tree register-tree! just built into (modaliser fsm)
;; states + edges. Since dispatch-cutover-k11, this graph IS what dispatch
;; runs on (fsm-step!/fsm-step-back!, driven from modal-handle-key/
;; modal-step-back below) — lowering is no longer a passive shadow.
;;
;; State ids are region + key-path strings (graph-model-k8's readable-id
;; rule): a tree's root state is its scope string; each descendant appends
;; "/" + its own dispatch key (a literal key, or a range-command's display
;; key).

(define (fsm-child-id parent-id child) (string-append parent-id "/" (node-key child)))

;; Every distinct key-trigger string reachable from a category-flattened
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

;; (lower-node! id node parent-id inherited-exit-unknown?) — registers NODE
;; (and, for a group, everything reachable from it) as fsm state(s) under
;; ID. PARENT-ID is the enclosing group's fsm id, or #f at a tree root (a
;; root gets no up edge — backspace at depth 0 is the return-stack /
;; walk-root rule, not a graph edge). INHERITED-EXIT-UNKNOWN? is already
;; OR'd down from every ancestor group, so it is stamped on this state
;; directly instead of walked live at dispatch time (fsm-graph.md
;; "Lowering and the façade").
;;
;; Every state's payload is the ORIGINAL node alist — display-name, the
;; panel-grid renderer markers, 'cols/'loose/etc. all ride along for free,
;; satisfying "renderer payloads ride the state's presentation payload"
;; with no per-key special-casing, AND giving modal-root-node/modal-
;; current-node (below) their carried-presentation-node values for free.
(define (lower-node! id node parent-id inherited-exit-unknown?)
  (let ((exit-unknown? (or inherited-exit-unknown? (node-exit-on-unknown? node))))
    (cond
      ;; Selectors are always Terminal (CONTEXT.md "Dialog command" family):
      ;; opening the chooser IS this state's entry action — wrapped so
      ;; capture releases before the chooser opens, exactly as a plain
      ;; Terminal command's action does.
      ((selector? node)
       (fsm-state! id 'label (node-label node) 'payload node
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
           (fsm-state! id 'label (node-label node) 'payload node
             'exit-on-unknown exit-unknown? 'entry (node-action node)
             (fsm-auto-edge-for next parent-id))
           (fsm-state! id 'label (node-label node) 'payload node
             'exit-on-unknown exit-unknown?
             'entry (if (range-command? node)
                      (wrap-terminal-range-entry (node-action node))
                      (wrap-terminal-command-entry (node-action node)))))))
      ;; Groups become resting states: an implicit up edge to their
      ;; lowering parent, one key edge per distinct trigger (literal
      ;; shadows range, first range wins — computed once via find-child),
      ;; and recursion into every category-flattened child (panels stay
      ;; transparent — no state of their own). on-enter/on-leave are
      ;; presentation-gated (fired by the façade only when the overlay is
      ;; open — see fire-group-descent!), so they land on show/hide, not
      ;; entry/exit, which fire unconditionally.
      ((group? node)
       (fsm-state! id 'label (node-label node) 'payload node
         'exit-on-unknown exit-unknown?
         'show (node-on-enter node) 'hide (node-on-leave node)
         'provider (node-provider node)
         'entry (node-entry node) 'exit (node-exit node))
       (when parent-id (fsm-edge! id 'up parent-id))
       ;; A step-in child (ADR-0013) lowers to a direct, gated key edge to
       ;; an ALREADY-registered tree's root — no state of its own, so it is
       ;; excluded from both the ordinary find-child-resolved key edges
       ;; below (which would otherwise build a dangling fsm-child-id state
       ;; nobody ever registers) and the recursive per-child lowering.
       (let* ((flat     (flatten-categories (node-children node)))
              (step-ins (filter step-in? flat))
              (rest     (remove step-in? flat)))
         (for-each
           (lambda (c)
             (fsm-edge! id (node-key c) (node-step-in-target c)
               'gate (node-step-in-gate c)))
           step-ins)
         (for-each
           (lambda (k) (fsm-edge! id k (fsm-child-id id (find-child node k))))
           (dispatch-key-triggers rest))
         (for-each
           (lambda (c) (lower-node! (fsm-child-id id c) c id exit-unknown?))
           rest))))))

(define (lower-tree->fsm! scope-str tree) (lower-node! scope-str tree #f #f))

;; ─── Local-context-suffix gate (dispatch-cutover-k11) ───────────────────
;;
;; (modaliser event-dispatch) owns local-context-suffix (a config-facing
;; hook returning a suffix string like "/zellij" for the focused app, or
;; #f) — a HIGHER layer than this file, so it cannot be called directly
;; here (that would be circular: event-dispatch imports state-machine).
;; Mirroring the modal-key-handler-cell / on-leave-accepts-reason?-impl
;; pattern already in this file, event-dispatch installs a hook at its own
;; library-load time; the portable default never matches any suffix.
(define local-context-suffix-hook (lambda (bundle-id) #f))
(define (set-local-context-suffix-hook! fn) (set! local-context-suffix-hook fn))

;; (register-tree-entry! scope) — adds SCOPE's fsm entry-table row, so the
;; entry table enumerates exactly the leader-activatable scopes
;; (CONTEXT.md "Entry table" — "where can a leader land") instead of every
;; register-tree! call: (modaliser dsl)'s `screen` is the only caller — the
;; internal mode-id trees `walk`/rebuild-tree!/mux `register!` register
;; directly via `register-tree!` and stay call-edge-only targets, never
;; entry points. A bundle-id/suffix registration (SCOPE-STR containing
;; "/") 'refines its already-registered base, so fsm-entry-more-specific?
;; ranks it above the base by scope refinement (CONTEXT.md "Entry
;; table") — AND is gated on local-context-suffix-hook answering with
;; exactly this variant's own suffix, so resolve-entry-for-bundle (below)
;; picks the right one the same way resolve-app-tree's try-variant-then-
;; fall-back always did. Idempotent — a rebuilt/re-registered scope's entry
;; already exists, so a second call is a no-op, mirroring register-tree!'s
;; own safe-to-call-more-than-once contract.
(define (register-tree-entry! scope)
  (let ((scope-str (if (symbol? scope) (symbol->string scope) scope)))
    (unless (fsm-entry-ref scope-str)
      (let* ((parts (string-split scope-str "/"))
             (base  (car parts)))
        (if (and (pair? (cdr parts)) (fsm-entry-ref base))
          (let ((suffix (substring scope-str (string-length base) (string-length scope-str))))
            (fsm-entry! scope-str scope-str 'refines base
              'gate (lambda () (equal? (local-context-suffix-hook base) suffix))))
          (fsm-entry! scope-str scope-str))))))

;; (register-tree-up-edge! from-scope to-scope) — stamps FROM-SCOPE's root
;; with an explicit outward up edge to TO-SCOPE's root (ADR-0013's nested
;; entry point: the herdr entry node's edge to the iTerm node). An ordinary
;; up edge, ungated and never a call — backspace at FROM-SCOPE's root
;; follows it regardless of how FROM-SCOPE was entered (direct leader
;; activation via a gated entry-table row, or a step-in key edge), and
;; fsm-entry-more-specific?'s up-edge-containment check (fsm.sld) is what
;; then ranks FROM-SCOPE's entry above TO-SCOPE's — no 'refines stamp
;; needed. Idempotent — a state may carry at most one up edge (fsm.sld),
;; so a second call for the same FROM-SCOPE is a no-op, mirroring
;; register-tree-entry!'s own safe-to-call-more-than-once contract.
(define (register-tree-up-edge! from-scope to-scope)
  (let ((from-str (if (symbol? from-scope) (symbol->string from-scope) from-scope))
        (to-str   (if (symbol? to-scope)   (symbol->string to-scope)   to-scope)))
    (unless (fsm-up-edge from-str)
      (fsm-edge! from-str 'up to-str))))

;; (register-tree-entry-gated! scope gate) — registers SCOPE's entry-table
;; row directly gated on GATE (a 0-arg detection predicate), bypassing the
;; suffix-hook/'refines heuristic register-tree-entry! derives from a "/"
;; in the scope string. For a genuinely nested entry point (ADR-0013),
;; SCOPE's root already carries an explicit up edge into its container
;; (register-tree-up-edge!, above), so specificity against the container's
;; own entry is already correctly derived by structural nesting — this
;; entry needs only its own detection gate, not a 'refines stamp. Pair
;; with (screen scope 'auto-entry #f …), which suppresses the automatic
;; suffix-based row screen would otherwise add for a "/"-scoped tree.
;; Idempotent, mirroring register-tree-entry!.
(define (register-tree-entry-gated! scope gate)
  (let ((scope-str (if (symbol? scope) (symbol->string scope) scope)))
    (unless (fsm-entry-ref scope-str)
      (fsm-entry! scope-str scope-str 'gate gate))))

;; (resolve-entry-for-bundle bundle-id) → entry name (a registered scope
;; string) or #f — the most-specific PASSING entry among bundle-id's own
;; base entry and any of its suffix variants, mirroring resolve-app-tree's
;; try-variant-then-fall-back semantics but derived from the entry table:
;; scoped to bundle-id FIRST (so 'global, or any other app's entries, are
;; never candidates), then ranked by fsm-entry-more-specific? among
;; whichever of THIS bundle's own entries currently pass their gate.
;; Called by (modaliser event-dispatch)'s make-leader-handler for 'local
;; mode.
(define (entry-name-of row) (cdr (assoc 'name row)))
(define (entry-gate-of row) (cdr (assoc 'gate row)))

(define (entry-scope-matches-bundle? name bundle-id)
  (equal? (car (string-split name "/")) bundle-id))

(define (entry-gate-passing? row)
  (let ((g (entry-gate-of row)))
    (or (not g) ((fsm-behavior-proc g)))))

(define (resolve-entry-for-bundle bundle-id)
  (let* ((rows (filter (lambda (row) (entry-scope-matches-bundle? (entry-name-of row) bundle-id))
                       (fsm-entry-rows)))
         (passing (filter entry-gate-passing? rows)))
    (if (null? passing)
      #f
      (entry-name-of
        (let loop ((rest (cdr passing)) (best (car passing)))
          (if (null? rest)
            best
            (loop (cdr rest)
                  (if (fsm-entry-more-specific? (entry-name-of (car rest)) (entry-name-of best))
                    (car rest)
                    best))))))))

;; Look up a tree by scope. Returns #f if not found.
(define (lookup-tree scope)
  (let ((scope-str (if (symbol? scope) (symbol->string scope) scope)))
    (hash-table-ref/default tree-registry scope-str #f)))

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

;; Category nodes are TRANSPARENT for dispatch — they group group-children
;; under a label (a panel) but their children are spliced in-place by
;; find-child via flatten-categories. See dsl.sld's (panel …).
(define (category? node)
  (and (pair? node)
       (let ((kind (assoc 'kind node)))
         (and kind (eq? (cdr kind) 'category)))))

;; (flatten-categories children) → list of non-category nodes
;; Walks `children` and splices the children of any category node
;; into the result at the category's source position. Recursive — nested
;; categories flatten transparently. Used by find-child so dispatch sees
;; category-wrapped keys as if they were direct group children.
(define (flatten-categories children)
  (let loop ((rest children) (acc '()))
    (cond
      ((null? rest) (reverse acc))
      ((category? (car rest))
       (let ((inner (flatten-categories
                      (let ((e (assoc 'children (car rest))))
                        (if e (cdr e) '())))))
         (loop (cdr rest)
               (append (reverse inner) acc))))
      (else
       (loop (cdr rest) (cons (car rest) acc))))))

;; Splice nodes ('kind 'splice) are FULLY transparent. Unlike categories
;; (which survive into the tree and group children under a label for the
;; renderer), a splice's children are hoisted into the parent's child list
;; at construction time — so nothing downstream ever sees the splice; the
;; result is identical to writing those children inline. Produced by
;; (walk …) / (fragment …) (dsl.sld) and expanded by the container
;; constructors (register-tree! / group / overlay / category).
(define (splice? node)
  (and (pair? node)
       (let ((kind (assoc 'kind node)))
         (and kind (eq? (cdr kind) 'splice)))))

;; (expand-splices children) → children with every splice node replaced
;; in place by its (recursively expanded) children. Non-splice nodes —
;; including categories — pass through untouched.
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
;;   on-enter fires the moment the modal navigates *into* this group (initial
;;   modal-enter for the root, or descending into a child group).
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
;; register-tree! / screen.
(define (node-provider node)
  (let ((entry (assoc 'provider node)))
    (if entry (cdr entry) #f)))

;; (node-entry node) / (node-exit node) → procedure or #f
;; A group's optional unconditional action-slot pair (CONTEXT.md "Action
;; slots"): unlike on-enter/on-leave (presentation-gated, lowered onto
;; show/hide), entry/exit lower straight onto the resulting state's
;; 'entry/'exit slots — they fire at Visit come-to-rest / end regardless
;; of whether the overlay ever displays (how jump-chip paint/clear
;; escapes the overlay's show delay). Set via 'entry/'exit on
;; (group …) / register-tree! / screen / open.
(define (node-entry node)
  (let ((e (assoc 'entry node)))
    (if e (cdr e) #f)))

(define (node-exit node)
  (let ((e (assoc 'exit node)))
    (if e (cdr e) #f)))

(define (run-on-enter node)
  (let ((thunk (node-on-enter node)))
    (when thunk (thunk))))

;; Run a node's on-leave hook. The optional REASON (default 'navigate;
;; 'confirm / 'cancel / 'exit when leaving via modal-exit) is passed to hooks
;; that declare an argument — a hook may ask *why* the modal left it (e.g. to
;; commit vs. cancel an app-side interaction). Zero-arg hooks are unaffected.
;;
;; Note: this reaches a *raw* on-leave thunk — one set directly on a (group …)
;; or a register-tree! root. Hooks on the block-composed path (screen /
;; panel / open) go through (modaliser dsl) `compose-hooks`, which wraps
;; them in a nullary thunk (dsl.sld stays host-portable, so it can't do arity
;; introspection); those receive no reason. Reason-aware leave hooks therefore
;; belong on a (group …) — which is the natural home for an app-side sub-mode.
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
          (thunk)))))

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
;; on register-tree!. Returns #f for plain children (only roots use this).
(define (node-display-name node)
  (let ((entry (assoc 'display-name node)))
    (and entry (cdr entry))))

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
;; modal-enter (immediate- vs delayed-show) and modal-step-back's
;; walk-root exit rule (mirrored in the engine's own walk-root? — see
;; fsm.sld — for the actual step-back decision) and the overlay's
;; container marker.
(define (node-walk? node)
  (let loop ((children (flatten-categories (node-children node))))
    (cond
      ((null? children) #f)
      ((and (or (command? (car children)) (range-command? (car children)))
            (eq? (node-next (car children)) 'self))
       #t)
      (else (loop (cdr children))))))

;; (node-renderer node) → symbol or #f
;; The custom renderer type declared on a group via (group … 'renderer SYM …).
;; When set, the overlay dispatches to window.overlayRenderers[SYM] on both
;; initial render and push-updates, instead of using the built-in list
;; renderer. See render-overlay-custom / push-overlay-update in ui/overlay.scm.
(define (node-renderer node)
  (let ((entry (assoc 'renderer node)))
    (and entry (cdr entry))))

;; (node-renderer-payload node key) → value or #f
;; Generic accessor for any keyword passed to (group … 'k v …) and stored
;; via the group constructor's pass-through branch (e.g. 'panels for the
;; diagram renderer). Renderers read their own payload keys off the node;
;; the format is owned by each renderer.
(define (node-renderer-payload node key)
  (let ((entry (assoc key node)))
    (and entry (cdr entry))))

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
  (let loop ((children (flatten-categories (node-children node))) (range-hit #f))
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
;; lexically scoped, modal-enter cannot reference the cross-library
;; name directly. Instead, a mutable cell holds the handler;
;; (modaliser event-dispatch) installs it via (set-modal-key-handler! …)
;; once its own body has run.

(define modal-key-handler-cell (lambda (kc mods) #f))
(define (set-modal-key-handler! h) (set! modal-key-handler-cell h))

;; ─── Overlay/chooser hooks ────────────────────────────────────
;;
;; In the include-based loader, ui/overlay.scm and ui/chooser.scm
;; redefined the stub bindings below to install their real impls.
;; That pattern doesn't survive library encapsulation — once
;; state-machine becomes a library, its define bindings are hermetic.
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
;; that's compiled by an `(import (modaliser state-machine))` consumer,
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

;; The leader keycode of the OUTERMOST modal-enter — modal-leader-keycode
;; derives to this while the return stack is empty, and to #f while it
;; isn't (every cross-edge-entered mode is leaderless — CONTEXT.md "Call
;; edge / Return stack"), so backing all the way out restores it exactly
;; as modal-apply-context! used to.
(define %modal-root-leader-kc #f)

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

;; ─── Legacy context snapshot (kept for API compatibility; unused) ───────
;;
;; The old push-a-context / restore-a-context stack machinery enter-mode!
;; and modal-step-back used before dispatch-cutover-k11 — every observable
;; piece of it (root-node/current-node/current-path/leader-kc/root-segments)
;; is now DERIVED straight from fsm-current-state/fsm-return-stack (see
;; sync-modal-state-from-fsm! and fsm-tree-root/derive-current-path below),
;; so nothing in this file calls these anymore. No external caller was found
;; either (state-machine.sld was always their only caller), so they're kept
;; here only as harmless, still-exported no-ops rather than an outright
;; removal a hidden caller could still be relying on.
(define (modal-current-context)
  (list (cons 'root-node     modal-root-node)
        (cons 'current-node  modal-current-node)
        (cons 'current-path  modal-current-path)
        (cons 'leader-kc     modal-leader-keycode)
        (cons 'root-segments (modal-root-segments))))

(define (modal-apply-context! ctx)
  (set! modal-root-node     (cdr (assoc 'root-node     ctx)))
  (set! modal-current-node  (cdr (assoc 'current-node  ctx)))
  (set! modal-current-path  (cdr (assoc 'current-path  ctx)))
  (set! modal-leader-keycode (cdr (assoc 'leader-kc    ctx)))
  (set-modal-root-segments! (cdr (assoc 'root-segments ctx))))

;; (set-overlay-delay! seconds) — set the overlay delay.
;; 0 shows the overlay immediately; typical values are 0.3–1.0 seconds.
(define (set-overlay-delay! seconds)
  (set! modal-overlay-delay seconds))

;; ─── Deriving façade state from the FSM engine ─────────────────────────
;;
;; Every descendant state carries an up edge to its lowering parent
;; (lower-node! above). A registered tree's ROOT carries none of its
;; own EXCEPT when register-tree-up-edge! (below) has stamped one — the
;; nested-context entry point's outward edge into its container
;; (ADR-0013: the herdr entry node's up edge to the iTerm node). So
;; fsm-ancestors(id), walked to its end, no longer reliably lands on id's
;; own tree root: it would climb straight through a nested root's outward
;; edge into the CONTAINER's tree. registered-tree-root?/ancestors-within-
;; tree below stop the climb at the nearest ancestor that is itself a
;; registered tree (including id's own root) — that boundary is id's tree
;; root for breadcrumb purposes, regardless of what lies beyond it. A
;; cross edge (a CALL, tracked by fsm-return-stack) is unrelated to this —
;; it never contributes an up edge. And because a state's own id is built
;; by literally appending "/" + key onto its parent's id (fsm-child-id
;; above), the key at each hop is recoverable by stripping the parent id
;; as a string prefix off the child id — robust even when the ROOT id
;; itself contains "/" (a bundle-id/suffix scope).

(define (last-in-list lst) (if (null? (cdr lst)) (car lst) (last-in-list (cdr lst))))

;; (registered-tree-root? id) → boolean — true iff id is itself a
;; register-tree! scope (the boundary ancestors-within-tree/fsm-tree-root
;; stop at, rather than following a nested entry point's outward up edge
;; into its container's own tree).
(define (registered-tree-root? id)
  (and (hash-table-ref/default tree-registry id #f) #t))

;; (ancestors-within-tree id) → ancestor ids from id (exclusive) up to and
;; INCLUDING the nearest registered-tree-root ancestor, nearest first.
;; Mirrors fsm-ancestors' cycle/dangling guards, but additionally stops
;; climbing the moment it reaches a registered tree root — id's own root
;; when id has no nested-context up edge, or the nested entry point's
;; root itself (never its container) when it does. Uses the RESOLVED
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
;; (the outermost modal-enter) first: fsm-return-stack (most-recent-push
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
;; modal-enter/modal-exit/modal-handle-key/modal-step-back below. See the
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
      (set! modal-leader-keycode (if (null? (fsm-return-stack)) %modal-root-leader-kc #f))
      (set! modal-stack (fsm-return-stack))
      (set-modal-root-segments! (derive-root-segments)))))

;; ─── Modal Navigation ──────────────────────────────────────────

;; Show overlay immediately, cancelling any pending delayed show.
;; on-enter for the current node fires here, so subscribers see the same
;; "user is now looking at this level" event the overlay represents.
(define (modal-show-overlay-now)
  (set! modal-overlay-generation (+ modal-overlay-generation 1))
  (run-on-enter modal-current-node)
  (show-overlay modal-root-node modal-current-path))

;; Schedule overlay to appear after modal-overlay-delay seconds.
;; If a key is pressed before the delay, the show is cancelled — and so are
;; the on-enter hooks. Quick muscle-memory presses produce no UI at all
;; (no overlay, no hint chips, nothing).
(define (modal-show-overlay-delayed)
  (if (<= modal-overlay-delay 0)
    (begin
      (run-on-enter modal-current-node)
      (show-overlay modal-root-node modal-current-path))
    (let ()
      (set! modal-overlay-generation (+ modal-overlay-generation 1))
      (let ((gen modal-overlay-generation))
        (after-delay modal-overlay-delay
          (lambda ()
            (when (and modal-active? (= gen modal-overlay-generation))
              (run-on-enter modal-current-node)
              (show-overlay modal-root-node modal-current-path))))))))

;; Enter modal mode with the given tree and leader keycode. TREE is always
;; a lookup-tree result in every caller found (event-dispatch's
;; make-leader-handler, this file's own callers, and every regression
;; test) — hence already lowered into the FSM graph by register-tree!.
;; Defensively lowers it on the fly if it somehow isn't (façade audit,
;; docs/specs/fsm-graph.md "Lowering and the façade").
;;
;; Registers the catch-all key handler. For ordinary transient trees the
;; overlay show is delayed (quick muscle-memory presses produce no UI);
;; a Walk root shows the overlay immediately because the overlay is
;; the mode indicator — the user must always know they're in a mode.
;;
;; on-enter for the root tree is NOT fired synchronously here in the
;; delayed-show path — it fires inside the overlay-show callback, so quick
;; keypresses that race past the delay never trigger the hooks (no overlay,
;; no hint chips, no flash). In the immediate-show path it fires now.
(define (modal-enter tree leader-kc)
  (when tree
    (let ((scope-str (alist-ref tree 'scope #f)))
      (when (and scope-str (not (fsm-state-ref scope-str)))
        (lower-tree->fsm! scope-str tree))
      (set! %modal-root-leader-kc leader-kc)
      (fsm-activate! scope-str)
      (sync-modal-state-from-fsm!)
      (register-all-keys! modal-key-handler-cell)
      (if (node-walk? tree)
        (modal-show-overlay-now)
        (modal-show-overlay-delayed)))))

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
;; The next modal-enter overwrites it, so staleness can't leak into a new
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
      (modal-show-overlay-delayed))))

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
;; registered tree root carries (register-tree!'s own 'scope field), or #f
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
;; Falls back to scope-string resolution otherwise. Called by modal-enter,
;; and by derive-root-segments above for every tree on the current call
;; chain.
(define (compute-tree-root-segments tree)
  (let ((display (node-display-name tree)))
    (cond
      (display (list display))
      (else
       (compute-root-segments (or (alist-ref tree 'scope #f) ""))))))

))
