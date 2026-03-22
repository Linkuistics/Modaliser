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
         (begin (modal-handle-key char) #t)
         (begin (modal-exit) #t))))))

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
                     ((eq? mode 'local)  (and bundle-id (lookup-tree bundle-id)))
                     (else (or (and bundle-id (lookup-tree bundle-id))
                               (lookup-tree "global"))))))
        (when tree
          (modal-enter tree leader-kc))))))
