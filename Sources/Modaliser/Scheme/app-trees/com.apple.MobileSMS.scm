;; Apple Messages (com.apple.MobileSMS) — F17 local tree.
;;
;; Included from config.scm via
;; (include "app-trees/com.apple.MobileSMS.scm"); inherits its imports.

(screen 'com.apple.MobileSMS

  (key "n" "New Message" (λ () (send-keystroke '(cmd) "n")))
  (key "f" "Find"        (λ () (send-keystroke '(cmd) "f")))

  ;; Conversation Walk: j/k step through the conversation list and
  ;; stay armed (each carries 'next 'self); any other key exits.
  ;; ⚠️ next/prev-conversation shortcuts are unverified — confirm in
  ;; Messages (Window menu) and adjust the two "verify" lines if needed.
  (group "c" "Conversations"
    'exit-on-unknown #t
    (key "j" "Next" (λ () (send-keystroke '(cmd shift) "]")) 'next 'self)    ; verify
    (key "k" "Prev" (λ () (send-keystroke '(cmd shift) "[")) 'next 'self)))  ; verify
