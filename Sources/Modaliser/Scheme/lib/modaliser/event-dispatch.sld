;; (modaliser event-dispatch) — Keyboard event dispatch into the modal
;; state machine. The catch-all key handler installed by modal-enter
;; lives here, as does the leader-key handler factory.
;;
;; modal-key-handler is installed into the state-machine via the
;; set-modal-key-handler! setter — Task 5 introduced that hook so
;; state-machine could be hermetic while event-dispatch was still an
;; include. Now that event-dispatch is itself a library, the install
;; runs at library-load time.

(define-library (modaliser event-dispatch)
  (export modal-key-handler
          local-context-suffix
          set-local-context-suffix!
          resolve-app-tree
          make-leader-handler)
  (import (scheme base)
          (scheme char)              ; string-upcase (used for shift handling)
          (modaliser keymap)
          (modaliser keyboard)
          (modaliser app)
          (modaliser state-machine))
  (begin

;; The catch-all key handler. Registered via (register-all-keys!) when
;; modal mode is entered, deregistered when it exits.
;;
;; Receives (keycode modifiers). Returns #t to suppress, #f to pass through.
(define (modal-key-handler keycode modifiers)
  (cond
    ;; Leader key toggle — exit modal (treated as a cancel)
    ((and modal-leader-keycode (= keycode modal-leader-keycode))
     (modal-exit 'cancel)
     #t)
    ;; Return — confirm-and-exit. Distinct from Escape so a leave hook can
    ;; commit an app-side interaction on Return and cancel it otherwise.
    ((= keycode RETURN)
     (modal-exit 'confirm)
     #t)
    ;; Escape — cancel-and-exit
    ((= keycode ESCAPE)
     (modal-exit 'cancel)
     #t)
    ;; Delete — step back
    ((= keycode DELETE)
     (modal-step-back)
     #t)
    ;; Cmd+anything — pass through to system
    ((has-cmd? modifiers)
     #f)
    ;; Regular key — map to character and handle. Modifiers build an
    ;; effective key string a binding can be declared on:
    ;;   - Shift on a letter upcases it ("h" → "H") — the case carries
    ;;     the shift, no prefix.
    ;;   - Shift on a non-letter (digit, symbol), where case can't, adds
    ;;     an "S-" prefix ("1" → "S-1").
    ;;   - Ctrl and Alt add "C-" / "M-" prefixes.
    ;; Order is C- M- S- so a fully-modified key reads "C-M-S-x". Cmd
    ;; is handled above (passthrough).
    (else
     (let ((char (keycode->char keycode)))
       (if char
         (let* ((shift?    (has-shift? modifiers))
                (alpha?    (not (string=? (string-upcase char)
                                          (string-downcase char))))
                (base      (cond
                             ((not shift?) char)
                             (alpha?       (string-upcase char))
                             (else         (string-append "S-" char))))
                (with-alt  (if (has-alt? modifiers)
                             (string-append "M-" base) base))
                (effective (if (has-ctrl? modifiers)
                             (string-append "C-" with-alt) with-alt)))
           (modal-handle-key effective) #t)
         (begin (modal-exit 'cancel) #t))))))

;; Hook: given the focused app's bundle ID, return a suffix string like
;; "/zellij" to try a more specific tree first, or #f to use the plain
;; bundle-id tree. User configs override this via (set-local-context-suffix! fn).
(define local-context-suffix-impl (lambda (bundle-id) #f))
(define (local-context-suffix bundle-id) (local-context-suffix-impl bundle-id))
(define (set-local-context-suffix! fn) (set! local-context-suffix-impl fn))

;; Resolve the per-app tree for a bundle ID, preferring a context-suffixed
;; variant (e.g. "com.googlecode.iterm2/zellij") when the suffix hook
;; returns one and that variant is registered.
(define (resolve-app-tree bundle-id)
  (and bundle-id
       (or (let ((suffix (local-context-suffix bundle-id)))
             (and suffix (lookup-tree (string-append bundle-id suffix))))
           (lookup-tree bundle-id))))

;; Create a leader key handler for a specific mode. `mode` is always
;; 'global or 'local — set-leader! requires it.
;; 'global → always uses the "global" tree
;; 'local  → uses the app-specific tree for the focused app; if that app
;;           has no tree, nothing opens — no fallback to the global tree.
;;
;; Pass-and-arm passthrough is implemented entirely in Swift (see
;; KeyboardHandlerRegistry). When the focused app is in arm-bundle-ids,
;; the dispatch layer arms a Swift-side state machine and returns
;; passThrough, *without* calling this handler. On the second trigger
;; within the arm window, Swift posts Escape, then calls this handler
;; — at which point Scheme just enters the local modal as for a normal
;; idle press.
(define (make-leader-handler leader-kc mode)
  (lambda ()
    (cond
      ((chooser-open?)
       (close-chooser))
      (modal-active?
       (modal-exit))
      (else
       (let* ((bundle-id (focused-app-bundle-id))
              (tree (cond
                      ((eq? mode 'global) (lookup-tree "global"))
                      ((eq? mode 'local)  (resolve-app-tree bundle-id))
                      (else (error "make-leader-handler: invalid mode" mode)))))
         (when tree
           (modal-enter tree leader-kc)))))))

;; Install modal-key-handler into the state-machine library's dispatch cell.
;; Runs at library-load time, after modal-key-handler is defined above.
(set-modal-key-handler! modal-key-handler)

)) ;; end begin / define-library
