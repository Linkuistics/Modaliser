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
        (prefix (modaliser apps iterm)      iterm:))

;; ─── Leader keys ─────────────────────────────────────────────────
;; F18 global, F17 local. arm-when-frontmost suppresses leader arming
;; while the Jump Desktop remote viewer is in front (its modifiers are
;; reserved for the remote machine).

(set-leaders! 'global-keycode F18
              'local-keycode  F17
              'arm-when-frontmost '("com.p5sys.jump.mac.viewer"))

(set-overlay-delay! 0.3)

;; Theme colours and any other styling live in
;; ~/.config/modaliser/theme.css (auto-loaded at boot). The bundled
;; defaults — including the chip colours — pick up --color-host-bg /
;; --color-host-fg from there. See docs/reference/theming.md.

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

  ;; Window manager overlay ("w"). Each block is declared explicitly so
  ;; the structure of the overlay is visible at the config level. Swap
  ;; in different (window:divisions …) matrices to change the layout;
  ;; chip styling lives in the .chip CSS rule (base.css +
  ;; ~/.config/modaliser/theme.css — see docs/reference/theming.md).
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

  (category "Instant Apps"
    (key "b" "Browser"          (λ () (launch-app "Dia")))
    (key "e" "Editor"           (λ () (launch-app "Zed")))
    (key "t" "Terminal"         (λ () (launch-app "iTerm"))))

  (category "AI"
    (key "c" "ChatGPT"          (λ () (launch-app "ChatGPT")))
    (key "C" "Claude Desktop"   (λ () (launch-app "Claude"))))

  (category "Search"
    (key "g" "Google"           (web-search:google))
    (key "a" "Find Application" (launcher:find-application))
    (key "f" "Find File"        (launcher:find-file)))

  (category "Apps"
    (key "j" "Jump Desktop"     (λ () (launch-app "Jump Desktop")))
    (key "m" "Mail"             (λ () (launch-app "Mail")))
    (key "n" "Notes"            (λ () (launch-app "Notes")))
    (key "o" "Obsidian"         (λ () (launch-app "Obsidian")))
    (key "z" "Zotero"           (λ () (launch-app "Zotero"))))
)

;; ─── Per-app trees (F17 when that app is focused) ────────────────

(safari:register!)

;; iTerm tree inlined here (formerly (iterm:register!)) so it's easy
;; to tweak. The pane-selection mechanism is the (iterm:pane-list-block)
;; block: it paints pane chips, renders a row list at the bottom of the
;; overlay (one per pane), and dispatches digits 1..0 to focus the
;; matching pane by session UUID. Layout is re-snapshotted on every
;; overlay open, so panes added or moved between presses Just Work
;; without a separate tree rebuild step.
;;
;; Splits and pane moves rely on these iTerm key bindings — set them
;; once in iTerm → Settings → Keys → Key Bindings:
;;   Cmd+Ctrl+Shift+H → Swap With Split Pane on Left
;;   Cmd+Ctrl+Shift+J → Swap With Split Pane Below
;;   Cmd+Ctrl+Shift+K → Swap With Split Pane Above
;;   Cmd+Ctrl+Shift+L → Swap With Split Pane on Right

(define-tree 'com.googlecode.iterm2

  (key "c" "Copy Mode"   (λ () (send-keystroke '(cmd shift) "c")))
  (key "z" "Toggle Zoom" (λ () (send-keystroke '(cmd shift) "return")))

  ;; Focus / Split / Move use the (modaliser apps iterm) factory's
  ;; named operations. Each is a 0-arg procedure, so it can be passed
  ;; directly as the `key` action without wrapping in a lambda. The
  ;; AppleScript split, the split-then-swap sequencing for left/up,
  ;; and the swap-keystroke emission all live inside the library.

  (category "Focus"
    (key "h" "Left"  iterm:focus-pane-left)
    (key "j" "Down"  iterm:focus-pane-down)
    (key "k" "Up"    iterm:focus-pane-up)
    (key "l" "Right" iterm:focus-pane-right))

  (category "Split"
    (key "H" "Left"  iterm:split-pane-left)
    (key "J" "Down"  iterm:split-pane-down)
    (key "K" "Up"    iterm:split-pane-up)
    (key "L" "Right" iterm:split-pane-right))

  ;; Move Pane sticky modal — m enters the group, hjkl swap the focused
  ;; pane in that direction and stay; any other key exits.
  (group "m" "Move"
    'sticky #t
    'exit-on-unknown #t
    (key "h" "Left"  iterm:move-pane-left)
    (key "j" "Down"  iterm:move-pane-down)
    (key "k" "Up"    iterm:move-pane-up)
    (key "l" "Right" iterm:move-pane-right))

  ;; Bottom: labelled panes list. 'chips? #t paints the pane chips and
  ;; bundles a hidden digit key-range that focuses panes by UUID.
  (iterm:pane-list-block 'chips? #t))
