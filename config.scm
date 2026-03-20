;; Modaliser configuration
;; This file is evaluated by the Scheme engine at startup.
;; DSL functions and native libraries are auto-imported.

;; Leader keys
(set-leader! 'global F18)
(set-leader! 'local F17)

;; Helper: open a URL
(define (open-url-action url)
  (lambda () (open-url url)))

;; Helper: send a keystroke to the focused app
(define (keystroke mods key-name)
  (lambda () (send-keystroke mods key-name)))

;; ─── Global command tree ────────────────────────────────────────────────

(define-tree 'global

  ;; Quick-launch keys
  (key "s" "Safari"
    (lambda () (launch-app "Safari")))
  (key "i" "iTerm"
    (lambda () (launch-app "iTerm")))
  (key "z" "Zed"
    (lambda () (launch-app "Zed")))
  (key " " "Spotlight"
    (keystroke '(cmd) " "))

  ;; Find group
  (group "f" "Find"
    (selector "a" "Find Apps"
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

    (key "e" "Emoji & Symbols"
      (open-url-action "raycast://extensions/raycast/emoji-symbols/search-emoji-symbols"))

    (selector "f" "Find File"
      'prompt "Find file…"
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

    (key "m" "Menu Items"
      (open-url-action "raycast://extensions/raycast/navigation/search-menu-items")))

  ;; Open application group
  (group "o" "Open App"
    (group "c" "C"
      (key "h" "ChatGPT"
        (lambda () (launch-app "ChatGPT")))
      (key "o" "Codex"
        (lambda () (launch-app "Codex")))
      (key "r" "Chrome"
        (lambda () (launch-app "Google Chrome"))))
    (key "g" "GitButler"
      (lambda () (launch-app "GitButler")))
    (key "j" "Jump Desktop"
      (lambda () (launch-app "Jump Desktop")))
    (group "m" "M"
      (key "a" "Mail"
        (lambda () (launch-app "Mail")))
      (key "e" "Messages"
        (lambda () (launch-app "Messages"))))
    (group "n" "N"
      (key "a" "Apple Notes"
        (lambda () (launch-app "Notes")))
      (key "r" "Raycast Notes"
        (open-url-action "raycast://extensions/raycast/raycast-notes/raycast-notes")))
    (key "o" "Obsidian"
      (lambda () (launch-app "Obsidian")))
    (group "s" "S"
      (key "a" "Safari"
        (lambda () (launch-app "Safari")))
      (key "i" "Signal"
        (lambda () (launch-app "Signal"))))
    (key "t" "Telegram"
      (lambda () (launch-app "Telegram")))
    (group "z" "Z"
      (key "e" "Zed"
        (lambda () (launch-app "Zed")))
      (key "o" "Zotero"
        (lambda () (launch-app "Zotero")))))

  ;; Reload group
  (group "r" "Reload"
    (key "r" "Reload Config"
      (lambda () (run-shell "echo 'Reload not yet implemented'"))))

  ;; Window management group
  (group "w" "Windows"
    (key "c" "Center"
      (lambda () (center-window)))
    (key "d" "First Third"
      (lambda () (move-window 0 0 1/3 1)))
    (key "e" "First Two Thirds"
      (lambda () (move-window 0 0 2/3 1)))
    (key "f" "Center Third"
      (lambda () (move-window 1/3 0 1/3 1)))
    (key "g" "Last Third"
      (lambda () (move-window 2/3 0 1/3 1)))
    (key "m" "Maximise"
      (lambda () (toggle-fullscreen)))
    (key "r" "Restore"
      (lambda () (restore-window)))
    (selector "s" "Switch Window"
      'prompt "Select window…"
      'source list-windows
      'on-select focus-window
      'actions
        (list
          (action "Focus" 'description "Switch to window" 'key 'primary
            'run (lambda (c) (focus-window c)))))
    (key "t" "Last Two Thirds"
      (lambda () (move-window 1/3 0 2/3 1))))

  ;; Raycast notes
  (key "n" "Raycast Notes"
    (open-url-action "raycast://extensions/raycast/raycast-notes/raycast-notes")))

;; ─── App-local command trees ────────────────────────────────────────────

;; Safari (F17 when Safari is focused)
(define-tree 'com.apple.Safari
  (group "t" "Tabs"
    (key "n" "New Tab"
      (keystroke '(cmd) "t"))
    (key "w" "Close Tab"
      (keystroke '(cmd) "w"))
    (key "r" "Reopen Closed Tab"
      (keystroke '(cmd shift) "t")))
  (group "b" "Browser"
    (key "l" "Focus Address Bar"
      (keystroke '(cmd) "l"))
    (key "f" "Find on Page"
      (keystroke '(cmd) "f"))))

;; Zed (F17 when Zed is focused)
(define-tree 'dev.zed.Zed
  (group "p" "Pane"
    (key "h" "Focus Left"
      (keystroke '(cmd alt) "left"))
    (key "l" "Focus Right"
      (keystroke '(cmd alt) "right"))
    (key "k" "Focus Up"
      (keystroke '(cmd alt) "up"))
    (key "j" "Focus Down"
      (keystroke '(cmd alt) "down")))
  (group "g" "Git"
    (key "p" "Command Palette"
      (keystroke '(cmd shift) "p")))
  (group "t" "Task"
    (key "r" "Run via Palette"
      (keystroke '(cmd shift) "p"))))

;; iTerm (F17 when iTerm is focused)
(define-tree 'com.googlecode.iterm2
  (group "t" "Tabs"
    (key "n" "New Tab"
      (keystroke '(cmd) "t"))
    (key "w" "Close Tab"
      (keystroke '(cmd) "w")))
  (group "p" "Pane"
    (key "h" "Focus Left"
      (keystroke '(cmd alt) "left"))
    (key "l" "Focus Right"
      (keystroke '(cmd alt) "right"))
    (key "k" "Focus Up"
      (keystroke '(cmd alt) "up"))
    (key "j" "Focus Down"
      (keystroke '(cmd alt) "down"))))
