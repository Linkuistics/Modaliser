;; Modaliser configuration — first-run seed.
;;
;; This file is copied to ~/.config/modaliser/config.scm on first launch
;; and serves as a tutorial of the bundled (modaliser …) libraries.
;; Tweak freely; restart Modaliser (or use the "," → "r" reload binding)
;; to see your changes.

(import (modaliser dsl)
        (modaliser keyboard)
        (modaliser input)
        (modaliser shell)
        (modaliser app)
        (modaliser pasteboard)
        (modaliser lifecycle)
        (modaliser leader)
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

(set-host-header!
  'name       (run-shell "hostname -s")
  'background the-color
  'foreground "white")

;; ─── Global command tree (F18) ───────────────────────────────────

(define-tree 'global

  (group "," "Settings"
    (key "e" "Edit"
      (lambda ()
        (run-shell
          "/usr/bin/open -a Zed \"$HOME/.config/modaliser/config.scm\" || /usr/bin/open \"$HOME/.config/modaliser/config.scm\"")))
    (key "r" "Reload"
      (lambda () (relaunch!))))

  ;; macOS Spaces 1..9 via the system's Ctrl+digit shortcut.
  ;; Enable "Mission Control → Switch to Desktop N" in System Settings →
  ;; Keyboard → Keyboard Shortcuts for this to work.
  (spaces-range-binding 'display-key "1..")

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

  ;; Google search — uses web-search-handler / web-search-on-select from
  ;; the legacy lib/web-search.scm (still loaded via include in root.scm).
  (selector "g" "Google Search"
    'prompt "Search Google…"
    'dynamic-search web-search-handler
    'on-select web-search-on-select)

  (selector "a" "Applications"
    'prompt "Find app…"
    'source find-installed-apps
    'on-select activate-app
    'remember "apps"
    'id-field "bundleId"
    'actions
      (list
        (action "Open" 'description "Launch or focus" 'key 'primary
          'run (lambda (c) (activate-app c)))
        (action "Show in Finder" 'description "Reveal in Finder" 'key 'secondary
          'run (lambda (c) (reveal-in-finder c)))
        (action "Copy Path" 'description "Copy full path to clipboard"
          'run (lambda (c) (set-clipboard! (cdr (assoc 'path c)))))
        (action "Copy Bundle ID" 'description "Copy app bundle identifier"
          'run (lambda (c) (set-clipboard! (cdr (assoc 'bundleId c)))))))

  (selector "f" "Files"
    'prompt "File…"
    'file-roots (list "~")
    'on-select (lambda (c) (run-shell (string-append "/usr/bin/open \"" (cdr (assoc 'path c)) "\"")))
    'actions
      (list
        (action "Open" 'description "Open with default app" 'key 'primary
          'run (lambda (c) (run-shell (string-append "/usr/bin/open \"" (cdr (assoc 'path c)) "\""))))
        (action "Show in Finder" 'description "Reveal in Finder" 'key 'secondary
          'run (lambda (c) (reveal-in-finder c)))
        (action "Copy Path" 'description "Copy full path to clipboard"
          'run (lambda (c) (set-clipboard! (cdr (assoc 'path c)))))
        (action "Open in Zed" 'description "Open file in Zed editor"
          'run (lambda (c) (open-with "Zed" (cdr (assoc 'path c)))))))

  ;; Window management group — third/half/center/maximise/restore + selector.
  (window-actions-group))

;; ─── Per-app trees (F17 when that app is focused) ────────────────

(safari-register!)

;; iTerm: dynamic-pane tree + sticky 'iterm-panes-focus mode + context-
;; suffix handler. Override the chip background to thread the host theme
;; through to the pane chips. Defaults: digit pane labels (1..0), large
;; chips with a black border.
(iterm-register!
  'hint-options
    (list (cons 'offset-x-frac 0.02)
          (cons 'offset-y-frac 0.02)
          (cons 'font-size 56)
          (cons 'padding 16)
          (cons 'corner-radius 8)
          (cons 'color "white")
          (cons 'background the-color)
          (cons 'border-width 1)
          (cons 'border-color "black")))
