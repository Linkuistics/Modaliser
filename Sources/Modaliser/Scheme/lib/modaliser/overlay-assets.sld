;; (modaliser overlay-assets) — library wrapper for the overlay's
;; asset-registration hook. Lets renderer libraries (diagram-panel,
;; future custom renderers) import add-overlay-asset! without depending
;; on the side-effecting top-level overlay.scm being loaded as a file.
;;
;; State stored here; overlay.scm reads via (overlay-assets-concat …).

(define-library (modaliser overlay-assets)
  (export add-overlay-asset!
          add-overlay-asset-file!
          overlay-assets-concat
          overlay-assets-set-resolver!)
  (import (scheme base)
          (modaliser util))
  (begin
    ;; Each entry is either ('inline . string) — a literal snippet —
    ;; or ('file . relative-path) — read on demand from disk. File
    ;; entries are needed because a library's begin block can't see
    ;; the top-level *scheme-directory* binding, so renderer
    ;; libraries can't resolve absolute paths at import time. The
    ;; resolver thunk is set by overlay.scm (top-level) and called
    ;; lazily when overlay-assets-concat runs.
    (define overlay-extra-css '())
    (define overlay-extra-js  '())
    (define overlay-asset-resolver (lambda (rel) rel))

    (define (overlay-assets-set-resolver! proc)
      (set! overlay-asset-resolver proc))

    (define (add-overlay-asset! kind text)
      (cond
        ((eq? kind 'css) (set! overlay-extra-css (append overlay-extra-css (list (cons 'inline text)))))
        ((eq? kind 'js)  (set! overlay-extra-js  (append overlay-extra-js  (list (cons 'inline text)))))
        (else (error "add-overlay-asset!: kind must be 'css or 'js" kind))))

    (define (add-overlay-asset-file! kind relative-path)
      (cond
        ((eq? kind 'css) (set! overlay-extra-css (append overlay-extra-css (list (cons 'file relative-path)))))
        ((eq? kind 'js)  (set! overlay-extra-js  (append overlay-extra-js  (list (cons 'file relative-path)))))
        (else (error "add-overlay-asset-file!: kind must be 'css or 'js" kind))))

    (define (resolve-entry entry)
      (case (car entry)
        ((inline) (cdr entry))
        ((file)   (read-file-text (overlay-asset-resolver (cdr entry))))
        (else "")))

    (define (overlay-assets-concat kind)
      (let ((items (case kind ((css) overlay-extra-css)
                              ((js)  overlay-extra-js)
                              (else '()))))
        (string-join (map resolve-entry items) "\n")))))
