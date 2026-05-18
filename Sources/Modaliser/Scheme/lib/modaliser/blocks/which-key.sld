;; (modaliser blocks which-key) — which-key block constructor.
;;
;; (make-which-key-block) returns a marker spec; the block has no
;; spec-level data. At render time the block-list renderer in
;; ui/overlay.scm walks the parent group's children, filters out keys
;; claimed by any sibling block via 'consumed-keys, partitions what
;; remains into (misc | category) segments preserving source order,
;; and emits the payload below.
;;
;; The render-time partitioning lives in ui/overlay.scm because that's
;; where the parent group is in scope. This library only exposes the
;; constructor + asset registration.

(define-library (modaliser blocks which-key)
  (export make-which-key-block)
  (import (scheme base)
          (modaliser overlay-assets))
  (begin

    (define (make-which-key-block)
      (list (cons 'type 'which-key)))

    (add-overlay-asset-file! 'css "lib/modaliser/blocks/which-key.css")
    (add-overlay-asset-file! 'js  "lib/modaliser/blocks/which-key.js")))
