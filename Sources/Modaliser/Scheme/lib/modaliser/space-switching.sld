;; (modaliser space-switching) — Bind digits 1..N to macOS Space switching.
;;
;; Requires "Mission Control → Switch to Desktop N" enabled in
;; System Settings → Keyboard → Keyboard Shortcuts. The default sends
;; Ctrl+<n>; pass 'modifiers '(ctrl) (or whatever you prefer) to change.
;;
;; Returns a (key-range …) node that displays as one overlay row, e.g.
;; "1..9 Goto Space <n>". Splice into your tree:
;;
;;   (define-tree 'global
;;     (spaces-range-binding)
;;     ...)
;;
;; The overlay row collapses to "1.. Goto Space <n>" by default — the
;; open-ended ".." matches the seed's compact look. Override with
;; 'display-key for a closed range (e.g. "1..9").

(define-library (modaliser space-switching)
  (export spaces-range-binding
          spaces-1-9-register!)
  (import (scheme base)
          (modaliser dsl)
          (modaliser util)
          (modaliser input))
  (begin

    (define default-keys
      (list "1" "2" "3" "4" "5" "6" "7" "8" "9"))

    (define (spaces-range-binding . opts)
      (let* ((alist        (apply props->alist opts))
             (keys         (alist-ref alist 'keys default-keys))
             (label        (alist-ref alist 'label "Goto Space <n>"))
             (modifiers    (alist-ref alist 'modifiers '(ctrl)))
             (default-disp (string-append (car keys) ".."))
             (display      (alist-ref alist 'display-key default-disp)))
        (key-range display label keys
          (lambda (k) (send-keystroke modifiers k)))))

    (define (spaces-1-9-register! . opts)
      (let* ((alist (apply props->alist opts))
             (scope (alist-ref alist 'tree-scope 'global)))
        (define-tree scope (apply spaces-range-binding opts))))))
