;; Signal (org.whispersystems.signal-desktop) — F17 local tree.
;;
;; ⚠️ Unverified: Signal's official shortcut page blocks scraping, so the
;; new/search/find bindings below are best-guess. Confirm them against
;; Signal → Help → Show Keyboard Shortcuts and adjust if wrong; the lines
;; tagged "verify" are the ones to check.
;;
;; Included from config.scm via
;; (include "app-trees/org.whispersystems.signal-desktop.scm").

(screen 'org.whispersystems.signal-desktop

  (key "n" "New Message"          (λ () (send-keystroke '(cmd) "n")))        ; verify
  (key "/" "Search"               (λ () (send-keystroke '(cmd shift) "f"))) ; verify
  (key "f" "Find in Conversation" (λ () (send-keystroke '(cmd) "f")))       ; verify
  (key "," "Preferences"          (λ () (send-keystroke '(cmd) ","))))
