;; Modaliser configuration — first-run seed.
;;
;; Copied to ~/.config/modaliser/config.scm on first launch. Reads as a
;; tutorial of the bundled (modaliser …) libraries and the presentation-first
;; layout DSL: the overlay is authored as a tree of SCREENS, each an implicit
;; grid of PANELS (banded cards). Tweak freely; restart Modaliser (or use the
;; menu-bar "Relaunch") to see your changes.
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
        (prefix (modaliser display-actions) display:)
        (modaliser window)                  ; list-windows, focus-window
        (prefix (modaliser web-search)      web-search:)
        (prefix (modaliser apps safari)     safari:)
        (prefix (modaliser apps iterm)      iterm:)
        (prefix (modaliser muxes herdr)     herdr:)  ; herdr mux backend + variant wiring
        (prefix (modaliser terminal)        terminal:)
        (modaliser event-dispatch))         ; set-local-context-suffix! (composed hook)

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
;;
;; (screen 'scope panel…) registers a tree as a grid of panels (the
;; presentation-first replacement for (define-tree …)). Each (panel
;; "Label" child…) is a banded card; its children are dispatch atoms
;; (key / keys / open / a live-list block). A panel is TRANSPARENT for
;; dispatch — keys keep their paths — so this is purely a presentation
;; layer over the same operational tree the state machine reads. Loose
;; top-level keys (outside any panel) render BARE in a header-less loose
;; region above the panel grid — there is no "General" card. Here Switch
;; Space, Settings, Highlight Cursor and the "w" Windows drill-down are
;; such loose rows.

(screen 'global

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

  ;; Window manager drill-down ("w"). (open KEY LABEL panel…) is the
  ;; navigable, panel-native replacement for the old (key K L (overlay …))
  ;; idiom: pressing "w" descends into a sub-screen whose own grid holds
  ;; the layout diagram, the select/restore actions, and the live windows
  ;; list. Swap in different (window:layout-block …) matrices to change the
  ;; layout; chip styling lives in the .chip CSS rule (base.css +
  ;; ~/.config/modaliser/overlay.css — see docs/reference/theming.md).
  (open "w" "Windows"

    ;; The layout diagram. Each form is a matrix of keys (with #f for
    ;; empty cells), or (center K) for the inward-arrows centre panel. The
    ;; diagram draws each cell's key, so it embeds as a (wide) panel: the
    ;; matching move-window bindings ride hidden under it for dispatch.
    ;; Headerless (panel #f …): the diagram needs no "Layout" eyebrow — it
    ;; reads as a layout map on its own.
    (panel #f
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
       (center "c")))                            ; centre (inward arrows)

    ;; Window actions that aren't geometry presets.
    (panel "Select"
      (key "s" "Select Window"
           (selector 'prompt "Select window by name…"
                     'source list-windows
                     'on-select focus-window))
      (key "r" "Restore" (λ () (restore-window))))

    ;; Labelled windows list. 'chips? #t enables the on-screen window
    ;; chips. Chip appearance (colour, font, padding, …) is controlled by
    ;; the .chip CSS rule and inherits the host-header colour automatically
    ;; — no per-callsite plumbing required. A panel holding a live list
    ;; auto-promotes to a wide (2-column) span.
    (panel "Windows"
      (window:list-block 'chips? #t))

    ;; Display chips (round, top-right): one per display. Plain letter moves the
    ;; focused window to that display, preserving its size/position as a fraction
    ;; of the display's visible area; Shift+letter focuses the display so macOS
    ;; Space/Mission-Control keys act on it. Default labels h j k l n o.
    ;; (Its OWN panel: a panel embeds at most one live-list block.)
    (panel "Displays"
      (display:display-list-block 'chips? #t)))

  (panel "Applications"
    (key "j" "Jump Desktop"     (λ () (launch-app "Jump Desktop")))
    (key "b" "Browser"          (λ () (launch-app "Dia")))
    (key "e" "Editor"           (λ () (launch-app "Zed")))
    (key "t" "Terminal"         (λ () (launch-app "iTerm")))
    (key "m" "Mail"             (λ () (launch-app "Mail")))
    (key "n" "Notes"            (λ () (launch-app "Notes")))
    (key "o" "Obsidian"         (λ () (launch-app "Obsidian")))
    (key "z" "Zotero"           (λ () (launch-app "Zotero"))))

  (panel "AI"
    (key "c" "ChatGPT"          (λ () (launch-app "ChatGPT")))
    (key "C" "Claude Desktop"   (λ () (launch-app "Claude"))))

  (panel "Search"
    (key "g" "Google"       (web-search:google))
    (key "a" "Applications" (launcher:find-application))
    (key "f" "Files"        (launcher:find-file))))

;; ─── Per-app trees (F17 when that app is focused) ────────────────
;;
;; Each app's tree lives in its own file under app-trees/, named after
;; the app's bundle id, and is pulled in with (include …). The included
;; files hold just the (screen '<bundle-id> …) form (plus any app-specific
;; helper defines) and inherit the imports above — no per-file import
;; boilerplate. Adding an app = drop an app-trees/<bundle-id>.scm file and
;; add one (include …) line here.
;;
;; Safari is the exception: it has no inline tree, only the factory
;; registration call from (modaliser apps safari).

(safari:register!)

(include "app-trees/com.googlecode.iterm2.scm")
(include "app-trees/company.thebrowser.dia.scm")
(include "app-trees/com.apple.finder.scm")
(include "app-trees/com.apple.mail.scm")
(include "app-trees/com.tinyspeck.slackmacgap.scm")
(include "app-trees/dev.zed.Zed.scm")
(include "app-trees/org.whispersystems.signal-desktop.scm")
(include "app-trees/com.apple.MobileSMS.scm")
(include "app-trees/com.tdesktop.Telegram.scm")
(include "app-trees/md.obsidian.scm")
(include "app-trees/org.zotero.zotero.scm")
