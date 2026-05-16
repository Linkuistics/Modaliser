;; (modaliser state-machine) — Modal navigation state machine.
;;
;; Hosts the tree registry, modal-* state, and the overlay/chooser hook
;; setters (see Task 4 for why setters instead of define-redefinition).

(define-library (modaliser state-machine)
  (export
    ;; Tree registry
    register-tree! lookup-tree
    ;; Node predicates
    command? group? selector? range-command?
    ;; Node accessors
    node-key node-label node-action node-children node-range-keys
    node-on-enter node-on-leave node-sticky? node-exit-on-unknown?
    node-display-name
    run-on-enter run-on-leave
    find-child navigate-to-path
    ;; Sticky helpers
    deepest-sticky-on-path in-sticky-context? any-on-path?
    exit-on-unknown-context?
    modal-reset-to-sticky-ancestor
    ;; Modal state
    modal-active? modal-current-node modal-root-node modal-current-path
    modal-leader-keycode modal-overlay-generation modal-overlay-delay
    modal-root-segments set-modal-root-segments! modal-stack
    modal-current-context modal-apply-context!
    ;; Modal lifecycle
    modal-enter modal-exit modal-step-back modal-handle-key
    modal-show-overlay-now modal-show-overlay-delayed
    enter-mode!
    set-overlay-delay!
    ;; Key handler hook (installed by event-dispatch after it defines modal-key-handler)
    set-modal-key-handler!
    ;; Overlay/chooser hooks
    overlay-open? show-overlay update-overlay hide-overlay open-chooser
    set-overlay-open! set-show-overlay! set-update-overlay!
    set-hide-overlay! set-open-chooser!
    ;; Host header
    host-header-name host-header-background host-header-foreground
    host-header-separator-color
    set-host-header! host-header-css
    ;; Breadcrumb
    resolve-app-segments compute-root-segments compute-tree-root-segments)
  (import (scheme base)
          (modaliser util)
          (modaliser app)
          (modaliser keyboard)
          (modaliser lifecycle))
  (begin

;; core/state-machine.scm — Modal navigation state machine
;;
;; Manages command tree registration, lookup, and modal navigation.
;; All trees are stored in a hash table keyed by scope string.
;; Navigation is side-effecting: modal-handle-key directly executes
;; actions, updates the overlay, and opens the chooser.

;; ─── Tree Registry ──────────────────────────────────────────────

(define tree-registry (make-hashtable string-hash string=?))

;; Register a command tree for a scope.
;; scope: symbol or string (e.g. 'global or "com.apple.Safari")
;; rest:  optional leading keyword/value pairs followed by child nodes.
;;
;; Recognized keywords (mirror the (group ...) DSL):
;;   'on-enter THUNK     — runs when the modal navigates into this tree
;;   'on-leave THUNK     — runs when the modal navigates out of this tree
;;   'sticky      BOOL   — root is a sticky group: firing a command leaf
;;                         resets navigation to the nearest sticky ancestor
;;                         instead of exiting the modal. Unknown keys are
;;                         ignored (no accidental exit on typo) and the
;;                         overlay shows immediately on entry. Any (group ...)
;;                         child can also carry its own 'sticky #t; the
;;                         reset target is always the *deepest* sticky group
;;                         on the path. Escape fully exits the modal from
;;                         any depth; Backspace navigates back one level
;;                         and at the root of a sticky tree exits ("back
;;                         out of the sticky group"). Transient launcher
;;                         trees treat root-backspace as a no-op.
;;   'exit-on-unknown BOOL — unrecognised keys dismiss the modal instead
;;                         of being swallowed. Inherited by descendants:
;;                         if any group on the current path has it, an
;;                         unknown key exits. Useful for sticky focus-
;;                         movement modes (e.g. iTerm pane navigation)
;;                         where typing a non-binding key should hand
;;                         control back to the underlying app instead of
;;                         forcing an explicit Escape.
;;   'display-name STR   — overrides the breadcrumb scope segment. For
;;                         non-bundle-ID scopes (mode IDs) the auto-resolution
;;                         in resolve-app-segments would otherwise surface
;;                         the raw scope string.
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
               (sticky #f) (display-name #f) (exit-unk #f))
      (cond
        ((and (pair? args) (symbol? (car args)) (pair? (cdr args)))
         (case (car args)
           ((on-enter)        (loop (cddr args) (cadr args) on-leave sticky display-name exit-unk))
           ((on-leave)        (loop (cddr args) on-enter (cadr args) sticky display-name exit-unk))
           ((sticky)          (loop (cddr args) on-enter on-leave (cadr args) display-name exit-unk))
           ((display-name)    (loop (cddr args) on-enter on-leave sticky (cadr args) exit-unk))
           ((exit-on-unknown) (loop (cddr args) on-enter on-leave sticky display-name (cadr args)))
           (else (error "register-tree!: unknown keyword" (car args)))))
        (else
          (let* ((acc (list (cons 'kind 'group)
                            (cons 'key "")
                            (cons 'scope scope-str)
                            (cons 'children args)))
                 (acc (if on-leave     (cons (cons 'on-leave on-leave)         acc) acc))
                 (acc (if on-enter     (cons (cons 'on-enter on-enter)         acc) acc))
                 (acc (if sticky       (cons (cons 'sticky #t)                 acc) acc))
                 (acc (if exit-unk     (cons (cons 'exit-on-unknown #t)        acc) acc))
                 (acc (if display-name (cons (cons 'display-name display-name) acc) acc)))
            (hashtable-set! tree-registry scope-str acc)))))))

;; Look up a tree by scope. Returns #f if not found.
(define (lookup-tree scope)
  (let ((scope-str (if (symbol? scope) (symbol->string scope) scope)))
    (hashtable-ref tree-registry scope-str #f)))

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

(define (run-on-enter node)
  (let ((thunk (node-on-enter node)))
    (when thunk (thunk))))

(define (run-on-leave node)
  (let ((thunk (node-on-leave node)))
    (when thunk (thunk))))

;; Is this group node sticky? (Either set via 'sticky #t on a tree root
;; or on a (group ...) child.)
(define (node-sticky? node)
  (let ((entry (assoc 'sticky node)))
    (and entry (cdr entry))))

;; Does this group declare that unknown keys should exit the modal?
;; Opt-in (default forgiving). Inherited by descendants via path walk;
;; see exit-on-unknown-context?.
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

;; Find the child that handles KEY. Specific bindings (key …) always win
;; over a range-command that lists KEY among its keys — letting a literal
;; binding carve a slot out of an existing range. Range matches are taken
;; in declaration order if multiple ranges include KEY (first wins).
(define (find-child node key)
  (let loop ((children (node-children node)) (range-hit #f))
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
;; modal-key-handler is defined in core/event-dispatch.scm which is
;; include-loaded after this library. Since library-internal bindings
;; are lexically scoped, modal-enter cannot reference the global name
;; directly. Instead, a mutable cell holds the handler; event-dispatch.scm
;; installs it via (set-modal-key-handler! ...) after defining it.

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
(define %overlay-open?-flag #f)
(define (overlay-open?) %overlay-open?-flag)
(define (set-overlay-open! v) (set! %overlay-open?-flag v))

(define show-overlay-impl   (lambda (node path) (if #f #f)))
(define update-overlay-impl (lambda (node path) (if #f #f)))
(define hide-overlay-impl   (lambda ()          (if #f #f)))
(define open-chooser-impl   (lambda (sel)       (if #f #f)))

(define (show-overlay   node path) (show-overlay-impl node path))
(define (update-overlay node path) (update-overlay-impl node path))
(define (hide-overlay)             (hide-overlay-impl))
(define (open-chooser selector-node) (open-chooser-impl selector-node))

(define (set-show-overlay!   fn) (set! show-overlay-impl   fn))
(define (set-update-overlay! fn) (set! update-overlay-impl fn))
(define (set-hide-overlay!   fn) (set! hide-overlay-impl   fn))
(define (set-open-chooser!   fn) (set! open-chooser-impl   fn))

;; ─── Modal State ────────────────────────────────────────────────

(define modal-active? #f)
(define modal-current-node #f)
(define modal-root-node #f)
(define modal-current-path '())
(define modal-leader-keycode #f)
(define modal-overlay-generation 0) ;; generation counter for delayed overlay show
(define modal-overlay-delay 1.0)    ;; seconds before overlay appears (0 = immediate)
;; modal-root-segments is exported as a *procedure* (thunk) for the same reason
;; as overlay-open?: LispKit snapshots '() at compile time in importing scopes.
(define %modal-root-segments '())    ;; breadcrumb root: host? + scope segments
(define (modal-root-segments) %modal-root-segments)
(define (set-modal-root-segments! v) (set! %modal-root-segments v))

;; Stack of saved modal contexts, most-recent first. Pushed by enter-mode!
;; when it switches into a mode from inside an already-active modal so
;; backspace at the new mode's root can pop back to the caller (e.g. an
;; iTerm launcher tree → focus mode → backspace → launcher reappears).
;; Cleared by modal-exit so an Escape from any depth fully tears down.
(define modal-stack '())

;; Snapshot the current modal context for the stack.
(define (modal-current-context)
  (list (cons 'root-node     modal-root-node)
        (cons 'current-node  modal-current-node)
        (cons 'current-path  modal-current-path)
        (cons 'leader-kc     modal-leader-keycode)
        (cons 'root-segments (modal-root-segments))))

;; Restore a context onto the active modal variables.
(define (modal-apply-context! ctx)
  (set! modal-root-node     (cdr (assoc 'root-node     ctx)))
  (set! modal-current-node  (cdr (assoc 'current-node  ctx)))
  (set! modal-current-path  (cdr (assoc 'current-path  ctx)))
  (set! modal-leader-keycode (cdr (assoc 'leader-kc    ctx)))
  (set-modal-root-segments! (cdr (assoc 'root-segments ctx))))

;; (set-overlay-delay! seconds) — set the which-key overlay delay.
;; 0 shows the overlay immediately; typical values are 0.3–1.0 seconds.
(define (set-overlay-delay! seconds)
  (set! modal-overlay-delay seconds))

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

;; Enter modal mode with the given tree and leader keycode.
;; Registers the catch-all key handler. For ordinary transient trees the
;; overlay show is delayed (quick muscle-memory presses produce no UI);
;; sticky-root trees show the overlay immediately because the overlay is
;; the mode indicator — the user must always know they're in a mode.
;;
;; on-enter for the root tree is NOT fired synchronously here in the
;; delayed-show path — it fires inside the overlay-show callback, so quick
;; keypresses that race past the delay never trigger the hooks (no overlay,
;; no hint chips, no flash). In the immediate-show path it fires now.
(define (modal-enter tree leader-kc)
  (when tree
    (set! modal-active? #t)
    (set! modal-root-node tree)
    (set! modal-current-node tree)
    (set! modal-current-path '())
    (set! modal-leader-keycode leader-kc)
    (set-modal-root-segments!
      (compute-tree-root-segments tree))
    (register-all-keys! modal-key-handler-cell)
    (if (node-sticky? tree)
      (modal-show-overlay-now)
      (modal-show-overlay-delayed))))

;; (enter-mode! id) — enter a registered tree as a new modal context.
;; Intended use is from inside the action thunk of a leader-tree leaf, e.g.
;;   (key "p" "Pane Mode" (lambda () (enter-mode! 'iterm-panes)))
;;
;; If a modal is already active when this is called (the typical case —
;; the action ran from inside modal-handle-key, which now defers the
;; transient post-action exit so the calling context is still alive),
;; the current context is *pushed* onto modal-stack and the new tree
;; becomes active without unregistering the catch-all key handler.
;; Backspace at the root of the new tree (when sticky) pops the stack
;; back to the calling context — see modal-step-back.
;;
;; Leader-kc is #f — the mode isn't bound to a leader hotkey, so the
;; "leader toggles modal off" branch in modal-key-handler simply doesn't
;; match (it's guarded by an `and` on modal-leader-keycode).
(define (enter-mode! id)
  (let ((tree (lookup-tree id)))
    (cond
      ((not tree)
       (error "enter-mode!: no tree registered for" id))
      ((not modal-active?)
       (modal-enter tree #f))
      (else
       (when (overlay-open?)
         (run-on-leave modal-current-node))
       (set! modal-stack (cons (modal-current-context) modal-stack))
       (set! modal-root-node tree)
       (set! modal-current-node tree)
       (set! modal-current-path '())
       (set! modal-leader-keycode #f)
       (set-modal-root-segments! (compute-tree-root-segments tree))
       ;; Always show immediately on mode switch — the caller's overlay
       ;; was up, so no flash of "nothing" between the two modes.
       (modal-show-overlay-now)))))

;; Exit modal mode. Deregisters catch-all and hides overlay.
;; Idempotent: a second call after the modal is already inactive is a no-op.
;;
;; on-leave only fires if the overlay was actually visible — paired with
;; on-enter, which only fires when the overlay shows. A modal that exits
;; before the overlay's display delay elapses produces zero hook fires.
(define (modal-exit)
  (when modal-active?
    (when (and modal-current-node (overlay-open?))
      (run-on-leave modal-current-node))
    (set! modal-overlay-generation (+ modal-overlay-generation 1))
    (unregister-all-keys!)
    (hide-overlay)
    (set! modal-active? #f)
    (set! modal-current-node #f)
    (set! modal-root-node #f)
    (set! modal-current-path '())
    (set! modal-leader-keycode #f)
    ;; Clear the entire stack — exit is a full teardown regardless of
    ;; depth. Escape from a stacked mode unwinds all callers at once.
    (set! modal-stack '())))
;; modal-root-segments is intentionally NOT reset here. A selector key in
;; the modal calls (modal-exit) before (open-chooser ...), and the chooser
;; reads modal-root-segments to render its breadcrumb. The next modal-enter
;; overwrites it, so staleness can't leak into a new session.

;; (deepest-sticky-on-path root path) → (node . path-to-it) or #f
;;
;; Walks from ROOT following PATH, returning the deepest group on that
;; walk whose 'sticky flag is true, paired with the key-path from root to
;; it. The root itself is eligible (counts as taken-path '()).
;;
;; Used by modal-handle-key to decide:
;;   1. whether we're "in sticky context" (any sticky ancestor exists) and
;;      should therefore swallow unknown keys / re-arm after a leaf fires,
;;   2. which ancestor to reset to after a leaf fires — always the deepest,
;;      so nested sticky subgroups stay sticky in their own right.
(define (deepest-sticky-on-path root path)
  (let loop ((node root) (remaining path) (taken '()) (best #f))
    (let ((best* (if (node-sticky? node) (cons node taken) best)))
      (if (null? remaining)
        best*
        (let ((child (find-child node (car remaining))))
          (if child
            (loop child (cdr remaining)
                  (append taken (list (car remaining)))
                  best*)
            best*))))))

;; True iff the current navigation point has any sticky ancestor (or the
;; current group itself is sticky). Cheap path walk; called per keypress.
(define (in-sticky-context?)
  (and modal-active?
       (deepest-sticky-on-path modal-root-node modal-current-path)
       #t))

;; (any-on-path? root path pred) → bool
;;
;; Walk from ROOT along PATH; return #t if PRED holds on any visited
;; group (including ROOT and the final current node). Used by callers
;; that need ancestor-inherited flags (e.g. exit-on-unknown).
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

;; True iff the current path has 'exit-on-unknown set on any ancestor
;; (or the current group itself). Unknown keys in that context exit the
;; modal instead of being swallowed.
(define (exit-on-unknown-context?)
  (and modal-active?
       (any-on-path? modal-root-node modal-current-path node-exit-on-unknown?)))

;; Reset navigation to the deepest sticky group on the current path,
;; refreshing the overlay. Fires on-leave for the group we're leaving
;; (if any) and on-enter for the sticky target — same gating as descend.
;; If the current node is already the deepest sticky (nothing to leave),
;; only the overlay is refreshed so a re-fired leaf still updates state
;; that downstream subscribers care about.
(define (modal-reset-to-sticky-ancestor)
  (let ((target (deepest-sticky-on-path
                  modal-root-node modal-current-path)))
    (when target
      (let ((target-node (car target))
            (target-path (cdr target)))
        (cond
          ((and (eq? target-node modal-current-node)
                (equal? target-path modal-current-path))
           (when (overlay-open?)
             (update-overlay modal-root-node modal-current-path)))
          (else
           (when (overlay-open?)
             (run-on-leave modal-current-node))
           (set! modal-current-node target-node)
           (set! modal-current-path target-path)
           (when (overlay-open?)
             (run-on-enter modal-current-node)
             (update-overlay modal-root-node modal-current-path))))))))

;; Handle a character key press while modal is active.
;; Side-effecting: directly calls actions, updates overlay, etc.
;;
;; Default keymap is forgiving: unknown keys are swallowed, never drop
;; the modal. Groups can opt back into dismissal by setting
;; 'exit-on-unknown #t — typing a non-binding key then exits the modal,
;; useful for sticky focus-movement modes (iTerm pane mode) where the
;; user's next typing should reach the underlying app without an
;; explicit Escape first.
;;
;; Sticky context only changes the *command-leaf* branch: instead of
;; exiting after firing the action (transient launcher behaviour), it
;; resets navigation to the deepest sticky ancestor so the next key
;; starts from that level.
;;
;; In both transient and sticky branches the action runs *before* the
;; cleanup decision, and the cleanup is conditional on the modal state
;; not having been changed by the action. This lets (enter-mode! ...)
;; inside the action push the calling context onto modal-stack — if we
;; exited or reset to a stale tree first, that push would be against
;; the wrong context (or impossible). Detection is by root-node identity:
;; if modal-root-node still matches the one we saw before the action,
;; the action didn't switch modes, and we proceed with cleanup.
;;
;; Selectors still exit the modal: the chooser owns input focus, so a
;; sticky context can't survive its lifecycle in v1.
(define (modal-handle-key char)
  (let ((child (find-child modal-current-node char)))
    (cond
      ((not child)
       (if (exit-on-unknown-context?)
         (modal-exit)
         (if #f #f)))
      ((command? child)
       (let ((action (node-action child))
             (sticky? (in-sticky-context?))
             (root-before modal-root-node))
         (when action (action))
         (when (and modal-active? (eq? modal-root-node root-before))
           (cond
             (sticky? (modal-reset-to-sticky-ancestor))
             (else    (modal-exit))))))
      ((range-command? child)
       ;; Same cleanup semantics as a plain command leaf; only the call
       ;; shape differs — the action receives the matched key so it can
       ;; vary per-key (e.g. "switch to space N").
       (let ((action (node-action child))
             (sticky? (in-sticky-context?))
             (root-before modal-root-node))
         (when action (action char))
         (when (and modal-active? (eq? modal-root-node root-before))
           (cond
             (sticky? (modal-reset-to-sticky-ancestor))
             (else    (modal-exit))))))
      ((group? child)
       ;; Hooks pair with overlay visibility — fire transitions only when
       ;; the user actually sees the change. Fast descent before the
       ;; overlay shows gets neither leave nor enter; the eventual
       ;; overlay-show callback will fire on-enter for whatever the
       ;; current node is at that moment.
       (when (overlay-open?)
         (run-on-leave modal-current-node))
       (set! modal-current-node child)
       (set! modal-current-path
         (append modal-current-path (list char)))
       (cond
         ((overlay-open?)
          (run-on-enter child)
          (update-overlay modal-root-node modal-current-path))
         (else
          (modal-show-overlay-delayed))))
      ((selector? child)
       (modal-exit)
       (open-chooser child))
      (else
       (if #f #f)))))

;; Step back one level in the navigation path.
;; Hooks only fire if the overlay was visible — same gating as the descent
;; case in modal-handle-key.
;;
;; Tree-navigational, with stack-aware behaviour at the root:
;;   * At depth > 0 — retreat to the parent group.
;;   * At the root of a *sticky* tree:
;;       - if modal-stack is non-empty, pop the caller context — i.e.
;;         "back out of the sticky group" returns to the tree that
;;         invoked (enter-mode!). The user descends through their
;;         modal hierarchy in reverse.
;;       - else, exit the modal (no caller to return to).
;;   * At the root of a transient launcher — no-op. Transient trees have
;;     no "outside" to back into; the user keeps the launcher until
;;     they pick a leaf or press Escape.
;; Escape remains the one-shot exit-from-any-depth, regardless of stack.
(define (modal-step-back)
  (cond
    ((null? modal-current-path)
     (cond
       ((not (in-sticky-context?))
        (if #f #f))
       ((not (null? modal-stack))
        (when (overlay-open?)
          (run-on-leave modal-current-node))
        (modal-apply-context! (car modal-stack))
        (set! modal-stack (cdr modal-stack))
        (when (overlay-open?)
          (run-on-enter modal-current-node)
          (show-overlay modal-root-node modal-current-path)))
       (else
        (modal-exit))))
    (else
     (let* ((new-path (reverse (cdr (reverse modal-current-path))))
            (new-node (navigate-to-path modal-root-node new-path))
            (leaving  modal-current-node))
       (when (overlay-open?) (run-on-leave leaving))
       (set! modal-current-path new-path)
       (set! modal-current-node new-node)
       (when (overlay-open?) (run-on-enter new-node))
       (update-overlay modal-root-node modal-current-path)))))

;; Navigate from root following a list of key strings.
(define (navigate-to-path root path)
  (if (null? path)
    root
    (let ((child (find-child root (car path))))
      (if child
        (navigate-to-path child (cdr path))
        #f))))

;; ─── Host Header ────────────────────────────────────────────────
;;
;; Optional banner identifying which Modaliser instance owns the
;; overlay/chooser. Set once at config load via (set-host-header! ...).

(define host-header-name #f)              ;; #f → no host segment, no recolour
(define host-header-background #f)         ;; CSS colour string or #f
(define host-header-foreground #f)         ;; CSS colour string or #f
(define host-header-separator-color #f)    ;; CSS colour string or #f

;; (set-host-header! 'name VAL
;;                   [ 'background      CSS ]
;;                   [ 'foreground      CSS ]
;;                   [ 'separator-color CSS ])
;;
;; Keyword-style API mirroring set-leader!.  Only 'name is required.
;; Re-calling overwrites the previous values. All values are whitespace-
;; trimmed so (run-shell "hostname -s") and similar shell-derived strings
;; can be passed directly without callers handling the trailing newline.
(define (set-host-header! . args)
  (let loop ((rest args)
             (name #f) (bg #f) (fg #f) (sep #f) (saw-name? #f))
    (cond
      ((null? rest)
       (unless saw-name?
         (error "set-host-header!: missing required 'name keyword"))
       (set! host-header-name (string-trim name))
       (set! host-header-background (and bg (string-trim bg)))
       (set! host-header-foreground (and fg (string-trim fg)))
       (set! host-header-separator-color (and sep (string-trim sep))))
      ((eq? (car rest) 'name)
       (loop (cddr rest) (cadr rest) bg fg sep #t))
      ((eq? (car rest) 'background)
       (loop (cddr rest) name (cadr rest) fg sep saw-name?))
      ((eq? (car rest) 'foreground)
       (loop (cddr rest) name bg (cadr rest) sep saw-name?))
      ((eq? (car rest) 'separator-color)
       (loop (cddr rest) name bg fg (cadr rest) saw-name?))
      (else
       (error "set-host-header!: unknown keyword" (car rest))))))

;; (host-header-css) → string
;; Returns a :root { ... } CSS block defining --color-host-bg / --color-host-fg
;; / --color-host-sep when set, or "" when none are set. Concatenated into the
;; <style> block by both the overlay and the chooser renderers.
(define (host-header-css)
  (if (and (not host-header-background)
           (not host-header-foreground)
           (not host-header-separator-color))
    ""
    (string-append
      ":root {"
      (if host-header-background
        (string-append " --color-host-bg: " host-header-background ";") "")
      (if host-header-foreground
        (string-append " --color-host-fg: " host-header-foreground ";") "")
      (if host-header-separator-color
        (string-append " --color-host-sep: " host-header-separator-color ";") "")
      " }")))

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
;; Builds the breadcrumb root: optional host name, then scope segments.
;;   global tree              → (host? "Global")
;;   app-local tree           → (host? app-name [variant])
(define (compute-root-segments scope-str)
  (let ((host-prefix (if host-header-name (list host-header-name) '()))
        (scope-segs  (if (equal? scope-str "global")
                       (list "Global")
                       (resolve-app-segments scope-str))))
    (append host-prefix scope-segs)))

;; (compute-tree-root-segments tree) → list of strings
;;
;; Like compute-root-segments but uses the tree's 'display-name when set
;; (so registered modes show a human label instead of the raw mode-id).
;; Falls back to scope-string resolution otherwise. Called by modal-enter.
(define (compute-tree-root-segments tree)
  (let ((display (node-display-name tree)))
    (cond
      (display
       (append (if host-header-name (list host-header-name) '())
               (list display)))
      (else
       (compute-root-segments (or (alist-ref tree 'scope #f) ""))))))

))
