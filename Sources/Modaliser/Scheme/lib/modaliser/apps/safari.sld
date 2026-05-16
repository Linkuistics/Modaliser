;; (modaliser apps safari) — minimal Safari per-app tree.
;;
;;   (safari-register!)                 ; defaults
;;   (safari-register! 'extra-bindings (list (key "/" "Search" …)))

(define-library (modaliser apps safari)
  (export safari-tree
          safari-register!)
  (import (scheme base)
          (modaliser dsl)
          (modaliser util)
          (modaliser input))
  (begin

    (define (keystroke mods key-name)
      (lambda () (send-keystroke mods key-name)))

    (define (safari-tree . opts)
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

    (define (safari-register! . opts)
      (apply define-tree 'com.apple.Safari (apply safari-tree opts)))))
