;; Modaliser configuration — first-run seed.
;;
;; Copied to ~/.config/modaliser/config.scm on first launch. Reads as a
;; tutorial of the bundled (modaliser …) libraries: the user picks a
;; theme colour and which library factories to splice into the global
;; tree. Tweak freely; restart Modaliser (or use the "," → "r" reload
;; binding) to see your changes.
;;
;; The (modaliser …) factory libraries use bare-name exports (`register!`,
;; `actions`, `tree`, etc.); imports are prefix-style so the call sites
;; read as `<lib>:<verb>` — see https://small.r7rs.org for the `prefix`
;; import modifier.

(import (modaliser dsl)
        (modaliser keyboard)
        (modaliser input)
        (modaliser shell)
        (modaliser cursor)                  ; highlight-cursor
        (modaliser util)                    ; string-split, string-trim, string-join
        (modaliser app)
        (modaliser pasteboard)
        (modaliser lifecycle)
        (modaliser leader)
        (prefix (modaliser settings-menu)   settings:)
        (prefix (modaliser launchers)       launcher:)
        (prefix (modaliser window-actions)  window:)
        (modaliser blocks which-key)        ; which-key-block
        (modaliser window)                  ; list-windows, focus-window
        (prefix (modaliser web-search)      web-search:)
        (prefix (modaliser apps safari)     safari:)
        (prefix (modaliser apps iterm)      iterm:)
        (prefix (modaliser terminal)        terminal:))

;; ─── Leader keys ─────────────────────────────────────────────────
;; F18 global, F17 local. arm-when-frontmost suppresses leader arming
;; while the Jump Desktop remote viewer is in front (its modifiers are
;; reserved for the remote machine).

(set-leaders! 'global-keycode F18
              'local-keycode  F17
              'arm-when-frontmost '("com.p5sys.jump.mac.viewer"))

(set-overlay-delay! 0.3)

;; Theme colours and any other styling live in
;; ~/.config/modaliser/overlay.css (auto-loaded at boot). The bundled
;; chip default reads --color-host-bg from there. See
;; docs/reference/theming.md.

;; ─── Global command tree (F18) ───────────────────────────────────

