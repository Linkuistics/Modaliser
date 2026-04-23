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
    (register-all-keys! modal-key-handler)
    (modal-show-overlay-delayed)))

;; Exit modal mode. Deregisters catch-all and hides overlay.
(define (modal-exit)
  (set! modal-overlay-generation (+ modal-overlay-generation 1))
  (unregister-all-keys!)
  (hide-overlay)
  (set! modal-active? #f)
  (set! modal-current-node #f)
  (set! modal-root-node #f)
  (set! modal-current-path '())
  (set! modal-leader-keycode #f))

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
