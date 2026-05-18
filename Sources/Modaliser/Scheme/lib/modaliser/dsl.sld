;; (modaliser dsl) — User-facing DSL.
;;
;; This is the surface user configs import:
;;
;;   (import (modaliser dsl))
;;
;; Then write (key …), (group …), (selector …), (action …),
;; (define-tree …), (set-leader! …) etc. directly in their config.scm
;; or in their own .sld libraries. The library is portable: imports
;; only (scheme …) and other (modaliser …) — no host-specific libraries.

(define-library (modaliser dsl)
  (export key key-range group selector action
          category
          define-tree set-theme!
          modifier-symbols->mask set-leader!
          ;; Re-exported from (modaliser state-machine) so user configs
          ;; can do a single (import (modaliser dsl)) for the common case.
          set-host-header! set-overlay-delay! set-overlay-aspect-ratio!)
  (import (scheme base)
          (scheme bitwise)
          (modaliser state-machine)
          (modaliser event-dispatch)
          (modaliser keyboard))
  (begin

;; Pure Scheme node constructors for the command tree. These produce
;; alist nodes consumed by the modal state machine.

;; (key k label action [keyword value]...) → command alist
;;
;; Optional trailing keyword/value pairs:
;;   'sticky-target MODE-ID — after running `action`, transition modal
;;                            navigation into the sticky tree registered
;;                            under MODE-ID (a symbol). Equivalent to
;;                            having the action end with
;;                            (enter-mode! MODE-ID), but declarative so
;;                            the overlay renders a marker on the cell.
;;                            Composes with sticky ancestors (overrides
;;                            transient/sticky cleanup on this command).
(define (key k label action . opts)
  (let loop ((rest opts) (acc (list (cons 'kind 'command)
                                    (cons 'key k)
                                    (cons 'label label)
                                    (cons 'action action))))
    (cond
      ((null? rest) acc)
      ((or (null? (cdr rest)) (not (symbol? (car rest))))
       (error "key: expected trailing keyword/value pairs" rest))
      ((eq? (car rest) 'sticky-target)
       (loop (cddr rest) (cons (cons 'sticky-target (cadr rest)) acc)))
      (else
       (error "key: unknown keyword" (car rest))))))

;; (key-range display-key label keys action-fn) → range-command alist
;;
;; Binds multiple keys to a single shared action, displayed as one row in the
;; overlay. Useful for sequences like "1..9 Space <n>" or "a..p Pane <n>"
;; where listing every key would clutter the overlay.
;;
;;   display-key : string shown in the overlay's key column (e.g. "1..9").
;;                 Purely cosmetic — the actual dispatch keys are in `keys`.
;;   label       : string shown in the overlay's label column (e.g.
;;                 "Space <n>"). The <n> is literal text, not a placeholder
;;                 the system substitutes — readers infer "n varies per key".
;;   keys        : non-empty list of single-char key strings to bind. A
;;                 sibling (key …) for the same character wins, so a literal
;;                 binding can override one slot of a range.
;;   action-fn   : (lambda (matched-key) ...) — invoked with the actual key
;;                 string that fired the binding, so the action can vary per
;;                 key (e.g. switch space N) while sharing one closure.
(define (key-range display-key label keys action-fn)
  (list (cons 'kind 'range-command)
        (cons 'key display-key)
        (cons 'keys keys)
        (cons 'label label)
        (cons 'action action-fn)))

;; (group k label [keyword value]... . children) → group alist
;;
;; Optional leading keyword/value pairs. Recognized keywords:
;;   'on-enter THUNK        — called when modal navigates into this group
;;   'on-leave THUNK        — called when modal navigates out of this group
;;   'sticky          BOOL  — firing a command leaf at or below this group
;;                            returns navigation to this group instead of
;;                            exiting the modal. Composes with sticky
;;                            ancestors: the deepest sticky group on the
;;                            current path wins. See register-tree!'s
;;                            'sticky doc for full semantics.
;;   'exit-on-unknown BOOL  — unrecognised keys at or below this group
;;                            dismiss the modal instead of being swallowed.
;;                            Useful for sticky focus-movement modes where
;;                            typing a non-binding key should hand control
;;                            back to the underlying app.
;;
;; Args after the keyword pairs are children. Disambiguation: a child node
;; is always a pair whose first element is a pair (alist starting with
;; (kind . ...)); a keyword is a bare symbol. So leading bare symbols start
;; the keyword tail and the first non-symbol begins the children.
(define (group k label . rest)
  (let loop ((args rest)
             (on-enter #f) (on-leave #f)
             (sticky #f) (exit-unk #f)
             (extras '())            ; reverse-accumulated alist of unknown kw/val pairs
             (children '()))
    (cond
      ((null? args)
        (let* ((acc (list (cons 'kind 'group)
                          (cons 'key k)
                          (cons 'label label)
                          (cons 'children (reverse children))))
               (acc (if exit-unk    (cons (cons 'exit-on-unknown exit-unk) acc) acc))
               (acc (if sticky      (cons (cons 'sticky sticky)            acc) acc))
               (acc (if on-leave    (cons (cons 'on-leave on-leave)        acc) acc))
               (acc (if on-enter    (cons (cons 'on-enter on-enter)        acc) acc))
               (acc (append (reverse extras) acc)))   ; extras carried through as-is
          acc))
      ((and (symbol? (car args)) (not (null? (cdr args))))
       (case (car args)
         ((on-enter)        (loop (cddr args) (cadr args) on-leave sticky exit-unk extras children))
         ((on-leave)        (loop (cddr args) on-enter (cadr args) sticky exit-unk extras children))
         ((sticky)          (loop (cddr args) on-enter on-leave (cadr args) exit-unk extras children))
         ((exit-on-unknown) (loop (cddr args) on-enter on-leave sticky (cadr args) extras children))
         (else
           ;; Unknown keyword — accumulate as opaque alist entry.
           ;; Used by renderer-style extensions like 'renderer 'diagram 'panels (...).
           (loop (cddr args) on-enter on-leave sticky exit-unk
                 (cons (cons (car args) (cadr args)) extras)
                 children))))
      (else
       ;; Positional child node.
       (loop (cdr args) on-enter on-leave sticky exit-unk extras
             (cons (car args) children))))))

;; (category label . children) → category alist
;;
;; Category nodes group a slice of group children under a label for
;; rendering by the (modaliser blocks which-key) block. The state machine
;; treats them as TRANSPARENT for dispatch: find-child descends through
;; category nodes as if their children were hoisted into the parent.
;; This lets configs add visual grouping without changing key paths.
(define (category label . children)
  (list (cons 'kind 'category)
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
(define (set-theme! . args) (if #f #f))

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
;;   'arm-when-frontmost <strs>             ; bundle IDs that trigger pass-and-arm
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
    (let loop ((rest tail) (mod-mask 0) (arm-bundle-ids '()))
      (cond
        ((null? rest)
         (register-hotkey! keycode
                           (make-leader-handler keycode mode)
                           mod-mask
                           arm-bundle-ids))
        ((eq? (car rest) 'modifiers)
         (loop (cddr rest) (modifier-symbols->mask (cadr rest)) arm-bundle-ids))
        ((eq? (car rest) 'arm-when-frontmost)
         (loop (cddr rest) mod-mask (cadr rest)))
        (else
         (error "set-leader!: unknown keyword" (car rest)))))))

)) ;; end begin / define-library
