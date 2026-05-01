
;; Modaliser configuration
;; This file is evaluated by the Scheme engine at startup.
;; DSL functions and native libraries are auto-imported.

;; Leader keys
(set-leader! 'global F18 'passthrough-when-frontmost '("com.p5sys.jump.mac.viewer"))
(set-leader! 'global F18 'modifiers '(shift))

(set-leader! 'local F17 'passthrough-when-frontmost '("com.p5sys.jump.mac.viewer"))
(set-leader! 'local F17 'modifiers '(shift))

(set-overlay-delay! 0.3)

;; Identify this Modaliser instance in the overlay/chooser breadcrumb.
;; Useful when you run multiple instances simultaneously (e.g. a local
;; instance plus one on a remote host viewed via Jump Desktop / VNC).
;; Optional. All colour fields take any CSS colour value; separator-color
;; defaults to following the foreground when unset.
;;
;; (set-host-header!
;;   'name            (run-shell "hostname -s")
;;   'background      "#7a1f3d"
;;   'foreground      "#ffffff"
;;   'separator-color "#cccccc")

;; Helper: open a URL
(define (open-url-action url)
  (lambda () (open-url url)))

;; Helper: send a keystroke to the focused app
(define (keystroke mods key-name)
  (lambda () (send-keystroke mods key-name)))

;; Helper: split the focused WezTerm pane in the given direction
;; (one of "left", "right", "top", "bottom"). Queries the focused
;; pane via list-clients first because WEZTERM_PANE is not set when
;; modaliser shells out from outside any pane.
(define (wezterm-split direction)
  (lambda ()
    (run-shell
      (string-append
        "PANE=$(/opt/homebrew/bin/wezterm cli list-clients --format json"
        " | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)[0][\"focused_pane_id\"])')"
        " && /opt/homebrew/bin/wezterm cli split-pane --pane-id \"$PANE\" --" direction))))

;; ─── Global command tree ────────────────────────────────────────────────

(define-tree 'global

  ;; Quick-launch keys
  (key " " "Spotlight"
    (keystroke '(cmd) " "))
  (key "c" "ChatGPT"
    (lambda () (launch-app "ChatGPT")))
  (key "j" "Jump Desktop"
    (lambda () (launch-app "Jump Desktop")))
  (key "n" "Notes"
    (lambda () (launch-app "Notes")))
  (key "s" "Safari"
    (lambda () (launch-app "Safari")))
  (key "t" "Terminal (WezTerm)"
    (lambda () (launch-app "WezTerm")))
  (key "," "Settings"
    (lambda ()
      (run-shell
        "/usr/bin/open -a Zed \"$HOME/.config/modaliser/config.scm\" || /usr/bin/open \"$HOME/.config/modaliser/config.scm\"")))

  ;; Google search
  (selector "g" "Google Search"
    'prompt "Search Google…"
    'dynamic-search web-search-handler
    'on-select web-search-on-select)

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
    (group "g" "G"
      (key "b" "GitButler"
        (lambda () (launch-app "GitButler")))
      (key "h" "Ghostty"
        (lambda () (launch-app "Ghostty"))))
    (group "m" "M"
      (key "a" "Mail"
        (lambda () (launch-app "Mail")))
      (key "e" "Messages"
        (lambda () (launch-app "Messages"))))
    (key "n" "Notes"
        (lambda () (launch-app "Notes")))
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
    (key "w" "WezTerm"
      (lambda () (launch-app "WezTerm")))
    (group "z" "Z"
      (key "e" "Zed"
        (lambda () (launch-app "Zed")))
      (key "o" "Zotero"
        (lambda () (launch-app "Zotero")))))

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
            'run (lambda (c) (focus-window c)))))))

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

;; WezTerm (F17 when WezTerm is focused)
;;
;; Mirrors the iTerm-tree shape but uses WezTerm's native bindings. Pane
;; h/j/k/l fire Alt+hjkl, which routes through the alt_nav callback in
;; ~/.config/wezterm/wezterm.lua — so they work whether the focused pane
;; is nvim or a plain shell. Toggle Zoom mirrors the Cmd+Shift+Enter
;; binding defined there.
;;
;; Nvim-aware variants (analogous to com.googlecode.iterm2/nvim) can be
;; added later by registering com.github.wez.wezterm/nvim and extending
;; local-context-suffix below. Foreground-process probing in WezTerm can
;; use `wezterm cli list --format json`.
(define-tree 'com.github.wez.wezterm
  (group "t" "Tabs"
    (key "n" "New Tab"
      (keystroke '(cmd) "t"))
    (key "w" "Close Tab"
      (keystroke '(cmd) "w"))
    (key "]" "Next Tab"
      (keystroke '(cmd shift) "]"))
    (key "[" "Previous Tab"
      (keystroke '(cmd shift) "[")))
  (group "p" "Pane"
    (key "h" "Focus Left"
      (keystroke '(alt) "h"))
    (key "j" "Focus Down"
      (keystroke '(alt) "j"))
    (key "k" "Focus Up"
      (keystroke '(alt) "k"))
    (key "l" "Focus Right"
      (keystroke '(alt) "l"))
    (key "z" "Toggle Zoom"
      (keystroke '(cmd shift) "return"))
    (group "s" "Split"
      (key "h" "Split Left"  (wezterm-split "left"))
      (key "j" "Split Down"  (wezterm-split "bottom"))
      (key "k" "Split Up"    (wezterm-split "top"))
      (key "l" "Split Right" (wezterm-split "right"))))
  (key "s" "Select (Copy Mode)"
    (keystroke '(ctrl shift) "space")))

;; iTerm (F17 when iTerm is focused)
;;
;; Three trees are registered: the plain iTerm tree, a "/zellij" variant,
;; and a "/nvim" variant. local-context-suffix picks between them based on
;; what's actually running in the focused pane. Precedence: nvim wins over
;; zellij (so nvim-inside-zellij routes to /nvim), zellij wins over plain.
;;
;; Nvim focus detection (including nvim-inside-zellij) requires each nvim
;; to maintain the global g:modaliser_focused, which flips to 1 on
;; FocusGained and 0 on FocusLost. Nvim fires the events but doesn't
;; cache the state anywhere queryable via RPC, so we have to stash it
;; ourselves. On a LazyVim setup drop this into
;; ~/.config/nvim/lua/config/autocmds.lua (elsewhere just put it in
;; init.lua):
;;
;;   vim.g.modaliser_focused = 1
;;   vim.api.nvim_create_autocmd('FocusGained',
;;     { callback = function() vim.g.modaliser_focused = 1 end })
;;   vim.api.nvim_create_autocmd('FocusLost',
;;     { callback = function() vim.g.modaliser_focused = 0 end })
;;
;; iTerm2 and zellij both forward xterm focus-reporting escapes by
;; default, so exactly one nvim across the system reports 1 at any time.

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

;; Composable "additions" — keep each chunk separate so tree variants can
;; union them (e.g. zellij+nvim gets both the zellij and nvim tops).
(define zellij-additions
  (list (key "z" "Zellij (Ctrl+G)"
          (keystroke '(ctrl) "g"))))

(define nvim-additions
  (list (key "w" "Nvim :w (save)"
          (lambda () (nvim-remote-send ":w<CR>")))))

(apply define-tree 'com.googlecode.iterm2 iterm-bindings)
(apply define-tree 'com.googlecode.iterm2/zellij
  (append iterm-bindings zellij-additions))
(apply define-tree 'com.googlecode.iterm2/nvim
  (append iterm-bindings nvim-additions))
(apply define-tree 'com.googlecode.iterm2/zellij+nvim
  (append iterm-bindings zellij-additions nvim-additions))

;; Dispatcher hook. Single foreground-process probe, then optional RPC
;; scan only when a known multiplexer is in the pane — keeps the typical
;; (plain nvim or plain shell) case to one subprocess round.
;;
;; Precedence:
;;   nvim directly in iTerm                 → /nvim
;;   nvim inside zellij (nvim claims focus) → /zellij+nvim (merged)
;;   zellij with no focused nvim            → /zellij
;;   anything else                          → #f (plain iTerm tree)
(define (local-context-suffix bundle-id)
  (cond
    ((equal? bundle-id "com.googlecode.iterm2")
     (let ((cmd (focused-terminal-foreground-command)))
       (cond
         ((not cmd) #f)
         ((string-contains? cmd "nvim") "/nvim")
         ((or (string-contains? cmd "zellij")
              (string-contains? cmd "zj"))
          (if (focused-nvim-socket) "/zellij+nvim" "/zellij"))
         (else #f))))
    (else #f)))
