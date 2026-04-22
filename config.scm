
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
  (key "c" "ChatGPT"
    (lambda () (launch-app "ChatGPT")))
  (key "i" "iTerm"
    (lambda () (launch-app "iTerm")))
  (key "j" "Jump Desktop"
    (lambda () (launch-app "Jump Desktop")))
  (key "z" "Zed"
    (lambda () (launch-app "Zed")))
  (key " " "Spotlight"
    (keystroke '(cmd) " "))
  (key "," "Settings"
    (lambda () (open-settings!)))

  ;; Google search
  (selector "g" "Google Search"
    'prompt "Search Google…"
    'dynamic-search web-search-handler
    'on-select web-search-on-select)

  (key "c" "ChatGPT"
    (lambda () (launch-app "ChatGPT")))

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
      (open-url-action "raycast://extensions/raycast/navigation/search-menu-items"))

    (selector "w" "Window"
        'prompt "Find window…"
        'source list-windows
        'on-select focus-window
        'actions
        (list
            (action "Focus" 'description "Switch to window" 'key 'primary
            'run (lambda (c) (focus-window c))))))

  ;; Open application group
  (group "o" "Open App"
    (group "c" "C"
      (key "h" "ChatGPT"
        (lambda () (launch-app "ChatGPT")))
      (key "m" "cmux"
        (lambda () (launch-app "cmux")))
      (key "o" "Codex"
        (lambda () (launch-app "Codex")))
      (key "r" "Chrome"
        (lambda () (launch-app "Google Chrome"))))
    (key "g" "GitButler"
      (lambda () (launch-app "GitButler")))
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
           (lambda () (launch-app "Signal")))
      (key "l" "Slack"
        (lambda () (launch-app "Slack"))))
    (key "t" "Telegram"
      (lambda () (launch-app "Telegram")))
    (key "w" "Wire"
      (lambda () (launch-app "Wire")))
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
    (key "d" "First Third"
      (lambda () (move-window 0 0 1/3 1)))
    (key "D" "First Third Top"
      (lambda () (move-window 0 0 1/3 1/2)))
    (key "C" "First Third Bottom"
      (lambda () (move-window 0 1/2 1/3 1/2)))
    (key "f" "Center Third"
      (lambda () (move-window 1/3 0 1/3 1)))
    (key "F" "Center Third Top"
      (lambda () (move-window 1/3 0 1/3 1/2)))
    (key "V" "Center Third Bottom"
      (lambda () (move-window 1/3 1/2 1/3 1/2)))
    (key "g" "Last Third"
      (lambda () (move-window 2/3 0 1/3 1)))
    (key "G" "Last Third Top"
      (lambda () (move-window 2/3 0 1/3 1/2)))
    (key "B" "Last Third Bottom"
      (lambda () (move-window 2/3 1/2 1/3 1/2)))
    (key "e" "First Two Thirds"
      (lambda () (move-window 0 0 2/3 1)))    
    (key "t" "Last Two Thirds"
      (lambda () (move-window 1/3 0 2/3 1)))
    (key "c" "Center"
      (lambda () (center-window)))
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
            'run (lambda (c) (focus-window c))))))

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
  (key "s" "Select (Terminal Vi Mode)"
    (keystroke '(ctrl shift) "space"))
  (group "t" "Task"
    (key "r" "Run via Palette"
      (keystroke '(cmd shift) "p"))))

;; iTerm (F17 when iTerm is focused)
;;
;; Two trees are registered: the plain iTerm tree, and a "/zellij" variant
;; that is selected by local-context-suffix when zellij is the foreground
;; process on iTerm's focused pane. The zellij variant adds a "z" key that
;; sends Ctrl+G to hand control to zellij's own modal/which-key.

(define iterm-bindings
  (list
    (group "t" "Tabs"
      (key "n" "New Tab"
        (keystroke '(cmd) "t"))
      (key "w" "Close Tab"
        (keystroke '(cmd) "w")))
    (key "s" "Select (Copy Mode)"
      (keystroke '(cmd shift) "c"))
    (group "p" "Pane"
      (key "h" "Focus Left"
        (keystroke '(cmd alt) "left"))
      (key "l" "Focus Right"
        (keystroke '(cmd alt) "right"))
      (key "k" "Focus Up"
        (keystroke '(cmd alt) "up"))
      (key "j" "Focus Down"
        (keystroke '(cmd alt) "down")))))

(apply define-tree 'com.googlecode.iterm2 iterm-bindings)

(apply define-tree 'com.googlecode.iterm2/zellij
  (append iterm-bindings
          (list (key "z" "Zellij (Ctrl+G)"
                  (keystroke '(ctrl) "g")))))

;; True when iTerm's focused pane has zellij (or the `zj` wrapper) as its
;; foreground process. Only called when iTerm is the focused app, so it
;; can't false-positive against zellij running in an unfocused window.
(define (iterm-running-zellij?)
  (let ((cmd (focused-terminal-foreground-command)))
    (and cmd
         (or (string-contains? cmd "zellij")
             (string-contains? cmd "zj")))))

;; Dispatcher hook: return a suffix to append to the bundle-id before tree
;; lookup. Used by event-dispatch.scm; returning #f falls through to the
;; plain bundle-id tree.
(define (local-context-suffix bundle-id)
  (cond
    ((and (equal? bundle-id "com.googlecode.iterm2")
          (iterm-running-zellij?))
     "/zellij")
    (else #f)))
