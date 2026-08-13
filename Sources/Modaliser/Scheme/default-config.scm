;; Modaliser configuration — first-run seed.
;;
;; Copied to ~/.config/modaliser/config.scm on first launch. Reads as a
;; tutorial of the bundled (modaliser …) libraries and the
;; configuration-value model: libraries export PURE CONSTRUCTORS that
;; return fragments — printable pieces of configuration — and this file
;; composes them with ordinary Scheme into ONE configuration value.
;; Nothing takes effect until the single (modaliser:start! …) call at
;; the bottom hands that value to the engine; everything above that call
;; is inspectable data you can print or evaluate piecemeal. Tweak
;; freely; restart Modaliser (or use the menu-bar "Relaunch") to see
;; your changes.
;;
;; The (modaliser …) factory libraries use bare-name exports
;; (`fragment`, `context`, `actions`, `tree`, …); imports are
;; prefix-style so the call sites read as `<lib>:<verb>` — see
;; https://small.r7rs.org for the `prefix` import modifier.

(import (modaliser dsl)
        (modaliser configuration)           ; configuration, leaders, overlay-delay, …
        (modaliser handoff)                 ; modaliser:start!
        (modaliser keyboard)                ; F17 / F18 keycodes
        (modaliser input)                   ; send-keystroke & friends
        (modaliser cursor)                  ; highlight-cursor
        (modaliser app)                     ; launch-app
        (modaliser lifecycle)               ; relaunch!
        (prefix (modaliser settings-menu)   settings:)
        (prefix (modaliser launchers)       launcher:)
        (prefix (modaliser window-actions)  window:)
        (prefix (modaliser display-actions) display:)
        (modaliser window)                  ; list-windows, focus-window
        (prefix (modaliser web-search)      web-search:)
        (prefix (modaliser apps dia)        dia:)
        (prefix (modaliser apps iterm)      iterm:)
        (prefix (modaliser muxes herdr)     herdr:)
        (prefix (modaliser muxes zellij)    zellij:)
        (prefix (modaliser tools nvim)      nvim:))

;; Theme colours and any other styling live in
;; ~/.config/modaliser/theme.css (auto-loaded at boot). The bundled
;; chip default reads --color-host-bg from there. See
;; docs/reference/theming.md.

