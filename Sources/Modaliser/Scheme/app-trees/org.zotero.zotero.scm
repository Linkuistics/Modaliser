;; Zotero (org.zotero.zotero) — F17 local tree.
;;
;; Deliberately small: most Zotero shortcuts are user-customizable in
;; Settings → Advanced, so only the stable ⌘F / ⌘⇧F search bindings are
;; surfaced here. Add your own as you set them.
;; Included from config.scm via (include "app-trees/org.zotero.zotero.scm").

(screen 'org.zotero.zotero

  (key "/" "Quick Search"    (λ () (send-keystroke '(cmd) "f")))
  (key "a" "Advanced Search" (λ () (send-keystroke '(cmd shift) "f"))))
