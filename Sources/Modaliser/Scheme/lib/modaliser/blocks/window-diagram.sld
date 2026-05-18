;; (modaliser blocks window-diagram) — block constructor for the
;; window-diagram block type. Used by the block-list renderer; co-located
;; with its JS + CSS so the asset trio lives in one directory.
;;
;; (make-window-diagram-block panel-specs) → block-spec alist
;;
;; panel-specs is a list of panel-spec alists in the camelCase shape the
;; JS renderer expects (see window-actions.sld's js-cell). Returns an
;; alist with:
;;   'type           — 'window-diagram
;;   'panels         — verbatim panel-specs (carried through to JS)
;;   'consumed-keys  — every key painted on a cell/center/fill, used by
;;                     the which-key block to skip those keys when
;;                     rendering the entries list.

(define-library (modaliser blocks window-diagram)
  (export make-window-diagram-block)
  (import (scheme base)
          (modaliser overlay-assets))
  (begin

    ;; (panel-bound-keys panels) → list of strings
    ;; Mirrors the helper in ui/overlay.scm but lives here so the block is
    ;; self-contained — the renderer reads 'consumed-keys off the spec
    ;; and doesn't need to know how to walk panels.
    (define (panel-bound-keys panels)
      (let loop ((ps panels) (acc '()))
        (cond
          ((null? ps) (reverse acc))
          (else
            (let* ((p (car ps))
                   (ptype (let ((e (assoc 'type p))) (and e (cdr e)))))
              (cond
                ((eq? ptype 'grid)
                 (let* ((cells-entry (assoc 'cells p))
                        (cells (and cells-entry (cdr cells-entry))))
                   (loop (cdr ps)
                         (let cells-loop ((cs (or cells '())) (a acc))
                           (cond
                             ((null? cs) a)
                             (else
                               (let* ((c (car cs))
                                      (ke (assoc 'key c))
                                      (k (and ke (cdr ke))))
                                 (cells-loop (cdr cs) (if k (cons k a) a)))))))))
                ((or (eq? ptype 'center) (eq? ptype 'fill))
                 (let* ((ke (assoc 'key p))
                        (k (and ke (cdr ke))))
                   (loop (cdr ps) (if k (cons k acc) acc))))
                (else (loop (cdr ps) acc))))))))

    (define (make-window-diagram-block panels)
      (list (cons 'type 'window-diagram)
            (cons 'panels panels)
            (cons 'consumed-keys (panel-bound-keys panels))))

    (add-overlay-asset-file! 'css "lib/modaliser/blocks/window-diagram.css")
    (add-overlay-asset-file! 'js  "lib/modaliser/blocks/window-diagram.js")))
