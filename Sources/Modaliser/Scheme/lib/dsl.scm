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

;; (define-tree scope . children) → registers tree
;; scope: symbol or string (e.g. 'global, 'com.apple.Safari)
(define (define-tree scope . children)
  (apply register-tree! scope children))

;; (set-leader! keycode) → registers a hotkey that activates modal
;; When pressed: looks up focused app, finds tree, enters modal.
(define (set-leader! keycode)
  (register-hotkey! keycode (make-leader-handler keycode)))
