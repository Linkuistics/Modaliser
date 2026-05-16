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
;;                         on the path. Escape always fully exits the modal;
;;                         Backspace steps back one level (no-op at root).
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
               (sticky #f) (display-name #f))
      (cond
        ((and (pair? args) (symbol? (car args)) (pair? (cdr args)))
         (case (car args)
           ((on-enter)     (loop (cddr args) (cadr args) on-leave sticky display-name))
           ((on-leave)     (loop (cddr args) on-enter (cadr args) sticky display-name))
           ((sticky)       (loop (cddr args) on-enter on-leave (cadr args) display-name))
           ((display-name) (loop (cddr args) on-enter on-leave sticky (cadr args)))
           (else (error "register-tree!: unknown keyword" (car args)))))
        (else
          (let* ((acc (list (cons 'kind 'group)
                            (cons 'key "")
                            (cons 'scope scope-str)
                            (cons 'children args)))
                 (acc (if on-leave     (cons (cons 'on-leave on-leave)         acc) acc))
                 (acc (if on-enter     (cons (cons 'on-enter on-enter)         acc) acc))
                 (acc (if sticky       (cons (cons 'sticky #t)                 acc) acc))
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

;; (node-display-name node) → string or #f
;; Optional human label for a tree root, used as the breadcrumb scope
;; segment in place of an auto-resolved app name. Set via 'display-name
;; on register-tree!. Returns #f for plain children (only roots use this).
(define (node-display-name node)
  (let ((entry (assoc 'display-name node)))
    (and entry (cdr entry))))

(define (find-child node key)
  (let loop ((children (node-children node)))
    (cond
      ((null? children) #f)
      ((equal? (node-key (car children)) key)
       (car children))
      (else (loop (cdr children))))))

;; ─── Overlay Hooks (overridden by ui/overlay.scm) ───────────────
;; These stubs allow state-machine.scm to be loaded and tested
;; independently. When overlay.scm loads, it redefines these.

(define overlay-open? #f)
(define (show-overlay node path) (void))
(define (update-overlay node path) (void))
(define (hide-overlay) (void))
(define (open-chooser selector-node) (void))

;; ─── Modal State ────────────────────────────────────────────────

(define modal-active? #f)
(define modal-current-node #f)
(define modal-root-node #f)
(define modal-current-path '())
(define modal-leader-keycode #f)
(define modal-overlay-generation 0) ;; generation counter for delayed overlay show
(define modal-overlay-delay 1.0)    ;; seconds before overlay appears (0 = immediate)
(define modal-root-segments '())     ;; breadcrumb root: host? + scope segments

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
    (set! modal-root-segments
      (compute-tree-root-segments tree))
    (register-all-keys! modal-key-handler)
    (if (node-sticky? tree)
      (modal-show-overlay-now)
      (modal-show-overlay-delayed))))

;; (enter-mode! id) — enter a registered sticky tree from anywhere.
;; Intended use is from inside the action thunk of a leader-tree leaf, e.g.
;;   (key "p" "Pane Mode" (lambda () (enter-mode! 'iterm-panes)))
;; If a modal is already active (the launcher hasn't exited yet because
;; the action is being invoked from inside modal-handle-key's pre-action
;; modal-exit window), exit it first.
;;
;; Leader-kc is #f — the mode isn't bound to a leader hotkey, so the
;; "leader toggles modal off" branch in modal-key-handler simply doesn't
;; match (it's guarded by an `and` on modal-leader-keycode).
(define (enter-mode! id)
  (let ((tree (lookup-tree id)))
    (cond
      ((not tree)
       (error "enter-mode!: no tree registered for" id))
      (else
       (when modal-active? (modal-exit))
       (modal-enter tree #f)))))

;; Exit modal mode. Deregisters catch-all and hides overlay.
;; Idempotent: a second call after the modal is already inactive is a no-op.
;;
;; on-leave only fires if the overlay was actually visible — paired with
;; on-enter, which only fires when the overlay shows. A modal that exits
;; before the overlay's display delay elapses produces zero hook fires.
(define (modal-exit)
  (when modal-active?
    (when (and modal-current-node overlay-open?)
      (run-on-leave modal-current-node))
    (set! modal-overlay-generation (+ modal-overlay-generation 1))
    (unregister-all-keys!)
    (hide-overlay)
    (set! modal-active? #f)
    (set! modal-current-node #f)
    (set! modal-root-node #f)
    (set! modal-current-path '())
    (set! modal-leader-keycode #f)))
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
           (when overlay-open?
             (update-overlay modal-root-node modal-current-path)))
          (else
           (when overlay-open?
             (run-on-leave modal-current-node))
           (set! modal-current-node target-node)
           (set! modal-current-path target-path)
           (when overlay-open?
             (run-on-enter modal-current-node)
             (update-overlay modal-root-node modal-current-path))))))))

;; Handle a character key press while modal is active.
;; Side-effecting: directly calls actions, updates overlay, etc.
;;
;; Sticky context overrides two transient defaults:
;;   * Unknown key — normally exits the modal; in sticky context it is
;;     swallowed (typing past a stale binding shouldn't drop the mode).
;;   * Command leaf — normally exits then runs the action; in sticky
;;     context, runs the action then resets navigation to the deepest
;;     sticky ancestor so the next key starts from that level. If the
;;     action itself exited the modal (e.g. via enter-mode!), don't
;;     touch the navigation state.
;;
;; Selectors still exit the modal: the chooser owns input focus, so a
;; sticky context can't survive its lifecycle in v1.
(define (modal-handle-key char)
  (let ((child (find-child modal-current-node char)))
    (cond
      ((not child)
       (if (in-sticky-context?)
         (void)
         (modal-exit)))
      ((command? child)
       (let ((action (node-action child))
             (sticky? (in-sticky-context?)))
         (cond
           (sticky?
            (when action (action))
            (when modal-active?
              (modal-reset-to-sticky-ancestor)))
           (else
            (modal-exit)
            (when action (action))))))
      ((group? child)
       ;; Hooks pair with overlay visibility — fire transitions only when
       ;; the user actually sees the change. Fast descent before the
       ;; overlay shows gets neither leave nor enter; the eventual
       ;; overlay-show callback will fire on-enter for whatever the
       ;; current node is at that moment.
       (when overlay-open?
         (run-on-leave modal-current-node))
       (set! modal-current-node child)
       (set! modal-current-path
         (append modal-current-path (list char)))
       (cond
         (overlay-open?
          (run-on-enter child)
          (update-overlay modal-root-node modal-current-path))
         (else
          (modal-show-overlay-delayed))))
      ((selector? child)
       (modal-exit)
       (open-chooser child))
      (else
       (modal-exit)))))

;; Step back one level in the navigation path.
;; Hooks only fire if the overlay was visible — same gating as the descent
;; case in modal-handle-key.
;;
;; At the root (path empty) there's no level left to retreat to, so this
;; exits the modal — including sticky modes (backspace is a "go back one"
;; that bottoms out by leaving the mode altogether). Escape exits from any
;; depth in one shot; backspace unwinds gradually.
(define (modal-step-back)
  (cond
    ((null? modal-current-path)
     (modal-exit))
    (else
     (let* ((new-path (reverse (cdr (reverse modal-current-path))))
            (new-node (navigate-to-path modal-root-node new-path))
            (leaving  modal-current-node))
       (when overlay-open? (run-on-leave leaving))
       (set! modal-current-path new-path)
       (set! modal-current-node new-node)
       (when overlay-open? (run-on-enter new-node))
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
