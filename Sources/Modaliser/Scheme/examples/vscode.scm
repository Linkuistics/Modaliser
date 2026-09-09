;; Modaliser example — a per-app screen for Visual Studio Code.
;;
;; ⚠️ THIS FILE IS NEVER LOADED. Modaliser reads exactly one user file,
;; `~/.config/modaliser/config.scm`; everything in `examples/` is
;; reference material that arrives fresh with each installed build (via
;; the `sys/` mirror) and sits there inert. Nothing you change here has
;; any effect, and nothing here can go stale in your config.
;;
;; It exists because a fresh install seeds a Safari screen but not a
;; VSCode one — the seed can only carry one set of choices, and choices
;; are the one thing Modaliser's libraries deliberately do not make for
;; you (docs/adr/0021-decision-free-libraries.md).
;;
;; TO USE IT, one of:
;;
;;   • Copy the three marked ▶ blocks below into your own
;;     `~/.config/modaliser/config.scm` — the import, the screen, and
;;     the one line for the `(configuration …)` call at its bottom.
;;   • Or copy this whole file over `config.scm` as a starting point: it
;;     is a complete, working configuration in its own right (that is
;;     also how the test suite proves it still composes).
;;
;; Then relaunch Modaliser. With VSCode focused, F17 lands here.
;;
;; ─── What this example is really showing ─────────────────────────
;;
;; The other half of the story `examples/chrome.scm` tells. Chrome needs
;; no library at all: its screen is menu shortcuts and `send-keystroke`.
;; VSCode is the case where a library earns its place — not because the
;; chords are hard, but because "select from the open windows" needs the
;; window enumeration filtered to VSCode, reshaped so the thing you see
;; is the PROJECT rather than the window title, ordered so the same
;; project sits in the same place twice running, and focused back
;; through a choice alist that keeps the real title as its fallback
;; match. That is machinery, it is version-sensitive, and it belongs
;; somewhere it stays current across upgrades. The keys and labels
;; below are the half that does not: they are yours — including the
;; three alphabets the Projects panel draws its jump labels from.
;;
;; The screen's last row goes further: it composes TWO libraries that
;; know nothing of each other — `(modaliser apps vscode)`, which can say
;; which folder the front window is rooted at, and `(modaliser tools
;; grove)`, which can say which task file is live in a folder — into
;; "open this project's grove leaf". That join is a decision, so it
;; lives in configuration rather than in either library, and it is the
;; clearest example in the examples/ tree of why the split is drawn
;; where it is.
;;
;; Read `(modaliser apps vscode)`'s own header before rebinding
;; anything — it records what each of the three chords ACTUALLY does,
;; established against the shipped VSCode bundle. In particular:
;; ctrl-` is a toggle and hides the terminal when the terminal already
;; has focus, and shift-cmd-e bounces to the editor when the explorer
;; already has focus. Both are VSCode's behaviour, not Modaliser's. The
;; same header explains why the `[` / `]` rows below go through
;; `editor-cycler` rather than sending the cycle chords directly.

;; ▶ 1/3 — the import. Prefix-style, as with every peer app library:
;; the bare exports (`window-source`, `focus-window!`) would collide.
(import (modaliser dsl)
        (modaliser configuration)
        (modaliser handoff)
        (modaliser keyboard)
        (modaliser input)
        (modaliser app)
        (modaliser dialogs)
        (prefix (modaliser apps vscode) code:)
        ;; For the "Grove Leaf" row at the bottom of the screen. Drop
        ;; this import and that row together if you do not use grove —
        ;; nothing else on the screen touches it.
        (prefix (modaliser tools grove) grove:))

;; The jump-label alphabet for the Projects panel, named once and
;; passed three times below (one-key pool, leader preference order,
;; second-key pool). A label that collides with a bound key loses, so
;; the home row here cost one move: Grove Leaf sits on "G" rather than
;; "g". That is preference and it is yours — the library defaults no
;; alphabet and authors no key (ADR-0021), so both this list and the
;; keys it has to dodge are decisions you make, not ones you inherit.
(define vscode-label-keys '("a" "s" "d" "f" "g"))

;; ▶ 2/3 — the VSCode screen. Keys, labels and grouping are preference;
;; rebind, drop or regroup any of it. The scope symbol is VSCode's
;; bundle id, which is what makes F17 land here when VSCode is frontmost.
(define vscode-screen
  (screen 'com.microsoft.VSCode

    ;; The Edge provider behind the Projects panel at the bottom of this
    ;; screen. At come-to-rest — once per visit, before anything renders
    ;; — it enumerates the open VSCode windows, orders them by PROJECT
    ;; (the folder each is rooted at), and mints exactly the jump labels
    ;; that many projects earn. The panel below draws that same
    ;; assignment, so the rows and the live labels cannot disagree, and a
    ;; label pressed faster than the overlay appears still works.
    ;;
    ;; Cross-space: a project parked on another desktop is labelled and
    ;; reachable like any other.
    ;;
    ;; ALL THREE ALPHABETS ARE YOURS and none is defaulted — jump labels
    ;; are keys, and no library authors a key (ADR-0021). Passing the
    ;; same list three times is the ordinary case: it doubles as the
    ;; one-key pool, the leader preference order, and the second-key
    ;; pool. Escalation is automatic — five single-key labels here, and
    ;; past that each leader opens five more.
    ;;
    ;; Keep these OFF the keys bound elsewhere on this screen. The list
    ;; below deliberately avoids t/e/i/p/P//f/g.
    'provider (code:project-provider
                'single-alphabet vscode-label-keys
                'leader-alphabet vscode-label-keys
                'second-alphabet vscode-label-keys
                'panel-label     "Projects")

    ;; Flat rows, deliberately: every operation is one key from the
    ;; leader. Group them if you prefer — that is the half of this file
    ;; that is yours.
    (key "t" "Terminal" code:toggle-terminal)
    (key "e" "Explorer" code:focus-explorer)
    (key "i" "Editor"   code:focus-editor)

    ;; The chords VSCode shares with every other editor — no library
    ;; needed for these, exactly as `examples/chrome.scm` shows.
    (key "p" "File Finder"     (λ () (send-keystroke '(cmd) "p")))
    (key "P" "Command Palette" (λ () (send-keystroke '(cmd shift) "p")))
    (key "/" "Project Search"  (λ () (send-keystroke '(cmd shift) "f")))

    ;; ─── Cycling the open editors ───────────────────────────────
    ;;
    ;; `[` and `]` because they are next to each other and they are
    ;; punctuation, so they sit outside the jump-label alphabet above by
    ;; construction. Both are yours to move.
    ;;
    ;; These are NOT bare chords, and the difference is the whole reason
    ;; the library exports a cycler rather than two more thunks.
    ;; VSCode's previousEditor / nextEditor are live from anywhere in
    ;; the workbench, but the editor they open only takes focus if focus
    ;; was ALREADY inside the editor group — so pressed from the
    ;; terminal or the explorer they change the tab under a pane you
    ;; cannot type into. `editor-cycler` focuses first, then cycles.
    ;;
    ;; The focus chord is the parameter, because the right one differs
    ;; per user. Left alone it is `focus-editor` — VSCode's own cmd-1,
    ;; which is focusFirstEditorGroup and lands on the LEFTMOST group
    ;; rather than the active one when several are open. If you have
    ;; bound workbench.action.focusActiveEditorGroup in your
    ;; keybindings.json (it ships with no default binding at all), pass
    ;; a lambda sending YOUR chord and the gap closes:
    ;;
    ;;   (code:editor-cycler 'next
    ;;     'focus (λ () (send-keystroke '(ctrl alt) "i")))
    ;;
    ;; Both commands cross editor groups and wrap around the window, so
    ;; with one group these cycle its tabs and with several they cycle
    ;; every tab you have open.
    (key "[" "Prev Editor" (code:editor-cycler 'previous))
    (key "]" "Next Editor" (code:editor-cycler 'next))

    ;; ─── The composition row ────────────────────────────────────
    ;;
    ;; Open THIS window's grove task file, with the explorer landing on
    ;; it. Worth reading even if you have never used grove, because it
    ;; is the shape every "do something with this project" row takes.
    ;;
    ;; Two libraries meet here and NEITHER knows about the other. The
    ;; VSCode library knows only VSCode: which folder the front window
    ;; is rooted at, and how to open a file and focus a panel. The
    ;; grove library knows only grove: given a directory, which task
    ;; file is live in it. The join — "the front window's folder is the
    ;; directory to ask about" — is a decision, so it lives here, in
    ;; configuration, and not in either library.
    ;;
    ;; Every step answers #f rather than raising, which is why this is
    ;; an `and` chain and not error handling: the front window may not
    ;; be a VSCode window, it may have no folder, its folder may not be
    ;; in VSCode's stored state yet (that file is written on window
    ;; state change, so a window opened seconds ago can be missing),
    ;; the folder may not be a grove, and the grove may be finished.
    ;;
    ;; What to SAY about a miss is yours too. A dialog is the loudest
    ;; option and is here because a silent no-op on a key you meant to
    ;; press is worse than an interruption; replace it with nothing at
    ;; all if you disagree.
    ;;
    ;; `reveal-file!` takes an optional follow-up, run once the file is
    ;; open, and defaults to VSCode's own shift-cmd-e. If you have bound
    ;; a strict-focus explorer command in your keybindings.json, pass a
    ;; lambda sending YOUR chord instead — shift-cmd-e bounces to the
    ;; editor when the explorer already has focus.
    ;; On "L" — for Leaf — since lowercase g is a Projects jump label
    ;; above. The capital plane is untouched by the label alphabets.
    (key "L" "Grove Leaf"
         (λ ()
           (let* ((worktree (code:focused-workspace-path))
                  (leaf     (and worktree (grove:live-leaf worktree))))
             (if leaf
                 (code:reveal-file! leaf)
                 (dialog-info "No live grove leaf for this window.")))))

    ;; ─── The Projects panel ─────────────────────────────────────
    ;;
    ;; One row per open VSCode window, ordered by project name, each
    ;; carrying the label that focuses it. This replaced a chooser row
    ;; (a `selector` over `code:window-source`, which is still exported
    ;; if you prefer fuzzy matching): with one window per worktree the
    ;; list is short and stable, so a jump label beats typing enough of
    ;; a forty-character folder name to disambiguate it.
    ;;
    ;; Note there is no `'next 'self` anywhere on this screen. The
    ;; provider re-runs at every come-to-rest and its accessibility
    ;; sweep costs 8-29ms warm and past 200ms cold, and auto-repeat is
    ;; not filtered — so a HELD key would queue sweeps faster than they
    ;; drain. Fire and exit.
    (panel "Projects"
      (code:project-listing))))

;; ─── The rest is a minimal config, so this file stands alone ───────

(define global-screen
  (screen 'global
    (panel "Applications"
      (key "e" "Editor" (λ () (launch-app "Visual Studio Code"))))))

(modaliser:start!
  (configuration
    (leaders
      (leader 'global F18)
      (leader 'local  F17))
    (overlay-delay 0.3)
    global-screen

    ;; ▶ 3/3 — the screen itself, composed into the configuration value.
    vscode-screen))
