;; iTerm2 (com.googlecode.iterm2) — F17 local tree.
;;
;; Split out of config.scm into its own per-bundle-id file, included via
;; (include "app-trees/com.googlecode.iterm2.scm"). Inherits config.scm's
;; imports (dsl, terminal, input, shell, …); no per-file import needed.

;; Register the iTerm backend with (modaliser terminal) so the façade's
;; (terminal:focus-pane-*) / (terminal:split-pane-*) / (terminal:move-
;; pane-*) calls below route to iTerm. 'install-tree? #f skips the
;; library's own rebuild-tree! — the inline (screen 'com.googlecode.iterm2
;; …) below is the tree we want, not the library's stock one.
;;
;; 'install-context-suffix? #f: we compose our OWN suffix hook at the
;; bottom of this file (herdr replace/augment + the iTerm nvim/zellij
;; branch). A single global suffix slot is last-write-wins, so herdr must
;; compose, not install a second hook — see ADR-0013 and the
;; set-local-context-suffix! call below.
(iterm:register! 'install-tree? #f 'install-context-suffix? #f)

;; Register the herdr mux backend so (terminal:in-chain? 'herdr) resolves
;; when the focused iTerm pane runs the herdr client. This is what the
;; composed suffix hook (bottom of file) gates the herdr variant trees on.
(herdr:register!)

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

;; ── Tab + Split Walk navigation sets ─────────────────────────────────
;; Shared 0-arg tab action thunks. The tab list is vertical, so
;; "previous" = up/left and "next" = down/right.
(define (tab-focus-prev) (send-keystroke '(cmd shift) "["))      ; ⌘⇧[
(define (tab-focus-next) (send-keystroke '(cmd shift) "]"))      ; ⌘⇧]
(define (tab-move-prev)  (send-keystroke '(alt shift cmd) "["))  ; ⌥⇧⌘[
(define (tab-move-next)  (send-keystroke '(alt shift cmd) "]"))  ; ⌥⇧⌘]

;; (walk …) defines each "act + latch" set ONCE: it registers the mode
;; tree (the latch target, where hjkl/HJKL keep firing, each cycling via
;; 'next 'self) AND yields a splice node we drop into the Tabs/Splits
;; sub-screens below — so the key list isn't duplicated between the mode
;; and the entry points. The operation is in each label, so no panel
;; grouping is needed.
(define tab-nav
  (walk 'iterm-tab-walk "Tabs" 'order 'declared
    (key "h" "Focus Prev" tab-focus-prev)
    (key "j" "Focus Next" tab-focus-next)
    (key "k" "Focus Prev" tab-focus-prev)
    (key "l" "Focus Next" tab-focus-next)
    (key "H" "Move Prev"  tab-move-prev)
    (key "J" "Move Next"  tab-move-next)
    (key "K" "Move Prev"  tab-move-prev)
    (key "L" "Move Next"  tab-move-next)))

;; Panes (iTerm "splits") are 2-D, so each of hjkl is a distinct
;; direction; terminal:{focus,move}-pane-* come from (modaliser terminal).
(define split-nav
  (walk 'iterm-split-walk "Splits" 'order 'declared
    (key "h" "Focus Left"  terminal:focus-pane-left)
    (key "j" "Focus Down"  terminal:focus-pane-down)
    (key "k" "Focus Up"    terminal:focus-pane-up)
    (key "l" "Focus Right" terminal:focus-pane-right)
    (key "H" "Move Left"   terminal:move-pane-left)
    (key "J" "Move Down"   terminal:move-pane-down)
    (key "K" "Move Up"     terminal:move-pane-up)
    (key "L" "Move Right"  terminal:move-pane-right)))

;; iTerm tree inlined here (formerly (iterm:register!)) so it's easy
;; to tweak. The pane-selection mechanism is the (iterm:pane-list-block)
;; block: it paints pane chips, renders a row list (one per pane), and
;; dispatches digits 1..0 to focus the matching pane by session UUID.
;; Layout is re-snapshotted on every overlay open, so panes added or moved
;; between presses Just Work without a separate tree rebuild step.
;;
;; Splits, pane moves, Copy Mode and Toggle Zoom rely on eight iTerm
;; key bindings. The (iterm:configure-entry) action below provisions
;; them — it appears in this screen as "Configure iTerm" (Ctrl+Shift+I)
;; only while iTerm is unconfigured, and vanishes once set up.

(screen 'com.googlecode.iterm2

  (key "c" "Copy Mode"   (λ () (send-keystroke '(cmd shift) "c")))
  (key "z" "Toggle Zoom" (λ () (send-keystroke '(cmd shift) "return")))

  ;; One-shot iTerm key-binding setup. Hidden once iTerm is configured.
  (iterm:configure-entry)

  ;; Splits panel — one-shot pane focus (h/j/k/l: fire-and-exit, no latching)
  ;; plus the full split toolkit behind s, in one panel. Pressing s drills
  ;; into the Splits sub-screen: split-nav splices the Focus (hjkl) /
  ;; Move (HJKL) Walk (each crossing into 'iterm-split-walk); n → hjkl makes a
  ;; new split in that direction; the pane-list block paints chips and
  ;; dispatches digits 1..0 to focus a pane by number. terminal:{focus,split}-
  ;; pane-* are the (modaliser apps iterm) factory's 0-arg procedures
  ;; (split-then-swap for left/up lives in the library). A nested (open …)
  ;; inside a panel renders as a drill-down row (see PanelGridRendererTests).
  (panel "Splits"
    (key "h" "Focus Left"  terminal:focus-pane-left)
    (key "j" "Focus Down"  terminal:focus-pane-down)
    (key "k" "Focus Up"    terminal:focus-pane-up)
    (key "l" "Focus Right" terminal:focus-pane-right)
    (open "s" "Splits"
      split-nav
      (group "n" "New Split"
        (key "h" "Split Left"  terminal:split-pane-left)
        (key "j" "Split Down"  terminal:split-pane-down)
        (key "k" "Split Up"    terminal:split-pane-up)
        (key "l" "Split Right" terminal:split-pane-right))
      (panel "Panes"
        (iterm:pane-list-block 'chips? #t))))

  ;; Tabs sub-screen (t). The tab-list block lifts its hidden 1.. range onto
  ;; the open's group, so pressing t shows every tab (the focused one marked)
  ;; and a digit switches to it. r/n/d act on tabs; tab-nav splices in the
  ;; Focus (hjkl) / Move (HJKL) entry keys, which cross into the
  ;; 'iterm-tab-walk mode. The vertical tab list makes h/k = Prev and j/l = Next.
  (open "t" "Tabs"
    (key "r" "Rename" rename-iterm-tab!)
    (key "n" "New"    new-iterm-tab!)
    (key "d" "Delete" close-iterm-tab!)
    tab-nav
    (panel "Tabs"
      (iterm:tab-list-block)))

  ;; Top-level pane list — pane chips + digits 1..0 to focus a pane by
  ;; number. The most-used path, so it's surfaced here at the top level
  ;; (it also lives inside the Splits screen s, keeping that subtree
  ;; self-contained). Live list → wide panel.
  (panel "Panes"
    (iterm:pane-list-block 'chips? #t)))

;; ── herdr variant trees (ADR-0013) ──────────────────────────────────
;;
;; When the focused iTerm pane runs the herdr client, the composed suffix
;; hook below swaps in a herdr variant tree. herdr owns the top-level hjkl
;; pane focus in both (identical muscle memory); the augment tree is the
;; replace tree PLUS the iTerm `i`-splits drill for the other iTerm splits.
;; Both are skeletons here — the full herdr surface (splits / move / zoom /
;; digit-jump, tabs, workspaces) is grown alongside the herdr block helpers.

;; herdr per-pane scrollback, reachable at the herdr tree top level in BOTH
;; variants (herdr-copy-mode-k16). The replace tree ships zero iTerm controls by
;; design, so without this there is no way to reach scrollback/copy when herdr
;; owns the whole window — the gap the user hit.
;;
;; iTerm's own Copy Mode (Cmd+Shift+C) is WRONG here: iTerm sees herdr as a
;; SINGLE session and paints selection across the entire herdr canvas, ignoring
;; herdr's per-pane layout. herdr's native per-pane scrollback (edit_scrollback,
;; default `prefix e` = `ctrl+b e`) is layout-aware — it acts on herdr's focused
;; pane. herdr's CLI/socket API cannot trigger it (edit_scrollback is a
;; client-side UI binding; `pane send-keys` targets the shell PTY, not herdr's
;; input layer), so we send the `ctrl+b e` keystroke sequence into the focused
;; iTerm session where the herdr client is listening: prefix (ctrl+b) then e.
;; Each send-keystroke is self-contained (ctrl is bracketed on `b` only), so the
;; trailing `e` carries no stray modifier.
;;
;; It is a HOST-delivered keystroke, hence host-specific, so it lives HERE at
;; the config composition layer, not in the portable host-agnostic
;; (muxes herdr) build-herdr-tree. In replace mode herdr owns the sole iTerm
;; session so the sequence lands on it; in augment mode it lands on the focused
;; (herdr) split (the herdr trees only show when herdr is focused). `c` is free
;; in build-herdr-tree (top-level keys: x m z d t w g b a).
;;
;; v1 assumption: the user runs herdr on the DEFAULT prefix (ctrl+b). herdr
;; exposes no CLI to query the resolved prefix; if the user rebinds herdr's
;; prefix, update the ctrl+b below to match.
(define herdr-copy-mode-key
  (key "c" "Scrollback"
       (λ ()
         (send-keystroke '(ctrl) "b")   ; herdr prefix
         (send-keystroke "e"))))        ; edit_scrollback (per-pane)

;; Replace: herdr is the sole current-tab iTerm split, so it owns the whole
;; window — a herdr-only tree, zero iTerm controls (plus the shared Scrollback).
(apply screen 'com.googlecode.iterm2/herdr
  (append (herdr:build-herdr-tree)
          (list herdr-copy-mode-key)))

;; Augment: the iTerm window carries other splits too, so the herdr tree
;; gains an `i` drill for the iTerm splits. The drill binds iterm-DIRECT
;; ops — in augment mode the (modaliser terminal) façade resolves to herdr,
;; so its shims would drive the wrong layer.
(apply screen 'com.googlecode.iterm2/herdr+split
  (append (herdr:build-herdr-tree)
          (list herdr-copy-mode-key
                (iterm:build-iterm-splits-drill))))

;; The composed context-suffix hook. One global slot, last-write-wins, so
;; this single handler does both jobs (ADR-0013):
;;   1. herdr focused in iTerm → classify replace vs augment by the
;;      CURRENT-TAB split count (tab-scoped iterm-list-session-ids, NOT an
;;      all-tabs AX count — avoids the multi-tab miscount, R1). The
;;      (terminal:in-chain? 'herdr) gate short-circuits the AppleScript
;;      count query when herdr is not focused.
;;   2. Otherwise delegate to (iterm:context-suffix-handler …) for the
;;      existing nvim / zellij branches. 'rebuild? #f keeps it from
;;      clobbering the inline (screen 'com.googlecode.iterm2 …) tree above
;;      (it still refreshes the pane snapshot the pane-list block reads).
(set-local-context-suffix!
 (lambda (bundle-id)
   (or (and (equal? bundle-id "com.googlecode.iterm2")
            (terminal:in-chain? 'herdr)
            (herdr:classify-herdr-variant
             (length (iterm:iterm-list-session-ids))))
       (iterm:context-suffix-handler bundle-id 'rebuild? #f))))
