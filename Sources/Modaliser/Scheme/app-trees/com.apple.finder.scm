;; Finder (com.apple.finder) — F17 local tree.
;;
;; Curated Finder shortcuts surfaced in the overlay. Every binding emits
;; Finder's own menu shortcut via send-keystroke, so the tree tracks
;; whatever the app's menus do. Included from config.scm via
;; (include "app-trees/com.apple.finder.scm"); inherits its imports.
;;
;; A (screen …) whose body is only loose keys/groups renders them BARE in
;; a header-less loose region (no card): the keys as plain rows, the
;; View/Go groups as drill-down rows. There is no "General" panel.

(screen 'com.apple.finder

  (key "n" "New Window"        (λ () (send-keystroke '(cmd) "n")))
  (key "N" "New Folder"        (λ () (send-keystroke '(cmd shift) "n")))
  (key "g" "Go to Folder…"     (λ () (send-keystroke '(cmd shift) "g")))
  (key "i" "Get Info"          (λ () (send-keystroke '(cmd) "i")))
  (key "k" "Connect to Server" (λ () (send-keystroke '(cmd) "k")))
  (key "." "Toggle Hidden"     (λ () (send-keystroke '(cmd shift) ".")))

  ;; View modes — Finder maps ⌘1–4 to Icon / List / Column / Gallery.
  (group "v" "View"
    (key "i" "Icon"    (λ () (send-keystroke '(cmd) "1")))
    (key "l" "List"    (λ () (send-keystroke '(cmd) "2")))
    (key "c" "Column"  (λ () (send-keystroke '(cmd) "3")))
    (key "g" "Gallery" (λ () (send-keystroke '(cmd) "4"))))

  ;; Go menu — the standard ⌘⇧ / ⌘⌥ destinations.
  (group "o" "Go"
    (key "h" "Home"         (λ () (send-keystroke '(cmd shift) "h")))
    (key "a" "Applications" (λ () (send-keystroke '(cmd shift) "a")))
    (key "d" "Desktop"      (λ () (send-keystroke '(cmd shift) "d")))
    (key "l" "Downloads"    (λ () (send-keystroke '(cmd alt) "l")))
    (key "r" "Recents"      (λ () (send-keystroke '(cmd shift) "f")))
    (key "c" "Computer"     (λ () (send-keystroke '(cmd shift) "c")))))
