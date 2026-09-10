# Library reference

Every bundled `(modaliser …)` library that user configs are expected
to import directly. Native primitives (Swift-backed libraries like
`(modaliser app)` or `(modaliser hints)`) are listed briefly at the end
— their canonical reference is the source, since signatures track the
host.

## Import conventions

The factory libraries use **bare-name exports** (`fragment`, `wiring`,
`focus-pane-left`, `find-application`, …) so call sites read
short — and several deliberately share names across libraries, so that
swapping mux or host is a change of prefix, not of screen. To keep them
apart, the recommended import style is **prefix-style**:

```scheme
(import (prefix (modaliser apps iterm)      iterm:)
        (prefix (modaliser apps dia)        dia:)
        (prefix (modaliser apps vscode)     code:)
        (prefix (modaliser muxes herdr)     herdr:)
        (prefix (modaliser muxes zellij)    zellij:)
        (prefix (modaliser wms paneru)      paneru:)
        (prefix (modaliser tools grove)     grove:)
        (prefix (modaliser window-actions)  window:)
        (prefix (modaliser launchers)       launcher:)
        (prefix (modaliser settings-menu)   settings:)
        (prefix (modaliser web-search)      web-search:))
```

Foundational libraries (`(modaliser dsl)`, `(modaliser configuration)`,
`(modaliser handoff)`,
`(modaliser util)`, `(modaliser ax-hints)`, `(modaliser terminal)`) have
unique long names and are typically imported unprefixed because they're
the vocabulary you use everywhere. The one exception is
`(modaliser display-dsl)`, which is imported **prefixed** (`d:` by
convention) because its `panel` deliberately shares a name with the
sugar's.

---

## Configuration

### `(modaliser configuration)`

