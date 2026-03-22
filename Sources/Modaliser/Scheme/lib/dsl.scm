;; lib/dsl.scm — User-facing DSL functions
;;
;; Pure Scheme replacements for the Swift ModaliserDSLLibrary.
;; These produce alist nodes for the command tree.

;; (key k label action) → command alist
(define (key k label action)
  (list (cons 'kind 'command)
        (cons 'key k)
        (cons 'label label)
        (cons 'action action)))

;; (group k label . children) → group alist
(define (group k label . children)
  (list (cons 'kind 'group)
        (cons 'key k)
        (cons 'label label)
        (cons 'children children)))

;; (selector k label . props) → selector alist
(define (selector k label . props)
  (let loop ((rest props) (entries (list (cons 'kind 'selector)
                                         (cons 'key k)
                                         (cons 'label label))))
    (if (or (null? rest) (null? (cdr rest)))
      (reverse entries)
      (loop (cdr (cdr rest))
            (cons (cons (car rest) (car (cdr rest))) entries)))))

;; (action name . props) → action alist
(define (action name . props)
  (let loop ((rest props) (entries (list (cons 'name name))))
    (if (or (null? rest) (null? (cdr rest)))
      (reverse entries)
      (loop (cdr (cdr rest))
            (cons (cons (car rest) (car (cdr rest))) entries)))))

;; (define-tree scope . children) → registers tree
;; scope: symbol or string (e.g. 'global, 'com.apple.Safari)
(define (define-tree scope . children)
  (apply register-tree! scope children))

;; (set-theme! . args) → no-op stub for backward compatibility
;; Theming moves to CSS in Phase 3.
(define (set-theme! . args) (void))

;; (set-leader! keycode) or (set-leader! 'mode keycode) → registers a hotkey
;; The two-arg form is backward compatible with the old API.
;; 'global → always uses the global tree
;; 'local  → uses the app-specific tree for the focused app
;; Single-arg form defaults to global-with-app-fallback.
(define (set-leader! first . rest)
  (if (null? rest)
    ;; Single arg: keycode only, default behavior
    (register-hotkey! first (make-leader-handler first #f))
    ;; Two args: mode + keycode
    (let ((mode first)
          (keycode (car rest)))
      (register-hotkey! keycode (make-leader-handler keycode mode)))))
