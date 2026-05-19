;; (modaliser blocks which-key) — which-key block constructor.
;;
;; (which-key-block . CHILDREN) returns a block spec carrying its
;; own children:
;;
;;   ((type . which-key) (block-children . (<child> ...)))
;;
;; Children may include (key …), (key-range …), (selector …),
;; (category …), or any node-alist accepted by the state machine.
;; Categories are rendered as labelled units; everything else flows as
;; misc rows in source order. Children are transparently flattened for
;; dispatch via state-machine.flatten-categories.
;;
;; The block-list renderer (ui/overlay.scm) reads block-children at
;; render time and partitions them into the misc/category segments the
;; JS expects. The parent `(window:overlay …)` constructor also lifts
;; block-children onto the group's 'children so find-child can dispatch
;; them.

(define-library (modaliser blocks which-key)
  (export which-key-block)
  (import (scheme base)
          (modaliser overlay-assets))
  (begin

    (define (which-key-block . children)
      (list (cons 'type 'which-key)
            (cons 'block-children children)))

    (add-overlay-asset-file! 'css "lib/modaliser/blocks/which-key.css")
    (add-overlay-asset-file! 'js  "lib/modaliser/blocks/which-key.js")))
