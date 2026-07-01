;; Apple Messages (com.apple.MobileSMS) — F17 local tree.
;;
;; Included from config.scm via
;; (include "app-trees/com.apple.MobileSMS.scm"); inherits its imports.

(screen 'com.apple.MobileSMS

  (key "n" "New Message" (λ () (send-keystroke '(cmd) "n")))
  (key "f" "Find"        (λ () (send-keystroke '(cmd) "f")))

  ;; Sticky conversation walk: j/k step through the conversation list and
  ;; stay armed; any other key exits.
  ;; ⚠️ next/prev-conversation shortcuts are unverified — confirm in
  ;; Messages (Window menu) and adjust the two "verify" lines if needed.
  (group "c" "Conversations"
    'sticky #t
    'exit-on-unknown #t
    (key "j" "Next" (λ () (send-keystroke '(cmd shift) "]")))    ; verify
    (key "k" "Prev" (λ () (send-keystroke '(cmd shift) "[")))))  ; verify
