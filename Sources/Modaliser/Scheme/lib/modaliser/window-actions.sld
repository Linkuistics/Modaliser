;; (modaliser window-actions) — window-management binding builder.
;;
;; Returns a group node containing the standard third/half/center moves
;; plus maximise/restore/center, and (optionally) a window switcher.
;; Compose with other groups in your config:
;;
;;   (import (modaliser dsl) (modaliser window-actions))
;;   (define-tree 'global
;;     (window-actions)
;;     (key "i" "iTerm" (lambda () (launch-app "iTerm"))))
;;
;; The convenience (window-actions-register!) registers a standalone
;; tree containing only the windows group — useful when you want
;; window helpers under a dedicated leader (a separate tree-scope).

(define-library (modaliser window-actions)
  (export window-actions
          window-actions-register!)
  (import (scheme base)
          (modaliser dsl)
          (modaliser util)
          (modaliser window))
  (begin

    (define (window-actions . opts)
      (let* ((alist        (apply props->alist opts))
             (group-key    (alist-ref alist 'key "w"))
             (group-label  (alist-ref alist 'label "Windows"))
             (include-sw?  (alist-ref alist 'include-switcher? #t))
             (extra        (alist-ref alist 'extra-bindings '()))
             (core
               (list
                 (key "d" "First Third"
                   (lambda () (move-window 0 0 1/3 1)))
                 (key "D" "First Third Top"
                   (lambda () (move-window 0 0 1/3 1/2)))
                 (key "C" "First Third Bottom"
                   (lambda () (move-window 0 1/2 1/3 1/2)))
                 (key "f" "Center Third"
                   (lambda () (move-window 1/3 0 1/3 1)))
                 (key "F" "Center Third Top"
                   (lambda () (move-window 1/3 0 1/3 1/2)))
                 (key "V" "Center Third Bottom"
                   (lambda () (move-window 1/3 1/2 1/3 1/2)))
                 (key "g" "Last Third"
                   (lambda () (move-window 2/3 0 1/3 1)))
                 (key "G" "Last Third Top"
                   (lambda () (move-window 2/3 0 1/3 1/2)))
                 (key "B" "Last Third Bottom"
                   (lambda () (move-window 2/3 1/2 1/3 1/2)))
                 (key "e" "First Two Thirds"
                   (lambda () (move-window 0 0 2/3 1)))
                 (key "t" "Last Two Thirds"
                   (lambda () (move-window 1/3 0 2/3 1)))
                 (key "c" "Center"
                   (lambda () (center-window)))
                 (key "m" "Maximise"
                   (lambda () (toggle-fullscreen)))
                 (key "r" "Restore"
                   (lambda () (restore-window)))))
             (switcher
               (if include-sw?
                 (list
                   (selector "s" "Select Window"
                     'prompt "Select window…"
                     'source list-windows
                     'on-select focus-window
                     'actions
                       (list
                         (action "Focus" 'description "Select window" 'key 'primary
                           'run (lambda (c) (focus-window c))))))
                 '())))
        (apply group group-key group-label
               (append core switcher extra))))

    (define (window-actions-register! . opts)
      (let* ((alist (apply props->alist opts))
             (scope (alist-ref alist 'tree-scope 'global)))
        (define-tree scope (apply window-actions opts))))))
