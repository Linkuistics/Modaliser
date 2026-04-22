;; core/event-dispatch.scm — Keyboard event dispatch
;;
;; The modal key handler that processes all keys while modal is active.
;; This replaces Swift's KeyEventDispatcher and SchemeModalBridge.

;; The catch-all key handler. Registered via (register-all-keys!) when
;; modal mode is entered, deregistered when it exits.
;;
;; Receives (keycode modifiers). Returns #t to suppress, #f to pass through.
(define (modal-key-handler keycode modifiers)
  (cond
    ;; Leader key toggle — exit modal
    ((and modal-leader-keycode (= keycode modal-leader-keycode))
     (modal-exit)
     #t)
    ;; Escape — exit modal
    ((= keycode ESCAPE)
     (modal-exit)
     #t)
    ;; Delete — step back
    ((= keycode DELETE)
     (modal-step-back)
     #t)
    ;; Cmd+anything — pass through to system
    ((has-cmd? modifiers)
     #f)
    ;; Regular key — map to character and handle
    (else
     (let ((char (keycode->char keycode)))
       (if char
         (let ((effective (if (has-shift? modifiers)
                            (string-upcase char)
                            char)))
           (modal-handle-key effective) #t)
         (begin (modal-exit) #t))))))

;; Hook: given the focused app's bundle ID, return a suffix string like
;; "/zellij" to try a more specific tree first, or #f to use the plain
;; bundle-id tree. User configs override this with their own definition.
(define (local-context-suffix bundle-id) #f)

;; Resolve the per-app tree for a bundle ID, preferring a context-suffixed
;; variant (e.g. "com.googlecode.iterm2/zellij") when the suffix hook
;; returns one and that variant is registered.
(define (resolve-app-tree bundle-id)
  (and bundle-id
       (or (let ((suffix (local-context-suffix bundle-id)))
             (and suffix (lookup-tree (string-append bundle-id suffix))))
           (lookup-tree bundle-id))))

;; Create a leader key handler for a given keycode.
;; When pressed, looks up the focused app's bundle ID, finds the
;; appropriate tree, and enters modal mode.
;; Create a leader key handler for a specific mode.
;; 'global → always uses the "global" tree
;; 'local  → uses the app-specific tree for the focused app (no fallback)
;; If mode is #f (single-arg set-leader!), behaves like global with app fallback.
(define (make-leader-handler leader-kc mode)
  (lambda ()
    (if modal-active?
      (modal-exit)
      (let* ((bundle-id (focused-app-bundle-id))
             (tree (cond
                     ((eq? mode 'global) (lookup-tree "global"))
                     ((eq? mode 'local)  (resolve-app-tree bundle-id))
                     (else (or (resolve-app-tree bundle-id)
                               (lookup-tree "global"))))))
        (when tree
          (modal-enter tree leader-kc))))))
