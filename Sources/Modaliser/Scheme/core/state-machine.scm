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
(define (register-tree! scope . children)
  (let* ((scope-str (if (symbol? scope) (symbol->string scope) scope))
         (label (if (equal? scope-str "global") "Global" scope-str))
         (root (list (cons 'kind 'group)
                     (cons 'key "")
                     (cons 'label label)
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

;; ─── Modal State ────────────────────────────────────────────────

(define modal-active? #f)
(define modal-current-node #f)
(define modal-root-node #f)
(define modal-current-path '())
(define modal-leader-keycode #f)

;; ─── Modal Navigation ──────────────────────────────────────────

;; Enter modal mode with the given tree and leader keycode.
;; Registers the catch-all key handler and shows the overlay (Phase 2).
(define (modal-enter tree leader-kc)
  (when tree
    (set! modal-active? #t)
    (set! modal-root-node tree)
    (set! modal-current-node tree)
    (set! modal-current-path '())
    (set! modal-leader-keycode leader-kc)
    (register-all-keys! modal-key-handler)
    ;; Overlay will be wired in Phase 2
    (log "modal-enter: activated")))

;; Exit modal mode. Deregisters catch-all and hides overlay.
(define (modal-exit)
  (unregister-all-keys!)
  (set! modal-active? #f)
  (set! modal-current-node #f)
  (set! modal-root-node #f)
  (set! modal-current-path '())
  (set! modal-leader-keycode #f)
  ;; Overlay will be wired in Phase 2
  (log "modal-exit: deactivated"))

;; Handle a character key press while modal is active.
;; Side-effecting: directly calls actions, updates overlay, etc.
(define (modal-handle-key char)
  (let ((children (node-children modal-current-node)))
    (log "modal-handle-key: '" char "' children: " (length children))
    (when (pair? children)
      (log "  first child keys: " (map node-key children))
      (log "  looking for key='" char "' equal to first='" (node-key (car children)) "'? " (equal? (node-key (car children)) char))))
  (let ((child (find-child modal-current-node char)))
    (log "  child found: " (if child (node-label child) "NONE"))
    (cond
      ((not child)
       (log "  -> no binding, exiting")
       (modal-exit))
      ((command? child)
       (let ((action (node-action child)))
         (log "  -> command: " (node-label child))
         (modal-exit)
         (when action (action))))
      ((group? child)
       (set! modal-current-node child)
       (set! modal-current-path
         (append modal-current-path (list char)))
       (log "  -> group: " (node-label child)))
      ((selector? child)
       (modal-exit)
       (log "  -> selector: " (node-label child)))
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
      ;; Overlay update will be wired in Phase 2
      (log "modal-step-back: " new-path))))

;; Navigate from root following a list of key strings.
(define (navigate-to-path root path)
  (if (null? path)
    root
    (let ((child (find-child root (car path))))
      (if child
        (navigate-to-path child (cdr path))
        #f))))
