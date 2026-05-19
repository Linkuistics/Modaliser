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
        (modaliser blocks which-key)        ; make-which-key-block
        (modaliser window)                  ; list-windows, focus-window
        (prefix (modaliser space-switching) space:)
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

  (settings:actions)

  (space:switch-actions)

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

  (web-search:google)

  (launcher:find-application)
  (launcher:find-file)

  ;; Window manager overlay ("w"). Each block is declared explicitly so
  ;; the structure of the overlay is visible at the config level. Swap
  ;; in different (window:divisions …) matrices to change the layout,
  ;; or override chip-options to match your theme.
  (overlay 'key "w" 'label "Windows"
    ;; Top: panel grid + matching move-window key bindings.
    (window:layout-block
      ;; Row 1 of the panel grid.
      (window:divisions '(("d" "f" "g")))         ; full thirds
      (window:divisions '(("D" "F" "G")
                          ("C" "V" "B")))         ; half thirds
      (window:divisions '(("e" "e" #f)))          ; left two-thirds
      ;; Row 2 of the panel grid.
      (window:divisions '((#f "t" "t")))          ; right two-thirds
      (window:divisions '(("m")))                 ; maximise (full cell)
      (window:center-panel "c"))                  ; centre (inward arrows)
    ;; Middle: which-key strip listing the remaining bindings.
    (make-which-key-block
      (selector "n" "Named…"
        'prompt "Select window…"
        'source list-windows
        'on-select focus-window)
      (key "r" "Restore" (lambda () (restore-window))))
    ;; Bottom: labelled windows list. The presence of 'chip-options
    ;; (even '()) enables the on-screen window chips; the alist value
    ;; supplies overrides. Other keys (font-size, padding, color,
    ;; faded-background, …) inherit from the block's defaults — see
    ;; (modaliser blocks window-list).
    (window:list-block 'chip-options `((background . ,the-color)))))

;; ─── Per-app trees (F17 when that app is focused) ────────────────

(safari:register!)

;; iTerm: dynamic-pane tree + sticky 'iterm-panes-focus mode + context-
;; suffix handler. Only the chip background needs threading through;
;; everything else (label set, font, padding, etc.) defaults inside
;; the library.
(iterm:register!
  'hint-options `((background . ,the-color)))
