;; Slack (com.tinyspeck.slackmacgap) — F17 local tree.
;;
;; Included from config.scm via
;; (include "app-trees/com.tinyspeck.slackmacgap.scm"); inherits its
;; imports. Bindings emit Slack's documented keyboard shortcuts.

(screen 'com.tinyspeck.slackmacgap

  (key "k" "Jump to…"        (λ () (send-keystroke '(cmd) "k")))
  (key "d" "Direct Messages" (λ () (send-keystroke '(cmd shift) "k")))
  (key "/" "Search"          (λ () (send-keystroke '(cmd) "f")))
  (key "a" "All Unreads"     (λ () (send-keystroke '(cmd shift) "a")))
  (key "t" "Threads"         (λ () (send-keystroke '(cmd shift) "t")))
  (key "m" "Mentions"        (λ () (send-keystroke '(cmd shift) "m")))
  (key "h" "Back"            (λ () (send-keystroke '(cmd) "[")))
  (key "l" "Forward"         (λ () (send-keystroke '(cmd) "]")))
  ;; Esc marks the current channel/conversation as read.
  (key "e" "Mark Read"       (λ () (send-keystroke "escape"))))
