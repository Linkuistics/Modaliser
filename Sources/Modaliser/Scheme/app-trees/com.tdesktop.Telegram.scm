;; Telegram Desktop (com.tdesktop.Telegram) — F17 local tree.
;;
;; Shortcuts confirmed against the tdesktop keyboard-shortcuts reference.
;; Included from config.scm via
;; (include "app-trees/com.tdesktop.Telegram.scm"); inherits its imports.

(screen 'com.tdesktop.Telegram

  (key "k" "Jump to Chat"   (λ () (send-keystroke '(cmd) "k")))
  (key "/" "Search in Chat" (λ () (send-keystroke '(cmd) "f")))

  ;; Sticky chat walk — ⌘↑/⌘↓ step chats, ⌥⌘↑/↓ step unread chats. j/k
  ;; stay armed; any other key exits.
  (group "c" "Chats"
    'sticky #t
    'exit-on-unknown #t
    (key "j" "Next"        (λ () (send-keystroke '(cmd) "down")))
    (key "k" "Prev"        (λ () (send-keystroke '(cmd) "up")))
    (key "J" "Next Unread" (λ () (send-keystroke '(cmd alt) "down")))
    (key "K" "Prev Unread" (λ () (send-keystroke '(cmd alt) "up")))))
