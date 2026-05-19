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

  ;; (category LABEL . CHILDREN) groups a slice of the overlay into a
  ;; labelled column. Categories may appear anywhere a (key …) can; the
  ;; renderer flows categories and loose-key runs as columns, left to
  ;; right, wrapping onto a new row when the overlay runs out of width.

  (category "Apps"
    (key "b" "Browser"          (λ () (launch-app "Dia")))
    (key "e" "Editor"           (λ () (launch-app "Zed")))
    (key "t" "Terminal"         (λ () (launch-app "iTerm")))
    (key "j" "Jump Desktop"     (λ () (launch-app "Jump Desktop")))
    (key "m" "Mail"             (λ () (launch-app "Mail")))
    (key "n" "Notes"            (λ () (launch-app "Notes")))
    (key "o" "Obsidian"         (λ () (launch-app "Obsidian")))
    (key "z" "Zotero"           (λ () (launch-app "Zotero"))))

  (category "AI"
    (key "c" "ChatGPT"          (λ () (launch-app "ChatGPT")))
    (key "C" "Claude Desktop"   (λ () (launch-app "Claude"))))

  (category "Search"
    (key "g" "Google"           (web-search:google))
    (key "a" "Find Application" (launcher:find-application))
    (key "f" "Find File"        (launcher:find-file)))

  ;; Window manager overlay ("w"). Each block is declared explicitly so
  ;; the structure of the overlay is visible at the config level. Swap
  ;; in different (window:divisions …) matrices to change the layout,
  ;; or override chip-options to match your theme.
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

        ;; Bottom: labelled windows list. The presence of 'chip-options
        ;; (even '()) enables the on-screen window chips; the alist value
        ;; supplies overrides. Other keys (font-size, padding, color,
        ;; faded-background, …) inherit from the block's defaults — see
        ;; (modaliser blocks window-list).

        (window:list-block 'chip-options `((background . ,the-color))))))

;; ─── Per-app trees (F17 when that app is focused) ────────────────

(safari:register!)

;; iTerm: dynamic-pane tree + sticky 'iterm-panes-focus mode + context-
;; suffix handler. Only the chip background needs threading through;
;; everything else (label set, font, padding, etc.) defaults inside
;; the library.
(iterm:register!
 'hint-options `((background . ,the-color)))
