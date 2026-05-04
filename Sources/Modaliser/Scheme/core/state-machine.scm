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
;;   'on-enter THUNK  — runs when the modal navigates into this tree
;;   'on-leave THUNK  — runs when the modal navigates out of this tree
;;
;; Children are alist nodes produced by (key ...), (group ...), (selector ...).
;; Disambiguation: a child node's car is a pair; a keyword is a bare symbol.
;;
;; The root node carries 'scope (the raw key string) instead of a label;
;; the breadcrumb is computed at modal-enter time via compute-root-segments,
;; not from a baked-in root label.
(define (register-tree! scope . rest)
  (let ((scope-str (if (symbol? scope) (symbol->string scope) scope)))
    (let loop ((args rest) (on-enter #f) (on-leave #f))
      (cond
        ((and (pair? args) (symbol? (car args)) (pair? (cdr args)))
         (case (car args)
           ((on-enter) (loop (cddr args) (cadr args) on-leave))
           ((on-leave) (loop (cddr args) on-enter (cadr args)))
           (else (error "register-tree!: unknown keyword" (car args)))))
        (else
          (let* ((base (list (cons 'kind 'group)
                             (cons 'key "")
                             (cons 'scope scope-str)
                             (cons 'children args)))
                 (with-leave (if on-leave
                               (cons (cons 'on-leave on-leave) base)
                               base))
                 (with-enter (if on-enter
                               (cons (cons 'on-enter on-enter) with-leave)
                               with-leave)))
            (hashtable-set! tree-registry scope-str with-enter)))))))

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
;; Registers the catch-all key handler and schedules delayed overlay show.
;; on-enter for the root tree is NOT fired here — it fires inside the
;; overlay-show callback, so quick keypresses that race past the delay
;; never trigger the hooks (no overlay, no hint chips, no flash).
(define (modal-enter tree leader-kc)
  (when tree
    (set! modal-active? #t)
    (set! modal-root-node tree)
    (set! modal-current-node tree)
    (set! modal-current-path '())
    (set! modal-leader-keycode leader-kc)
    (set! modal-root-segments
      (compute-root-segments
        (or (alist-ref tree 'scope #f) "")))
    (register-all-keys! modal-key-handler)
    (modal-show-overlay-delayed)))

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

;; Handle a character key press while modal is active.
;; Side-effecting: directly calls actions, updates overlay, etc.
(define (modal-handle-key char)
  (let ((child (find-child modal-current-node char)))
    (cond
      ((not child)
       (modal-exit))
      ((command? child)
       (let ((action (node-action child)))
         (modal-exit)
         (when action (action))))
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
(define (modal-step-back)
  (if (null? modal-current-path)
    (modal-exit)
    (let* ((new-path (reverse (cdr (reverse modal-current-path))))
           (new-node (navigate-to-path modal-root-node new-path))
           (leaving  modal-current-node))
      (when overlay-open? (run-on-leave leaving))
      (set! modal-current-path new-path)
      (set! modal-current-node new-node)
      (when overlay-open? (run-on-enter new-node))
      (update-overlay modal-root-node modal-current-path))))

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
