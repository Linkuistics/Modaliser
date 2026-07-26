;; (modaliser event-dispatch) — Keyboard event dispatch into the modal
;; state machine: the catch-all key handler installed by modal-activate!.
;;
;; modal-key-handler is installed into the modal façade via the
;; set-modal-key-handler! setter at library-load time (the façade is a
;; lower layer, so it cannot reference this library's binding directly).
;; Leader activation lives elsewhere: the handoff arms leaders whose
;; handlers resolve through resolve-activation against the installed
;; configuration value ((modaliser handoff), ADR-0018/ADR-0013) — the
;; entry-table/suffix-hook leader path this library used to own retired
;; at cutover-contract-k13.

(define-library (modaliser event-dispatch)
  (export modal-key-handler)
  (import (scheme base)
          (scheme char)              ; string-upcase (used for shift handling)
          (modaliser keymap)
          (modaliser keyboard)       ; keycode constants + keycode->char
          (modaliser fsm))
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
    ;; Return — when a list cursor is active and has a selection, ⏎ activates
    ;; the highlighted row (modal-list-cursor-activate! returns #t, consuming
    ;; the key). Otherwise Return confirm-exits — distinct from Escape so a
    ;; leave hook can commit an app-side interaction on Return and cancel it
    ;; otherwise.
    ((and (= keycode RETURN) (modal-list-cursor-activate!))
     #t)
    ((= keycode RETURN)
     (modal-exit 'confirm)
     #t)
    ;; ↑/↓ move the list selection cursor when one is active (keycode->char
    ;; doesn't map arrows, so they're matched by keycode here, not as chars).
    ;; modal-list-cursor-move! returns #f when no cursor is active, so the
    ;; clause falls through and the arrow drops to the no-char branch below
    ;; (which cancels — arrows aren't bindable keys).
    ((and (= keycode UP)   (modal-list-cursor-move! -1)) #t)
    ((and (= keycode DOWN) (modal-list-cursor-move! 1))  #t)
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

;; Install modal-key-handler into the modal façade's dispatch cell.
;; Runs at library-load time, after modal-key-handler is defined above.
(set-modal-key-handler! modal-key-handler)

)) ;; end begin / define-library
