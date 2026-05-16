;; (modaliser leader) — Small conveniences around set-leader!.
;;
;; (set-global-leader! keycode opts...)  — shorthand for set-leader! 'global.
;; (set-local-leader!  keycode opts...)  — shorthand for set-leader! 'local.
;; (set-leaders! opts...)                — set both scopes in one call. Options:
;;     'global-keycode, 'local-keycode   — keycodes (e.g. F18, F17). Either
;;                                         may be omitted to skip that scope.
;;     'modifiers, 'arm-when-frontmost   — passed verbatim to both calls.
;;
;; The shared options apply to both scopes. If you need scope-asymmetric
;; options, call (set-global-leader! …) and (set-local-leader! …) directly.

(define-library (modaliser leader)
  (export set-global-leader!
          set-local-leader!
          set-leaders!)
  (import (scheme base)
          (modaliser dsl)
          (modaliser util))
  (begin

    (define (set-global-leader! keycode . opts)
      (apply set-leader! 'global keycode opts))

    (define (set-local-leader! keycode . opts)
      (apply set-leader! 'local keycode opts))

    (define (set-leaders! . opts)
      (let* ((alist           (apply props->alist opts))
             (global-keycode  (alist-ref alist 'global-keycode #f))
             (local-keycode   (alist-ref alist 'local-keycode #f))
             ;; Build the shared keyword/value list, skipping the two
             ;; keycode pairs (which are scope-routing, not pass-through).
             (shared
               (let loop ((kvs opts) (acc '()))
                 (cond
                   ((null? kvs) (reverse acc))
                   ((null? (cdr kvs))
                    (error "set-leaders!: odd keyword/value list"))
                   ((or (eq? (car kvs) 'global-keycode)
                        (eq? (car kvs) 'local-keycode))
                    (loop (cddr kvs) acc))
                   (else
                    (loop (cddr kvs)
                          (cons (cadr kvs) (cons (car kvs) acc))))))))
        (when global-keycode
          (apply set-leader! 'global global-keycode shared))
        (when local-keycode
          (apply set-leader! 'local local-keycode shared))))))
