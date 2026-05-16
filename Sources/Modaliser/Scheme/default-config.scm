;; Modaliser configuration
;; This file is evaluated by the Scheme engine at startup.
;; DSL functions and native libraries are auto-imported.

;; Leader keys
(set-leader! 'global F18 'arm-when-frontmost '("com.p5sys.jump.mac.viewer"))
(set-leader! 'local F17 'arm-when-frontmost '("com.p5sys.jump.mac.viewer"))

(set-overlay-delay! 0.3)

(define the-color "dodgerblue")

(set-host-header!
    'name            (run-shell "hostname -s")
    'background      the-color
    'foreground      "white")

;; Helper: open a URL
(define (open-url-action url)
    (lambda () (open-url url)))

;; Helper: send a keystroke to the focused app
(define (keystroke mods key-name)
    (lambda () (send-keystroke mods key-name)))

;; ─── Global command tree ────────────────────────────────────────────────

(define-tree 'global

    (group "," "Settings"
        (key "e" "Edit"
        (lambda ()
            (run-shell
            "/usr/bin/open -a Zed \"$HOME/.config/modaliser/config.scm\" || /usr/bin/open \"$HOME/.config/modaliser/config.scm\"")))
        (key "r" "Reload"
        (lambda () (relaunch!))))

    ;; Switch to macOS Space 1..9 via the system's Ctrl+digit shortcut.
    ;; Requires "Mission Control → Switch to Desktop N" enabled in
    ;; System Settings → Keyboard → Keyboard Shortcuts.
    (key-range "1.." "Goto Space <n>"
        '("1" "2" "3" "4" "5" "6" "7" "8" "9")
        (lambda (k) (send-keystroke '(ctrl) k)))

    (key "b" "Browser - Dia"
        (lambda () (launch-app "Dia")))
    (key "e" "Editor - Zed"
        (lambda () (launch-app "Zed")))
    (key "t" "Terminal - iTerm"
        (lambda () (launch-app "iTerm")))

    (key "j" "Jump Desktop"
        (lambda () (launch-app "Jump Desktop")))

    (key "c" "ChatGPT"
        (lambda () (launch-app "ChatGPT")))
    (key "C" "Claude Desktop"
        (lambda () (launch-app "Claude")))

    (key "m" "Mail"
        (lambda () (launch-app "Mail")))
    (key "n" "Notes"
        (lambda () (launch-app "Notes")))

    (key "o" "Obsidian"
        (lambda () (launch-app "Obsidian")))

    (key "z" "Zotero"
        (lambda () (launch-app "Zotero")))

    ;; Google search
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
        (selector "s" "Select Window"
            'prompt "Select window…"
            'source list-windows
            'on-select focus-window
            'actions
            (list
                (action "Focus" 'description "Select window" 'key 'primary
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

;; ─── iTerm dynamic pane tree ──────────────────────────────────────
;;
;; The iTerm tree is rebuilt on every leader press (see local-context-suffix
;; below) so pane bindings track the current pane layout. Pane labels sit
;; at the iTerm tree's top level alongside h/j/k/l directional focus, "c"
;; copy-mode, "z" zoom and "x" split. While the modal overlay is visible,
;; each pane is painted with a small chip showing its label — type the
;; chip's letter to focus that pane.
;;
;; Pane selection bridges AX → iTerm AppleScript by walk-order index:
;; AX gives us the pane frame (chip placement) and a 0-based 'idx field
;; recording subview-walk position. AppleScript's `id of every session
;; of current tab` returns session UUIDs in the same order (verified:
;; iTerm's session enumeration is the NSView subview tree DFS, same as
;; AX walks). So pane at AX walk-idx N corresponds to the N-th UUID in
;; AppleScript's list. We capture both at discovery time and bind each
;; chip's action to the UUID directly:
;;   tell first session whose id is "<UUID>" to select
;; — race-free, no event injection, no cursor disturbance, no clicks
;; landing on terminal cells. UUIDs are URL-safe so no escaping is
;; needed; the only string interpolated into the AppleScript is a
;; pre-validated UUID. Names (often duplicated, "zsh"+ in particular)
;; are NOT used for the join — the index correspondence handles
;; duplicates correctly. (We tried setting AXFocusedUIElement on the
;; scroll area; iTerm reports focus state but ignores focus writes.)

(define iterm-pane-labels
  (list "1" "2" "3" "4" "5" "6" "7" "8" "9" "0"))

;; Iterm-tuned chip appearance: large, red-on-white, soft border. Override
;; any subset by editing here — defaults in lib/ax-hints.scm are smaller.
(define iterm-pane-hint-options
  (list (cons 'offset-x-frac 0.02)
        (cons 'offset-y-frac 0.02)
        (cons 'font-size 56)
        (cons 'padding 16)
        (cons 'corner-radius 8)
        (cons 'color "white")
        (cons 'background the-color)
        (cons 'border-width 1)
        (cons 'border-color "black")))

;; Query iTerm for the UUIDs of every session in the focused window's
;; current tab, in iTerm's enumeration order. Returns a list of strings
;; (one per session), or '() if iTerm isn't running or the call fails.
;; iTerm's `id of every session` returns "U1, U2, ..." (one line, comma-
;; space separated). UUIDs don't contain commas, so the parse is safe.
(define (iterm-list-session-ids)
  (let* ((out (run-shell
                (string-append
                  "osascript -e 'tell application \"iTerm\" to "
                  "id of every session of current tab of current window' "
                  "2>/dev/null")))
         (trimmed (string-trim out)))
    (if (string=? trimmed "")
      '()
      (let loop ((parts (string-split trimmed ",")) (acc '()))
        (cond
          ((null? parts) (reverse acc))
          (else
            (let ((s (string-trim (car parts))))
              (loop (cdr parts)
                    (if (string=? s "") acc (cons s acc))))))))))

;; Activate the iTerm session whose UUID equals SESSION-ID. UUIDs are
;; alphanumeric + hyphens (URL-safe), so they can be inlined into the
;; AppleScript source without escaping. No name interpolation, no shell
;; quoting hazards.
(define (iterm-select-session-by-id session-id)
  (run-shell
    (string-append
      "osascript -e 'tell application \"iTerm\" to "
      "tell first session of current tab of current window "
      "whose id is \"" session-id "\" to select' "
      "2>/dev/null")))

;; Build a single (key-range ...) node covering every labelled pane.
;; Resolves each pane's session UUID up-front via its AX walk-order index
;; (the 'idx field set by ax-find-elements-named); the dispatch closure
;; reads from the resulting (label . uuid) alist so the action varies per
;; key while the overlay collapses all panes into a single
;; "1..N Pane <n>" row. The display-key tracks the actual bound count, so
;; a 3-pane window reads "1..3" rather than the full label list. If the
;; AppleScript call returns fewer UUIDs than AX found scroll areas, those
;; panes are dropped from the range. Returns a 0- or 1-element list so
;; the caller's (append (iterm-pane-bindings …) …) keeps splicing cleanly.
(define (iterm-pane-bindings labelled-panes session-ids)
  (let loop ((ps labelled-panes) (label->sid '()) (keys '()))
    (cond
      ((null? ps)
       (cond
         ((null? keys) '())
         (else
           (let* ((alist  label->sid)
                  (ks     (reverse keys))
                  (first  (car ks))
                  (last   (car (reverse ks)))
                  (display (string-append first "..")))
             (list
               (key-range display "Focus Pane <n>"
                 ks
                 (lambda (k)
                   (let ((entry (assoc k alist)))
                     (when entry
                       (iterm-select-session-by-id (cdr entry)))))))))))
      (else
        (let* ((entry (car ps))
               (label (car entry))
               (pane  (cdr entry))
               (idx   (cdr (assoc 'idx pane)))
               (sid   (and (< idx (length session-ids))
                           (list-ref session-ids idx))))
          (loop (cdr ps)
                (if sid (cons (cons label sid) label->sid) label->sid)
                (if sid (cons label keys)                  keys)))))))

(define (rebuild-iterm-tree!)
  (let* ((raw-panes (ax-find-elements-named "com.googlecode.iterm2" "AXScrollArea" "AXStaticText"))
         (panes (label-pairs iterm-pane-labels raw-panes))
         (session-ids (iterm-list-session-ids)))
    (apply define-tree 'com.googlecode.iterm2
        'on-enter (lambda () (hints-show (ax-target-hints panes iterm-pane-hint-options)))
        'on-leave (lambda () (hints-hide))
        (append
            (iterm-pane-bindings panes session-ids)
            (list
                (key "c" "Copy Mode" (keystroke '(cmd shift) "c"))
                (key "f" "Focus" (lambda () (enter-mode! 'iterm-panes-focus)))
                (key "z" "Toggle Zoom" (keystroke '(cmd shift) "return"))
                (group "x" "Split"
                    (key "h" "Left"  (keystroke '(cmd ctrl shift) "h"))
                    (key "j" "Down"  (keystroke '(cmd ctrl shift) "j"))
                    (key "k" "Up"    (keystroke '(cmd ctrl shift) "k"))
                    (key "l" "Right" (keystroke '(cmd ctrl shift) "l"))))))))

;; ─── iTerm sticky pane mode ──────────────────────────────────────
;;
;; A persistent modal: while active, hjkl move pane focus and "x h/j/k/l"
;; splits in a direction without exiting. Escape exits to insert mode;
;; Backspace steps back one level (e.g. out of the Split subgroup). The
;; nested (group "x" 'sticky #t ...) keeps the user in Split after a split
;; fires — useful for laying out a grid of panes in quick succession.
;;
;; Entered from the regular F17 iTerm tree via `p`. The bundled per-app
;; tree stays transient (one keypress launcher) so this is purely additive.
(define-tree 'iterm-panes-focus
    'sticky #t
    'exit-on-unknown #t
    'display-name "Focus"
    (key "h" "Left"  (keystroke '(cmd alt) "left"))
    (key "j" "Down"  (keystroke '(cmd alt) "down"))
    (key "k" "Up"    (keystroke '(cmd alt) "up"))
    (key "l" "Right" (keystroke '(cmd alt) "right")))

;; Dispatcher hook. For iTerm, refresh the dynamic tree (panes may have
;; changed) then probe the pane to pick a tree variant.
(define (local-context-suffix bundle-id)
  (cond
    ((equal? bundle-id "com.googlecode.iterm2")
     (rebuild-iterm-tree!)
     (let ((cmd (focused-terminal-foreground-command)))
       (cond
         ((not cmd) #f)
         ((string-contains? cmd "nvim") "/nvim")
         ((or (string-contains? cmd "zellij")
              (string-contains? cmd "zj"))
          (if (focused-nvim-socket) "/zellij+nvim" "/zellij"))
         (else #f))))
    (else #f)))

;; Pre-register the iTerm tree at load time so lookups don't return #f
;; before the first leader press. Cheap when iTerm isn't running (the AX
;; query returns an empty list); local-context-suffix re-fires this on
;; every leader press, so the tree always reflects the current layout.
(rebuild-iterm-tree!)
