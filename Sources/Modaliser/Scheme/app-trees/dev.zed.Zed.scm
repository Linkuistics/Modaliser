;; Zed (dev.zed.Zed) — F17 local tree.
;;
;; Shortcuts confirmed against zed.dev/docs (default macOS keymap).
;; Included from config.scm via (include "app-trees/dev.zed.Zed.scm");
;; inherits its imports.

(screen 'dev.zed.Zed

  (key "p" "File Finder"     (λ () (send-keystroke '(cmd) "p")))
  (key "P" "Command Palette" (λ () (send-keystroke '(cmd shift) "p")))
  (key "/" "Project Search"  (λ () (send-keystroke '(cmd shift) "f")))
  (key "f" "Find in File"    (λ () (send-keystroke '(cmd) "f")))
  (key "e" "Project Panel"   (λ () (send-keystroke '(cmd shift) "e")))
  (key "t" "Terminal"        (λ () (send-keystroke '(ctrl) "`"))))
