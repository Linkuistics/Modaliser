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
;; three alphabets each of the three panels draws its jump labels from.
;;
;; The screen carries THREE labelled panels — Projects, Terminals and
;; Editors — on a state that has exactly ONE `'provider` slot, which is
;; the other thing this example is showing. They are merged by
;; `jump-list-compose-providers`, which RAISES on a collision the engine
;; would otherwise resolve silently in favour of whichever panel came
;; first. Read the comment on the merge below before adding a fourth.
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
        (only (modaliser json) json-ref)
        (only (modaliser util) alist-ref)
        (prefix (modaliser apps vscode) code:)
        ;; The merge that puts three labelled panels on one 'provider
        ;; slot. Bare rather than prefixed: it collides with nothing.
        (only (modaliser jump-list) jump-list-compose-providers)
        ;; For the "Grove Leaf" row at the bottom of the screen. Drop
        ;; this import, the helper below and that row if you do not use grove —
        ;; nothing else on the screen touches it.
        (prefix (modaliser tools grove) grove:))

;; One snapshot binds cleanup to the initiating window. Send before pick so a
;; finished/removed grove still gets cleanup. Neither a peer miss nor a cleanup
;; failure gates the existing reveal. Optional AFTER replaces the explorer
;; follow-up, e.g. with a user's strict-focus chord.
(define (vscode-show-grove-leaf! . after)
  (let* ((parts (guard (ex (else #f)) (code:vscode-parts)))
         (workspace (and parts (json-ref parts "workspace")))
         (worktree (if (and (string? workspace) (not (string=? workspace "")))
                       workspace (code:focused-workspace-path))))
    (when worktree
      (for-each
        (lambda (target)
          (when (grove:task-path? (alist-ref target 'path) worktree)
            (code:close-editor-if-missing! target)))
        (code:editor-rows parts)))
    (let ((leaf (and worktree (grove:live-leaf worktree))))
      (if leaf
          (apply code:reveal-file! leaf after)
          (dialog-info "No live grove leaf for this window.")))))

;; The jump-label alphabet for the Projects panel, named once and
;; passed three times below (one-key pool, leader preference order,
;; second-key pool). A label that collides with a bound key loses, so
;; the home row here cost one move: Grove Leaf sits on "G" rather than
;; "g". That is preference and it is yours — the library defaults no
;; alphabet and authors no key (ADR-0021), so both this list and the
;; keys it has to dodge are decisions you make, not ones you inherit.
(define vscode-label-keys '("a" "s" "d" "f" "g"))

;; And one alphabet per NEW panel, because the human's request was a
;; separate set of shortcut keys for each. Three pools, and what has to
;; stay disjoint is wider than it looks — see the merge below.
;;
;; Home row split three ways: `a s d f g` for Projects (left hand),
;; `t y u i o` for Terminals (upper row), `h j k l ;` for Editors (right
;; hand). Freeing `t` and `i` for the Terminals pool is why the Terminal
;; and Editor ROWS came off this screen: those operations are now a jump
;; label away in the panels, which is strictly more than the rows did.
(define vscode-terminal-keys '("t" "y" "u" "i" "o"))
(define vscode-editor-keys   '("h" "j" "k" "l" ";"))

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
    ;; Keep every pool OFF the keys bound elsewhere on this screen. The
    ;; three lists above deliberately avoid e/p/P//L/[/].
    ;;
    ;; ─── THREE PANELS, ONE 'provider SLOT ───────────────────────
    ;;
    ;; A state has exactly one `'provider`, and this screen wants three
    ;; labelled panels on it. `jump-list-compose-providers` calls each
    ;; contributor, appends their edges and states, and RAISES if two of
    ;; them collide — because the engine will not. It folds a provider's
    ;; edges in with the state's own by plain append and then resolves a
    ;; key by FIRST match, so two panels claiming `j` is not an error
    ;; anywhere: it is an editor's label focusing a terminal, silently.
    ;;
    ;; Each contributor is NAMED, and the name is yours. An ordinal
    ;; cannot repair a configuration — "Editors and Terminals both claim
    ;; j" tells you what to move; "provider 1 and provider 2" does not.
    ;;
    ;; ── What the merge checks that you cannot check by eye.
    ;;
    ;; It validates against the SCREEN'S OWN KEYS too, not just against
    ;; the other panels — and that is the likelier collision, because
    ;; the screen's keys are already spoken for. It also validates the
    ;; state ids against every permanently registered state.
    ;;
    ;; And the disjointness you have to keep is WIDER than the single
    ;; alphabets. A panel's edges are one per surviving single-key label
    ;; PLUS ONE PER PROMOTED LEADER, so the pool two panels must keep
    ;; disjoint is `single-alphabet ∪ leader-alphabet`. Leader promotion
    ;; is data-dependent — it only happens once a panel has more rows
    ;; than its single alphabet covers — so two panels can share a
    ;; leader key, coexist happily for months, and collide the first
    ;; time one of them grows. That is exactly why the check runs at
    ;; come-to-rest rather than at config load: at load there is no row
    ;; count to check against.
    'provider (jump-list-compose-providers
                "Projects"
                (code:project-provider
                  'single-alphabet vscode-label-keys
                  'leader-alphabet vscode-label-keys
                  'second-alphabet vscode-label-keys
                  'panel-label     "Projects")
                "Terminals"
                (code:terminal-provider
                  'single-alphabet vscode-terminal-keys
                  'leader-alphabet vscode-terminal-keys
                  'second-alphabet vscode-terminal-keys
                  'panel-label     "Terminals")
                "Editors"
                (code:editor-provider
                  'single-alphabet vscode-editor-keys
                  'leader-alphabet vscode-editor-keys
                  'second-alphabet vscode-editor-keys
                  'panel-label     "Editors"))

    ;; Flat rows, deliberately: every operation is one key from the
    ;; leader. Group them if you prefer — that is the half of this file
    ;; that is yours.
    ;;
    ;; There is no "Terminal" or "Editor" row here any more. Both are
    ;; better served by the panels below, which say WHICH terminal and
    ;; WHICH editor rather than toggling a pane — and taking them off is
    ;; what frees `t` and `i` for the Terminals alphabet. The ops are
    ;; still exported (`code:toggle-terminal`, `code:focus-editor`) if
    ;; you want either back; move a pool key out of the way first.
    (key "e" "Explorer" code:focus-explorer)

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
    ;; the folder may not be a grove, and the grove may be finished. The
    ;; helper above first asks the initiating peer to clean missing task tabs,
    ;; including when no leaf remains; reveal does not wait for those closes.
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
         vscode-show-grove-leaf!)

    ;; ─── This window's terminals and editors ────────────────────
    ;;
    ;; The same affordance one level in: the parts of the window you are
    ;; already IN. Both come from a companion VSCode extension over a
    ;; Unix socket — VSCode exposes nothing from outside that says what
    ;; is open inside a window, so Modaliser runs a small peer inside it
    ;; (docs/specs/vscode-window-parts.md, ADR-0026). It ships inside
    ;; Modaliser.app; the row below installs it, and until it is
    ;; installed both panels are simply empty and nothing errors.
    ;;
    ;; The Terminals panel lists every terminal WHETHER OR NOT the
    ;; terminal panel is showing, which is the whole reason the source
    ;; is the extension rather than the accessibility tree. The Editors
    ;; panel lists every tab across every editor group.
    ;;
    ;; A row with a dimmed label and no arrow is an editor tab of a kind
    ;; that cannot be reactivated by name — a webview, a diff. It is
    ;; listed because omitting it would make the panel disagree with the
    ;; tab strip you are looking at, and would renumber every label
    ;; below it.
    ;; ─── Installing the companion ───────────────────────────────
    ;;
    ;; The extension is built into Modaliser.app and copied into
    ;; ~/.vscode/extensions only when you press this and confirm
    ;; (ADR-0028). Modaliser never writes there on its own.
    ;;
    ;; The `'hidden` gate is the interesting half: paired with the
    ;; predicate, the row RETIRES ITSELF the moment the shipped version
    ;; is installed, and comes BACK when a Modaliser upgrade ships a
    ;; newer one than what is on disk. So this costs a slot only while
    ;; it has something to do. The same pairing configures kitty and
    ;; iTerm2 — see `examples/` for those.
    ;;
    ;; On "I" because the lowercase plane is jump-label territory. Move
    ;; it wherever you like; the key and the label are yours (ADR-0021).
    (key "I" "Install VSCode Companion" code:install-companion!
         'hidden code:companion-installed?)

    (panel "Terminals"
      (code:terminal-listing))

    (panel "Editors"
      (code:editor-listing))

    ;; ─── The Projects panel ─────────────────────────────────────
    ;;
    ;; One row per open VSCode window, ordered by project name, each
    ;; carrying the label that focuses it. This replaced a chooser row
    ;; (a `selector` over `code:window-source`, which is still exported
    ;; if you prefer fuzzy matching): with one window per worktree the
    ;; list is short and stable, so a jump label beats typing enough of
    ;; a forty-character folder name to disambiguate it.
    ;;
    ;; Note there is no `'next 'self` anywhere on this screen, and it
    ;; matters three times over now. ALL THREE providers re-run at every
    ;; come-to-rest: one accessibility sweep for this panel (8-29ms warm,
    ;; past 200ms cold) and one socket round-trip for each of the two
    ;; above. Auto-repeat is not filtered, so a HELD key would queue
    ;; gathers faster than they drain. Fire and exit.
    ;;
    ;; The socket reads are the cheap half — a healthy peer answers in
    ;; about a twenty-fifth of a millisecond, and each is bounded at
    ;; 200ms even when the extension host is wedged, so the worst case
    ;; the two of them add is 400ms rather than something unbounded.
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
