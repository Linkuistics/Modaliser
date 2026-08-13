# How to vary the terminal tree by what's in the focused pane

You want F17 (the local leader) to show different bindings depending
on what is running in the focused terminal pane — e.g. an
nvim-specific tree when nvim is focused, a git tree when lazygit is
focused. The configuration's **Terminal context map** does this: one
`exe → tree` mapping, consulted by every terminal-like screen. The
same entries work whether the focused terminal is iTerm, WezTerm,
Kitty, Ghostty, or a multiplexer inside one of them, because the
detection primitive (`focused-terminal-path`) is generic across all
configured backends — no host names an inner tool; no inner tool names
a host.

## How it works

On a local-leader press over a terminal-like screen, activation walks
the **detection chain** — host terminal, through any multiplexer, down
to the innermost foreground command — and looks each layer's exe name
up in the context map. It lands in the **innermost mapped** context's
tree, with the return stack seeded so **backspace steps outward** one
context at a time (nvim → zellij → iTerm) and Escape exits from any
depth. Every terminal-like screen also derives a gated **`.` step-in
edge** stepping one mapped context inward. Nothing is ranked and
nothing re-probes on the way out: the chain itself is the containment
order ([ADR-0013](../adr/0013-nested-context-entry-points.md),
[configuration-value spec](../specs/configuration-value.md)).

For how detection works — what the TTY probe does, which terminals
support it, and the nvim RPC route — see
[`../reference/terminal-detection.md`](../reference/terminal-detection.md).

## You'll need

- A **terminal-like host** composed into your configuration — a host's
  wiring fragment (`(iterm:wiring)`, or `kitty:`/`wezterm:`/`ghostty:`/
  `alacritty:` `fragment`) plus your own `(screen "<bundle-id>" …)` for
  it. The screen's scope must be the host backend record's match-key;
  that is what makes it terminal-like.
- Context entries for the inner tools — the bundled factories
  (`herdr:wiring`, `tmux:wiring`, `zellij:wiring`, `nvim:wiring`) or
  your own (worked example below). All four ship **integration only**:
  each screen is yours to author, under the scope the entry names
  (ADR-0021, and the herdr worked example below).
