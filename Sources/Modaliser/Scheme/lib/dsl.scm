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

;; (group k label [keyword value]... . children) → group alist
;;
;; Optional leading keyword/value pairs. Recognized keywords:
;;   'on-enter THUNK  — called when modal navigates into this group
;;   'on-leave THUNK  — called when modal navigates out of this group
;;
;; Args after the keyword pairs are children. Disambiguation: a child node
;; is always a pair whose first element is a pair (alist starting with
;; (kind . ...)); a keyword is a bare symbol. So leading bare symbols start
;; the keyword tail and the first non-symbol begins the children.
(define (group k label . rest)
  (let loop ((args rest) (on-enter #f) (on-leave #f))
    (cond
      ((and (pair? args) (symbol? (car args)) (pair? (cdr args)))
       (case (car args)
         ((on-enter) (loop (cddr args) (cadr args) on-leave))
         ((on-leave) (loop (cddr args) on-enter (cadr args)))
         (else (error "group: unknown keyword" (car args)))))
      (else
        (let ((base (list (cons 'kind 'group)
                          (cons 'key k)
                          (cons 'label label)
                          (cons 'children args))))
          (let* ((with-leave (if on-leave
                               (cons (cons 'on-leave on-leave) base)
                               base))
                 (with-enter (if on-enter
                               (cons (cons 'on-enter on-enter) with-leave)
                               with-leave)))
            with-enter))))))

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

;; Convert a list of modifier symbols (e.g. '(shift ctrl)) to the integer
;; bitmask expected by register-hotkey!. Unknown symbols are ignored.
(define (modifier-symbols->mask syms)
  (let loop ((s syms) (mask 0))
    (cond
      ((null? s) mask)
      ((eq? (car s) 'cmd)   (loop (cdr s) (bitwise-ior mask MOD-CMD)))
      ((eq? (car s) 'shift) (loop (cdr s) (bitwise-ior mask MOD-SHIFT)))
      ((eq? (car s) 'alt)   (loop (cdr s) (bitwise-ior mask MOD-ALT)))
      ((eq? (car s) 'ctrl)  (loop (cdr s) (bitwise-ior mask MOD-CTRL)))
      (else (loop (cdr s) mask)))))

;; (set-leader! [mode] keycode [keyword value]...) → registers a hotkey
;;
;; Forms:
;;   (set-leader! keycode)                  ; default mode
;;   (set-leader! 'global keycode)
;;   (set-leader! 'local keycode)
;;
;; Optional trailing keyword/value pairs:
;;   'modifiers <symbol-list>               ; e.g. '(shift) or '(cmd alt)
;;   'passthrough-when-frontmost <strs>     ; bundle IDs that pass through
;;
;; Disambiguation: only 'global / 'local count as a leading mode arg —
;; other symbols (e.g. 'modifiers) start the keyword tail.
(define (set-leader! . args)
  (let-values
    (((mode keycode tail)
      (if (and (pair? args)
               (symbol? (car args))
               (or (eq? (car args) 'global) (eq? (car args) 'local)))
        (values (car args) (cadr args) (cddr args))
        (values #f (car args) (cdr args)))))
    (let loop ((rest tail) (mod-mask 0) (passthrough '()))
      (cond
        ((null? rest)
         (register-hotkey! keycode
                           (make-leader-handler keycode mode)
                           mod-mask
                           passthrough))
        ((eq? (car rest) 'modifiers)
         (loop (cddr rest) (modifier-symbols->mask (cadr rest)) passthrough))
        ((eq? (car rest) 'passthrough-when-frontmost)
         (loop (cddr rest) mod-mask (cadr rest)))
        (else
         (error "set-leader!: unknown keyword" (car rest)))))))
