;; Telegram Desktop (com.tdesktop.Telegram) — F17 local tree.
;;
;; Shortcuts confirmed against the tdesktop keyboard-shortcuts reference.
;; Included from config.scm via
;; (include "app-trees/com.tdesktop.Telegram.scm"); inherits its imports.

(screen 'com.tdesktop.Telegram

  (key "k" "Jump to Chat"   (λ () (send-keystroke '(cmd) "k")))
  (key "/" "Search in Chat" (λ () (send-keystroke '(cmd) "f")))

  ;; Chats Walk — ⌘↑/⌘↓ step chats, ⌥⌘↑/↓ step unread chats. j/k stay
  ;; armed (each carries 'next 'self); any other key exits.
  (group "c" "Chats"
    'exit-on-unknown #t
    (key "j" "Next"        (λ () (send-keystroke '(cmd) "down")) 'next 'self)
    (key "k" "Prev"        (λ () (send-keystroke '(cmd) "up")) 'next 'self)
    (key "J" "Next Unread" (λ () (send-keystroke '(cmd alt) "down")) 'next 'self)
    (key "K" "Prev Unread" (λ () (send-keystroke '(cmd alt) "up")) 'next 'self)))