The pure configuration model (ADR-0018): contribution constructors, the
settings constructors, the `configuration` merge, and the value's
accessors. Full authoring reference:
[dsl.md](dsl.md#composing-the-configuration-value); model:
[configuration-value spec](../specs/configuration-value.md).

| Export | Description |
|---|---|
| `configuration` | `(configuration fragment…)` — the pure merge + validation; returns the Configuration value. |
| `leader`, `leaders` | Leader specs and the `'leaders` setting. |
| `overlay-delay` | The `'overlay-delay` setting (validates: non-negative real). |
| `terminal-contexts` | Groups context entries into the Terminal context map fragment. |
| `tree`, `backend`, `context`, `setting` | The four raw contribution constructors — the closed tag vocabulary factories build on. |
| `configuration?`, `configuration-trees`, `configuration-backends`, `configuration-contexts`, `configuration-settings`, `configuration-tree-ref`, `configuration-backend-ref`, `configuration-context-ref`, `configuration-setting-ref` | Value predicate and accessors — take the merged value apart in tests or tooling. |

### `(modaliser display-dsl)`

The Display value model (ADR-0011): the **bare authoring surface** and the
pure resolution seam the renderer reads through. Portable. Full authoring
reference: [dsl.md](dsl.md#the-bare-authoring-surface).

| Export | Description |
|---|---|
| `with-display` | `(with-display node clause…)` — attach the assembled display value as the node's single `'display` entry. Pure; validates every ref at attach time. |
| `panel`, `loose`, `block` | The structural clauses: a panel of the grid, the loose region, and a block row-reference by id. |
| `span`, `order`, `cols`, `layout`, `embed`, `display-name` | The scalar clauses — a panel's width, row ordering, authored column count, panel packing, the per-edge embed choice, the breadcrumb override. |
| `resolve-display` | `(resolve-display children display)` → render plan. The pure seam the overlay serializes; also how tooling reads a node's rendering without touching dispatch. |
| `block-ref-id` | The id a display references a block-spec by (`'id`, else `'type`). |
| `sort-rows` | The canonical row-key sort, shared with the default list renderer. |

### `(modaliser handoff)`

| Export | Description |
|---|---|
| `modaliser:start!` | The Handoff — validate, lower, install, arm the leaders. One-shot; see [dsl.md](dsl.md#modaliserstart-config). |
| `modaliser:configuration` | The installed value, or `#f` before (or after a failed) handoff — `#f` *is* the config-error state. |
| `make-configured-leader-handler` | The leader-press handler factory the handoff arms; exposed for tests. |

### `(modaliser activation)`

Pure activation resolution — no engine state, the chain is an argument.

| Export | Description |
|---|---|
| `resolve-activation` | `(resolve-activation leader-kind bundle-id chain config)` → landing (`root` + seeded `stack`) or `#f`. See [state-machine.md](state-machine.md#activation-screen-set--context-map). |
| `resolve-direct-activation` | The programmatic-entry variant: scope symbol × chain × config. |
| `lower-with-activation` | `lower-configuration` plus the derived `.` step-in providers composed onto terminal-like roots — what the handoff actually installs. |

---

## Dispatch core

### `(modaliser fsm)`

The explicit FSM graph (ADR-0015) — the graph model, the step engine
dispatch actually runs on, the pure lower function, and the **modal
façade** (the `modal-*` names, derived from the engine's configuration
after every step). Most configs never
need more than the `modal-*` introspection surface — reach deeper only
when introspecting the graph (tooling, a future renderer)
or driving the engine below the DSL. Full semantics:
[state-machine.md](state-machine.md) and
[docs/specs/fsm-graph.md](../specs/fsm-graph.md). Portable, like
`(modaliser dsl)` — no host-specific imports.

**Lowering and graph construction** (driven by the handoff; rarely
called directly from a config):

| Export | Signature | Description |
|---|---|---|
| `lower-configuration` | `(lower-configuration config)` | The pure lower: a merged Configuration value → a fresh graph, validated closed over its authored references. |
| `fsm-make-graph` | `(fsm-make-graph)` | A fresh, empty graph value. |
| `fsm-graph-state!` | `(fsm-graph-state! g id [keyword value]... edge...)` | Add a state to a graph. Keywords: `'label`, `'payload`, `'entry`, `'exit`, `'show`, `'hide`, `'provider`, `'exit-on-unknown`. |
| `fsm-graph-edge!` | `(fsm-graph-edge! g from trigger target [keyword value]...)` | Add an edge — `trigger` is a key string, `'up`, or `'auto`; keywords `'gate` and `'call`. |
| `edge` | `(edge trigger target [keyword value]...)` | Build an edge spec for inline use in `fsm-graph-state!`. |
| `fsm-graph-check-closed` | `(fsm-graph-check-closed g)` | Validate every authored reference resolves; returns the graph or errors naming the offending ids. |
| `fsm-install-graph!` | `(fsm-install-graph! g)` | Install a lowered graph as the live one — the handoff's effectful step. |
| `named` | `(named symbol-name procedure)` | Wrap a behaviour-slot procedure with a display name for `fsm-print`. |

**Queries:**

| Export | Description |
|---|---|
| `fsm-state-ids`, `fsm-state-ref`, `fsm-state-label`, `fsm-state-payload` | State lookups against the installed graph. |
| `fsm-state-edges`, `fsm-up-edge`, `fsm-ancestors`, `fsm-state-class` | Edge/class introspection — `fsm-state-class` returns `'resting`, `'transient`, or `'terminal`. |
| `fsm-resolve-state`, `fsm-resolved-payload`, `fsm-resolved-up-edge`, `fsm-resolved-state-class` | Like the above, but also seeing the current visit's provided (synthetic) states. |
| `fsm-graph->alist`, `fsm-print` | The whole graph as printable data — what a renderer or debugging tool would walk. |

**Step engine** (what the `modal-*` façade bindings
derive from after every call):

| Export | Description |
|---|---|
| `fsm-activate!` | Direct activation by state id (with an optional seeded return stack). |
| `fsm-step!`, `fsm-step-back!`, `fsm-halt!` | Key dispatch, backspace, global halt (Escape). |
| `fsm-active?`, `fsm-current-state`, `fsm-return-stack`, `fsm-live-edges` | Configuration queries — the current visit owner, the return stack, and its live (gate-filtered, provider-extended) edge set. |

---

## Selectors

### `(modaliser launchers)`

Application and file pickers.

**Imports:**

```scheme
(import (prefix (modaliser launchers) launcher:))
```

**Exports:**

| Export | Signature | Returns |
|---|---|---|
| `find-application` | `(find-application [keyword value]...)` | Undecorated selector node — wrap with `(key K L (launcher:find-application …))`. |
| `find-file` | `(find-file [keyword value]...)` | Undecorated selector node. |

**`find-application` options:**

| Keyword | Default | Description |
|---|---|---|
| `'prompt` | `"Find app…"` | Chooser prompt. |
| `'remember` | `"apps"` | MRU bucket name. `#f` disables MRU. |
| `'extra-actions` | `'()` | Action nodes appended to the four defaults (Open, Reveal, Copy Path, Copy Bundle ID). |

**`find-file` options:**

| Keyword | Default | Description |
|---|---|---|
| `'prompt` | `"File…"` | Chooser prompt. |
| `'file-roots` | `'("~")` | Search roots. |
| `'editor` | `"Zed"` | App for the "Open in editor" action. |
| `'extra-actions` | `'()` | Action nodes appended to the four defaults. |

```scheme
(key "a" "Find Application" (launcher:find-application))
(key "f" "Find File"        (launcher:find-file 'editor "VSCode"))
```

### `(modaliser web-search)`

Web search via a dynamic-search selector.

**Imports:**

```scheme
(import (prefix (modaliser web-search) web-search:))
```

**Exports (user-facing):**

| Export | Signature | Description |
|---|---|---|
| `google` | `(google [keyword value]...)` | Undecorated selector node — Google search with live suggestions. |

**`google` options:**

| Keyword | Default | Description |
|---|---|---|
| `'prompt` | `"Search Google…"` | Chooser prompt. |

```scheme
(key "g" "Google" (web-search:google))
```

The library also exports lower-level pieces (`web-search-handler`,
`build-web-search-results`, `set-web-search-fetch!`) for composing
custom search providers. See the source for details — most users only
need `google`.

### `(modaliser settings-menu)`

One operation: open the user's Modaliser config directory in an editor.

**Imports:**

```scheme
(import (prefix (modaliser settings-menu) settings:))
```

**Exports:**

| Export | Signature | Description |
|---|---|---|
| `open-config-dir!` | `(open-config-dir! [keyword value]...)` | Opens the config **directory** (not a single file), so the editor's project view shows `config.scm`, `theme.css` and any `.sld` libraries of your own side by side. Effectful — wrap it in a `λ` at a key. |

**Options:**

| Keyword | Default | Description |
|---|---|---|
| `'config-dir` | `"$HOME/.config/modaliser"` | Directory opened. A fact about Modaliser (ADR-0019), hence a default. |
| `'editor` | *(none)* | App name to open with; an `\|\| open` fallback catches an editor that is not installed. Omitted → whatever macOS opens a folder with. |

The Settings **menu** is a decision, so it is yours (ADR-0021). The
seeded `default-config.scm` authors it like this:

```scheme
(import (prefix (modaliser settings-menu) settings:)
        (modaliser lifecycle))            ; relaunch!

(screen 'global
  (group "," "Settings"
    (key "e" "Edit"   (λ () (settings:open-config-dir! 'editor "Zed")))
    (key "r" "Reload" relaunch!))
  …)
```

Everything a library-owned constructor used to take as an option — the
group's key, its label, extra rows — is ordinary Scheme above.

---

## Window manager

### `(modaliser window-actions)`

High-level block constructors for the windows overlay. The bundled seed
places `layout-block` and `list-block` in panels of an `(open "w"
"Windows" …)` drill-down to produce the canonical Windows view — each
block embedded in its own `(panel …)`.

**Imports:**

```scheme
(import (prefix (modaliser window-actions) window:))
```

**Exports:**

| Export | Signature | Description |
|---|---|---|
| `layout-block` | `(layout-block form...)` (macro) | Window-diagram block + matching `(move-window …)` key bindings. Each `form` is a matrix of keys (with `#f` for empty cells) or `(center K)` for the centre panel. |
| `default-layout-block` | `(default-layout-block)` | The 6-panel default layout — full thirds, half thirds, two-thirds spans, maximise, centre. |
| `list-block` | `(list-block [keyword value]...)` | Window-list block + `1..` digit dispatch for focus-by-label. |
| `divisions` | `(divisions matrix)` → `(panel-spec key-list)` | Lower-level matrix parser, used by `layout-block`. |
| `center-panel` | `(center-panel key)` → `(panel-spec key-list)` | Centre-panel constructor. |

**`layout-block` form shapes:**

- A matrix `(("d" "f" "g") (…))` — keys arranged in rows/cols; each
  unique key gets a `(move-window …)` binding sized by its cell's
  bounding box.
- `(center K)` — a centred-window cell with inward arrows.
- `#f` in any cell — empty slot (no binding).

**`list-block` options:**

| Keyword | Default | Description |
|---|---|---|
| `'chips?` | `#f` | When `#t`, paints on-screen labelled chips for each window. Chip styling lives in CSS — see [theming.md](theming.md). |

Chip appearance is no longer threaded through the block constructor.
Override `.chip` / `.chip.faded` in `~/.config/modaliser/theme.css` to
customise; relaunch picks up the changes.

```scheme
(open "w" "Windows"
  (panel "Layout"
    (window:layout-block
      (("d" "f" "g"))
      (("D" "F" "G") ("C" "V" "B"))
      (("e" "e" #f))
      ((#f "t" "t"))
      (("m"))
      (center "c")))
  (panel "Select"
    (key "s" "Select Window"
         (selector 'prompt "Select window by name…"
                   'source list-windows
                   'on-select focus-window))
    (key "r" "Restore" (λ () (restore-window))))
  (panel "Windows"
    (window:list-block 'chips? #t)))
```

### `(modaliser window)`

Native window-management primitives. Imported by `(modaliser
window-actions)` internally; user configs typically import for
`list-windows` / `focus-window` when composing custom window selectors.

| Export | Signature | Description |
|---|---|---|
| `list-windows` | `(list-windows)` | List visible windows as alists with `title`, `app`, `id`, etc. |
| `focus-window` | `(focus-window window)` | Bring the window to the front and focus it. |
| `move-window` | `(move-window x y w h)` | Reposition the focused window to the given screen fraction. |
| `center-window` | `(center-window)` | Centre the focused window. |
| `restore-window` | `(restore-window)` | Restore the focused window's previous frame. |
| `list-displays` | `(list-displays)` | List displays left-to-right as alists with `id`, `x`, `y`, `w`, `h` (AX-visible frame), `is-primary`. |
| `set-focused-window-frame` | `(set-focused-window-frame x y w h)` | Place the focused window at an absolute AX-coord rect (the absolute sibling of `move-window`). |
| `focus-display` | `(focus-display id)` | Focus a display by its `list-displays` id, so macOS Space/Mission-Control keys act on it. |

(Native library — exact surface is implemented in Swift. See the source
under `Sources/Modaliser/` for the canonical list.)

---

### `(modaliser display-actions)`

Display-management block — the sibling of `(modaliser window-actions)`. Embed
`(display:display-list-block …)` in a window sub-screen to paint round display
chips (top-right) alongside the square window chips (top-left):

```scheme
(import (modaliser dsl)
        (prefix (modaliser window-actions)  window:)
        (prefix (modaliser display-actions) display:))

(open "w" "Windows"
  (window:list-block 'chips? #t)
  (display:display-list-block 'chips? #t))
```

Per display label, two keys are bound: the **plain letter** moves the focused
window to that display (preserving its size/position as a fraction of the
display's visible frame — a ⅓-width window stays ⅓-width across displays of
differing size/aspect), and the **Shift+letter** focuses that display. Default
labels `h j k l n o` (left-to-right), overridable with `'labels`. The chip
corner is `'corner` (default `'top-right`).

| Export | Signature | Description |
|---|---|---|
| `display-list-block` | `(display-list-block 'chips? #t ['labels '(…)] ['corner 'top-right])` | Display-chip block carrying its move/focus dispatch keys. |
| `move-focused-window-to-display` | `(move-focused-window-to-display id)` | Proportional move of the focused window to display `id`. |
| `remap-frame` | `(remap-frame win src tgt)` | Pure: `(newX newY newW newH)` for the proportional remap (exported for tests). |

---

### `(modaliser wms paneru)`

Keyboard control of [paneru](https://github.com/karinushka/paneru), an
**external** sliding window manager: windows live on an infinite
horizontal strip and opening one never resizes its neighbours. A daemon
owns the strip; the `paneru` binary talks to it over a Unix socket, and
Modaliser is a *client* of it. paneru ships no keyboard layer of its own
(its `paneru.toml` `[bindings]` section is empty), so this library is
how it gets one.

`wms/` is a category peer to `apps/`, `muxes/` and `tools/`. Unlike a
mux, paneru sits behind **no façade**: no backend record, no `wiring`,
no Terminal-context-map entry — it owns the desktop rather than living
inside a pane, so there is nothing for a façade to dispatch to.

Its ops do **not** map onto `(modaliser window-actions)`'s geometry ops
and are not a backend for them: absolute rects on a bounded screen and
relative motion along an unbounded strip are different vocabularies.
When paneru drives the desktop you compose the window screen from
*these* ops instead — see **the composition** below.

**Imports:**

```scheme
(import (prefix (modaliser wms paneru) paneru:))
```

**Exports:**

| Export | Signature | Description |
|---|---|---|
| `focus-west` / `focus-east` | `(focus-west)` | Move focus one column along the strip. |
| `swap-west` / `swap-east` | `(swap-west)` | Move the focused window one column along the strip. |
| `grow` / `shrink` | `(grow)` | Next / previous entry in paneru's own `preset_column_widths`. |
| `center` | `(center)` | Scroll the strip to centre the focused window. |
| `installed?` | `(installed?)` → boolean | `command -v paneru` on the derived tool path (ADR-0017). The composition predicate. |
| `strip-provider` | `(strip-provider [keyword value]...)` → 1-arg proc | The **Edge provider** for a state's `'provider` slot; mints this Visit's jump labels. |
| `strip-listing` | `(strip-listing)` → block spec | The **Strip listing** block, drawing the provider's snapshot. |
| `parse-strip-windows` | `(parse-strip-windows text)` → rows | Pure. Query payload → the active workspace's rows, in strip order (exported for tests). |
| `join-strip-targets` | `(join-strip-targets rows enumeration)` → targets | Pure. Recovers each row's `ownerPid` by id join (exported for tests). |
| `strip-focus-choice` | `(strip-focus-choice target)` → alist | Pure. One target → the choice alist `focus-window` reads (exported for tests). |
| `strip-provider-result` | `(strip-provider-result assigned owner-id panel-label)` → alist | Pure. A label assignment → `'edges` + `'states` (exported for tests). Since the VSCode project panel wanted the same shape over a different row source, the lowering itself lives in [`(modaliser jump-list)`](#modaliser-jump-list) and this composes it, injecting the three things that are paneru's: how a target is named, what pressing it does, and what the narrowed listing draws. The signature is unchanged. |

**Seven ops, not twenty.** The rest of paneru's surface — `resize`,
`fullwidth`, `stack`/`unstack`, `equalize`, `balance`, `manage`, the
workspace verbs, the display verbs, `focus first`/`last`/`<n>` — is
deliberately absent. Each further op is one line here when someone wants
it, rather than speculative surface. Every op is fire-and-forget: the
daemon acknowledges nothing and **silently discards** an unrecognised
command, so a wrong wire form fails invisibly (which is why each op's
exact command string is pinned by a test).

#### The Strip listing

The paneru screen carries the active virtual workspace's windows as
overlay rows, in strip order, each reachable by a **jump label**. Rows
come from paneru; focusing comes from Modaliser, joined on window id —
paneru knows the strip's membership and order, Modaliser holds the
`ownerPid` that `focus-window` needs, and neither has the other's half
(**ADR-0024**; `window focus <n>` is *not* used, because a column number
is not derivable from a listed window and stacked columns make position
arithmetic silently wrong).

Dispatch is **provider-minted**, not a static key range: `strip-provider`
runs at come-to-rest — before any render — and returns exactly the edges
this Visit's strip earns. A one-key label edges straight to its window; a
two-key label narrows into a prefix state whose second keys finish the
jump and whose backspace un-narrows. The block draws the *same* snapshot
the provider took, so the rows and the live labels cannot disagree, and a
label pressed faster than the overlay appears still dispatches.

**`strip-provider` options:**

| Keyword | Default | Description |
|---|---|---|
| `'single-alphabet` | `'()` | Ordered one-char strings: the one-key labels. |
| `'leader-alphabet` | `'()` | First key of a two-key label, once the singles run out. |
| `'second-alphabet` | `'()` | Second key of a two-key label. |
| `'panel-label` | `""` | Panel label for the **narrowed** listing a leader drills into. |
| `'enumerate` | `list-current-space-windows` | 0-arg thunk supplying the window enumeration the id join reads. A test seam; leave it alone otherwise. |

`'enumerate` is **not** a performance knob. Swapping in the wider,
cached, staler `list-windows` was measured at 13 ms against the default's
14 — inside the noise, same tail. It is a lever on the join's *hit rate*,
should that ever prove a problem in practice, and nothing else.

All three alphabets come from **you**. Jump labels are keys and no
library file may author a key (ADR-0021), so none is defaulted — an
omitted alphabet yields fewer labels, never a library-chosen letter.
Escalation is automatic and minimal ([`(modaliser
jump-labels)`](#modaliser-jump-labels)): a strip no longer than
`'single-alphabet` never touches the leaders, and past that only the
minimum number of leaders is promoted. Past *both* pools the tail renders
with a blank key and no dispatch, the existing list-block convention.

#### The plane rule

**Provider edges and static edges share one key space, and static edges
match first.** So any key you bind to an op is silently unreachable as a
jump label — no error, no warning, just a label drawn on a row that does
nothing. The library authors neither side, so it cannot enforce this: the
split is yours to keep. `examples/paneru.scm` splits the way herdr's jump
space does — **labels on lowercase, ops on capitals**. Any disjoint split
works; overlap is the trap.

#### The composition

One `if` at config load (ADR-0018), choosing between two `open` bodies —
`open` is a procedure, so a whole drill-down is a value you can name and
splice:

```scheme
(define windows-screen
  (if (paneru:installed?)
      (open "w" "Windows"
        'provider (paneru:strip-provider
                    'single-alphabet '("h" "j" "k" "l" "n" "m" "u" "i" "o" "p")
                    'leader-alphabet '("a" "s" "d" "f")
                    'second-alphabet '("h" "j" "k" "l" "n" "m" "u" "i" "o" "p")
                    'panel-label     "Jump")
        (panel "Move"
          (key "H" "Focus West" paneru:focus-west)
          (key "L" "Focus East" paneru:focus-east)
          (key "S" "Swap West"  paneru:swap-west)
          (key "D" "Swap East"  paneru:swap-east))
        (panel "Size"
          (key "G" "Grow"   paneru:grow)
          (key "R" "Shrink" paneru:shrink)
          (key "C" "Center" paneru:center))
        (panel "Strip"
          (paneru:strip-listing)))

      (open "w" "Windows"
        (panel #f (window:default-layout-block))
        (panel "Windows" (window:list-block 'chips? #t)))))
```

The predicate tests **installation, not liveness**. A liveness test would
make the meaning of `"w"` depend on whether Modaliser or the paneru
daemon won the startup race; installation cannot race. A daemon that is
down degrades quietly instead — the query answers nothing, the listing is
empty, no label dispatches — which is the established empty-output path
(ADR-0017, ADR-0023). Under `swift test` no shell runner is installed, so
the predicate is false and the paneru screen never composes at all.

`examples/paneru.scm` is the complete, working version of the above —
never loaded, mirrored into
`~/.config/modaliser/sys/scheme/examples/` for you to copy from.

#### What `'next 'self` costs here

The provider runs on the **dispatch path**: every come-to-rest re-runs
it, a cyclic `'next 'self` re-arm included. So binding the relative-motion
ops with `'next 'self` — which re-arms the screen in place, the natural
shape for a run of moves — makes each press pay the whole pipeline
synchronously, before the next key is handled. Measured on an
eleven-window strip in a **release** build:

| Stage | Median |
|---|---|
| `paneru query state --json` | 14 ms |
| Window enumeration (AX sweep) | 13 ms |
| `parse-strip-windows` | 5 ms |
| `join-strip-targets` | 2 ms |
| **Come-to-rest total** | **≈34 ms** |

Per *deliberate* press that is a bargain: re-entering the screen runs the
same provider, so `'next 'self` pays the same ≈34 ms and saves two
keystrokes. What keeps it out of the reference composition is the
**tail** — the AX sweep ranges 8–29 ms warm and past 200 ms cold, and
Modaliser does not filter auto-repeat, so *holding* Focus West queues
work faster than it drains and the strip keeps sliding after release.
Add `'next 'self` if you press deliberately; leave it off if you hold
keys down. Full table, method and ruling:
[paneru-window-management spec](../specs/paneru-window-management.md)
decision 4. (Re-running the measurement requires `-c release` — a debug
build inflates the interpreted stages 2–5× and misattributes the cost to
the JSON read.)

---

## Per-app factories

Every factory follows the same doctrine: pure constructors returning
fragments; include the fragment in your `configuration` call, and build
the screen yourself from the exported ops and blocks. **No library here
ships a screen** (ADR-0021) — which operations are surfaced, on which
keys, under which labels is preference.

### Apps that need no library at all

Most apps need none. If every binding is one of the app's own menu
shortcuts, `send-keystroke` from `(modaliser input)` is the whole
mechanism and the screen is plain DSL:

```scheme
(screen 'com.apple.Safari
  (group "t" "Tabs"
    (key "n" "New Tab"   (λ () (send-keystroke '(cmd) "t")))
    (key "w" "Close Tab" (λ () (send-keystroke '(cmd) "w"))))
  (group "b" "Browser"
    (key "l" "Focus Address Bar" (λ () (send-keystroke '(cmd) "l")))
    (key "f" "Find on Page"      (λ () (send-keystroke '(cmd) "f")))))
```

That is exactly how the seeded `default-config.scm` authors Safari,
Finder, Mail, Slack, Zed, Signal, Messages, Telegram, Obsidian and
Zotero; `Scheme/examples/chrome.scm` is a standalone copy for Chrome.
There were once `(modaliser apps safari)` and `(modaliser apps chrome)`
libraries holding those trees — they were deleted, having nothing in
them but preference.

A library earns its place only when an app needs machinery a keystroke
cannot express: AppleScript enumeration, an IPC socket, live-list
blocks, a terminal backend record. The ones below are those cases.

### `(modaliser apps vscode)`

Visual Studio Code (`com.microsoft.VSCode`). The smallest case of "a
library earns its place": most of its operations *are* just
`send-keystroke`, but "select from the open windows" is not — it needs
the window enumeration filtered to VSCode, reshaped so the thing you see
and fuzzy-match is the **project** rather than the window title, and
focused back through a choice alist that keeps the real title as its
fallback match. That is machinery, it is sensitive to VSCode's version,
and it belongs where it stays current across upgrades. The chords are
exported as named ops beside it so one import covers the whole screen.

**Imports:**

```scheme
(import (prefix (modaliser apps vscode) code:))
```

`Scheme/examples/vscode.scm` is a complete worked screen to copy from.
No stock screen ships here (ADR-0021): which operation sits on which key
under which label is preference.

Everything below the `open-file-command` row in the table reaches a
**companion VSCode extension** rather than VSCode-from-outside — see
*What is open inside a window* at the end of this section.

```scheme
(define vscode-label-keys '("a" "s" "d" "f" "g"))

(screen 'com.microsoft.VSCode
  'provider (code:project-provider
              'single-alphabet vscode-label-keys
              'leader-alphabet vscode-label-keys
              'second-alphabet vscode-label-keys
              'panel-label     "Projects")
  …
  (panel "Projects"
    (code:project-listing)))
```

The alphabets are yours and none is defaulted — jump labels are keys
(ADR-0021). `window-source` / `focus-window!` remain exported for a
chooser row if you prefer fuzzy matching to a jump label; the two are
different affordances over the same windows.

**Exports:**

| Export | Description |
|---|---|
| `bundle-id` | `"com.microsoft.VSCode"` — VSCode's own fact, so a caller filtering or launching by it need not restate the literal. The screen's scope symbol is still yours to spell. |
| `window-source` | `(window-source)` → chooser items, one per open VSCode window, cross-space, **alphabetical by project**. Each item's `'text` (the chooser's display **and** fuzzy-match field) is the window's project; the untouched title stays under `'title`. |
| `focus-window!` | `(focus-window! item)` — focus the window an item names. |
| `windows-of` | `(windows-of enumeration)` → items, sorted. The pure half of `window-source`, taking the window list as an argument — which is where the tests land. |
| `project-name` | `(project-name title)` → the folder segment of a VSCode window title. Pure. |
| `focus-choice` | `(focus-choice item)` → the alist `focus-window` reads. Pure, and exported because the title it carries is load-bearing (see below). |
| `project-provider` | `(project-provider 'single-alphabet … 'leader-alphabet … 'second-alphabet … ['panel-label STRING] ['enumerate THUNK])` → a 1-arg procedure for a state's `'provider` slot. At come-to-rest it enumerates, orders by project and mints one jump-label edge per project, lowering the assignment through `(modaliser jump-list)`. `'enumerate` is the test seam, defaulting to the cross-space `list-windows`. |
| `project-listing` | `(project-listing)` → the **Project listing** block spec, reading the *same* per-Visit assignment `project-provider` took — so the rows and the live labels cannot disagree. |
| `toggle-terminal`, `focus-explorer`, `focus-editor` | Zero-arg thunks over VSCode's default macOS chords, ready for a key slot. Read the next section before binding them. |
| `previous-editor`, `next-editor` | The same shape, for `workbench.action.previousEditor` / `.nextEditor` (alt-cmd-Left / alt-cmd-Right). Bind these directly only if focus is already in the editor — otherwise use `editor-cycler`. |
| `editor-cycler` | `(editor-cycler DIRECTION ['focus THUNK-or-#f] ['cycle THUNK])` → a zero-arg thunk that **focuses the editor and then cycles**. `DIRECTION` is `'previous` or `'next` (anything else is `'next`). `'focus` defaults to `focus-editor` and `#f` drops the step; `'cycle` defaults to the direction's chord and is the test seam. See *Why cycling needs a focus step* below. |
| `cycle-thunk` | `(cycle-thunk DIRECTION)` → the chord thunk for that direction. Pure, and the single place the mapping lives. |
| `focused-workspace-path` | `(focused-workspace-path)` → the absolute path of the folder the **frontmost** VSCode window is rooted at, or `#f`. Impure: reads VSCode's stored window state and the live window list. |
| `open-workspaces` | `(open-workspaces)` → every folder-rooted open window as `((path . ABS) (name . BASENAME))`. Impure: reads the state file. |
| `state-file-path` | `(state-file-path)` → where that file lives. |
| `workspaces-of` | `(workspaces-of text)` → the list above, from the state file's **text**. Pure, and the seam every test lands on. |
| `opened-windows-json` | `(opened-windows-json text)` → the `openedWindows` array's own JSON text, or `""`. Pure. |
| `workspace-for-title` | `(workspace-for-title title workspaces)` → the one that window is rooted at, or `#f`. Pure. |
| `title-of-window-id` | `(title-of-window-id id enumeration)` → a VSCode window's title, or `#f`. Pure. |
| `reveal-file!` | `(reveal-file! path [after])` — open `path` in the window that owns its folder, then run `after` (default `focus-explorer`). **Asynchronous**; a `#f` or empty path does nothing. |
| `open-file-command` | `(open-file-command path)` → the command `reveal-file!` would spawn. Pure. |
| `current-vscode-socket-pointer-path` | Parameter. Where the companion extension writes the socket path of the window that last took focus. Defaults to **`#f`** — "no VSCode extension configured" — and `root.scm` installs the real path at boot, the same shape `(modaliser muxes herdr-socket)` uses. The inert default is what keeps `swift test` structurally unable to dial a live editor (ADR-0023). |
| `vscode-default-socket-pointer-path` | `(vscode-default-socket-pointer-path)` → `$HOME/.config/modaliser/vscode/focused`. The resolution policy; the decision to go live is the host's. |
| `vscode-protocol-version` | `1`. The wire contract's version. A reply that does not carry exactly this is treated as an unreachable peer, because Modaliser and the extension are installed separately and can skew (ADR-0026). |
| `vscode-parts` | `(vscode-parts)` → the `parts` **result object**, or `#f`. Impure: reads the pointer file, one round-trip on a 200 ms timeout. `#f` — never a raise — for an unreachable peer, a protocol mismatch, a reply whose `focused` is false, and a reply with no result. The result carries `peer`, `workspace`, `terminals` and `editors`; see the [spec](../specs/vscode-window-parts.md) for each field. |
| `current-vscode-query-runner` | Parameter, the read side's one seam: `(peer method params)` → parsed envelope or `#f`. Defaults to `vscode-socket-request`. A test installs a canned runner here. |
| `current-vscode-notify-runner` | Parameter, the act side's: `(peer method params)` → `#t`/`#f`, fire-and-forget. Defaults to `vscode-socket-send`. Two seams rather than one, so a deliberately abandoned reply is never indistinguishable from a timeout — and so a recording runner can assert *which peer* an action was addressed to, which is the only way ADR-0027's binding is pinned rather than asserted. |
| `vscode-query`, `vscode-notify` | `(… peer method params)` — the dispatchers through those seams. The peer is an **argument**: a read resolves it from the pointer once, and every action addresses the peer the read's own reply named (ADR-0027). |
| `vscode-socket-request`, `vscode-socket-send` | The real transports the two seams default to. Exported so a test can exercise the actual envelope/parse path rather than only the seams above it. |
| `terminal-rows`, `editor-rows` | `(… PARTS)` → **Terminal target**s / **Editor target**s. **Pure**, and where every behavioural test of either listing lands. Each target carries the reply's own `peer` beside its token, plus `text`, `detail`, `current`, `dirty`, `inert` and (editors) `group`. A `#f` reply joins to no rows rather than raising. |
| `shorten-path` | `(shorten-path PATH WORKSPACE)` → `PATH` with the workspace prefix and its separator removed, or `PATH`. Pure. Shortens **where the prefix matches** and never assumes it does — a folderless window and a file opened from outside the workspace both keep the whole path. |
| `terminal-source`, `editor-source` | `(… )` → the rows of one `vscode-parts` call. Impure. `'()` on any miss. |
| `focus-terminal!`, `focus-editor-tab!` | `(… target)` — one fire-and-forget notification to the **target's own peer**, carrying its token. Nothing is waited for and nothing is returned (ADR-0014); every refusal is the peer's and is silent from here. |
| `terminal-provider`, `editor-provider` | `(… 'single-alphabet … 'leader-alphabet … 'second-alphabet … ['panel-label STRING] ['enumerate THUNK])` → a 1-arg procedure for a state's `'provider` slot. Same shape as `project-provider`; `'enumerate` defaults to `vscode-parts`. **No alphabet is defaulted** (ADR-0021). A screen carrying more than one of these must merge them with [`jump-list-compose-providers`](#modaliser-jump-list). |
| `terminal-listing`, `editor-listing` | `(… )` → the block spec each panel draws, reading the *same* per-Visit assignment its own provider took. Both are `part-list` blocks with distinct `'id`s. |

#### The two part panels

The Projects panel one level in: the terminals and the editor tabs of
the **frontmost** window, each reachable by a jump label from its own
alphabet. The row source is a companion VSCode extension over a Unix
socket — VSCode exposes nothing from outside that says what is open
inside a window (ADR-0026, ADR-0027,
[the spec](../specs/vscode-window-parts.md)).

Three properties worth knowing before binding either:

- **A target is `(peer, token)`, never a token alone.** The counter is
  per-window, so the integer `3` is live in as many windows as are open;
  an action carrying only the integer would be an address several
  windows answer to. Every target carries the peer its own reply named,
  and the action goes back to *that* socket — never to whatever the
  pointer file says by then.
- **A row can be inert by design**, and it is normal use rather than a
  race: a tab of a kind with no specified activation carries no token,
  so it is listed, consumes its label, and has no action.
- **Two panels means two `parts` round-trips per come-to-rest**,
  deliberately un-memoised but bounded — the read timeout is 200 ms, so
  the worst case is 400 ms of blocked eval thread. A healthy peer
  answers in ~0.04 ms measured. If a *third* panel lands on the screen
  the answer is one shared read, not a shorter timeout: the `parts`
  reply already carries both listings.

Every miss — no extension, a stale pointer, a protocol skew, a wedged
host — produces **no rows, never wrong rows**. A window with no folder
open is *not* a miss: it lists normally, with its paths unshortened.

#### What the three chords actually do

Established by reading the shipped bundle's own command registrations
(VSCode 1.136.2), not from a shortcut cheat-sheet — all three are
commonly mis-stated.

| Op | Chord | Command | The catch |
|---|---|---|---|
| `toggle-terminal` | ctrl-` | `workbench.action.terminal.toggleTerminal` | A **toggle**: pressed while the terminal already has focus it *hides* the panel. The strict-focus command `workbench.action.terminal.focus` is bound to cmd-Down and only `when` the terminal is already the active panel, so it is not reachable as a general focus chord. Bind it in `keybindings.json` if the toggle grates. |
| `focus-explorer` | shift-cmd-e | `workbench.view.explorer` | **Not** a sidebar toggle, despite the folklore: the registered action opens and focuses the explorer unless the sidebar already has focus, in which case it focuses the *editor*. So it reaches the explorer from anywhere except the explorer. |
| `focus-editor` | cmd-1 | `workbench.action.focusFirstEditorGroup` | The exact command is `focusActiveEditorGroup`, but it registers with **no default keybinding at all**, so a synthetic keystroke cannot reach it. cmd-1 differs only with several editor groups open, where it lands on the leftmost rather than the active one. |

#### Why cycling needs a focus step

`[` and `]` look like two more `send-keystroke` one-liners and are not.
Read out of the same bundle (1.136.2):

| | `previousEditor` | `nextEditor` |
|---|---|---|
| mac primary | alt-cmd-Left | alt-cmd-Right |
| mac secondary | shift-cmd-`[` | shift-cmd-`]` |
| `when` clause | none | none |

Four consequences, none of them guessable:

- **The chord is live from anywhere in the workbench** — no `when`
  clause, weight 200.
- **It survives the integrated terminal.** Both ids are in the default
  `terminal.integrated.commandsToSkipShell` list, so the workbench
  handles the chord rather than the shell swallowing it.
- **They cross editor groups and wrap.** `navigate` walks the active
  group's *sequential* editor list, then asks for the adjacent group
  with wrap-around on. One group cycles its tabs; several cycle every
  tab in the window.
- **And the editor they open does not take focus unless focus was
  already inside the editor group.** The open path guards its `focus()`
  call on the previously-focused element being within the editor
  group's own subtree, and activating the group short-circuits when the
  active group has not changed — which focus moving to the terminal
  never does.

So pressed from the terminal or the explorer, the bare chord changes
the tab under a pane you cannot type into. `editor-cycler` is one op
over both halves for that reason, and the focus half is a **parameter**
because the right chord differs per user: the default `focus-editor` is
cmd-1 (`focusFirstEditorGroup`, the leftmost group), while the exact
command `focusActiveEditorGroup` is reachable only if you bind it in
your own `keybindings.json`.

```scheme
(key "[" "Prev Editor" (code:editor-cycler 'previous))
(key "]" "Next Editor" (code:editor-cycler 'next
                         'focus (λ () (send-keystroke '(ctrl alt) "i"))))
```

The focus step is sent **unconditionally** — nothing in Modaliser can
ask VSCode where focus is — which is correct as long as the focus thunk
is idempotent when the editor already has focus. A strict-focus command
is; cmd-1 with a second editor group open is not, and will move you.

#### Why the list is alphabetical

The window enumeration's order is front-to-back stacking order, so it
changes every time you focus a window. Both affordances need the
opposite: the same project must sit in the same place twice running, or
a chooser cannot be learned and a jump label is worse than useless —
the panel's whole premise is that `a` means the same project today as
yesterday. So `windows-of`
sorts by project name, case-insensitively (a human reading folder names
is not thinking in ASCII, and a plain `string<?` would sort every
capitalised name ahead of every lowercase one), with the case-sensitive
comparison as tie-break so the order is **total**: names differing only
in case cannot swap places between presses either.

#### Why the item keeps its raw title

VSCode's default macOS window title is
`${activeEditorShort}${separator}${rootName}${separator}${profileName}`
with `${separator}` a spaced em dash, and empty variables collapse — so
under the default profile a title is `<folder>` or `<file> — <folder>`
and the last em-dash segment is the folder. Under a **named** profile
the profile is appended after the folder and the last segment is the
profile instead. Hence two rules:

- `focus-choice` puts the **real** title in the choice, not the item's
  display text. `focus-window` resolves the window id against a live
  accessibility sweep and falls back to the title when that misses;
  handing it a folder name would silently degrade the fallback to never
  matching.
- Anything resolving a window to a real **directory** should join
  against a source that knows the folders (VSCode's own stored window
  state) and test *every* segment, rather than trusting the last one.
  That is what `'title` is preserved for.


#### Which directory is a window rooted at?

The window enumeration cannot say: a title carries a folder's **name**
and never its path, and a name is not a location. So the path comes
from VSCode's own record of it —
`~/Library/Application Support/Code/User/globalStorage/storage.json`,
whose `windowsState.openedWindows` is one entry per open window, each
with an exact `folder` URI — and the title is demoted to a **join key**,
matched against the folder basenames. Every em-dash segment is tested,
not just the last, so a named profile (which appends itself after the
folder) does not break the join.

Three things about that file, all accepted with eyes open:

- **The format is undocumented** and may change across VSCode releases.
  The mitigation is placement: the reading is one pure function over the
  file's *text*, pinned by a test running off a fixture captured from a
  real file. When the format moves, a test says so and one function
  changes.
- **It is written on window state change**, not continuously, so a
  window opened seconds ago may not be in it. Then the answer is `#f` —
  an ordinary result, not an error. What to *say* about a miss is the
  screen's call, not the library's.
- **It is ~100 KB**, and handing all of it to `(modaliser json)` cost
  **899 ms** on a debug build — squarely inside ADR-0014's stalled-tap
  territory for something that runs on a key press. So the reader slices
  the `openedWindows` array out with a bracket scan and parses only
  that. The scan looks for its anchor key *backwards* from the end: the
  key is unique, so direction cannot change the answer, and walking the
  last 5% rather than the first 95% took a release-build scan from
  ~490 ms to ~40 ms.

#### Opening a file in the right window

`code <file>` with no flags routes the file to the window that owns its
folder, not to the last-focused one — established by reading the shipped
main process (VSCode 1.136.2, `out/main.js`), where the CLI open path
with no folder argument returns the window whose opened folder is an
ancestor of the file, preferring the longest such folder when several
nest, and falls back to the last active window only when no window owns
it. `-r` (reuse the last active window) and `-n` (force a new one) would
both break that, so `open-file-command` passes neither.

`reveal-file!` is **asynchronous**: `code` against a running instance
takes ~1.1 s to return, so a synchronous spawn would hold the thread
that owns the CGEvent tap for that whole second. The follow-up fires
from the callback, which also puts it after the open rather than racing
it — that ordering is why "focus the explorer yourself afterwards" is
not an equivalent the caller can write. The explorer *selects* the file
without being asked, because `explorer.autoReveal` defaults to true —
pin it explicitly if you depend on it.

The follow-up is a parameter because **which chord reaches the explorer
is not a fact about VSCode on every machine**. The default
`focus-explorer` is VSCode's own shift-cmd-e, correct for a stock
install but liable to bounce to the editor when the explorer already has
focus; anyone who has bound a strict-focus command in their own
`keybindings.json` passes that instead (ADR-0021).

#### What is open *inside* a window

Everything above reads VSCode from outside, and nothing outside VSCode can say
what is open **inside** one window — its editor tabs, its terminals. VSCode's
*extension API* carries exactly that, so Modaliser runs a small peer inside
each window and talks to it over a Unix-domain socket: the **companion
extension** in `vscode-extension/`, which ships inside `Modaliser.app` and is
copied into `~/.vscode/extensions` on the user's confirmed request (ADR-0028).
ADR-0026 records why a companion
extension rather than the accessibility tree or the stored editor state;
ADR-0027 records how one window is addressed among several;
[the spec](../specs/vscode-window-parts.md) is the protocol.

Three things to know before using the surface:

- **It is installed on request, never on Modaliser's initiative.** The library
  exports `install-companion!` and `companion-installed?`; the user's config
  binds a key and a label to them (ADR-0021), and `examples/vscode.scm` ships
  the row. Pairing the two as a `'hidden` gate is what makes the row retire
  itself once the shipped version is installed and return when a Modaliser
  upgrade ships a newer one — the predicate is a **path test** rather than a
  `parts` probe precisely because a socket miss cannot tell *absent* from
  *unreachable*. Where the payload lives is host knowledge, so
  `current-vscode-companion-payload-dir` defaults to "no payload in this build"
  and `root.scm` installs the real path at boot, exactly as it installs the
  socket pointer; un-configured, the predicate answers not-installed and the op
  is a no-op that logs why (ADR-0028, ADR-0023). Note that
  `build-app.sh`'s exact-mirror invariant (ADR-0019) still covers `Scheme/`
  only, so nothing fails a Modaliser build if the extension goes stale: the
  reply carries a protocol version and a mismatch is answered with `#f`, so a
  skew is an empty panel and a log line rather than misread fields.
- **Every miss is `#f`.** Extension not installed, not yet activated, disabled
  for the profile, a stale pointer, a crashed host, a window that has lost
  focus — all of them are `#f`, and `#f` is no rows. That is deliberate: a
  wrong row is worse than no row, because a wrong row jumps somewhere.
- **A read is addressed by the pointer file; an act is addressed by the reply.**
  `vscode-parts` resolves the pointer once. Every action must go to the `peer`
  path *that reply* carried, and `vscode-notify` takes it as an argument for
  that reason. Re-reading the pointer at act time is a one-line shortcut and is
  wrong: every window's token counter starts at the same place, so a pointer
  that moved between the read and the press delivers window A's token to window
  B, where it **resolves** — to a different tab (ADR-0027).

```scheme
(let ((parts (code:vscode-parts)))
  (when parts
    (json-ref parts "terminals")          ; this window's terminals
    (json-ref parts "editors")            ; its editor tabs
    ;; and, to act on one, the peer that drew it:
    (code:vscode-notify (json-ref parts "peer")
                        "focus-terminal"
                        (list (cons "token" 12)))))
```

Rows, providers and listings are built on this in `(modaliser apps vscode)`'s
panel surface; the transport is the layer documented here.

#### Installing the companion

The op and its gate, bound in your own config — the key and the label are
yours (ADR-0021), and the `'hidden` pairing is what makes the row retire
itself:

```scheme
(key "I" "Install VSCode Companion" code:install-companion!
     'hidden code:companion-installed?)
```

| export | answers |
|---|---|
| `(install-companion!)` | confirm, copy the bundled payload into `~/.vscode/extensions`, re-probe. Idempotent; a no-op that logs why when this build carries no payload. |
| `(companion-installed?)` | is *this build's* version already installed. Cached — the gate is read on every overlay render. |
| `(companion-identity)` | `<publisher>.<name>-<version>`, from the file `build-app.sh` stamps beside the payload |
| `(companion-install-dir)` | where an install would land |
| `(companion-install-command)` | what would be spawned — the shipped sweep-and-copy script, pointed at the payload |
| `current-vscode-companion-payload-dir` | the host-installed payload path; `#f` means "no payload in this build" |

Nothing is written to `~/.vscode` without a confirmed dialog, and the dialog
names two things the terminal libraries' `configure!` dialogs have no need to:
that this installs extension code which activates in every VSCode window, and
that a plain `brew uninstall` leaves it behind (ADR-0028).

### `(modaliser apps iterm)`

iTerm's integration — the terminal backend record (carrying the
`'canvas-frame` host capability behind herdr's chip geometry) and the
digit-jump mode tree — plus the pane/tab ops and live-list blocks a
screen binds. iTerm ships **no stock screen** (ADR-0021 — a library
holds facilities, configuration holds decisions).

**Imports:**

```scheme
(import (prefix (modaliser apps iterm) iterm:))
```

#### iTerm: wiring in the library, screen in your config

`(iterm:wiring)` carries the integration; the screen is yours:

```scheme
(configuration
  …
  (iterm:wiring)        ; backend record + 'iterm-pane-digit tree
  iterm-screen          ; (screen 'com.googlecode.iterm2 …), authored by you
  iterm-focus-walk)     ; (tree 'iterm-panes-focus …), if you want one
```

The seeded `default-config.scm` carries the full stock composition —
read it there and edit it in place; it is the reference, not a copy of
one. Two scope symbols are **machinery**, not preference:
`'com.googlecode.iterm2` (the backend record's match-key — a screen
under any other scope is not terminal-like, so it never consults the
Terminal context map and never derives its gated `.` step-in edge) and
`'iterm-pane-digit` (what the record's `focus-pane-by-digit` slot names).
`'iterm-panes-focus` is yours to name.

Being terminal-like, your screen consults the Terminal context map at
every local-leader press (see
[terminal-pane-aware-tree.md](../how-to/terminal-pane-aware-tree.md)).

Eight of the ops below — the four splits, the four moves, plus
`copy-mode` and `toggle-pane-zoom` — ride on key bindings that only
`configure!` writes into iTerm's preferences. If you bind those ops,
surface `configure!` too, or they silently do nothing on a fresh
machine.

**Exports:**

| Export | Description |
|---|---|
| `wiring` | `(wiring)` — the `'iterm` backend record and the `'iterm-pane-digit` mode tree. No screen, no key, no label. |
| `focus-pane-{left,right,up,down}` | iTerm's shipped Cmd+Alt+Arrow focus bindings — no setup needed. |
| `split-pane-{left,right,up,down}` | Cmd+D / Cmd+Shift+D; left/up split the native way, then swap. **Provisioned.** |
| `move-pane-{left,right,up,down}` | Ctrl+Shift+H/J/K/L pane swaps. **Provisioned.** |
| `toggle-pane-zoom`, `copy-mode` | Cmd+Shift+Return (maximize active pane) and Cmd+Shift+C (copy mode). **Provisioned.** |
| `rename-tab!`, `new-tab!`, `close-tab!` | Tab ops. Rename clicks iTerm's *Edit Tab Title* menu item; new inherits the current session's profile. |
| `tab-focus-{prev,next}`, `tab-move-{prev,next}` | ⌘⇧[ / ⌘⇧] and ⌥⇧⌘[ / ⌥⇧⌘]. Direction-free naming — which of h/j/k/l reaches each is your screen's call. |
| `configure!` | The one-shot provisioning action: confirm dialog, back up iTerm's prefs, write the eight bindings, relaunch iTerm. Idempotent. |
| `configured?` | `#t` when iTerm already carries all eight. Cached, so it is cheap enough for a `'hidden` gate. |
| `pane-list-block` | Live pane list block (`'chips? #t` paints pane chips) — place it in a panel or leave it loose. |
| `tab-list-block` | Live tab list block, carrying its digit dispatch keys. |
| `select-session-by-id`, `select-tab-by-index`, `iterm-list-session-ids` | Lower-level pane/tab operations behind the blocks. |
| `default-pane-labels` | `("1" "2" … "9" "0")` — default pane-label list. |
| `current-iterm-provision-runner` | The test seam for the provisioning script: a `(lambda (shell-command callback) ...)` matching `run-shell-async`'s shape, mirroring `current-dialog-runner`. Default: `(modaliser shell)`'s `run-shell-async` — the seam, so under `swift test` even the un-overridden path spawns nothing (ADR-0023). |

Pairing `configure!` with `configured?` is what makes the setup row
retire itself — on the next overlay open after provisioning, with no
relaunch:

```scheme
(key "C-I" "Configure iTerm" iterm:configure! 'hidden iterm:configured?)
```

Pane-chip styling lives in CSS: the chips read from the same `.chip`
rule the window-list block uses; edit `~/.config/modaliser/theme.css`
to customise.

The seeded screen holds loose `c` (Copy Mode), `z` (Toggle Zoom), and
the self-retiring setup row; a Splits panel (one-shot hjkl pane focus,
plus `s` drilling into the full split toolkit — the Focus/Move walk, a
New Split group, and the pane list with chips); a `t` Tabs sub-screen
(rename/new/delete, the tab walk, and the live tab list); and a
top-level pane list panel. Panels are banded cards but stay transparent
for dispatch. Its focus Walk (`'iterm-panes-focus`) cycles via
`'next 'self` and uses `'exit-on-unknown #t` so typing any non-binding
key returns control to iTerm.

### Terminal hosts: `(modaliser apps kitty)`, `(modaliser apps wezterm)`, `(modaliser apps ghostty)`, `(modaliser apps alacritty)`

Each exports `backend` and a zero-arg `fragment` carrying the backend
record (and, where the terminal has native splits, a digit-jump mode
tree). None ships a stock screen — compose the fragment with your own
`(screen "<bundle-id>" …)`, whose scope is what makes the screen
terminal-like against the record's match-key. Alacritty's backend is
detection-only (no native splits — run a mux inside for splits); kitty
and alacritty also export the provisioning pair `configure!` /
`configured?` for their one-shot host setup, which a configuration
binds as a self-retiring row:

```scheme
(key "C-I" "Configure Kitty" kitty:configure! 'hidden kitty:configured?)
```

See
[terminal-pane-aware-tree.md](../how-to/terminal-pane-aware-tree.md).

### Muxes: `(modaliser muxes herdr)`, `(modaliser muxes tmux)`, `(modaliser muxes zellij)`

Each exports `backend` plus a zero-arg `wiring` constructor carrying the
tool's Terminal-context-map entry, its backend record, and its
digit-jump mode tree — so composing the tool into *every* terminal-like
host is one call inside `(terminal-contexts …)`. **None ships a
screen** (ADR-0021): each also exports its ops one name apiece, and the
screen that binds them is yours. `(modaliser tools nvim)` follows the
same shape with less in it — a tree-only context entry, no backend
record, because nvim hosts no panes.

Where the stock composition lives differs only by whether a fresh
install runs the tool: herdr, zellij and nvim are authored inline in the
seeded `default-config.scm`; **tmux ships as
`Scheme/examples/tmux.scm`** — a complete, working configuration that is
never loaded, mirrored into `~/.config/modaliser/sys/scheme/examples/`
for you to copy from.

tmux and zellij drive their tools by shelling out; **herdr does not**.
It is driven over herdr's JSON-RPC Unix socket (ADR-0020), and its
backend record therefore carries **no `tool-name`** — nothing on the
tool path to probe, so herdr sits outside ADR-0017 Layer 2 entirely
(see [terminal-detection.md](terminal-detection.md#herdr-reachability)).

#### herdr: wiring in the library, screen in your config

herdr ships **no stock screen** (ADR-0021 — a library holds facilities,
configuration holds decisions). `(herdr:wiring)` carries the
integration; the screen is yours:

```scheme
(configuration
  …
  (terminal-contexts (herdr:wiring))   ; context entry + backend + digit tree
  herdr-screen                         ; (screen 'herdr …), authored by you
  herdr-focus-walk)                    ; (tree 'herdr-panes-focus …)
```

The seeded `default-config.scm` carries the full stock composition —
read it there and edit it in place; it is the reference, not a copy of
one. Two scope symbols are **machinery**, not preference: `'herdr` (the
wiring's context entry resolves to it, and the jump provider mints its
narrowing states under it) and `'herdr-panes-focus` (what the Focus rows
cross into). Rename either and the configuration fails
reference-closure validation at load.

Three of the exports below are the jump space, and it only works if your
screen wires all three: `'provider herdr-jump-provider`,
`'on-enter paint-jump-chips!` / `'on-leave clear-jump-chips!`, and a
`(panel "Jump" (jump-legend-block))`. Drop all three together, or keep
all three.

| Export | Description |
|---|---|
| `wiring` | `(wiring)` — the context-map entry, the `'herdr` backend record, and the `'herdr-pane-digit` mode tree. No screen, no key, no label. |
| `focus-pane-{left,right,up,down}` | `pane.focus_direction`. |
| `split-pane-{left,right,up,down}` | `pane.split` (left/up split the native way, then swap). |
| `move-pane-{left,right,up,down}` | `pane.swap` with the directional neighbour. |
| `toggle-pane-zoom`, `close-pane` | `pane.zoom {mode:"toggle"}`, `pane.close` on the focused pane. |
| `new-tab`, `close-focused-tab`, `rename-focused-tab!` | Tab ops; rename opens a pre-filled chooser prompt. |
| `new-workspace`, `close-focused-workspace`, `rename-focused-workspace!` | Space ops (herdr's API says *workspace*, its UI says *Space*). |
| `move-tab-{left,right}`, `move-space-{up,down}` | Reorder within the tab bar / sidebar. No-ops at either end. |
| `new-worktree!`, `remove-focused-worktree!` | Worktree create/remove. Remove never forces, so git still refuses a dirty tree. |
| `jump-to-next-blocked` | Round-robin to the next blocked agent; toasts when none. |
| `stop-server!` | Ends the herdr **server** behind a confirm dialog. Contrast `detach-op`. |
| `focus-pane-by-id`, `focus-tab-by-id`, `focus-workspace-by-id` | The by-id focus verbs — a `focus-fn` for the cycle ops and hand-rolled bindings. |
| `focused-tab-id`, `focused-workspace-id` | Zero-arg scope thunks, for scoping a ring the way its list block is scoped. |
| `cycle-prev-op`, `cycle-next-op` | `(cycle-*-op kind focus-fn scope-id-fn)` → thunk. One ring step over a list block's displayed rows; bind with `'next 'self` so presses chain. |
| `copy-mode-op`, `scrollback-op`, `detach-op` | `(op prefix)` → thunk. herdr's three client-side keybindings, emitted as prefix-then-key keystrokes. |
| `herdr-default-prefix` | `'((ctrl) "b")` — herdr's stock client prefix. Pass your own to the three ops above if you rebound it. |
| `pane-list-block` (`'chips? #t`), `tab-list-block`, `workspace-list-block`, `agent-list-block`, `worktree-list-block` | Live-list blocks, each carrying a hidden digit range that focuses the matching row. |
| `herdr-jump-provider`, `paint-jump-chips!`, `clear-jump-chips!`, `jump-legend-block` | The jump space — wire all four or none. |
| `current-herdr-command-runner`, `current-herdr-send-runner` | Test seams capturing the `(method params)` pair an op puts on the socket. The read side is `current-herdr-query-runner`, below. |

herdr exposes no way to query its resolved keybindings, so
`herdr-default-prefix` and each keystroke op's *second* key (`[`, `e`,
`q`) are assumptions. The prefix is one argument you correct in one
place; a rebound `copy_mode` / `edit_scrollback` / `detach` itself is a
one-line thunk you write in place of the op.

### `(modaliser muxes herdr-socket)`

herdr's transport, factored out of the backend so the herdr *blocks*
can reach it too — `(modaliser muxes herdr)` imports
`(modaliser blocks herdr-list)` for its chip-paint pipeline, so a
block importing the backend would close a cycle.

It owns everything about *how* to reach herdr and nothing about what to
say: the socket path, the round-trip timeout, the
`{"id","method","params"}` envelope built with `json-write`, and the two
transports over `(modaliser unix-socket)` —
`(herdr-socket-request method params)` → parsed response envelope \|
`#f`, and its no-reply sibling `(herdr-socket-send method params)`.

The path comes in two pieces, and the split is deliberate.
`(herdr-default-socket-path)` is the **policy** — `$HERDR_SOCKET_PATH`,
else `~/.config/herdr/herdr.sock` (the fallback is what a GUI-launched
Modaliser actually uses, since it inherits a stripped environment).
`current-herdr-socket-path` is the **parameter the transports dial**, and
it defaults to `#f`: no socket configured, every call degrading to the
same `#f` an unreachable herdr returns. The **host** installs the live
path at bootstrap — `root.scm` does
`(current-herdr-socket-path (herdr-default-socket-path))`, the same shape
as the arity predicates it installs into `(modaliser fsm)`. Reaching a
running herdr is a property of the app being live, not of the library
being imported, and the inert default is what keeps `swift test` off a
developer's own herdr session (ADR-0020).

`(herdr-query method params)` is the **one read seam** every herdr
reader in the tree goes through — the backend's detection/jump/ring
queries, `blocks/herdr-list`'s five live lists and two chip-geometry
queries, and `blocks/herdr-jump-legend`'s three name lookups. It routes
through the `current-herdr-query-runner` parameter, so one
`parameterize` stubs herdr's entire read surface in a test.

A `#f` from either transport covers every failure — unreachable socket,
timeout, unparseable reply, structured `error` — and nothing raises: a
leader press must not raise. The reason is logged rather than discarded
(the `2>/dev/null` it replaces is exactly what hid the `agent_not_found`
behind the pane-switching regression).

**Configure iTerm.** The split, swap, copy-mode and zoom ops fire
iTerm keyboard shortcuts that are not all iTerm defaults. `configure!`
provisions them, and the seeded config surfaces it on `Ctrl+Shift+I`
labelled "Configure iTerm", gated `'hidden iterm:configured?` so the row
shows only while iTerm lacks the bindings and disappears once they are
set. Triggering it shows a confirmation dialog; on Continue it quits
iTerm, writes eight `GlobalKeyMap` bindings, and relaunches iTerm — quit
can take several seconds (it polls for the process to exit), so the whole
provisioning step fires through `run-shell-async` (ADR-0014), keeping the
leader responsive while it runs:

| Shortcut | Action |
|---|---|
| `Ctrl+Shift+H/J/K/L` | swap pane left / down / up / right |
| `Cmd+D` | split pane right |
| `Cmd+Shift+D` | split pane down |
| `Cmd+Shift+C` | copy mode |
| `Cmd+Shift+Return` | maximize active pane |

A timestamped backup of iTerm's preferences is written first. If iTerm
is set to load preferences from a custom folder, that folder's plist
is the file updated.

### tmux and zellij: the same fourteen ops

`(modaliser muxes tmux)` and `(modaliser muxes zellij)` export an
identical surface — the same names, one per thing the mux can do, each a
0-arg thunk that drops straight into a `(key K L op)` slot. Only the
recipe underneath differs (`tmux select-pane -L` vs `zellij action
move-focus left`), which is the point: swapping mux means swapping the
prefix on the call sites, not rewriting the screen.

| Export | Description |
|---|---|
| `wiring` | `(wiring)` — the context-map entry, the backend record, and the `'<mux>-pane-digit` mode tree. No screen, no key, no label. |
| `backend` | The record itself, for hand-wiring outside `(terminal-contexts …)`. |
| `focus-pane-{left,right,up,down}` | Move focus to the directional neighbour. |
| `split-pane-{left,right,up,down}` | New pane on that side of the focused one. |
| `move-pane-{left,right,up,down}` | Swap the focused pane with the directional neighbour. No-op at the edge of the layout. |
| `toggle-pane-zoom` | Stateless zoom toggle (`resize-pane -Z` / `toggle-fullscreen`). |

The digit-jump chips need no binding: each backend record names its own
`'<mux>-pane-digit` tree, and the host's pane-list block fires it. Chip
*geometry* is derived from the focused iTerm split (both muxes paint
inside one terminal view), so chips are the one part of the surface that
is host-specific today.

Two scope symbols are **machinery**, not preference: `'tmux` / `'zellij`
(the wiring's context entry resolves to it) and `'tmux-pane-digit` /
`'zellij-pane-digit` (the record names it by key). Rename either and the
configuration fails reference-closure validation at load.

The stock composition for zellij is inline in the seeded
`default-config.scm`; tmux's is `Scheme/examples/tmux.scm`.

### `(modaliser tools nvim)`

Neovim as an **inner tool** with no pane surface of its own: its splits
are nvim windows, driven over nvim's msgpack-RPC socket, so `(wiring)`
is a tree-only context entry — no backend record, no chain
continuation, no derived step-in. Focus routing resolves the *focused*
nvim instance per press (see `(modaliser terminal)`'s
`nvim-remote-send`), so any number of concurrent instances work.

| Export | Description |
|---|---|
| `wiring` | `(wiring)` — the `"nvim"` → `'nvim` context-map entry, and nothing else. |
| `focus-window-{left,right,up,down}` | `<C-w>h/l/k/j` — move focus to the neighbouring nvim window. |
| `wincmd` | `(wincmd "v")` → thunk. The general form: any `<C-w>` command, notation passed to nvim verbatim (`s` split, `v` vsplit, `q` close, `=` equalise, …). |

The seeded `default-config.scm` surfaces window focus on hjkl and stops
there, deliberately — nvim power users live inside nvim's own maps, and
the point of the screen is that the pane-focus muscle memory crosses
*into* nvim windows. `wincmd` is the seam for wanting more.

### `(modaliser tools grove)`

[grove](https://github.com/linkuistics/grove) drives a long workstream
as a VCS-tracked tree of task files under `.grove/` in a working tree,
exactly one of which is the **live leaf**: the task a session is on
right now. Somebody working several groves at once — one per worktree,
one editor window per worktree — opens that file by hand, per tree, all
day. This library answers the one question that automates away.

That is the whole surface, deliberately. `grove-llm` has a dozen verbs
and all but one of them *write*; `pick` is the single read, so it is the
single thing wrapped here.

| Export | Description |
|---|---|
| `live-leaf` | `(live-leaf worktree)` → the absolute path of that worktree's live grove leaf, or `#f`. Impure: runs the CLI through the portable shell seam. |
| `live-leaf-command` | `(live-leaf-command worktree)` → the command it would spawn. Pure. |
| `leaf-of-output` | `(leaf-of-output text)` → the leaf path in the CLI's output, or `#f`. Pure. |

**`#f` is an ordinary answer, not an error.** Three of the four outcomes
are "no leaf" and none is worth raising into a leader press: the
directory is not a grove (`pick` exits 1), the grove has no live leaves
(exits 0), or the directory is not a VCS working tree (exits 1). All
three print their diagnostic on *stderr* and nothing on stdout, so every
miss arrives as the same empty string the shell seam hands back when no
runner is installed at all (ADR-0023) — one code path covers a missing
binary, an absent grove, a finished grove and a bare test engine.

**Nothing here knows about an editor**, and nothing about an editor
knows about this. Where the returned path is opened is the caller's
business, and the caller is user configuration:
`Scheme/examples/vscode.scm` composes it with `(modaliser apps vscode)`
into "open this window's grove leaf and land the explorer on it", and
the two libraries never reference each other.

---

## Blocks

Block constructors return alist specs (`'type SYM 'block-children (…)
…`). A block is a **dispatch atom**: author it as a child of the node,
and the Display value places it — inside a panel as that panel's live
list, or loose in the bare region. The full protocol is documented in
[renderer-protocol.md](renderer-protocol.md).

### `(modaliser blocks window-list)`

Low-level window-list block. The high-level wrapper is
`(window:list-block …)` from `(modaliser window-actions)`; reach for
the lower-level form only when composing a custom block.

| Export | Description |
|---|---|
| `make-window-list-block` | `(make-window-list-block [keyword value]...)` — accepts `'chips? #t` to enable chip painting. Returns a block spec. |
| `window-list-current-labels` | The label sequence the last render painted (for custom dispatch handlers). |
| `window-list-current-targets` | Alist of `label → window` from the last render. |

### `(modaliser blocks display-list)`

Block constructor behind `(display:display-list-block …)` from
`(modaliser display-actions)`; reach for that wrapper rather than this directly.
Paints one round display chip per display into the `'displays` hint group and
renders one overlay row per display.

### `(modaliser blocks paneru-strip)`

Renderer for the **Strip listing**. Reach for
[`(paneru:strip-listing)`](#modaliser-wms-paneru) rather than this
directly — that wrapper closes the block over the strip Edge provider's
snapshot, which is the whole point of it.

Display-only, mirroring `(modaliser blocks herdr-jump-legend)`: it
dispatches nothing, because the jump labels reach the keyboard as
provider edges. **It never queries** — its render hook reads a cell the
provider already filled, which inverts `window-list`'s contract (whose
`on-render-fn` *is* its data source) and is the main reason this is a
separate block rather than a parameterised `window-list`. It paints no
chips: paneru scrolls the strip under animation, so a chip's rect is
stale the moment it is drawn.

### `(modaliser blocks project-list)`

Renderer for the **Project listing**. Reach for
[`(code:project-listing)`](#modaliser-apps-vscode) rather than this
directly — that wrapper closes the block over the project Edge
provider's snapshot, which is the whole point of it.

Display-only and never-querying, on the same terms as `paneru-strip`.
One row per project: jump label, arrow, name — three columns, with the
name taking the full remaining width.

**Why this is not `paneru-strip`.** The two share the *subtle* half —
grouping, prefix states, re-minting — and share it properly, in
[`(modaliser jump-list)`](#modaliser-jump-list). What is duplicated is
presentation, and the asymmetry is deliberate: duplicated machinery
drifts silently, duplicated presentation drifts visibly. The content
differs too — a Strip row is an app name plus a window title in four
columns, a Project row is one long name (worktree folders run past forty
characters) that wants the whole width and an ellipsis.

| Export | Signature | Description |
|---|---|---|
| `make-project-list-block` | `(make-project-list-block ['assigned-fn THUNK])` | Block spec of `'type 'project-list`. `assigned-fn` returns the assignment; each target need only carry `'text`, the name to draw. Defaults to an empty listing. |
| `project-list-rows` | `(project-list-rows assigned)` | Pure assignment → row payload. Same length and order, nothing filtered. |

### `(modaliser blocks part-list)`

Renderer for a **window part** listing — the **Terminal listing** and
the **Editor listing** both. Reach for
[`(code:terminal-listing)` / `(code:editor-listing)`](#modaliser-apps-vscode)
rather than this directly; those wrappers close the block over each Edge
provider's own snapshot.

Display-only and never-querying, on the same terms as its two peers.
Four columns: jump label, arrow, name, and a dimmed trailing detail —
closer to `paneru-strip`'s grid than to `project-list`'s full width.

**Why ONE block for two panels.** k4's rule is *share machinery,
duplicate presentation*, and it cuts both ways. It bought `project-list`
its own existence beside `paneru-strip` because the content really
differed. Here it does not: a Terminal row is a short name plus a cwd
and an Editor row is a filename plus a workspace-relative path — one
presentation with two callers, so writing it twice would duplicate
presentation that is not different. Each caller supplies the *content*
of `text` and `detail`; the grid is the same grid.

**Two panels on one screen means two explicit `'id`s.** A panel's block
reference resolves through `block-ref-id` — the block's `'id` when it
has one, its `'type` otherwise — so two blocks both answering to
`part-list` are ambiguous and `resolve-display` raises.

**A row that renders and does not dispatch** is normal here, unlike in
either peer: a tab of a kind with no specified activation arrives with
no token at all, so it has a label and nothing behind it. It renders
dimmed and without an arrow. Listing it is honest — omitting it would
make the panel disagree with the tab strip the user is looking at, and
would renumber every label below it.

| Export | Signature | Description |
|---|---|---|
| `make-part-list-block` | `(make-part-list-block ['assigned-fn THUNK] ['id SYMBOL])` | Block spec of `'type 'part-list`. Each target may carry `'text`, `'detail`, `'current`, `'dirty` and `'inert`. `'id` is emitted only when given, because `block-ref-id` prefers it over `'type`. |
| `part-list-rows` | `(part-list-rows assigned)` | Pure assignment → row payload (`label`, `name`, `detail`, `current`, `dirty`, `inert`). Same length and order, nothing filtered. |

| Export | Description |
|---|---|
| `make-paneru-strip-block` | `(make-paneru-strip-block ['assigned-fn THUNK])` — the thunk returns the `((label . target) …)` snapshot. Rows are threaded in rather than imported, so this block knows nothing of paneru. |
| `paneru-strip-rows` | Pure snapshot → row payload (`label`, `app`, `title`, `focused`), exported for tests. |

### `(modaliser blocks window-diagram)`

Low-level window-diagram block. The high-level wrapper is
`(window:layout-block …)` from `(modaliser window-actions)`.

| Export | Signature |
|---|---|
| `make-window-diagram-block` | `(make-window-diagram-block panel-specs)` — `panel-specs` is a list of camelCase panel alists (`'key`, `'col`, `'row`, `'colSpan`, `'rowSpan`). |

---

## Helpers

### `(modaliser util)`

General Scheme utilities used by every other library.

| Export | Purpose |
|---|---|
| `alist-ref` | `(alist-ref alist key default)` — lookup with fallback. |
| `props->alist` | `(props->alist k v k v …)` — flat keyword list → alist. |
| `string-join` | Concatenate strings with a separator. |
| `string-split` | Split a string on a delimiter. |
| `string-trim` | Strip leading/trailing whitespace. |
| `string-contains?` | Substring search. |
| `escape-string` | `(escape-string str table)` — replace each char keyed in `table` (an alist of char → replacement-string) with its replacement; the shared char-walk behind the host UI's JS/JSON/HTML-attribute escapers, which supply their own tables. |
| `read-file-text` | Read a file's contents into a string. |
| `log` | Append a line to the Modaliser log. |

It also re-exports, from one base library, the standard bindings that LispKit's
`(scheme base)` omits — so a `(modaliser …)` library or portable config gets them
without importing `(scheme cxr)` / `(srfi 1)` / `(srfi 69)` by name:

| Re-exported family | Bindings |
|---|---|
| `(scheme cxr)` accessors | `caddr`, `cadddr`, and the rest of the 3-/4-deep `car`/`cdr` compositions. |
| `(srfi 1)` list ops | `filter`, `remove`, `partition`, `filter-map`, `find`. |
| `(srfi 69)` hashtables | `make-hash-table`, `hash-table-set!`, `hash-table-ref/default`, `string-hash`. |

### `(modaliser json)`

A small portable JSON reader and writer — the shared answer to socket-API
backends, which speak compact single-line JSON that the multiline `awk`
extractors of the CLI-native muxes cannot parse. Depends only on
`(scheme base)` + `(scheme char)`: no hashtable library, no host JSON
primitive.

The representation is chosen so objects and arrays never collide, and both
directions agree on it:

| JSON | Scheme |
|---|---|
| object | alist `(("key" . value) …)` — **empty object is `'()`** |
| array | vector `#(value …)` — **empty array is `#()`** |
| string / number | string / number |
| `true` / `false` | `#t` / `#f` |
| `null` | the symbol `null` |

| Export | Purpose |
|---|---|
| `json-parse` | Text → the representation above. Raises on malformed input; callers reading from an external process wrap it in `guard` so a stray line degrades to `#f` rather than breaking a leader press. |
| `json-ref` | `(json-ref obj key)` — look up a key in a parsed object. A missing key, or a lookup into an array or scalar, degrades to `#f`, so chained walks down a path that does not exist return `#f` instead of erroring. |
| `json-write` | The mirror: the representation above → compact JSON text. Objects emit in **alist order**, which makes a request line deterministic and therefore assertable in a test. Escapes `"`, `\`, and every control character. Raises on an unsupported value — building a request from malformed data is a programming error, not a wire condition. |

Two consequences of the representation are worth stating, because both are
inherited by every caller:

- A key whose value is JSON `false` reads back as `#f`, indistinguishable via
  `json-ref` from "key absent". Callers that must tell them apart check
  membership first.
- Symmetrically, on the write side `#f` *means* `false`, so an absent value must
  be **omitted from the alist** rather than written as `#f`.

`json-write` is what the herdr socket transport builds its
`{"id","method","params"}` request line with (ADR-0020), so escaping for every
param of every method is decided in exactly one place.

### `(modaliser keymap)`

Modifier predicates for keystroke handlers and AX listeners.

| Export | Returns |
|---|---|
| `has-cmd?`, `has-shift?`, `has-alt?`, `has-ctrl?` | Boolean predicates over the modifier mask integer. |

### `(modaliser theming)`

Resolves the live `.chip` / `.chip.faded` CSS rules to a concrete alist
of pixel/colour values. Used by `(modaliser blocks window-list)` and
`(modaliser apps iterm)` at chip-paint time so chip styling tracks
whatever the user puts in `~/.config/modaliser/theme.css`.

| Export | Signature | Description |
|---|---|---|
| `current-chip-theme` | `(current-chip-theme [variant])` | `variant` is `'normal` (default) or `'faded`. Returns an alist with keys `color`, `background`, `font-size`, `padding`, `corner-radius`, `border-width`, `border-color`. Colours are hex (`#rrggbb` / `#rrggbbaa`); numeric values are bare ints. |
| `chip-host-padding` | `(chip-host-padding)` | Canonical pixel inset used by chip painters: distance between the chip and its host's top-left corner, clearance the chip-placement search requires around an occluder edge, and gap left when two chips dodge each other. One value keeps the visual rhythm consistent across window-list and AX-hint chips. |

Resolution mechanism: a hidden offscreen probe WebView spawned at boot
loads the full overlay CSS cascade plus two probe `<div>`s, reads
`getComputedStyle`, and posts the resolved values back via
`webview-on-message`. The probe runs once per boot — relaunch is the
refresh path for chip styling. Before the probe completes, the
accessor returns seed defaults matching `base.css`. See
[theming.md](theming.md#how-chip-values-are-resolved) for the full
picture.

### `(modaliser ax-hints)`

Accessibility-target overlays — paint chips on AX-discovered UI
elements, used by `(modaliser apps iterm)` for pane chips. See the
source for the full API; the most common entry point is
`ax-target-hints`.

### `(modaliser terminal)`

The terminal-backend façade and detection helpers: backend records
(`make-terminal-backend` and the `terminal-backend-*` accessors), the
detection chain (`focused-terminal-path` — what activation's context
walk consumes), host capabilities (`host-capability`,
`terminal-backend-capability`), the 14 pane-op shims, and backend tool
health (ADR-0017). Notable simple export:
`focused-terminal-foreground-command` — the
command line of the foregrounded process in the focused terminal pane.
Also exports `modaliser-tool-path` (the derived PATH prefix every
mux/app backend prepends before shelling out) and the pure
`merge-tool-path` function behind it — see
[terminal-detection.md](terminal-detection.md) and
[ADR-0017](../adr/0017-tool-path-resolution.md).

### `(modaliser shell)`

The seam every shell-out in the tree passes through
([ADR-0023](../adr/0023-native-reach-is-host-installed.md)). It is a
*portable* library with no native import: `run-shell` and `run-shell-async`
dispatch through parameters that default to **no runner installed**, so the
library tree is structurally incapable of spawning a process until the host
wires one in. `root.scm` does that first thing at boot; `swift test` never
runs `root.scm`, which is what keeps the suite off the developer's live
tmux / zellij / wezterm / kitty / terminal apps.

An uninstalled runner degrades to `""` — the same empty output a backend
already reads as "the tool told us nothing" (ADR-0017) — so no caller needs
a branch for it.

| Export | Signature | Description |
|---|---|---|
| `run-shell` | `(run-shell command)` | Run `command`, returning stdout. `""` when no runner is installed. |
| `run-shell-async` | `(run-shell-async command callback ['timeout seconds])` | Non-blocking (ADR-0014); `callback` receives `(exit-code stdout stderr)`. With no runner installed the callback still fires, with `(-1 "" reason)` — the caller is answered, not stranded. |
| `current-shell-runner` | parameter | `(lambda (command) …) → stdout`, or `#f` for none. Set by `root.scm` to `run-shell-native`; a test may `parameterize` a canned runner to assert on the command a backend would have run. |
| `current-shell-async-runner` | parameter | The `run-shell-async` counterpart, set to `run-shell-async-native`. |

### `(modaliser http)`

The sibling seam, same shape and same ADR
([ADR-0023](../adr/0023-native-reach-is-host-installed.md)): a *portable*
library with no native import, whose `http-get` dispatches through a parameter
that defaults to **no runner installed**. Where the shell seam keeps the suite
off the developer's own running tools, this one keeps it off the public
internet — `swift test` never runs `root.scm`, which is the only installer, so
a bare engine cannot reach an endpoint however many `http-get` calls it makes.

An uninstalled runner answers the callback with `#f`, which the one consumer
(`(modaliser web-search)`, for Google Suggest) already reads as "network error
— keep showing just the pinned suggestion". The callback always fires, so a
caller awaiting a response is answered rather than stranded (ADR-0014).

Unlike the shell install, the host install is not order-sensitive: nothing in
the tree fetches at import time.

| Export | Signature | Description |
|---|---|---|
| `http-get` | `(http-get url callback)` | Fetch `url`; `callback` receives the response body as a string, or `#f` on failure — including the failure of having no runner installed. Returns immediately. |
| `current-http-runner` | parameter | `(lambda (url callback) …)`, or `#f` for none. Set by `root.scm` to `http-get-native`; a test may `parameterize` a canned runner to assert on the URL that would have been fetched, or to answer with a canned body. |

### `(modaliser event-dispatch)`

| Export | Description |
|---|---|
| `modal-key-handler` | The catch-all keyboard handler dispatching captured keys into the modal engine. Installed into the modal façade at load; configs never call it. |

### `(modaliser dialogs)`

Slim async AppleScript dialog helpers (ADR-0014). A dialog-raising command
is an ordinary Terminal leaf (CONTEXT.md "Dialog command") — dispatch has
already released modal capture before the action runs (ADR-0015), so this
library does no capture handling; it only fires through
`current-dialog-runner` (never a synchronous `run-shell`) so a leader press
while the dialog is up never stalls the keyboard tap.

| Export | Signature | Description |
|---|---|---|
| `dialog-confirm` | `(dialog-confirm message k ['title str] ['ok-label str] ['icon str])` | Cancel/affirmative-button confirm dialog; `k` receives `#t` iff the affirmative button was chosen. `ok-label` defaults to `"OK"`. |
| `dialog-info` | `(dialog-info message [k])` | Single-button "OK" alert; `k`, if given, is a 0-arg procedure called once dismissed. |
| `current-dialog-runner` | parameter | The test seam: a `(lambda (shell-command callback) ...)` matching `run-shell-async`'s shape. Default: `(modaliser shell)`'s `run-shell-async` — the seam, so under `swift test` even the un-overridden path spawns nothing (ADR-0023). |
| `sq-escape` | `(sq-escape str)` | POSIX single-quote escaping (the `'\''` idiom) for safe interpolation inside a single-quoted shell word — the one canonical implementation shared by callers with their own shell-quoting needs. |

Used by `(modaliser apps iterm)`, `(modaliser apps kitty)`, and
`(modaliser apps alacritty)` for their host-provisioning confirm dialogs.

### `(modaliser jump-labels)`

General parameterised jump-label assignment — the pure
function behind the herdr jump space's lowercase labels
([docs/specs/herdr-jump-navigation.md](../specs/herdr-jump-navigation.md)).
Ordered targets in, prefix-free one- or two-key labels out; the library
knows nothing about axes — the caller's target order encodes axis/visual
priority.

| Export | Signature | Description |
|---|---|---|
| `jump-labels-assign` | `(jump-labels-assign targets single-alphabet leader-alphabet second-alphabet)` | Assigns each target (in order) a label drawn from `single-alphabet`, escalating into `leader-alphabet` × `second-alphabet` two-key combinations only as needed — the minimum leaders promoted, in the order given. Returns a list of `(label . target)` pairs, same length/order as `targets`; `label` is `#f` once both pools are exhausted (the unlabelled tail). |

Each alphabet is an ordered list of distinct one-char strings, honoured as a
priority order (never re-sorted). `single-alphabet` and `leader-alphabet`
may overlap (a restricted single alphabet doubling as the leader
preference order — e.g. home-row-only) or be disjoint (dedicated
leader-only keys that never cost a single slot); both are handled
correctly and deterministically.

### `(modaliser jump-list)`

The other half of a labelled listing: `jump-labels-assign` says *which
label*, this says *what a label does*. An assignment in, an **Edge
provider result** out — `'edges` and `'states`, ready for a provided
state's `'provider` slot.

It exists because that lowering is subtle in exactly the same way for
every caller, and **fails silently when it is wrong**: a prefix state
minted with the wrong id garbles a breadcrumb, one minted without its
own provider makes a second key resolve to a state nobody minted, and
one minted without a payload narrows into a blank screen. None of those
raise. Extracted from `(modaliser wms paneru)`'s strip provider when the
VSCode project panel needed the same shape over a different row source;
both compose it now.

| Export | Signature | Description |
|---|---|---|
| `jump-list-provider-result` | `(jump-list-provider-result assigned owner-id panel-label 'state-id FN 'action FN 'block FN)` | Lowers `assigned` — `jump-labels-assign`'s own `(label . target)` list — onto the FSM. One direct edge per single-key label; one edge per *used* leader, to a narrowing prefix state that re-mints its own group. Pure: it constructs entry thunks and fires none. |
| `jump-list-prefix-state-id` | `(jump-list-prefix-state-id owner-id leader)` | `OWNER-ID + "/" + leader`. The shape is **not** free — `modal-current-path` `substring`s the parent's id off the child's to derive a breadcrumb segment. |
| `jump-list-compose-providers` | `(jump-list-compose-providers NAME PROVIDER NAME PROVIDER …)` → one Edge provider | Puts several labelled panels on a state's single `'provider` slot. Calls each contributor with the owner id the engine handed over, appends their `'edges` and `'states` in argument order, and **raises** on a collision. Asks `fsm-state-edges` / `fsm-state-ids` itself — there is no argument that can replace either. |
| `jump-list-validate-composition` | `(jump-list-validate-composition RESULTS NAMES OWNER-EDGES REGISTERED-STATE-IDS)` → the merged result, or raises | The pure half, taking every fact as data. This is the seam: all four collision cases are tested here by direct call, with no graph installed. |

The three injected functions are the whole domain boundary:

| Option | Signature | Description |
|---|---|---|
| `'state-id` | `TARGET → STRING` | A Terminal dispatch state's id. Free-form, but must be collision-free across live targets — namespace it per caller. Only ever called on a target `'action` already answered for. |
| `'action` | `TARGET → THUNK or #f` | What pressing this target's label does. `#f` means "nothing to do", which is *also* how a caller says a row is inert. The two are one question, so they are one function: the target with no action **is** the target with no edge. |
| `'block` | `PAIRS → BLOCK-SPEC` | The narrowed listing's block, given one leader's `((second-key . target) …)` survivors. Its own `block-ref-id` — its explicit `'id` when it has one, its `'type` otherwise — is read back out to reference it from the panel, so a caller never restates what it just constructed. That is the same accessor the overlay's own panel→block resolution uses, which matters as soon as two panels share one block type and disambiguate with ids. |

Two kinds of target are dropped from the edge set and **from nothing
else** — both still render as rows: an *unlabelled* one (`#f`, past both
pools) and an *inert* one. Dropping either during assignment instead
would renumber every label below it on one transient miss, and the
labels are muscle memory. A leader whose every second key is dropped
contributes no group at all, so the leader key stays dead rather than
narrowing into an empty listing.

`'panel-label` rides in from the user (ADR-0021): a label authored in a
library file sits inside the decision-free contract's spirit even where
`check-decision-free.sh`'s grep cannot see it.

#### Composing several panels onto one `'provider` slot

A state has **one** `'provider`, and a screen wanting two labelled
panels on it has to merge two provider results. Appending them is
mechanically fine and silently wrong when it is not, because nothing in
the engine checks — verified in `fsm.sld` rather than assumed. A
provider's edges are folded in with the owner state's own by plain
append; a key resolves to the **first** matching live edge; provided
states go into a table keyed by id, last-wins. So two panels claiming
`j` is not an error anywhere: it is a terminal's label focusing a
project, silently.

`jump-list-compose-providers` raises instead. Raising rather than
dropping, because a dropped edge is a dead key with no diagnostic — the
key still works, bound to whichever panel contributed first.

**What it validates is wider than the provider results**, and that is
where the first design of this fell short. Two collision sources the
engine has that checking only the results leaves uncovered:

- **the owner state's own static edges** — a promoted leader landing on
  a screen key dispatches to the *static* edge. This is the **likelier**
  collision, because the screen's keys are already spoken for;
- **permanently registered states** — a provided state shadows a
  permanent one of the same id, first-lookup-wins.

**The public operation takes no switch that can weaken its own
invariant.** An earlier draft passed those two facts in as optional
arguments so a test could supply them — which meant a user's config,
being Scheme calling the same exported procedure, could hand in two
empty readers and turn the check off while still appearing to compose
safely. So the surface splits at the *purity* line instead: the
validator takes every fact as data and is where the four cases are
tested; the wrapper asks the graph the two questions and has nothing in
it worth a seam.

**Contributors are named, because an ordinal cannot repair a
configuration.** The merge receives opaque procedures, and nothing
recoverable from a closure says which panel owns the colliding key. The
names are the caller's — the panel's own, out of the user's config — so
the library still authors no label (ADR-0021).

**The disjointness a screen has to keep is wider than it looks, and
cannot be checked statically.** A panel's edges are one per surviving
single-key label *plus one per promoted leader*, so the pool two panels
must keep disjoint is `single-alphabet ∪ leader-alphabet`. Leader
promotion is data-dependent — it happens only once a panel outgrows its
single alphabet — so two panels can share a leader key, coexist happily
for months, and collide the first time one of them grows. That is why
the check belongs at the merge, at come-to-rest, rather than at config
load: at load there is no row count to check against.

A raise at come-to-rest releases the keyboard on both dispatch paths and
tears the modal down on both: the leader path never registers or shows
anything, and the catch-all path applies `modal-abort!` after releasing
the keys. The overlay no longer outlives the error
([state-machine.md, "When a keypress raises"](state-machine.md#when-a-keypress-raises)).
The visible signal is still only the modal closing — the error text goes
to `/usr/bin/log`.

---

### `(modaliser input)`

Keystroke synthesis — how a binding drives an app that exposes no
scriptable surface — plus media-key emission. Native (`InputLibrary.swift` /
`KeystrokeEmitter.swift` / `MediaKeyEmitter.swift`).

| Export | Signature | Description |
|---|---|---|
| `send-keystroke` | `(send-keystroke [mods] key)` | Press and release `key` as one complete chord. |
| `send-key-down` | `(send-key-down [mods] key)` | Press `key` and leave it down. |
| `send-key-up` | `(send-key-up [mods] key)` | Release `key`. |
| `send-media-key` | `(send-media-key button)` | Press and release a media button — play/pause, track skip, volume. |

The first three take **one or two** arguments: `(send-keystroke "tab")` for a bare
key, `(send-keystroke '(cmd shift) "p")` with a modifier list (`'cmd`/
`'command`, `'ctrl`/`'control`, `'shift`, `'alt`/`'option`). `key` is a
character (`"t"`, `"["`, `" "`) or a named key (`"tab"`, `"return"`,
`"escape"`, `"left"`, `"f5"`, … — including the modifiers themselves,
`"ctrl"`, `"shift"`, `"cmd"`, `"alt"`). An unknown key name raises.

**A chord brackets its modifiers.** `send-keystroke` posts each modifier as a
real key-down before the key and a real key-up after it, so the chord ends
fully released. This matters for any UI that commits on modifier *release* —
Dia's recent-tab switcher opens on `ctrl+tab` and switches when control comes
up. Asserting the modifier flag alone, with no discrete modifier event, leaves
such a UI waiting forever.

**A held modifier survives later calls.** `send-key-down` of a modifier records
it as held; every subsequent event ORs it in *without* bracketing it, until the
matching `send-key-up`. So a walk holds control once and its steps are plain
keys:

```scheme
(group "r" "Recent Tabs"
  'exit-on-unknown #t
  'on-enter (λ () (send-key-up   "ctrl")     ; clear any stale hold
                  (send-key-down "ctrl")     ; hold control
                  (send-keystroke "tab"))    ; seen as ctrl+tab
  'on-leave (λ (reason)                      ; 'confirm on Return, else 'cancel
              (unless (eq? reason 'confirm) (send-keystroke "escape"))
              (send-key-up "ctrl"))          ; release — commits if confirmed
  (key "l" "Next" (λ () (send-keystroke "tab")) 'next 'self))
```

`send-key-down` on a modifier asserts that modifier's own flag, so
`(send-key-down "ctrl")` needs no `'(ctrl)` argument. A hold that is never
released corrupts later keystrokes — and the leak is the real OS-level
key-down, not just Modaliser's mirror of it — so pair every hold with its
`send-key-up` on **every** exit path, as the `on-leave` above does. The leading
`send-key-up` self-heals a hold stranded by an earlier abort.
`(modaliser apps dia)` wraps this protocol as `tab-step` / `tab-step-back`.

Every posted keystroke is tagged as Modaliser's own re-injection, so the
keyboard capture tap passes it through rather than the modal catch-all
swallowing it on the way back — sending keystrokes from inside a modal action
works.

**`send-media-key` is not a keystroke.** It takes a single **symbol**, one of
`'play-pause`, `'next`, `'previous`, `'volume-up`, `'volume-down`, `'mute`;
anything else raises, naming the offender and listing the valid set. Media
buttons have no virtual keycode, so they travel as an `NSSystemDefined`
subtype-8 event rather than through the `CGEvent` virtual-key path the three
keystroke procedures use — which is why this is its own primitive and not a row
in the named-key table. Each call emits a down/up pair, as real hardware does.

```scheme
(key "p" "Play/Pause" (λ () (send-media-key 'play-pause)))
```

**It reaches the Now Playing target, not the focused window.** macOS routes the
event to whichever client currently holds the system's Now Playing role —
Music, Podcasts, a browser tab playing video — which is generally *not* the
frontmost app. That is the point: one binding controls whatever is actually
playing, instead of scripting one named player. The trade is that the target is
implicit and **not queryable** (the supported API surface offers no way to ask
who it is), so no binding can display it, branch on it, or fall back when
nothing is playing — the key reaches whichever client held the role last. See
`CONTEXT.md`, **Media key** and **Now Playing target**.

The seeded `default-config.scm` binds only `'play-pause`. The other five ship
unbound because which keys carry them is your decision, not the library's
(ADR-0021) — add them to a screen, or gather them into a Walk with `'next
'self`, as you like.

---

### `(modaliser cursor)`

A momentary highlight drawn at the mouse pointer, for finding a lost cursor on
a large display. Native (`CursorLibrary.swift`): a click-through borderless
panel paints a glowing ring that converges on the pointer and fades out. Firing
it again mid-animation restarts cleanly at the new location.

| Export | Signature | Description |
|---|---|---|
| `highlight-cursor` | `(highlight-cursor ['color hex] ['size px] ['thickness px] ['glow px] ['duration secs] ['nudge bool])` | Flash a converging ring at the pointer. Every keyword is optional. |

```scheme
(key " " "Highlight Cursor" (λ () (highlight-cursor)))
(key " " "Highlight Cursor"
     (λ () (highlight-cursor 'color "#FF0000" 'duration 1 'thickness 16)))
```

| Keyword | Default | Meaning |
|---|---|---|
| `'color` | `"#FFCC33"` | Ring stroke and glow colour; `"#RGB"` or `"#RRGGBB"`. |
| `'size` | `240` | Starting ring diameter in px (it converges inward). |
| `'thickness` | `6` | Ring stroke width in px. |
| `'glow` | `18` | Glow blur radius around the ring, in px. |
| `'duration` | `0.45` | Animation length in seconds. |
| `'nudge` | `#t` | Jog the pointer ±1px first, revealing a cursor hidden by idle timeout. |

An unparseable colour, a non-numeric number, or an unknown keyword leaves the
default in place and logs a warning — `highlight-cursor` never raises. The
nudge nets zero displacement, so a precisely-placed pointer is preserved; it
cannot reveal a cursor another process has deliberately hidden (fullscreen
video, games that capture the pointer), though the ring still marks the spot.

---

## Native primitives

These libraries are Swift-backed: their exact signatures live in the
host implementation, not in a portable `.sld`. Names are stable
contracts (a port to a different host would re-implement them under
the same names).

| Library | What it provides |
|---|---|
| `(modaliser app)` | Process / app management: `launch-app`, `activate-app`, `find-installed-apps`, `app-display-name`, `reveal-in-finder`, `open-with`, etc. |
| `(modaliser keyboard)` | Keycode constants (`F18`, `F17`, …), modifier symbols. |
| `(modaliser input)` | Keystroke synthesis: `send-keystroke`, `send-key-down`, `send-key-up`; media buttons: `send-media-key` — documented above under [`(modaliser input)`](#modaliser-input). |
| `(modaliser shell-native)` | The raw `/bin/zsh -c` spawn: `run-shell-native`, `run-shell-async-native` (non-blocking; ADR-0014). **Not the library to import** — the tree shells out through the portable [`(modaliser shell)`](#modaliser-shell) seam documented above, and `scripts/check-portable-surface.sh` fails the build on a `lib/modaliser` import of this one (ADR-0023). |
| `(modaliser log)` | Diagnostic logging: `log-line`, an os.Logger line readable via `log show` (ADR-0017). |
| `(modaliser pasteboard)` | Clipboard: `set-clipboard!`, `read-clipboard`. |
| `(modaliser http-native)` | The raw `URLSession` fetch: `http-get-native`. **Not the library to import** — the tree fetches through the portable [`(modaliser http)`](#modaliser-http) seam documented above, and `scripts/check-portable-surface.sh` fails the build on a `lib/modaliser` import of this one (ADR-0023). |
| `(modaliser unix-socket)` | Line-framed AF_UNIX I/O, in two forms. `(unix-socket-request path line timeout-ms)` → response line \| `#f` does a full round-trip; `(unix-socket-send path line timeout-ms)` → `#t` \| `#f` connects, sends, and closes **without reading a reply**, for peers whose answer cannot arrive promptly (or at all) and would otherwise block the caller for the full timeout. Both own the newline framing in both directions (append on send, strip on receive); `timeout-ms` bounds the whole call as wall-clock. Both return `#f` on any I/O failure and log the reason via `(modaliser log)`'s subsystem — neither raises. Generic by design: the herdr socket transport's JSON-RPC envelope is Scheme (ADR-0020). |
| `(modaliser lifecycle)` | `relaunch!`, `after-delay`. |
| `(modaliser accessibility)` | AX tree introspection used by ax-hints. |
| `(modaliser hints)` | On-screen hint chips, keyed by group: `hints-show`, `hints-show-in`, `hints-hide`, `hints-hide-in`. |
| `(modaliser fuzzy)` | Fuzzy matching engine used by the chooser. |
| `(modaliser cursor)` | Mouse-pointer highlight: `highlight-cursor` — documented above under [`(modaliser cursor)`](#modaliser-cursor). |
| `(modaliser webview)` | WebView management for the overlay/chooser panels. |
| `(modaliser dom)` | DOM push-update helpers used by `ui/overlay.scm`. |
| `(modaliser library-path)` | `prepend-library-path!`. |

Canonical reference: the Swift sources under `Sources/Modaliser/`.

See also: [portability.md](portability.md) for which libraries are
pure-Scheme (portable) vs. native (host-specific).