(define-tree 'global

  ;; `key`'s third arg is evaluated at config-load: if it returns a
  ;; procedure, that's the action thunk; if it returns a pair (a node
  ;; alist), the node is decorated with this key/label. For inline
  ;; side-effecting calls like (launch-app "X"), wrap in (lambda () …)
  ;; so the call fires on key press rather than at config-load.

  ;; Map 1..9 to switch spaces. `keys` is the multi-key sibling of `key`:
  ;; one labelled row, action gets (key index keylist).
  (keys '("1" ..) "Switch Space" (λ (k i ks) (send-keystroke '(ctrl) k)))

  ;; Factory-returned nodes — call site decides the binding key/label.
  (key "," "Settings"         (settings:actions))

  ;; Find the mouse cursor (F18 → space): a glowing ring converges on the
  ;; pointer, and a 1px nudge reveals a cursor an app left idle-hidden.
  ;; From the bundled (modaliser cursor) library. Every keyword arg is
  ;; optional; bare (highlight-cursor) uses the defaults shown here:
  ;;   'color     "#FFCC33"  ring + glow colour, hex string ("#RGB" or "#RRGGBB")
  ;;   'size      240        starting ring diameter, px (it converges inward)
  ;;   'thickness 6          ring stroke width, px
  ;;   'glow      18         glow blur radius around the ring, px
  ;;   'duration  0.45       animation length, seconds
  ;;   'nudge     #t         #f to skip the reveal-hidden-cursor mouse nudge
  (key " " "Highlight Cursor"
       (λ () (highlight-cursor 'duration 1 'thickness 16)))

  ;; Window manager overlay ("w"). Each block is declared explicitly so
  ;; the structure of the overlay is visible at the config level. Swap
  ;; in different (window:divisions …) matrices to change the layout,
  ;; chip styling lives in the .chip CSS rule (base.css +
  ;; ~/.config/modaliser/overlay.css — see docs/reference/theming.md).
  (key "w" "Windows"
       (overlay
        ;; Top: panel grid + matching move-window key bindings. Each form
        ;; is a matrix of keys (with #f for empty cells), or (center K)
        ;; for the inward-arrows centre panel.

        (window:layout-block
         (("d" "f" "g"))                           ; full thirds
         (("D" "F" "G")
          ("C" "V" "B"))                           ; half thirds
         (("e" "e" #f))                            ; left two-thirds
         ((#f "t" "t"))                            ; right two-thirds
         (("q" "w"))                               ; halves
         (("Q" "W")                                ; quarters
          ("A" "S"))
         (("m"))                                   ; maximise (full cell)
         (center "c"))                             ; centre (inward arrows)

        ;; Middle: which-key strip listing the remaining bindings.

        (key "s" "Select Window"
             (selector 'prompt "Select window by name…"
                       'source list-windows
                       'on-select focus-window))
        (key "r" "Restore" (λ () (restore-window)))

        ;; Bottom: labelled windows list. 'chips? #t enables the on-screen
        ;; window chips. Chip appearance (colour, font, padding, …) is
        ;; controlled by the .chip CSS rule and inherits the host-header
        ;; colour automatically — no per-callsite plumbing required.

        (window:list-block 'chips? #t)))

  ;; (category LABEL . CHILDREN) groups a slice of the overlay into a
  ;; labelled column. Categories may appear anywhere a (key …) can; the
  ;; renderer flows categories and loose-key runs as columns, left to
  ;; right, wrapping onto a new row when the overlay runs out of width.

  (category "Applications"
    (key "j" "Jump Desktop"     (λ () (launch-app "Jump Desktop")))
    (key "b" "Browser"          (λ () (launch-app "Dia")))
    (key "e" "Editor"           (λ () (launch-app "Zed")))
    (key "t" "Terminal"         (λ () (launch-app "iTerm")))
    (key "m" "Mail"             (λ () (launch-app "Mail")))
    (key "n" "Notes"            (λ () (launch-app "Notes")))
    (key "o" "Obsidian"         (λ () (launch-app "Obsidian")))
    (key "z" "Zotero"           (λ () (launch-app "Zotero"))))

  (category "AI"
    (key "c" "ChatGPT"          (λ () (launch-app "ChatGPT")))
    (key "C" "Claude Desktop"   (λ () (launch-app "Claude"))))

  (category "Search"
    (key "g" "Google"       (web-search:google))
    (key "a" "Applications" (launcher:find-application))
    (key "f" "Files"        (launcher:find-file)))
)

;; ─── Per-app trees (F17 when that app is focused) ────────────────

(safari:register!)

;; Register the iTerm backend with (modaliser terminal) so the façade's
;; (terminal:focus-pane-*) / (terminal:split-pane-*) / (terminal:move-
;; pane-*) calls below route to iTerm. 'install-tree? #f skips the
;; library's own rebuild-tree! — the inline (define-tree
;; 'com.googlecode.iterm2 …) below is the tree we want, not the
;; library's stock one. The backend record + sticky focus mode + digit-
;; pick mode + context-suffix handler still install.
(iterm:register! 'install-tree? #f)

;; Tab rename — clicks iTerm's Window > Tab > Edit Tab Title menu via
;; System Events. iTerm opens its inline tab-bar editor; the user types
;; the new title and presses Enter inside iTerm.
;;
;; iTerm's `tab` class advertises a writable `title` property but
;; rejects writes at runtime (AppleEvent -10000). `name of session`
;; *is* writable and surfaces in the tab bar, but shell title escapes
;; (\e]0;…\a from precmd hooks) clobber it on the next prompt — and
;; it's not the per-tab override the menu sets. The menu click is the
;; only path to the real override.
(define (rename-iterm-tab!)
  (run-shell
   (string-append
    "osascript -e 'tell application \"System Events\" to tell process \"iTerm2\" "
    "to click menu item \"Edit Tab Title\" of menu \"Tab\" "
    "of menu item \"Tab\" of menu \"Window\" of menu bar 1' "
    "2>/dev/null")))

;; New tab inheriting the current session's profile, so it matches
;; whatever you're in now rather than the default profile. The profile is
;; read and used entirely inside AppleScript — nothing crosses into the
;; shell, so there is nothing to escape. (Inside `tell current window`,
;; `current session` already resolves to that window; adding `of current
;; window` there would double-resolve and error.)
(define (new-iterm-tab!)
  (run-shell
   (string-append
    "osascript -e 'tell application \"iTerm\" to tell current window "
    "to create tab with profile (profile name of current session)' "
    "2>/dev/null")))

;; Close the focused tab. iTerm raises its own \"a job is running\"
;; confirmation when the tab has a live process, so no extra guard here.
(define (close-iterm-tab!)
  (run-shell
   (string-append
    "osascript -e 'tell application \"iTerm\" to "
    "close (current tab of current window)' "
    "2>/dev/null")))

;; iTerm tree inlined here (formerly (iterm:register!)) so it's easy
;; to tweak. The pane-selection mechanism is the (iterm:pane-list-block)
;; block: it paints pane chips, renders a row list at the bottom of the
;; overlay (one per pane), and dispatches digits 1..0 to focus the
;; matching pane by session UUID. Layout is re-snapshotted on every
;; overlay open, so panes added or moved between presses Just Work
;; without a separate tree rebuild step.
;;
;; Splits, pane moves, Copy Mode and Toggle Zoom rely on eight iTerm
;; key bindings. The (iterm:configure-entry) action below provisions
;; them — it appears in this overlay as "Configure iTerm"
;; (Ctrl+Shift+I) only while iTerm is unconfigured, and vanishes once
;; set up.

(define-tree 'com.googlecode.iterm2

  (key "c" "Copy Mode"   (λ () (send-keystroke '(cmd shift) "c")))
  (key "z" "Toggle Zoom" (λ () (send-keystroke '(cmd shift) "return")))

  ;; One-shot iTerm key-binding setup. Hidden once iTerm is configured.
  (iterm:configure-entry)

  ;; Focus / Split / Move use the (modaliser apps iterm) factory's
  ;; named operations. Each is a 0-arg procedure, so it can be passed
  ;; directly as the `key` action without wrapping in a lambda. The
  ;; split, the split-then-swap sequencing for left/up, and the
  ;; swap-keystroke emission all live inside the library.

  (category "Focus"
    (key "h" "Left"  terminal:focus-pane-left)
    (key "j" "Down"  terminal:focus-pane-down)
    (key "k" "Up"    terminal:focus-pane-up)
    (key "l" "Right" terminal:focus-pane-right))

  (group "s" "Split"
    (key "h" "Left"  terminal:split-pane-left)
    (key "j" "Down"  terminal:split-pane-down)
    (key "k" "Up"    terminal:split-pane-up)
    (key "l" "Right" terminal:split-pane-right))

  ;; Move Pane sticky modal — m enters the group, hjkl swap the focused
  ;; pane in that direction and stay; any other key exits.
  (group "m" "Move"
    'sticky #t
    'exit-on-unknown #t
    (key "h" "Left"  terminal:move-pane-left)
    (key "j" "Down"  terminal:move-pane-down)
    (key "k" "Up"    terminal:move-pane-up)
    (key "l" "Right" terminal:move-pane-right))

  ;; Tab sub-overlay. (overlay …) renders its children as a block list
  ;; and lifts the tab-list block's hidden 1.. range onto this group, so
  ;; pressing t shows every tab (title + number, the focused one marked)
  ;; and a digit switches to that tab. r/n/d act on tabs.
  (overlay 'key "t" 'label "Tab"
    (key "r" "Rename" rename-iterm-tab!)
    (key "n" "New"    new-iterm-tab!)
    (key "d" "Delete" close-iterm-tab!)
    (iterm:tab-list-block))

  ;; Bottom: labelled panes list. 'chips? #t paints the pane chips and
  ;; bundles a hidden digit key-range that focuses panes by UUID.
  (iterm:pane-list-block 'chips? #t))

;; ─── Dia browser (company.thebrowser.dia) ───────────────────────
;;
;; Dia ships a real AppleScript dictionary: a `tab` class (title, id,
;; isFocused, URL) plus a `focus` command. The "Select Tab…" chooser
;; uses it to enumerate the front window's tabs and focus the picked
;; one by id.
;;
;; Front window only — matches ctrl-tab's own within-window scope. To
;; cover every window, swap `front window` for `every window` in
;; dia-tab-source and flatten; left out to keep it simple.
;;
;; No ctrl-tab binding: Dia's recent-tab switcher opens on ctrl+tab and
;; commits when control is *released*, but `send-keystroke` only sets
;; the control *flag* on the tab event — it never posts a discrete
;; control key-up (flagsChanged), so the switcher HUD opens and hangs
;; waiting for a release that never arrives. Reaching it needs real
;; modifier-down/up primitives in the app (KeystrokeEmitter, Swift).
;; The chooser is the config-only path that works.

;; Enumerate the front Dia window's tabs as a list of
;; ((text . <title>) (id . <uuid>)) alists for the chooser. The id and
;; title lists are pulled in bulk *inside* the tell block (per-tab
;; `tab i of w` access throws -1700 in Dia), then zipped with the `tab`
;; constant *outside* it — inside the tell, `tab` would bind to Dia's
;; tab class instead of the tab character. Each line is "<id>\t<title>".
(define (dia-tab-source)
  (let ((raw (run-shell
              (string-append
               "osascript"
               " -e 'tell application \"Dia\"'"
               " -e 'if (count of windows) is 0 then return \"\"'"
               " -e 'set theTitles to title of every tab of front window'"
               " -e 'set theIds to id of every tab of front window'"
               " -e 'end tell'"
               " -e 'set out to \"\"'"
               " -e 'repeat with i from 1 to (count of theTitles)'"
               " -e 'set out to out & (item i of theIds) & tab & (item i of theTitles) & linefeed'"
               " -e 'end repeat'"
               " -e 'return out'"
               " 2>/dev/null"))))
    (let loop ((lines (string-split (string-trim raw) "\n"))
               (acc '()))
      (if (null? lines)
          (reverse acc)
          (let* ((line  (string-trim (car lines)))
                 (parts (and (> (string-length line) 0)
                             (string-split line "\t"))))
            (loop (cdr lines)
                  (if (and parts (pair? parts) (pair? (cdr parts)))
                      ;; 'text is the chooser's display + fuzzy-match field
                      ;; (ui/chooser.scm), NOT 'name as the how-to claims.
                      (cons (list (cons 'text (string-join (cdr parts) "\t"))
                                  (cons 'id   (car parts)))
                            acc)
                      acc)))))))

;; Focus the chosen tab by id. The id is a UUID (hex + hyphens), so it
;; drops into the AppleScript string with no escaping — which is why
;; the chooser dispatches on id rather than the free-form title.
(define (dia-focus-tab! item)
  (run-shell
   (string-append
    "osascript -e 'tell application \"Dia\" to "
    "focus (first tab of front window whose id is \"" (cdr (assoc 'id item)) "\")' "
    "2>/dev/null")))

;; ── Recent-tab MRU walk (Dia's ctrl-tab switcher, driven from a modal) ──
;;
;; Dia's recent-tab switcher opens on ctrl+tab and commits when control is
;; *released*. We hold control across the whole sticky modal (via
;; send-key-down) and release it on exit (send-key-up). The input library
;; tracks held modifiers, so a plain (send-keystroke '() "tab") posted while
;; control is held is automatically seen as ctrl+tab — no need to restate the
;; modifier on every tap. See the app repo spec for the mechanics:
;; docs/specs/2026-06-19-keystroke-modifier-release-and-down-up.md
;;
;; One ctrl+tab (control is held by the modal, applied automatically):
(define (dia-tab-step)      (send-keystroke "tab"))

;; One ctrl+shift+tab — walk backward (held ctrl + the explicit shift):
(define (dia-tab-step-back) (send-keystroke '(shift) "tab"))

(define-tree 'company.thebrowser.dia
    (key "n" "New Tab"  (λ () (send-keystroke '(cmd) "t")))
    (key "f" "Find Tab" (λ () (send-keystroke '(cmd shift) "a")))

  ;; Sticky "Recent Tabs" walk. Enter holds control and steps once, so the
  ;; HUD opens on the most-recent (next) tab; j/k step forward/back through
  ;; the MRU stack.
  ;;
  ;; Exit is commit-or-cancel, distinguished by the reason the modal passes
  ;; to on-leave:
  ;;   • Return → 'confirm → just release control → Dia commits the
  ;;     highlighted tab.
  ;;   • Escape / any unbound key → 'cancel → send Escape *to Dia* (which
  ;;     dismisses the HUD without switching) and then release control.
  ;; So Esc truly cancels — opening and pressing Esc is a no-op.
  ;;
  ;; on-enter/on-leave are gated on overlay visibility and therefore
  ;; balanced — a held control always gets its matching release. The leading
  ;; (send-key-up "ctrl") self-heals any control left held by an aborted walk.
  (group "r" "Recent Tabs"
    'sticky #t
    'exit-on-unknown #t
    'on-enter (λ () (send-key-up   "ctrl")   ; clear any stale hold
                    (send-key-down "ctrl")   ; hold control (auto-asserts)
                    (dia-tab-step))          ; open HUD on the next tab
    'on-leave (λ (reason)
                (unless (eq? reason 'confirm)
                  (send-keystroke "escape"))  ; cancel Dia's HUD
                (send-key-up "ctrl"))         ; release (commit if confirmed)
    (key "l" "Next" (λ () (dia-tab-step)))
    (key "h" "Prev" (λ () (dia-tab-step-back)))))
