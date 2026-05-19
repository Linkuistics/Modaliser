;; (modaliser blocks window-diagram) — block constructor for the
;; window-diagram block type. Used by the block-list renderer; co-located
;; with its JS + CSS so the asset trio lives in one directory.
;;
;; (make-window-diagram-block panel-specs) → block-spec alist
;;
;; panel-specs is a list of panel-spec alists in the camelCase shape the
;; JS renderer expects (see window-actions.sld's js-cell). Returns an
;; alist with:
;;   'type    — 'window-diagram
;;   'panels  — verbatim panel-specs (carried through to JS)
;;
;; The block does NOT carry dispatch children itself. Use
;; (window:layout-block …) from (modaliser window-actions) when you
;; want the panel cells to also dispatch (move-window …) actions — that
;; wrapper bundles the panel-spec with the matching key bindings via
;; the 'block-children field.

(define-library (modaliser blocks window-diagram)
  (export make-window-diagram-block)
  (import (scheme base)
          (modaliser overlay-assets))
  (begin

    (define (make-window-diagram-block panels)
      (list (cons 'type 'window-diagram)
            (cons 'panels panels)))

    (add-overlay-asset-file! 'css "lib/modaliser/blocks/window-diagram.css")
    (add-overlay-asset-file! 'js  "lib/modaliser/blocks/window-diagram.js")))
