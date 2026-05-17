;; (modaliser apps chrome) — minimal Google Chrome per-app tree.
;;
;; Recommended import is prefix-style (bare exports collide with peers):
;;   (import (prefix (modaliser apps chrome) chrome:))
;;   (chrome:register!)                 ; defaults
;;   (chrome:register! 'extra-bindings (list (key "/" "Search" …)))

(define-library (modaliser apps chrome)
  (export tree
          register!)
  (import (scheme base)
          (modaliser dsl)
          (modaliser util)
          (modaliser input))
  (begin

    (define (keystroke mods key-name)
      (lambda () (send-keystroke mods key-name)))

    (define (tree . opts)
      (let* ((alist (apply props->alist opts))
             (extra (alist-ref alist 'extra-bindings '())))
        (append
          (list
            (group "t" "Tabs"
              (key "n" "New Tab"           (keystroke '(cmd) "t"))
              (key "w" "Close Tab"         (keystroke '(cmd) "w"))
              (key "r" "Reopen Closed Tab" (keystroke '(cmd shift) "t")))
            (group "b" "Browser"
              (key "l" "Focus Address Bar" (keystroke '(cmd) "l"))
              (key "f" "Find on Page"      (keystroke '(cmd) "f"))))
          extra)))

    (define (register! . opts)
      (apply define-tree 'com.google.Chrome (apply tree opts)))))
