;; Obsidian (md.obsidian) — F17 local tree.
;;
;; Default hotkeys (all remappable in Obsidian → Settings → Hotkeys).
;; Included from config.scm via (include "app-trees/md.obsidian.scm");
;; inherits its imports.

(screen 'md.obsidian

  (key "o" "Quick Switcher"   (λ () (send-keystroke '(cmd) "o")))
  (key "p" "Command Palette"  (λ () (send-keystroke '(cmd) "p")))
  (key "n" "New Note"         (λ () (send-keystroke '(cmd) "n")))
  (key "/" "Search All Files" (λ () (send-keystroke '(cmd shift) "f")))
  (key "f" "Find in File"     (λ () (send-keystroke '(cmd) "f")))
  (key "g" "Graph View"       (λ () (send-keystroke '(cmd) "g"))))
