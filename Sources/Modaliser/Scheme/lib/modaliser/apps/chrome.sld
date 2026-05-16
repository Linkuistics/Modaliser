;; (modaliser apps chrome) — minimal Google Chrome per-app tree.
;;
;;   (chrome-register!)                 ; defaults
;;   (chrome-register! 'extra-bindings (list (key "/" "Search" …)))

(define-library (modaliser apps chrome)
  (export chrome-tree
          chrome-register!)
  (import (scheme base)
          (modaliser dsl)
          (modaliser util)
          (modaliser input))
  (begin

    (define (keystroke mods key-name)
      (lambda () (send-keystroke mods key-name)))

    (define (chrome-tree . opts)
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

    (define (chrome-register! . opts)
      (apply define-tree 'com.google.Chrome (apply chrome-tree opts)))))
