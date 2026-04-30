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
;; children: alist nodes produced by (key ...), (group ...), etc.
;;
;; The root node carries 'scope (the raw key string) instead of a label;
;; the breadcrumb is computed at modal-enter time via compute-root-segments,
;; not from a baked-in root label.
(define (register-tree! scope . children)
  (let* ((scope-str (if (symbol? scope) (symbol->string scope) scope))
         (root (list (cons 'kind 'group)
                     (cons 'key "")
                     (cons 'scope scope-str)
                     (cons 'children children))))
    (hashtable-set! tree-registry scope-str root)))

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
(define (modal-show-overlay-now)
  (set! modal-overlay-generation (+ modal-overlay-generation 1))
  (show-overlay modal-root-node modal-current-path))

;; Schedule overlay to appear after modal-overlay-delay seconds.
;; If a key is pressed before the delay, the show is cancelled.
(define (modal-show-overlay-delayed)
  (if (<= modal-overlay-delay 0)
    (show-overlay modal-root-node modal-current-path)
    (let ()
      (set! modal-overlay-generation (+ modal-overlay-generation 1))
      (let ((gen modal-overlay-generation))
        (after-delay modal-overlay-delay
          (lambda ()
            (when (and modal-active? (= gen modal-overlay-generation))
              (show-overlay modal-root-node modal-current-path))))))))

;; Enter modal mode with the given tree and leader keycode.
;; Registers the catch-all key handler and schedules delayed overlay show.
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
(define (modal-exit)
  (when modal-active?
    (set! modal-overlay-generation (+ modal-overlay-generation 1))
    (unregister-all-keys!)
    (hide-overlay)
    (set! modal-active? #f)
    (set! modal-current-node #f)
    (set! modal-root-node #f)
    (set! modal-current-path '())
    (set! modal-leader-keycode #f)
    (set! modal-root-segments '())))

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
       (set! modal-current-node child)
       (set! modal-current-path
         (append modal-current-path (list char)))
       ;; If overlay already visible, update immediately; otherwise restart delay
       (if overlay-open?
         (update-overlay modal-root-node modal-current-path)
         (modal-show-overlay-delayed)))
      ((selector? child)
       (modal-exit)
       (open-chooser child))
      (else
       (modal-exit)))))

;; Step back one level in the navigation path.
(define (modal-step-back)
  (if (null? modal-current-path)
    (modal-exit)
    (let* ((new-path (reverse (cdr (reverse modal-current-path))))
           (new-node (navigate-to-path modal-root-node new-path)))
      (set! modal-current-path new-path)
      (set! modal-current-node new-node)
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

(define host-header-name #f)         ;; #f → no host segment, no recolour
(define host-header-background #f)   ;; CSS colour string or #f
(define host-header-foreground #f)   ;; CSS colour string or #f

;; (set-host-header! 'name VAL [ 'background CSS ] [ 'foreground CSS ])
;;
;; Keyword-style API mirroring set-leader!.  Only 'name is required.
;; Re-calling overwrites the previous values.
(define (set-host-header! . args)
  (let loop ((rest args)
             (name #f) (bg #f) (fg #f) (saw-name? #f))
    (cond
      ((null? rest)
       (unless saw-name?
         (error "set-host-header!: missing required 'name keyword"))
       (set! host-header-name name)
       (set! host-header-background bg)
       (set! host-header-foreground fg))
      ((eq? (car rest) 'name)
       (loop (cddr rest) (cadr rest) bg fg #t))
      ((eq? (car rest) 'background)
       (loop (cddr rest) name (cadr rest) fg saw-name?))
      ((eq? (car rest) 'foreground)
       (loop (cddr rest) name bg (cadr rest) saw-name?))
      (else
       (error "set-host-header!: unknown keyword" (car rest))))))

;; (host-header-css) → string
;; Returns a :root { ... } CSS block defining --color-host-bg and/or
;; --color-host-fg when set, or "" when neither is set.  Concatenated
;; into the <style> block by both the overlay and the chooser renderers.
(define (host-header-css)
  (if (and (not host-header-background) (not host-header-foreground))
    ""
    (string-append
      ":root {"
      (if host-header-background
        (string-append " --color-host-bg: " host-header-background ";") "")
      (if host-header-foreground
        (string-append " --color-host-fg: " host-header-foreground ";") "")
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
