;; Apple Mail (com.apple.mail) — F17 local tree.
;;
;; Included from config.scm via (include "app-trees/com.apple.mail.scm");
;; inherits its imports. Bindings emit Mail's native menu shortcuts.

(screen 'com.apple.mail

  (key "n" "New Message"   (λ () (send-keystroke '(cmd) "n")))
  (key "r" "Reply"         (λ () (send-keystroke '(cmd) "r")))
  (key "R" "Reply All"     (λ () (send-keystroke '(cmd shift) "r")))
  (key "f" "Forward"       (λ () (send-keystroke '(cmd shift) "f")))
  (key "u" "Toggle Unread" (λ () (send-keystroke '(cmd shift) "u")))
  (key "j" "Mark as Junk"  (λ () (send-keystroke '(cmd shift) "j")))
  (key "g" "Get New Mail"  (λ () (send-keystroke '(cmd shift) "n")))
  (key "/" "Search"        (λ () (send-keystroke '(cmd alt) "f")))
  ;; ⌘⌫ moves the selected message to Trash.
  (key "d" "Delete"        (λ () (send-keystroke '(cmd) "backspace"))))