;; ─── Global screen (F18) ─────────────────────────────────────────
;;
;; (screen 'scope panel…) builds a tree as a grid of panels: each
;; (panel "Label" child…) is a banded card; its children are dispatch
;; atoms (key / keys / open / a live-list block). A panel is TRANSPARENT
;; for dispatch — keys keep their paths — so panels are purely a
;; presentation layer over the operational tree the state machine runs.
;; Loose top-level keys (outside any panel) render BARE in a header-less
;; loose region above the panel grid — there is no "General" card. Here
;; Switch Space, Settings, Highlight Cursor and the "w" Windows
;; drill-down are such loose rows.
;;
;; `screen` returns a tree fragment; the define below holds it as a
;; value, and the (configuration …) call at the bottom is what puts it
;; in play.
;;
;; screen / panel / open are SUGAR: they author both of a node's two
;; layers at once — its flat dispatch children, and the one display value
;; that says how those children render. The canonical surface underneath
;; is bare and separable: compose the structure with tree-root / group /
;; key, then attach the display in one explicit step —
;;
;;   (import (prefix (modaliser display-dsl) d:))   ; `panel` exists on both
;;                                                  ; surfaces, so prefix it
;;   (tree 'demo
;;     (d:with-display (tree-root 'demo kz kc kB)
;;       (d:loose "z")                              ; rows referenced BY KEY
;;       (d:panel "W" (d:span 'wide) "c" "B")))
;;
;; — which is byte-for-byte what
;;
;;   (screen 'demo kz (panel "W" 'span 'wide kc kB))
;;
;; produces. Reach for the bare surface when the two layers should come
;; apart (a generated tree, a display swapped without touching keys);
;; otherwise the sugar reads better, and this file stays sugar throughout.
;; See docs/reference/dsl.md "The bare authoring surface".

(define global-screen
  (screen 'global

    ;; `key`'s third arg is evaluated at config-load: if it returns a
    ;; procedure, that's the action thunk; if it returns a pair (a node
    ;; alist), the node is decorated with this key/label. For inline
    ;; side-effecting calls like (launch-app "X"), wrap in (lambda () …)
    ;; so the call fires on key press rather than at config-load.

    ;; Map 1..9 to switch spaces. `keys` is the multi-key sibling of `key`:
    ;; one labelled row, action gets (key index keylist).
    (keys '("1" ..) "Switch Space" (λ (k i ks) (send-keystroke '(ctrl) k)))

    ;; Settings. Two rows, both ordinary Scheme: Edit opens this file's
    ;; directory (not the file — the editor's project view then shows
    ;; config.scm, theme.css and any .sld libraries of your own side by
    ;; side), Reload restarts Modaliser to pick the edits up. Name a
    ;; different 'editor, or drop the option to use whatever macOS opens
    ;; a folder with. `relaunch!` is a bare procedure from (modaliser
    ;; lifecycle), so it needs no λ wrapper; the Edit row takes arguments,
    ;; so it does.
    (group "," "Settings"
      (key "e" "Edit"   (λ () (settings:open-config-dir! 'editor "Zed")))
      (key "r" "Reload" relaunch!))

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
        (λ () (highlight-cursor 'color "#FF0000" 'duration 1 'thickness 16)))

    ;; Play/pause whatever is currently playing. `send-media-key` emits the
    ;; system media-key event the hardware ⏯ button sends, so macOS routes it
    ;; to whichever app holds Now Playing — Music, Podcasts, a browser tab —
    ;; rather than to the frontmost window. That target is implicit and cannot
    ;; be queried, which is the trade for reaching every player instead of one
    ;; named app. The library ships the whole family ('play-pause, 'next,
    ;; 'previous, 'volume-up, 'volume-down, 'mute); binding only this one is a
    ;; config decision, so add the rest here if you want a transport cluster.
    (key "p" "Play/Pause" (λ () (send-media-key 'play-pause)))

    ;; Window manager drill-down ("w"). (open KEY LABEL panel…) descends
    ;; into a sub-screen whose own grid holds the layout diagram, the
    ;; select/restore actions, and the live windows list. Swap in
    ;; different (window:layout-block …) matrices to change the layout;
    ;; chip styling lives in the .chip CSS rule (base.css +
    ;; ~/.config/modaliser/theme.css — see docs/reference/theming.md).
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
      (key "b" "Browser"      (λ () (launch-app "Dia")))
      (key "c" "ChatGPT"      (λ () (launch-app "ChatGPT")))
      (key "C" "Claude"       (λ () (launch-app "Claude")))
      (key "e" "Editor"       (λ () (launch-app "Zed")))
      (key "j" "Jump Desktop" (λ () (launch-app "Jump Desktop")))
      (key "k" "Kimi"         (λ () (launch-app "Kimi")))
      (key "t" "Terminal"     (λ () (launch-app "iTerm")))
      (key "m" "Mail"         (λ () (launch-app "Mail")))
      (key "n" "Notes"        (λ () (launch-app "Notes")))
      (key "o" "Obsidian"     (λ () (launch-app "Obsidian")))
      (key "z" "Zotero"       (λ () (launch-app "Zotero"))))

    (panel "Search"
      (key "g" "Google"       (web-search:google))
      (key "a" "Applications" (launcher:find-application))
      (key "f" "Files"        (launcher:find-file)))))

;; ─── Per-app screens (F17 when that app is focused) ──────────────
;;
;; Each app's screen is authored INLINE here: one (screen 'bundle-id …)
;; per app holding that app's keys, labels and walks — pure preference,
;; yours to edit. Machinery (AppleScript helpers, list blocks,
;; protocols) stays in the bundled (modaliser …) libraries and arrives
;; always-fresh on every launch, so nothing here goes stale when
;; Modaliser improves. Adding an app = write a (screen '<bundle-id> …)
;; below and list it in the (configuration …) call at the bottom.
;;
;; There is no exception left: every screen Modaliser runs is authored
;; in this file. No bundled library ships one, because which operations
;; are surfaced, on which keys, under which labels is preference and
;; preference is yours (docs/adr/0021-decision-free-libraries.md).
;;
;; iTerm, herdr, zellij and nvim are authored inline further down rather
;; than up here with the app screens — each pairs with a `wiring`
;; fragment from its library and each carries a paragraph of its own.
;; herdr / zellij / nvim attach through the Terminal context map; see the
;; (configuration …) call at the bottom.

;; ─── Safari (com.apple.Safari) ───────────────────────────────────
;;
;; Every binding emits one of Safari's own menu shortcuts, so the tree
;; tracks whatever Safari's menus do. Nothing here needs a library:
;; send-keystroke is the whole mechanism.
;;
;; Using Chrome, Firefox, Arc, …? Copy this screen and change the scope
;; symbol to that app's bundle id, which
;; `osascript -e 'id of app "Google Chrome"'` prints. For Chrome that
;; copy is already made: see `sys/scheme/examples/chrome.scm` in your
;; config directory.

(define safari-screen
  (screen 'com.apple.Safari

    (group "t" "Tabs"
      (key "n" "New Tab"           (λ () (send-keystroke '(cmd) "t")))
      (key "w" "Close Tab"         (λ () (send-keystroke '(cmd) "w")))
      (key "r" "Reopen Closed Tab" (λ () (send-keystroke '(cmd shift) "t"))))

    (group "b" "Browser"
      (key "l" "Focus Address Bar" (λ () (send-keystroke '(cmd) "l")))
      (key "f" "Find on Page"      (λ () (send-keystroke '(cmd) "f"))))))

;; ─── Dia browser (company.thebrowser.dia) ────────────────────────
;;
;; Machinery from (modaliser apps dia): dia:tab-step / dia:tab-step-back
;; drive Dia's ctrl-tab recent-tab switcher — the library documents the
;; ctrl-hold/release protocol the "r" walk below follows. It also
;; exports dia:tab-source / dia:focus-tab! (AppleScript tab enumeration
;; + focus-by-id), ready-made for a "Select Tab…" selector row if you
;; want chooser-based tab switching alongside f (Find Tab).

(define dia-screen
  (screen 'company.thebrowser.dia
    (key "n" "New Tab"  (λ () (send-keystroke '(cmd) "t")))
    (key "f" "Find Tab" (λ () (send-keystroke '(cmd shift) "a")))

    ;; Positional tab stepping, bound to Dia's own Tabs ▸ Next/Previous
    ;; menu shortcuts (Cmd+Shift+] / Cmd+Shift+[). Dia stacks tabs in a
    ;; *vertical* sidebar, so the hjkl mapping follows the sidebar's axis:
    ;; j (down) → next tab, k (up) → previous tab.
    ;;
    ;; A `walk` "act + latch": the j/k entry keys splice in here as
    ;; top-level Dia cells, and the first press steps a tab *and* crosses
    ;; into the 'dia-tab-walk collection, so further j/k keep stepping.
    ;; The walk is auto-tagged 'exit-on-unknown #t, so Esc or any unbound
    ;; key exits. This is *positional* stepping — distinct from the MRU
    ;; "Recent Tabs" walk on r below.
    (walk 'dia-tab-walk "Tabs"
      (key "j" "Next Tab" (λ () (send-keystroke '(cmd shift) "]")))
      (key "k" "Prev Tab" (λ () (send-keystroke '(cmd shift) "["))))

    ;; "Recent Tabs" Walk. Enter holds control and steps once, so the
    ;; HUD opens on the most-recent (next) tab; l/h step forward/back
    ;; through the MRU stack.
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
      'exit-on-unknown #t
      'on-enter (λ () (send-key-up   "ctrl")   ; clear any stale hold
                      (send-key-down "ctrl")   ; hold control (auto-asserts)
                      (dia:tab-step))          ; open HUD on the next tab
      'on-leave (λ (reason)
                  (unless (eq? reason 'confirm)
                    (send-keystroke "escape"))  ; cancel Dia's HUD
                  (send-key-up "ctrl"))         ; release (commit if confirmed)
      (key "l" "Next" (λ () (dia:tab-step)) 'next 'self)
      (key "h" "Prev" (λ () (dia:tab-step-back)) 'next 'self))))

;; ─── Finder (com.apple.finder) ───────────────────────────────────
;;
;; Curated Finder shortcuts surfaced in the overlay. Every binding emits
;; Finder's own menu shortcut via send-keystroke, so the tree tracks
;; whatever the app's menus do.
;;
;; A (screen …) whose body is only loose keys/groups renders them BARE in
;; a header-less loose region (no card): the keys as plain rows, the
;; View/Go groups as drill-down rows. There is no "General" panel.

(define finder-screen
  (screen 'com.apple.finder

    (key "n" "New Window"        (λ () (send-keystroke '(cmd) "n")))
    (key "N" "New Folder"        (λ () (send-keystroke '(cmd shift) "n")))
    (key "g" "Go to Folder…"     (λ () (send-keystroke '(cmd shift) "g")))
    (key "i" "Get Info"          (λ () (send-keystroke '(cmd) "i")))
    (key "k" "Connect to Server" (λ () (send-keystroke '(cmd) "k")))
    (key "." "Toggle Hidden"     (λ () (send-keystroke '(cmd shift) ".")))

    ;; View modes — Finder maps ⌘1–4 to Icon / List / Column / Gallery.
    (group "v" "View"
      (key "i" "Icon"    (λ () (send-keystroke '(cmd) "1")))
      (key "l" "List"    (λ () (send-keystroke '(cmd) "2")))
      (key "c" "Column"  (λ () (send-keystroke '(cmd) "3")))
      (key "g" "Gallery" (λ () (send-keystroke '(cmd) "4"))))

    ;; Go menu — the standard ⌘⇧ / ⌘⌥ destinations.
    (group "o" "Go"
      (key "h" "Home"         (λ () (send-keystroke '(cmd shift) "h")))
      (key "a" "Applications" (λ () (send-keystroke '(cmd shift) "a")))
      (key "d" "Desktop"      (λ () (send-keystroke '(cmd shift) "d")))
      (key "l" "Downloads"    (λ () (send-keystroke '(cmd alt) "l")))
      (key "r" "Recents"      (λ () (send-keystroke '(cmd shift) "f")))
      (key "c" "Computer"     (λ () (send-keystroke '(cmd shift) "c"))))))

;; ─── Apple Mail (com.apple.mail) ─────────────────────────────────
;;
;; Bindings emit Mail's native menu shortcuts.

(define mail-screen
  (screen 'com.apple.mail

    (key "n" "New Message"   (λ () (send-keystroke '(cmd) "n")))
    (key "r" "Reply"         (λ () (send-keystroke '(cmd) "r")))
    (key "R" "Reply All"     (λ () (send-keystroke '(cmd shift) "r")))
    (key "f" "Forward"       (λ () (send-keystroke '(cmd shift) "f")))
    (key "u" "Toggle Unread" (λ () (send-keystroke '(cmd shift) "u")))
    (key "j" "Mark as Junk"  (λ () (send-keystroke '(cmd shift) "j")))
    (key "g" "Get New Mail"  (λ () (send-keystroke '(cmd shift) "n")))
    (key "/" "Search"        (λ () (send-keystroke '(cmd alt) "f")))
    ;; ⌘⌫ moves the selected message to Trash.
    (key "d" "Delete"        (λ () (send-keystroke '(cmd) "backspace")))))

;; ─── Slack (com.tinyspeck.slackmacgap) ───────────────────────────
;;
;; Bindings emit Slack's documented keyboard shortcuts.

(define slack-screen
  (screen 'com.tinyspeck.slackmacgap

    (key "k" "Jump to…"        (λ () (send-keystroke '(cmd) "k")))
    (key "d" "Direct Messages" (λ () (send-keystroke '(cmd shift) "k")))
    (key "/" "Search"          (λ () (send-keystroke '(cmd) "f")))
    (key "a" "All Unreads"     (λ () (send-keystroke '(cmd shift) "a")))
    (key "t" "Threads"         (λ () (send-keystroke '(cmd shift) "t")))
    (key "m" "Mentions"        (λ () (send-keystroke '(cmd shift) "m")))
    (key "h" "Back"            (λ () (send-keystroke '(cmd) "[")))
    (key "l" "Forward"         (λ () (send-keystroke '(cmd) "]")))
    ;; Esc marks the current channel/conversation as read.
    (key "e" "Mark Read"       (λ () (send-keystroke "escape")))))

;; ─── Zed (dev.zed.Zed) ───────────────────────────────────────────
;;
;; Shortcuts confirmed against zed.dev/docs (default macOS keymap).

(define zed-screen
  (screen 'dev.zed.Zed

    (key "p" "File Finder"     (λ () (send-keystroke '(cmd) "p")))
    (key "P" "Command Palette" (λ () (send-keystroke '(cmd shift) "p")))
    (key "/" "Project Search"  (λ () (send-keystroke '(cmd shift) "f")))
    (key "f" "Find in File"    (λ () (send-keystroke '(cmd) "f")))
    (key "e" "Project Panel"   (λ () (send-keystroke '(cmd shift) "e")))
    (key "t" "Terminal"        (λ () (send-keystroke '(ctrl) "`")))))

;; ─── Signal (org.whispersystems.signal-desktop) ──────────────────
;;
;; ⚠️ Unverified: Signal's official shortcut page blocks scraping, so the
;; new/search/find bindings below are best-guess. Confirm them against
;; Signal → Help → Show Keyboard Shortcuts and adjust if wrong; the lines
;; tagged "verify" are the ones to check.

(define signal-screen
  (screen 'org.whispersystems.signal-desktop

    (key "n" "New Message"          (λ () (send-keystroke '(cmd) "n")))        ; verify
    (key "/" "Search"               (λ () (send-keystroke '(cmd shift) "f"))) ; verify
    (key "f" "Find in Conversation" (λ () (send-keystroke '(cmd) "f")))       ; verify
    (key "," "Preferences"          (λ () (send-keystroke '(cmd) ",")))))

;; ─── Apple Messages (com.apple.MobileSMS) ────────────────────────

(define messages-screen
  (screen 'com.apple.MobileSMS

    (key "n" "New Message" (λ () (send-keystroke '(cmd) "n")))
    (key "f" "Find"        (λ () (send-keystroke '(cmd) "f")))

    ;; Conversation Walk: j/k step through the conversation list and
    ;; stay armed (each carries 'next 'self); any other key exits.
    ;; ⚠️ next/prev-conversation shortcuts are unverified — confirm in
    ;; Messages (Window menu) and adjust the two "verify" lines if needed.
    (group "c" "Conversations"
      'exit-on-unknown #t
      (key "j" "Next" (λ () (send-keystroke '(cmd shift) "]")) 'next 'self)    ; verify
      (key "k" "Prev" (λ () (send-keystroke '(cmd shift) "[")) 'next 'self))))

;; ─── Telegram Desktop (com.tdesktop.Telegram) ────────────────────
;;
;; Shortcuts confirmed against the tdesktop keyboard-shortcuts reference.

(define telegram-screen
  (screen 'com.tdesktop.Telegram

    (key "k" "Jump to Chat"   (λ () (send-keystroke '(cmd) "k")))
    (key "/" "Search in Chat" (λ () (send-keystroke '(cmd) "f")))

    ;; Chats Walk — ⌘↑/⌘↓ step chats, ⌥⌘↑/↓ step unread chats. j/k stay
    ;; armed (each carries 'next 'self); any other key exits.
    (group "c" "Chats"
      'exit-on-unknown #t
      (key "j" "Next"        (λ () (send-keystroke '(cmd) "down")) 'next 'self)
      (key "k" "Prev"        (λ () (send-keystroke '(cmd) "up")) 'next 'self)
      (key "J" "Next Unread" (λ () (send-keystroke '(cmd alt) "down")) 'next 'self)
      (key "K" "Prev Unread" (λ () (send-keystroke '(cmd alt) "up")) 'next 'self))))

;; ─── Obsidian (md.obsidian) ──────────────────────────────────────
;;
;; Default hotkeys (all remappable in Obsidian → Settings → Hotkeys).

(define obsidian-screen
  (screen 'md.obsidian

    (key "o" "Quick Switcher"   (λ () (send-keystroke '(cmd) "o")))
    (key "p" "Command Palette"  (λ () (send-keystroke '(cmd) "p")))
    (key "n" "New Note"         (λ () (send-keystroke '(cmd) "n")))
    (key "/" "Search All Files" (λ () (send-keystroke '(cmd shift) "f")))
    (key "f" "Find in File"     (λ () (send-keystroke '(cmd) "f")))
    (key "g" "Graph View"       (λ () (send-keystroke '(cmd) "g")))))

;; ─── Zotero (org.zotero.zotero) ──────────────────────────────────
;;
;; Deliberately small: most Zotero shortcuts are user-customizable in
;; Settings → Advanced, so only the stable ⌘F / ⌘⇧F search bindings are
;; surfaced here. Add your own as you set them.

(define zotero-screen
  (screen 'org.zotero.zotero

    (key "/" "Quick Search"    (λ () (send-keystroke '(cmd) "f")))
    (key "a" "Advanced Search" (λ () (send-keystroke '(cmd shift) "f")))))

;; ─── iTerm (com.googlecode.iterm2) ───────────────────────────────
;;
;; iTerm is a terminal-like HOST: (iterm:wiring) — composed below —
;; carries the integration (the backend record, whose match-key is what
;; makes this screen terminal-like, and the digit-jump mode tree). This
;; screen carries the DECISIONS: which of iTerm's operations are
;; surfaced, on which keys, under which labels (ADR-0021). Every
;; `iterm:`-prefixed name below is an op or a block exported by
;; (modaliser apps iterm) — see docs/reference/libraries.md for the full
;; list. Rebind, drop, or regroup any of it.
;;
;; Being terminal-like, the screen consults the Terminal context map at
;; every F17 press, and the machinery derives its gated "." step-in edge
;; — neither is authored here.
;;
;; TWO SCOPE SYMBOLS ARE MACHINERY, not preference: 'com.googlecode.iterm2
;; (the backend record's match-key — a screen under any other scope is
;; not terminal-like) and 'iterm-pane-digit (the record names it by key).
;; 'iterm-split-walk / 'iterm-tab-walk / 'iterm-panes-focus below are
;; ours to name.

;; A standalone hjkl focus mode, registered as a tree so any key can
;; name it as a 'next cross target — including from another screen.
;; Nothing here reaches it by default; it is the seam the how-to guides
;; point at (docs/reference/state-machine.md).
(define iterm-focus-walk
  (tree 'iterm-panes-focus
    (tree-root 'iterm-panes-focus
      'exit-on-unknown #t
      'display-name "Focus"
      (key "h" "Left"  iterm:focus-pane-left  'next 'self)
      (key "j" "Down"  iterm:focus-pane-down  'next 'self)
      (key "k" "Up"    iterm:focus-pane-up    'next 'self)
      (key "l" "Right" iterm:focus-pane-right 'next 'self))))

(define iterm-screen
  (screen 'com.googlecode.iterm2

    (key "c" "Copy Mode"   iterm:copy-mode)
    (key "z" "Toggle Zoom" iterm:toggle-pane-zoom)

    ;; One-shot iTerm key-binding setup: the splits, moves, copy mode and
    ;; zoom above ride on eight entries in iTerm's GlobalKeyMap, and this
    ;; writes them (behind a confirm dialog, backing up iTerm's prefs
    ;; first). 'hidden takes the library's probe, so the row retires
    ;; itself on the next overlay open once iTerm is configured — no
    ;; relaunch. Drop the row if you provisioned iTerm by hand.
    (key "C-I" "Configure iTerm" iterm:configure! 'hidden iterm:configured?)

    ;; Splits panel — one-shot pane focus (hjkl: fire-and-exit) plus the
    ;; full split toolkit behind s.
    (panel "Splits"
      (key "h" "Focus Left"  iterm:focus-pane-left)
      (key "j" "Focus Down"  iterm:focus-pane-down)
      (key "k" "Focus Up"    iterm:focus-pane-up)
      (key "l" "Focus Right" iterm:focus-pane-right)
      (open "s" "Splits"
        ;; (walk …) writes each "act + latch" set ONCE: it registers the
        ;; mode tree (where hjkl/HJKL keep firing, each re-arming in
        ;; place) AND yields a splice of entry keys dropped in here, so
        ;; the key list is not duplicated between the two. Splits are
        ;; 2-D, so each of hjkl is a distinct direction.
        (walk 'iterm-split-walk "Splits" 'order 'declared
          (key "h" "Focus Left"  iterm:focus-pane-left)
          (key "j" "Focus Down"  iterm:focus-pane-down)
          (key "k" "Focus Up"    iterm:focus-pane-up)
          (key "l" "Focus Right" iterm:focus-pane-right)
          (key "H" "Move Left"   iterm:move-pane-left)
          (key "J" "Move Down"   iterm:move-pane-down)
          (key "K" "Move Up"     iterm:move-pane-up)
          (key "L" "Move Right"  iterm:move-pane-right))
        (group "n" "New Split"
          (key "h" "Split Left"  iterm:split-pane-left)
          (key "j" "Split Down"  iterm:split-pane-down)
          (key "k" "Split Up"    iterm:split-pane-up)
          (key "l" "Split Right" iterm:split-pane-right))
        ;; 'chips? #t paints the digit labels over the real panes.
        (panel "Panes" (iterm:pane-list-block 'chips? #t))))

    ;; Tabs sub-screen: r/n/d act on tabs, the walk splices the
    ;; Focus/Move entry keys, and the tab list block lifts its digits
    ;; onto the open. iTerm's tab strip is vertical here, so h/k reach
    ;; Prev and j/l reach Next — swap them if yours is horizontal.
    (open "t" "Tabs"
      (key "r" "Rename" iterm:rename-tab!)
      (key "n" "New"    iterm:new-tab!)
      (key "d" "Delete" iterm:close-tab!)
      (walk 'iterm-tab-walk "Tabs" 'order 'declared
        (key "h" "Focus Prev" iterm:tab-focus-prev)
        (key "j" "Focus Next" iterm:tab-focus-next)
        (key "k" "Focus Prev" iterm:tab-focus-prev)
        (key "l" "Focus Next" iterm:tab-focus-next)
        (key "H" "Move Prev"  iterm:tab-move-prev)
        (key "J" "Move Next"  iterm:tab-move-next)
        (key "K" "Move Prev"  iterm:tab-move-prev)
        (key "L" "Move Next"  iterm:tab-move-next))
      (panel "Tabs" (iterm:tab-list-block)))

    ;; Top-level pane list — the most-used path, surfaced here as well as
    ;; inside the Splits screen (which keeps that subtree self-contained).
    (panel "Panes" (iterm:pane-list-block 'chips? #t))))

;; ─── herdr (agent multiplexer) ───────────────────────────────────
;;
;; herdr is an *inner tool*, not an app: it runs inside a terminal pane.
;; So its screen is not keyed on a bundle id — it is keyed on the scope
;; 'herdr and reached through the Terminal context map at the bottom of
;; this file, which sends F17 straight here whenever the focused pane is
;; running herdr, in ANY terminal host.
;;
;; (herdr:wiring) — composed into (terminal-contexts …) below — carries
;; the integration: the context-map entry, herdr's terminal backend, and
;; the digit-jump mode tree. This screen carries the DECISIONS: which of
;; herdr's operations are surfaced, on which keys, under which labels
;; (ADR-0021). Every `herdr:`-prefixed name below is an op, a block, or a
;; provider exported by (modaliser muxes herdr) — see
;; docs/reference/libraries.md for the full list. Rebind, drop, or
;; regroup any of it; nothing here is load-bearing for herdr working.
;;
;; TWO SCOPE SYMBOLS ARE MACHINERY, not preference, and must keep their
;; names: 'herdr (the wiring's context entry resolves to it, and the jump
;; provider mints its narrowing states under it) and 'herdr-panes-focus
;; (the Focus rows cross into it). Rename either and the configuration
;; fails reference-closure validation at load — loudly, not silently.

;; herdr's client keybinding prefix. herdr offers no way to ask it what
;; the prefix resolved to, so this is an assumption: if you rebound
;; herdr's prefix in herdr's own config, change this one line and the
;; three keystroke-emitting ops below follow.
(define herdr-prefix herdr:herdr-default-prefix)   ; ⌃b

;; `[` Prev / `]` Next over a live list's displayed rows, as a reusable
;; splice — one keystroke tours the ring, so each key carries 'next 'self
;; (a cyclic edge re-arming in place) rather than entering a sub-mode.
;; The (kind focus-fn scope-id-fn) triple must match the list block it
;; sits beside, so ring and list agree on scope.
(define (herdr-cycle kind focus-fn scope-id-fn)
  (splice
    (key "[" "Prev" (herdr:cycle-prev-op kind focus-fn scope-id-fn) 'next 'self)
    (key "]" "Next" (herdr:cycle-next-op kind focus-fn scope-id-fn) 'next 'self)))

;; The Focus walk the Panes drill's hjkl cross into: the first press
;; focuses AND switches here, and each member re-arms in place, so
;; further hjkl keep moving focus without another leader press. `[`/`]`
;; ride along so cycling stays reachable mid-walk. Registered as a tree
;; in its own right, which is what makes it a valid 'next target.
(define herdr-focus-walk
  (tree 'herdr-panes-focus
    (tree-root 'herdr-panes-focus
      'exit-on-unknown #t
      'display-name "Focus"
      (key "h" "Left"  herdr:focus-pane-left  'next 'self)
      (key "j" "Down"  herdr:focus-pane-down  'next 'self)
      (key "k" "Up"    herdr:focus-pane-up    'next 'self)
      (key "l" "Right" herdr:focus-pane-right 'next 'self)
      (herdr-cycle 'panes herdr:focus-pane-by-id herdr:focused-tab-id))))

(define herdr-screen
  (screen 'herdr
    'display-name "herdr"

    ;; The jump space. 'provider re-mints one lowercase key per visible
    ;; pane / space / agent / tab on every come-to-rest; the on-enter /
    ;; on-leave pair paints and clears the matching on-screen chips when
    ;; the overlay actually shows; the Jump panel at the bottom lists the
    ;; same assignment. Drop all four together if you don't want it.
    'provider herdr:herdr-jump-provider
    'on-enter herdr:paint-jump-chips!
    'on-leave herdr:clear-jump-chips!

    (open "P" "Panes"
      (panel "Focus"
        (key "h" "Left"  herdr:focus-pane-left  'next 'herdr-panes-focus)
        (key "j" "Down"  herdr:focus-pane-down  'next 'herdr-panes-focus)
        (key "k" "Up"    herdr:focus-pane-up    'next 'herdr-panes-focus)
        (key "l" "Right" herdr:focus-pane-right 'next 'herdr-panes-focus))
      (group "n" "New"
        (key "h" "Left"  herdr:split-pane-left)
        (key "j" "Down"  herdr:split-pane-down)
        (key "k" "Up"    herdr:split-pane-up)
        (key "l" "Right" herdr:split-pane-right))
      ;; Move swaps the focused pane with its neighbour. A re-arming walk
      ;; ('next 'self) with 'exit-on-unknown, so a stray key exits rather
      ;; than trapping you.
      (group "m" "Move"
        'exit-on-unknown #t
        (key "h" "Left"  herdr:move-pane-left  'next 'self)
        (key "j" "Down"  herdr:move-pane-down  'next 'self)
        (key "k" "Up"    herdr:move-pane-up    'next 'self)
        (key "l" "Right" herdr:move-pane-right 'next 'self))
      (key "z" "Zoom"  herdr:toggle-pane-zoom)
      (key "d" "Close" herdr:close-pane)
      (herdr-cycle 'panes herdr:focus-pane-by-id herdr:focused-tab-id)
      ;; 'chips? #t paints the digit labels over the real panes on screen.
      (panel "Panes" (herdr:pane-list-block 'chips? #t)))

    (open "T" "Tabs"
      (key "n" "New"    herdr:new-tab)
      (key "r" "Rename" herdr:rename-focused-tab!)
      (key "d" "Close"  herdr:close-focused-tab)
      ;; herdr draws tabs in a horizontal bar, so Move offers h/l only —
      ;; a key for an axis the target cannot travel would be a lie.
      (group "m" "Move"
        'exit-on-unknown #t
        (key "h" "Left"  herdr:move-tab-left  'next 'self)
        (key "l" "Right" herdr:move-tab-right 'next 'self))
      (herdr-cycle 'tabs herdr:focus-tab-by-id herdr:focused-workspace-id)
      (panel "Tabs" (herdr:tab-list-block)))

    ;; "Spaces" is herdr's own UI term for what its API calls workspaces —
    ;; the labels follow the UI, the identifiers follow the API.
    (open "S" "Spaces"
      (key "n" "New"    herdr:new-workspace)
      (key "r" "Rename" herdr:rename-focused-workspace!)
      (key "d" "Close"  herdr:close-focused-workspace)
      ;; Spaces are a vertical sidebar list, so Move offers k/j.
      (group "m" "Move"
        'exit-on-unknown #t
        (key "k" "Up"   herdr:move-space-up   'next 'self)
        (key "j" "Down" herdr:move-space-down 'next 'self))
      (herdr-cycle 'workspaces herdr:focus-workspace-by-id #f)
      (panel "Spaces" (herdr:workspace-list-block)))

    ;; Worktrees: the digit rows smart-switch — focus the live space when
    ;; the worktree is open, else open the dormant worktree. `d` removes
    ;; behind a confirm, and never forces, so git still refuses a dirty
    ;; worktree.
    (open "W" "Worktrees"
      (key "n" "New"    herdr:new-worktree!)
      (key "d" "Remove" herdr:remove-focused-worktree!)
      (panel "Worktrees" (herdr:worktree-list-block)))

    ;; One keystroke to the next agent waiting on you — the differentiator,
    ;; so it keeps a top-level key rather than living inside `A`.
    (key "b" "Jump to Blocked" herdr:jump-to-next-blocked)

    (open "A" "Agents"
      (herdr-cycle 'agents herdr:focus-pane-by-id #f)
      (panel "Agents" (herdr:agent-list-block)))

    ;; herdr's two text-inspection surfaces — distinct operations, not two
    ;; spellings of one. Copy Mode selects in the LIVE pane; Scrollback
    ;; opens that pane's buffer in an editor. A host terminal's own copy
    ;; mode is wrong for both: it sees herdr as one session and selects
    ;; across the whole canvas, ignoring herdr's panes.
    ;;
    ;; Both emit herdr-prefix followed by herdr's own second key, so they
    ;; also assume herdr's defaults for `copy_mode` / `edit_scrollback`;
    ;; if you rebound those in herdr, write the thunk yourself.
    ;;
    ;; Keeping Copy Mode on `c` is why `c` never appears as a jump label:
    ;; a statically-bound key shadows a provider-supplied one, so a `c`
    ;; label would be silently unreachable. Rebind it elsewhere if you
    ;; like — `c` still won't become a jump label.
    (key "c" "Copy Mode"  (herdr:copy-mode-op  herdr-prefix))
    (key "C" "Scrollback" (herdr:scrollback-op herdr-prefix))

    ;; "Quit" alone is ambiguous between ending the client and ending the
    ;; server, so both are named. Detach leaves the server and every pane
    ;; running; Stop Server terminates them (behind a confirm).
    (group "Q" "Quit"
      (key "d" "Detach"      (herdr:detach-op herdr-prefix))
      (key "s" "Stop Server" herdr:stop-server!))

    ;; The jump legend: label → target, reading the same per-visit snapshot
    ;; the chips paint from, so the two can never disagree.
    (panel "Jump" (herdr:jump-legend-block))))

;; ─── zellij (terminal multiplexer) ───────────────────────────────
;;
;; Another inner tool, so the same shape as herdr: (zellij:wiring) —
;; composed below — carries the integration (the context-map entry,
;; zellij's terminal backend, and the digit-jump mode tree the backend
;; fires at), and this screen carries the DECISIONS (ADR-0021). Every
;; `zellij:`-prefixed name below is one of the fourteen ops exported by
;; (modaliser muxes zellij), each a `zellij action …` invocation.
;;
;; THE SCOPE SYMBOL 'zellij IS MACHINERY: the wiring's context entry
;; resolves to it, so renaming it fails reference-closure validation at
;; load rather than silently unbinding the screen.
;;
;; Digit jump needs no binding here — the backend names its own
;; 'zellij-pane-digit tree, and the host's pane-list block fires it.

(define zellij-screen
  (screen 'zellij
    'display-name "zellij"

    ;; hjkl focus, each re-arming in place ('next 'self), so one leader
    ;; press starts a run of moves. There is no separate Focus walk here
    ;; the way iTerm and herdr have one: zellij's screen is small enough
    ;; that the top-level rows can latch directly.
    (panel "Focus"
      (key "h" "Focus Left"  zellij:focus-pane-left  'next 'self)
      (key "j" "Focus Down"  zellij:focus-pane-down  'next 'self)
      (key "k" "Focus Up"    zellij:focus-pane-up    'next 'self)
      (key "l" "Focus Right" zellij:focus-pane-right 'next 'self))

    ;; Splits fire and exit — you almost never want two in a row.
    (group "n" "New Split"
      (key "h" "Split Left"  zellij:split-pane-left)
      (key "j" "Split Down"  zellij:split-pane-down)
      (key "k" "Split Up"    zellij:split-pane-up)
      (key "l" "Split Right" zellij:split-pane-right))

    ;; Move swaps the focused pane with its neighbour, so it latches like
    ;; Focus; 'exit-on-unknown means a stray key leaves rather than traps.
    (group "m" "Move Pane"
      'exit-on-unknown #t
      (key "h" "Left"  zellij:move-pane-left  'next 'self)
      (key "j" "Down"  zellij:move-pane-down  'next 'self)
      (key "k" "Up"    zellij:move-pane-up    'next 'self)
      (key "l" "Right" zellij:move-pane-right 'next 'self))

    (key "z" "Toggle Zoom" zellij:toggle-pane-zoom)))

;; ─── Neovim (nvim) ───────────────────────────────────────────────
;;
;; nvim is an inner tool that hosts no panes of its own — its splits are
;; nvim windows, driven over nvim's RPC socket — so (nvim:wiring) is a
;; single context-map entry and there is no backend record. As above,
;; the scope symbol 'nvim is machinery; everything else here is taste.
;;
;; Deliberately small: nvim power users live inside nvim's own maps, and
;; this exists so the hjkl pane-focus muscle memory crosses INTO nvim
;; windows. To reach the rest of nvim's `<C-w>` repertoire, build the
;; thunk yourself — (nvim:wincmd "v") splits vertically, "s"
;; horizontally, "=" equalises, "q" closes.

(define nvim-screen
  (screen 'nvim
    'display-name "Neovim"
    (panel "Windows"
      (key "h" "Focus Left"  nvim:focus-window-left  'next 'self)
      (key "j" "Focus Down"  nvim:focus-window-down  'next 'self)
      (key "k" "Focus Up"    nvim:focus-window-up    'next 'self)
      (key "l" "Focus Right" nvim:focus-window-right 'next 'self))))

;; ─── The configuration value → the engine ────────────────────────
;;
;; (configuration fragment…) is a PURE merge: it flattens the fragments
;; into one value keyed by scope / backend symbol / exe / setting name,
;; erroring on any genuine collision (there is no override and no
;; last-wins — customization is composition, not patching). The result
;; is the complete, printable description of what the engine runs.
;;
;; (modaliser:start! …) is the ONE effectful moment: it validates the
;; value (every authored reference must resolve), installs it — graph,
;; backends, settings — and arms the leaders. One-shot: reload is
;; relaunch. A config that errors before this call leaves the engine
;; cleanly empty.

(modaliser:start!
  (configuration

    ;; Leader keys — F18 global, F17 local. 'arm-when-frontmost
    ;; suppresses leader arming while the Jump Desktop remote viewer is
    ;; in front (its modifiers are reserved for the remote machine).
    (leaders
      (leader 'global F18 'arm-when-frontmost '("com.p5sys.jump.mac.viewer"))
      (leader 'local  F17 'arm-when-frontmost '("com.p5sys.jump.mac.viewer")))

    ;; Seconds the modal waits before showing the overlay — fast
    ;; muscle-memory sequences never see it paint.
    (overlay-delay 0.3)

    ;; The F18 global screen defined above.
    global-screen

    ;; iTerm's integration: the terminal backend record and the
    ;; digit-jump mode tree. The screen is below.
    (iterm:wiring)

    ;; The Terminal context map: exe → tree, consulted by any
    ;; terminal-like screen. When the focused pane runs one of these,
    ;; F17 lands directly in that tool's tree; backspace steps back out
    ;; through the chain; "." steps inward. One entry per inner tool —
    ;; no host is named, so the same entries work in any terminal whose
    ;; wiring is composed here. Each entry pairs with a screen of the
    ;; same scope, authored above.
    ;;
    ;; Using tmux? A fresh install does not seed it, so the stock tmux
    ;; composition ships as an EXAMPLE rather than as live config: copy
    ;; the marked pieces out of `sys/scheme/examples/tmux.scm` in your
    ;; config directory (the import, the screen, and the (tmux:wiring)
    ;; line for the call below) into this file.
    (terminal-contexts
      (herdr:wiring)       ; map entry + backend + digit-jump tree
      (zellij:wiring)      ; likewise, for the zellij action CLI
      (nvim:wiring))       ; map entry alone — nvim hosts no panes

    ;; The inner-tool and host screens, and the Focus walks two of them
    ;; register, all authored above.
    iterm-screen
    iterm-focus-walk
    herdr-screen
    herdr-focus-walk
    zellij-screen
    nvim-screen

    ;; Per-app screens, all authored inline above.
    safari-screen
    dia-screen
    finder-screen
    mail-screen
    slack-screen
    zed-screen
    signal-screen
    messages-screen
    telegram-screen
    obsidian-screen
    zotero-screen))