- For the nvim entry: the `FocusGained`/`FocusLost` autocmds in
  your nvim config — see [The nvim side](
  ../reference/terminal-detection.md#the-nvim-side) in the
  detection reference.
- For form-by-form detail: [reference/dsl.md](../reference/dsl.md)
  (`screen`, and "Nested contexts: the Terminal context map").

## The quick path: factory context entries

Add the factory entries to the `terminal-contexts` fragment of your
configuration:

```scheme
(import (modaliser dsl)
        (modaliser configuration)
        (modaliser handoff)
        (prefix (modaliser apps iterm)   iterm:)
        (prefix (modaliser muxes herdr)  herdr:)
        (prefix (modaliser muxes zellij) zellij:)
        (prefix (modaliser tools nvim)   nvim:))

(modaliser:start!
  (configuration
    …
    (iterm:wiring)            ; a terminal-like host: backend + digit tree
    (terminal-contexts        ; each entry is backend + map entry; every
      (herdr:wiring)          ;   screen below is yours (ADR-0021)
      (nvim:wiring)           ; hjkl window focus over nvim's RPC socket
      (zellij:wiring))        ; full pane ops via the zellij action CLI
    iterm-screen              ; your (screen 'com.googlecode.iterm2 …)
    herdr-screen              ; your (screen 'herdr …) — see below
    herdr-focus-walk          ; your (tree 'herdr-panes-focus …)
    nvim-screen               ; your (screen 'nvim …)
    zellij-screen))           ; your (screen 'zellij …)
```

The seeded `default-config.scm` authors all four of those screens
inline — read them there rather than inventing your own from scratch.
For a mux a fresh install does not seed, `Scheme/examples/tmux.scm` is
the same thing for tmux: a complete working configuration, never loaded,
mirrored to `~/.config/modaliser/sys/scheme/examples/` to copy from.

Tap F17 with nvim in the focused split — the nvim tree appears.
Switch the split to a plain shell — the host's own tree appears
instead. Backspace from the nvim tree steps back out to the host
tree; `.` from the host tree steps in while nvim is running.

## Worked example: your own context entry

A context entry is an ordinary fragment: the map entry (keyed by the
tool's **exe name**) plus the tree it selects. For lazygit:

```scheme
(import (modaliser dsl)
        (modaliser configuration)   ; context
        (modaliser input))          ; send-keystroke

(define (lazygit-context)
  (list
    (context "lazygit" 'tree 'lazygit)
    (screen 'lazygit
      'display-name "lazygit"
      (panel "lazygit"
        (key "p" "Push" (λ () (send-keystroke '() "P")))
        (key "f" "Pull" (λ () (send-keystroke '() "p")))))))

;; …then compose it like any factory entry:
(terminal-contexts
  (lazygit-context)
  (nvim:wiring))
```

Notes on the shape:

- The map key is the **exe name**: the basename of the first token of
  the focused pane's foreground command line (`"lazygit"` matches
  `/opt/homebrew/bin/lazygit`). One entry per tool, independent of
  which host contains the pane.
- A tree-only entry (like nvim's) names just `'tree`. A mux-style
  tool that drives its own panes also names `'backend` and ships the
  backend record in the same fragment — see `muxes/tmux.sld` for the
  canonical example.
- This one bundles its entry *and* its screen in a single constructor,
  which the bundled libraries deliberately do not do (ADR-0021 is a
  constraint on `lib/modaliser`, so that a library can never take a key
  you chose). In your own config the keys are already yours, so bundle
  or split as you please.
- Finer variation lives *inside* the tree, not in the map: for rows
  that should appear only in some states of the tool (say, an
  nvim-filetype-specific key), put an **edge gate** on the row — gates
  snapshot per visit, so the check runs once per landing (e.g.
  `(nvim-remote-expr "&filetype")` in a gate thunk).

## Worked example: herdr

[herdr](https://herdr.dev) — an "agent multiplexer" run *inside* a
terminal — has the richest surface of the bundled inner tools, and it
splits in two.

The **integration** is one call, and works in *any* terminal-like host:

```scheme
(terminal-contexts (herdr:wiring))
```

That contributes the context-map entry, herdr's terminal backend, and
the digit-jump mode tree — no key, no label, nothing to choose.

The **screen** is yours. herdr ships none (ADR-0021: a library holds
facilities, configuration holds decisions), so you author a
`(screen 'herdr …)` out of the ops, blocks and provider
`(modaliser muxes herdr)` exports, plus a `(tree 'herdr-panes-focus …)`
for the Focus walk. Both scope symbols are machinery — the wiring's
context entry resolves to `'herdr`, and the Focus rows cross into
`'herdr-panes-focus` — so rename either and the configuration fails
reference-closure validation at load, loudly.

**Start from the seed, not from scratch.** `default-config.scm` (copied
to `~/.config/modaliser/config.scm` on first run) carries the whole
stock composition described below, ready to edit in place. The rest of
this section is a tour of what it binds and why — not a spec: every
key and label in it is preference, and yours to change.

When the focused pane runs herdr, F17 lands directly in the **herdr
screen**; backspace steps back out to the host tree, so the host's full
splits/panes/tabs surface is always one keystroke away — there is no
second "augment" tree duplicating it.

The stock screen's top level follows the **plane rule**
(`docs/specs/herdr-jump-navigation.md`): capitals name the drills/Quit,
and `b` is the one lowercase key kept at this level — it is a jump
(Jump to Blocked), not a drill. Every other lowercase letter belongs to
the **jump space** — see below the drill list for how it dispatches and
paints chips. The `c`/`C` pair below is the rule's one deliberate
exception.

- **`P` Panes** — the entire pane surface, drilled:
  - **`hjkl`** — focus the pane in that direction (first press crosses
    into a focus Walk, so subsequent `hjkl` keep moving focus; `[`/`]`
    cycling below also works mid-walk).
  - **`n`** then `hjkl` — split a new pane that direction (left/up
    split the opposite native way then swap back).
  - **`m`** then `hjkl` — Move Walk: swap the focused pane with its
    neighbour.
  - **`[`** / **`]`** — Prev/Next: cycle focus through the displayed
    (tab-scoped) panes, wrapping at both ends.
  - **`z`** / **`d`** — toggle zoom / close the focused pane.
  - **Panes panel** — the panes live list plus digit **chips** over
    the on-screen panes (correct when herdr is the sole current-tab
    split; see below).
- **`T` Tabs**, **`S` Spaces** — each a drill with `n`/`r`/`d`
  (new / rename / close), `m` Move (below), `[`/`]` Prev/Next cycling
  (tabs are workspace-scoped; spaces are global), plus a live list whose
  digits switch. "Spaces" is the user-facing label everywhere
  (matching herdr's own UI term); the code identifiers underneath
  keep herdr's `workspace` stem.
  - **`m`** then a direction — Move Walk: reorder the focused target one
    place. Tabs take `h`/`l` (herdr draws them in a horizontal bar),
    spaces `k`/`j` (a vertical sidebar); each key carries only the axis
    its target can actually travel. Presses chain, and either end of the
    list is a no-op rather than a wrap — unlike `[`/`]`, which move
    *focus* and do wrap. See
    [terminal-detection.md](../reference/terminal-detection.md#herdr-tab--space-reorder-the-insert-index-model)
    for herdr's insert-index model.
- **`W` Worktrees** — `n` new (prompt a branch), `d` remove the
  focused worktree (behind a confirm), plus a live list whose digits
  *smart-switch* (focus a live workspace, or open a dormant worktree).
  No `[`/`]` — cycling covers four groups, not five.
- **`b` Jump to Blocked** — focus the next blocked agent in one press
  (round-robin; a toast when none are blocked).
- **`A` Agents** — `[`/`]` Prev/Next cycling over the displayed
  (status-banded) order, plus the agents live list, status-badged and
  blocked-first; a digit focuses that agent's pane.
- **`Q` Quit** — `d` Detach (ends the herdr *client* only, emitted as
  herdr's own `prefix+q` keystroke) or `s` Stop
  Server (ends the herdr *server*, behind a confirm dialog since
  herdr's CLI stops it immediately with no confirm of its own). See
  CONTEXT.md's Detach/Stop glossary entries for the distinction.
  Detach takes the client prefix, exactly like the two keys below —
  `(herdr:detach-op herdr-prefix)`.
- **`c` Copy Mode** / **`C` Scrollback** — herdr's two text-inspection
  surfaces, the plane rule's one exception (a lowercase key that is not a
  jump label, a capital that is not a drill). `c` enters herdr's per-pane
  selection mode in the *live* focused pane (`copy_mode`); `C` opens that
  pane's scrollback *buffer* in an editor (`edit_scrollback`). Both are
  client-side herdr keybindings with no socket verb, so both are emitted as
  prefix-then-key keystrokes to the frontmost app — which is what lets them
  live in herdr's screen rather than each host's. A host terminal's own copy
  mode is the wrong tool for either: the host sees herdr as one session and
  selects across the whole canvas, ignoring herdr's pane layout. All three
  keystroke ops take herdr's client prefix as their one argument —
  `(herdr:copy-mode-op p)` / `(herdr:scrollback-op p)` /
  `(herdr:detach-op p)`, where `p` defaults to `herdr:herdr-default-prefix`
  (`ctrl+b`). herdr exposes no way to query what its bindings resolved to,
  so both the prefix and each op's *second* key are assumptions: correct
  the prefix in one place, and if you rebound `copy_mode` /
  `edit_scrollback` / `detach` itself, write the one-line thunk in place
  of the op.

**The jump space (every other lowercase letter).** Typing a target's
assigned label focuses it directly, no drill in between
(`docs/specs/herdr-jump-navigation.md`). Targets are gathered fresh on
every visit — a `'provider` on the herdr screen root's state,
`herdr-jump-provider` — across four axes in stable-axis order (spaces →
agents → tabs → panes), visual order within an axis. Two visible targets
naming the same destination (an agent whose pane is already on-screen)
each keep their own independent label rather than collapsing to one — a
stable target set keeps label assignment stable too. Each axis assigns labels
from its OWN reserved letter pool — panes `h j k l ;`, spaces `a s d f
g`, agents then tabs sharing the top row (agents first, so agent churn
only ever shifts tab labels) — escalating to two-key labels, led by the
axis's own letters, only once that axis's pool is exhausted (the general
`jump-labels-assign` utility, `(modaliser jump-labels)`, called once per
axis).

- **Full-size letter chips** paint over the current tab's on-screen
  panes when the which-key overlay appears — a presentation-gated
  `'on-enter`/`'on-leave` pair (`paint-jump-chips!`/`clear-jump-chips!`,
  [state-machine.md](../reference/state-machine.md#hook-gating-on-enter--on-leave))
  reusing the same chip pipeline the `P` drill's digit chips use (see the
  split-tab caveat below). Chips share the overlay's own
  `modal-overlay-delay`, so a press fast enough to never raise the
  overlay paints nothing — the jump keys still dispatch, since the
  provider lowers its edges at come-to-rest whether or not anything is
  drawn.
- **Typing a two-key label's first (leader) key narrows**: the modal
  moves to a resting prefix state whose only live edges are that
  leader's second keys plus backspace (un-narrows back to the top
  level) and Escape (clears and exits, as usual). The design's
  vimium-style chip *dimming* during narrowing
  (`docs/specs/herdr-jump-navigation.md` "Narrowing", CONTEXT.md
  "Narrowing") isn't painted yet — chips stay full-brightness through a
  narrowing; that visual lands with the mini-chips work.
- **A jump firing is Terminal** — focus moves and the modal exits
  immediately, exactly like `b` Jump to Blocked.
- **Only the Panes axis has a visible chip today.** The Spaces/Agents/
  Tabs axes are already gathered, labelled, and dispatch correctly if
  you know their assigned key, but nothing paints a chip over the
  sidebar/tab-bar entries until the mini-chips work lands.

**Pane chips are correct only when herdr is the sole current-tab
split.** The stock screen's Panes panel paints digit chips over the
on-screen herdr panes, and the top-level jump space's letter chips
reuse that exact same pipeline; when the host tab holds other splits
too, the host-frame heuristic can target the wrong one, so either kind
of chip may be misplaced (`hjkl` focus, digit-jump, and jump-letter
dispatch by id are all unaffected) — a plain pane-chip-pipeline
geometry concern now, not a tree-model one.
See [herdr pane chips](../reference/terminal-detection.md#herdr-pane-chips).

## One tree across every backend: capability predicates

The 14-op surface on `(modaliser terminal)` lets a shared splice of
bindings drive any configured terminal — at call time the façade
routes each op to the backend the detection chain says owns the
focused pane. But not every backend supports every op (Kitty has no
zoom, Ghostty has no `move-pane-*`, Alacritty has no splits at all),
so a shared body that hard-codes every op will surface entries that
silently no-op where unsupported.

Because each host has its **own screen** in the configuration, shape
differences are a composition-time decision: build each host's screen
body from a shared splice plus only the ops that host supports —
you know the backend statically at the point you write its screen.

```scheme
(define focus-keys                       ; shared everywhere
  (splice
    (key "h" "Focus Left"  terminal:focus-pane-left)
    (key "j" "Focus Down"  terminal:focus-pane-down)
    (key "k" "Focus Up"    terminal:focus-pane-up)
    (key "l" "Focus Right" terminal:focus-pane-right)))

(screen "net.kovidgoyal.kitty"           ; kitty: no native zoom —
  (panel "Panes" focus-keys))            ; no z key authored

(screen "com.googlecode.iterm2"
  (panel "Panes" focus-keys
    (key "z" "Toggle Zoom" terminal:toggle-pane-zoom)))
```

For the residual *runtime* cases — a shared action that must branch on
the live backend at fire time — the capability predicates answer for
the **active** backend (the one the chain resolves at that moment):

- `(terminal:supports-splits?)` — backend exposes `split-pane-*`
- `(terminal:supports-move-pane?)` — backend exposes `move-pane-*`
- `(terminal:supports-digit-jump?)` — backend exposes `focus-pane-by-digit`
- `(terminal:supports-zoom?)` — backend exposes `toggle-pane-zoom`
- `(terminal:supports? 'focus-pane-left)` — universal introspection by op name

## Verify it worked

1. Focus a terminal split running nvim, tap F17: the nvim tree
   should appear.
2. Switch the split to a plain shell, tap F17: the host's own tree.
3. From the nvim tree, backspace: the host tree, without re-probing.

If you always get the host tree: the entry is missing from your
`terminal-contexts` call, the exe name doesn't match (it is the
basename of the foreground command's first token — check with
`(focused-terminal-path)`), or the host's screen isn't terminal-like
(its fragment must carry a host backend whose match-key is the
screen's scope — composing the factory's `wiring` / `fragment`
guarantees this).

## Notes

**Merge conflicts are loud.** Two entries for the same exe (or two
trees for the same scope) error at `configuration` time unless they
are the identical value — there is no last-wins hook to silently lose
a variant to.

**Save and relaunch** from the menu bar icon after any config change.
In-place reload is not supported — relaunch is the reload.

## Related

- [`../reference/terminal-detection.md`](../reference/terminal-detection.md)
  — how pane detection works, which terminals are supported, the nvim
  RPC route.
- [`add-a-per-app-tree.md`](add-a-per-app-tree.md) — per-app screens
  without pane-awareness.
- [ADR-0013](../adr/0013-nested-context-entry-points.md) — why nesting
  works as chain-seeded activation rather than a merged variant tree.
