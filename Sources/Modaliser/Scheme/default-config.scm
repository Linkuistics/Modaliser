;; Modaliser configuration — first-run seed.
;;
;; Copied to ~/.config/modaliser/config.scm on first launch. Reads as a
;; tutorial of the bundled (modaliser …) libraries: the user picks a
;; theme colour and which library factories to splice into the global
;; tree. Tweak freely; restart Modaliser (or use the "," → "r" reload
;; binding) to see your changes.

(import (modaliser dsl)
        (modaliser keyboard)
        (modaliser input)
        (modaliser shell)
        (modaliser app)
        (modaliser pasteboard)
        (modaliser lifecycle)
        (modaliser leader)
        (modaliser settings-menu)
        (modaliser launchers)
        (modaliser window-actions)
        (modaliser space-switching)
        (modaliser apps safari)
        (modaliser apps iterm))

;; ─── Theme ───────────────────────────────────────────────────────

(define the-color "dodgerblue")

;; ─── Leader keys ─────────────────────────────────────────────────
;; F18 global, F17 local. arm-when-frontmost suppresses leader arming
;; while the Jump Desktop remote viewer is in front (its modifiers are
;; reserved for the remote machine).

(set-leaders! 'global-keycode F18
              'local-keycode  F17
              'arm-when-frontmost '("com.p5sys.jump.mac.viewer"))

(set-overlay-delay! 0.3)

;; Host header: 'name defaults to (run-shell "hostname -s"), 'foreground
;; defaults to "white" when 'background is set, so the seed only needs to
;; supply the theme colour.
(set-host-header! 'background the-color)

;; ─── Global command tree (F18) ───────────────────────────────────

(define-tree 'global

  (settings-menu-group)

  (switch-space-actions)

  ;; Quick-launch keys
  (key "b" "Browser - Dia"    (lambda () (launch-app "Dia")))
  (key "e" "Editor - Zed"     (lambda () (launch-app "Zed")))
  (key "t" "Terminal - iTerm" (lambda () (launch-app "iTerm")))

  (key "j" "Jump Desktop"  (lambda () (launch-app "Jump Desktop")))

  (key "c" "ChatGPT"        (lambda () (launch-app "ChatGPT")))
  (key "C" "Claude Desktop" (lambda () (launch-app "Claude")))

  (key "m" "Mail"  (lambda () (launch-app "Mail")))
  (key "n" "Notes" (lambda () (launch-app "Notes")))

  (key "o" "Obsidian" (lambda () (launch-app "Obsidian")))
  (key "z" "Zotero"   (lambda () (launch-app "Zotero")))

  (google-search-action)
  (find-application-action)
  (find-file-action)
  (window-actions))

;; ─── Per-app trees (F17 when that app is focused) ────────────────

(safari-register!)

;; iTerm: dynamic-pane tree + sticky 'iterm-panes-focus mode + context-
;; suffix handler. Only the chip background needs threading through;
;; everything else (label set, font, padding, etc.) defaults inside
;; the library.
(iterm-register!
  'hint-options (list (cons 'background the-color)))
