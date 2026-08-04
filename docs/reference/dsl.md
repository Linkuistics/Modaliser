# DSL reference

Every form exported from `(modaliser dsl)` and `(modaliser display-dsl)`,
plus the configuration
constructors from `(modaliser configuration)` and the one-shot handoff
from `(modaliser handoff)` that a config composes them with. Signatures
are ground-truthed against
[`dsl.sld`](../../Sources/Modaliser/Scheme/lib/modaliser/dsl.sld),
[`display-dsl.sld`](../../Sources/Modaliser/Scheme/lib/modaliser/display-dsl.sld),
[`configuration.sld`](../../Sources/Modaliser/Scheme/lib/modaliser/configuration.sld),
and [`handoff.sld`](../../Sources/Modaliser/Scheme/lib/modaliser/handoff.sld).

## A node is dispatch structure plus a display value

Modaliser's overlay is a **dynamic cheat-sheet document** — a grid of
panels you read like a reference card — and your config is what draws it.
But drawing and dispatching are separate concerns, and the model keeps
them that way.

Every node in a Modaliser tree factors into two **disjoint** layers held
on the node
([ADR-0011](../adr/0011-dispatch-structure-with-attached-display.md)):

- **dispatch structure** — kind, key, label, action, gates, `'next`,
  providers, splices, and a **flat** `'children` list. This is what the
  state machine reads.
- a **Display value** — one `'display` entry, built by the display DSL,
  saying how the node *renders*: panels referencing the node's own rows
  **by key**, live-list block placement **by reference**, spans, row
  order, cols/layout, embeds, the breadcrumb name.

Dispatch reads never consult `'display`, so substituting a display value
*structurally cannot* change which keys are live. Presentation is one
value you can print, diff and replace — not metadata smeared through the
operational tree, and nothing panel-shaped sits among a node's children.

Two surfaces build that same representation:

| Surface | What you write | When to reach for it |
|---|---|---|
| **Bare** — canonical | the [dispatch atoms](#dispatch-atoms) compose plain data; [`with-display`](#the-bare-authoring-surface) attaches the display value as a separate explicit step | when you want the layers separable — a generated tree, tooling, a display swapped without touching keys |
| **Sugar** — ergonomic | [`screen` / `panel` / `open`](#layout-forms) author both layers at once, reading like the cheat sheet they draw | ordinary hand-written config; what `default-config.scm` uses throughout |

The sugar is a **veneer**: it compiles onto the bare surface at
construction time, and a sugar≡bare equivalence test pins the two
spellings to identical node output
([ADR-0012](../adr/0012-layout-dsl-surface-screen-panel-open-over-unchanged-atoms.md)).
A node with **no** display value renders as plain loose rows in
declaration order, so the dispatch atoms stand on their own.

**Then it lowers once more.** The node tree — however authored — is an
**intermediate representation (IR)**, the `(kind . group)` /
`(kind . command)` alist: the **handoff** (`(modaliser:start! …)`,
below) lowers it into the explicit **FSM graph** of states and labelled
edges that dispatch actually runs on (see
[state-machine.md](state-machine.md)). The dispatch behaviour this page
describes (Walks, the `'next` edge, transparent grouping, digit-jump,
selectors) is unchanged by that lowering. The overlay, meanwhile,
resolves the display value against the node's children through one pure
function (`resolve-display`) and serializes the resulting render plan —
it derives the panel-grid render path from the display value's *shape*,
with no authored renderer marker anywhere
([renderer-protocol.md](renderer-protocol.md)).

## Imports

A config pulls in three libraries for its skeleton, plus whatever
factories it composes:

```scheme
(import (modaliser dsl)            ; screen / panel / open / key / …
        (modaliser configuration)  ; configuration, leaders, overlay-delay
        (modaliser handoff))       ; modaliser:start!
```

`(modaliser dsl)` surfaces the layout forms `screen`, `panel`, `open`,
`splice`; the dispatch atoms `key`, `keys`, `key-range`, `group`,
`selector`, `action`, `walk`, `step-in`; the pure root builder
`tree-root`; and the helper `λ`. `(modaliser configuration)` surfaces
the settings constructors and the `configuration` merge;
`(modaliser handoff)` the single effectful call. The bundled seed
config also pulls in factory libraries prefix-style
(`(prefix (modaliser apps iterm) iterm:)`, `(prefix (modaliser muxes
herdr) herdr:)`, …) and a handful of native libraries
(`(modaliser app)`, `(modaliser keyboard)`, etc.).

The bare display surface is imported **prefixed**, because `panel`
deliberately exists on both surfaces (a config authors through one of
them at a time):

```scheme
(import (modaliser dsl)
        (prefix (modaliser display-dsl) d:))   ; d:with-display, d:panel, …
```

---

## Composing the configuration value

A config file is pure almost to its last form: everything builds
data — **fragments** — and exactly one call installs the assembled
value ([ADR-0018](../adr/0018-configuration-as-one-explicit-value.md),
[configuration-value spec](../specs/configuration-value.md)):

```scheme
(modaliser:start!
  (configuration
    (leaders
      (leader 'global F18)
      (leader 'local  F17))
    (overlay-delay 0.3)
    global-screen           ; a (screen 'global …) tree fragment
    (iterm:wiring)          ; a wiring fragment: backend + digit-jump tree
    (terminal-contexts      ; exe → tree map for terminal-like screens
      (herdr:wiring)
      (nvim:wiring))
    iterm-screen            ; every screen is yours to author (ADR-0021)
    herdr-screen
    nvim-screen))
```

### `(configuration fragment…)`

The **pure merge**. Flattens arbitrarily nested fragments into one
configuration value: trees (keyed by scope), backends (by symbol),
context-map entries (by exe name), settings (by name). Walk-carried
mode trees are hoisted into the tree set on the way. Two contributions
with the same key merge silently **iff they are the identical value**
(the diamond case — one fragment reached via two composition paths) and
**error otherwise**: there is no override and no last-wins.
Customization is composition, not patching — and there is no stock
tree to patch. No library authors a screen
([ADR-0021](../adr/0021-decision-free-libraries.md)); libraries export
wiring, ops, and blocks, and every screen in your configuration is one
you composed from them. "A different tree for that scope" is not a
special path, it is the only path — edit the screen already in your
`config.scm`.

The result is inspectable data: print it, test it, take it apart with
the `configuration-*` accessors ([libraries.md](libraries.md)) —
nothing has happened to the engine yet.

### `(leader mode keycode [keyword value]...)` and `(leaders spec…)`

`leader` builds one leader spec — pure data. `mode` is `'global` or
`'local`. `'global` opens the global tree. `'local` opens the focused
app's per-app screen, falling back to the global tree if that app has
none; on a terminal-like screen it consults the Terminal context map
(see [Nested contexts](#nested-contexts-the-terminal-context-map)).
Keywords:

| Keyword | Type | Description |
|---|---|---|
| `'modifiers` | symbol list | Required modifiers, e.g. `'(shift ctrl)`. |
| `'arm-when-frontmost` | string list | Bundle IDs that suppress leader arming while frontmost — useful for remote-desktop viewers whose modifiers should pass through. |

`leaders` wraps the specs into the single `'leaders` setting
contribution — one `(leaders …)` call per configuration (a second one
is a merge conflict). The leaders are armed by the handoff, from the
installed value.

```scheme
(leaders
  (leader 'global F18)
  (leader 'local  F17 'modifiers '(shift)))
```

### `(overlay-delay seconds)`

The `'overlay-delay` setting: how long after leader arm before the
overlay appears. Zero shows immediately. Typical values 0.3–1.0. Quick
muscle-memory keypresses produce no UI when the delay is non-zero — the
modal still dispatches the key.

### `(modaliser:start! config)`

The **Handoff** — the one effectful moment. Validates the value, runs
the pure lower to the FSM graph (every authored reference must resolve
— load-time errors, see [state-machine.md](state-machine.md)), installs
graph + screen set + context map + backends + settings into the engine,
and arms the leaders. One-shot: a second call is an error — reload is
relaunch. A config that fails before the handoff leaves the engine
cleanly empty: nothing was ever installed.

### Theming

All visual customisation — colours, fonts, spacing, host-theme
variables (`--color-host-bg`, `--color-host-fg`, …), chip styling —
lives in `~/.config/modaliser/theme.css`. Modaliser auto-loads that
file at startup. No Scheme surface for CSS is involved.

See [theming.md](theming.md) for the full variable inventory and
worked examples.

---

## Layout forms

The authoring sugar. Four forms — `screen`, `panel`, `open`, `splice` —
that build **both layers at once** at config-load, compiling onto the
[bare surface](#the-bare-authoring-surface): the dispatch atoms they
contain become the node's flat children, and the layout they describe
becomes its display value. (`splice` is the exception — it is pure
dispatch reuse and touches no display.)

### `(screen scope [keyword value]... . panels)`

Builds the command tree for `scope` and renders it as a **grid of
panels** — the top-level layout form. Pure: it returns a **tree
fragment** for the `configuration` merge (nothing installs until the
handoff). `scope`
is a symbol (or string) like `'global`, `'com.apple.Safari`, or
`'iterm-panes-focus`; symbols and strings are equivalent.

The body is an **implicit grid**: each `(panel …)` is a grid cell of
masonry-packed cards. Everything **not** wrapped in a `(panel …)` is the
**loose region** — it renders **bare** (header-less, no card) at the **top
of the screen body, above the grid**, like a plain `(group …)` or the
Settings overlay. The loose region holds, in declaration order:

- **loose atoms** — a `(key …)` / `(keys …)` / plain `(group …)` not in a
  panel → a bare row;
- **folded top-level opens** — a top-level `(open …)` → a single **"→ Label"
  drill row** (still navigable: its key drills into its sub-screen);
- **loose blocks** — a `(window:layout-block …)` diagram or a
  `(window:list-block …)` live-list placed directly in the body → rendered
  **bare** on the body tint (no card).

(An `(open …)` declared *inside* a panel is untouched — it renders as an
accent group-row in that panel. There is **no** "General" panel; loose
atoms are the screen's own inline rows.)

```scheme
(screen 'global
  (group "," "Settings"                      ; loose drill row — renders bare
    (key "r" "Reload" relaunch!))
  (key "a" "Apps" (launcher:find-application))  ; loose row: a factory node
  (key "/" "Help" (λ () (open-help)))           ; loose row: a thunk

  (open "w" "Windows"           ; folds into the loose region as "w → Windows";
    (window:layout-block …)     ; its FLAT body: a bare diagram,
    (key "s" "Select" …)        ; loose rows,
    (window:list-block 'chips? #t))  ; and a bare live list

  (panel "Applications"         ; a real panel → a masonry card below the loose rows
    (key "b" "Browser"  (λ () (launch-app "Safari")))
    (key "t" "Terminal" (λ () (launch-app "iTerm")))))
```

Optional leading keywords:

| Keyword | Type | Description |
|---|---|---|
| `'cols` | integer | Authored column count. Default is aspect-ratio **column balancing**: a JS measurement pass picks the count whose grid shape best fits a target width:height ratio (CSS auto-fit is only the no-JS fallback). Pins an explicit track count instead. |
| `'layout` | `'masonry` \| `'grid` | Panel packing. Default `'masonry`: each panel drops into the shortest lane, so a short panel tucks up under a shorter neighbour. `'grid` opts into a deterministic aligned grid where panels in a row share a track height. |
| `'order` | `'keys` \| `'declared` | Grid-wide row-ordering default. `'keys` (the ultimate default) key-sorts each panel's rows alphabetically; `'declared` renders them in declaration order. A panel inherits this unless it sets its own `'order`. |
| `'embed` | string list | The display layer's per-edge **embed** choice (ADR-0011): each listed key's edge target — which must lower to a group child, validated at load time — renders as an in-place **section** of this screen's display root instead of a drill row. Firing the key still genuinely navigates (a real Visit); presentation activates the section in place — it highlights, the rest of the root dims, backspace reverts. Pure display data — dispatch never reads it. See [renderer-protocol.md](renderer-protocol.md#embedded-sections-and-the-restyle-protocol). |
| `'on-enter` | thunk | Runs when the modal navigates into this screen. Any embedded live-list hooks fire alongside it, structurally (see below). |
| `'on-leave` | thunk or 1-arg procedure | Runs when the modal navigates out. If it declares an argument it receives the **exit reason** — `'navigate` \| `'confirm` \| `'cancel` \| `'exit` — see [state-machine.md](state-machine.md#the-exit-reason). |
| `'exit-on-unknown` | boolean | If `#t`, unrecognised keys exit the modal instead of being swallowed. Inherited by descendants. |
| `'display-name` | string | Overrides the breadcrumb scope segment. Useful for mode-id scopes (e.g. `'iterm-panes`) where the auto-resolved app name doesn't make sense. |
| `'provider` | procedure | An FSM edge provider on the tree root's own state — see `group`'s `'provider` above and [state-machine.md](state-machine.md#edge-providers-provider). |
| `'entry` | thunk or 1-arg procedure | The unconditional action-slot pair on the tree root's own state — see `group`'s `'entry`/`'exit` above and [state-machine.md](state-machine.md#unconditional-hooks-entry--exit). An argument, if declared, receives the arriving key. |
| `'exit` | thunk or 1-arg procedure | Pairs with `'entry` above; an argument, if declared, receives the exit reason. |

A `screen` lowers to a **tree-root group** whose children are the flat
dispatch atoms of its whole body — panels contribute their rows in place —
plus one `'display` entry holding the panel clauses, the loose region, and
whichever of `'cols` / `'layout` / `'order` / `'embed` / `'display-name`
were authored. The overlay selects the panel-grid render path from that
display value's shape; there is no renderer marker. The live-list
`'on-enter-fn` / `'on-leave-fn` of any block in the body fire alongside the
user hooks supplied to the `screen` — **structurally**, from the node's own
children, so a bare `tree-root` holding the same block behaves identically
(see [Block hooks](renderer-protocol.md#block-hooks)).

### `(panel label [span value] [order value] . children)`

A **transparent visual card** in a screen's grid — one declared
grouping of rows, with a banded header carrying `label`. Transparent
means it **never changes the keys beneath it**: a child `(key "b" …)`
dispatches at `b` whether or not a panel encloses it. (A panel is not a
node at all: at construction its rows join the enclosing screen/open's
flat dispatch children, and the panel survives only as a clause of that
node's display value, listing those rows by key. The state machine never
sees it.)

Pass `label` as `#f` for a **headerless panel** — the card renders with no
header band at all. Idiomatic for a panel whose body reads on its own (e.g. a
layout-diagram card: the diagram is its own legend, so it needs no "Layout"
eyebrow). The header is *config-controlled* — the renderer never drops it on
its own.

`children` are dispatch atoms (`key`/`keys`/`group`/`selector`/…) plus
**at most one** embedded live-list block. Splices (`splice` /
`walk`) hoist in place.

```scheme
(panel "Search"
  (key "g" "Google"           (web-search:google))
  (key "a" "Find Application" (launcher:find-application))
  (key "f" "Find File"        (launcher:find-file)))
```

Optional leading `'span` keyword:

| Span | Width | Notes |
|---|---|---|
| `'narrow` | 1 column | Default. |
| `'wide` | 2 columns | In a 1-track grid it still occupies the one track. |
| `'full` | all columns | Spans the whole row regardless of track count. |

```scheme
(panel "Panes" 'span 'wide
  (key "z" "Zoom" (λ () (toggle-zoom)))
  (iterm:pane-list-block 'chips? #t))   ; embedded live list
```

**Row ordering.** By default a panel **key-sorts** its rows alphabetically
(case-insensitive, lowercase first). The optional `'order` keyword overrides
that:

| Order | Effect |
|---|---|
| `'keys` | Sort rows by binding key. The historic behaviour; also the ultimate default. |
| `'declared` | Render rows in **declaration order** — exactly as authored. |

```scheme
(panel "Layouts" 'order 'declared       ; reads top-to-bottom as written
  (key "f" "Fullscreen" (λ () (fullscreen)))
  (key "l" "Left half"  (λ () (move-window 'left)))
  (key "r" "Right half" (λ () (move-window 'right))))
```

Resolution is **panel-explicit `'order` > the enclosing `screen`/`open` `'order`
default > `'keys`**, so a screen can set a grid-wide default that individual
panels override. Ordering is **presentation only** — dispatch is
key-addressed and unaffected. (The loose region above the grid already renders
in declaration order regardless.) `'span` and `'order` may appear in either
order before the children.

**Embedding a live list.** A panel may hold one dynamic-list block
(`window:list-block`, `iterm:pane-list-block`, `iterm:tab-list-block`)
among its children. The panel **auto-promotes to `'wide`** when it holds
a list (unless you give an explicit `'span`), since lists want
horizontal room. The block itself is a **dispatch atom**: it stays among
the enclosing node's flat children, where its hidden digit key-range
(the `1..` direct-jump selectors) expands at dispatch read time, and the
panel clause *references* it by id — the block's explicit `'id` entry
if it has one, else its `'type`. The embedded list also gains a
**selection cursor** (`↑↓` / `k j` to move, `⏎` to activate) — see
[Live lists & the selection cursor](#live-lists--the-selection-cursor).

It is an error to embed two list blocks in one panel, or to give two
blocks in one display the same reference id (add an explicit `'id` to
one of them).

### `(open KEY LABEL [keyword value]... . panels)`

A **navigable drill-down** into a sub-screen. Pressing `KEY`
descends into a fresh screen body. `open` is the
*only* navigable layout form; a `panel`, by contrast, is transparent and
never changes key paths. A **top-level** `(open …)` in a screen/open body
folds into the parent's loose region as a single **"→ LABEL" drill row**
(it is not its own card); pressing its key still drills in.

```scheme
(open "w" "Windows"
  (window:layout-block …)        ; a bare loose diagram
  (key "h" "Left"  (λ () (move-window 'left)))   ; loose rows
  (key "l" "Right" (λ () (move-window 'right)))
  (panel "Presets"               ; a real panel → a card below the loose rows
    (key "m" "Maximise" (λ () (maximise-window)))))
```

Its body lowers the same way a `screen` body does: real panels become
grid cards, and loose atoms / folded top-level opens / loose blocks render
bare in the loose region. Keywords: `'on-enter`, `'on-leave` (which may
declare an argument to receive the **exit reason** — see `group` below),
`'exit-on-unknown`, `'cols`, `'layout`, `'order` (the grid-wide row-ordering
default for this open's panels — see `panel`), `'embed` (the per-edge
in-place-section choice — see `screen`'s `'embed` above), `'entry`, `'exit`
(the unconditional action-slot pair, riding straight through to `group` — see
`group`'s `'entry`/`'exit` above), `'provider` (an FSM edge provider, riding
through to `group`'s own slot — a sub-drill whose content is per-Visit
dynamic declares it here; see `group`'s `'provider` below) — **not**
`'display-name` (a breadcrumb-root override a child group has no use for).
An `open` lowers to a navigable `group` whose children are its flat
sub-grid and whose `'display` entry carries that sub-grid's panel
clauses — the same two-layer shape a `screen` root gets.

A nested `(open …)` declared *inside* a `(panel …)` renders as an accent
drill-in `›` row in that panel; a top-level `(open …)` directly under a
`screen` renders as its own single-row cell.

### `(splice child…)`

A reusable, **named chunk of layout** — bind it once to a Scheme
variable and splice it into any number of screens or panels for DRY.
`child`s are panels (for screen-level reuse) or command rows (for
panel-level reuse). (Formerly `fragment`; renamed when "Fragment"
became the configuration-value term — a tagged contribution bag, not a
layout chunk.)

```scheme
(define window-ops
  (splice
    (key "c" "Center"   center-window)
    (key "m" "Maximise" maximise-window)))

(screen 'global (panel "Windows" window-ops (key "r" "Restore" …)))
(screen 'finder (panel "Layout"  window-ops))
```

A `splice` is **transparent for dispatch**: the splice node survives
construction as data, and expansion happens downstream (the dispatch
walk and the renderer both expand it in place), so the lowered tree is
identical to writing the children inline. Nested splices and `walk`s
compose for free, since the expansion recurses through splice
children.

`splice` is `walk`'s second half on its own: a transparent
splice node with **no** carried mode tree and **no** `'next`
decoration — pure structural reuse. Reach for `walk` when you want
the act-and-latch behaviour, `splice` when you only want to share
layout.

### Live lists & the selection cursor

Every dynamic list — a panel-embedded pane/window list **and** the
standalone [chooser](../how-to/fuzzy-finder.md) — supports a **selection
cursor** alongside its immediate digit selectors:

- `↑`/`↓` (and `k`/`j`) move the cursor; `⏎` activates the highlighted
  row. Movement is clamped (no wrap).
- The numeric selectors `1`–`9`/`0` stay **immediate** — a direct jump
  by the row's digit, race-free (it dispatches by the live target's
  identity, no event injection). `⏎` activates *through the same digit
  path*: the cursor adds a pointer, not a separate action.
- The footer advertises the keys (`↑↓ move · ⏎ select · 1–9 jump`) while
  a cursor is active.
- When a list knows which of its rows is currently focused — the iTerm
  Tab list (the current tab) and Panes list (the focused split) — the
  cursor **opens on that row** instead of the top, so `⏎` re-selects it
  or an arrow steps to a neighbour. (The global windows list does not yet
  seed this way.)

When a screen renders more than one live list, the **first** one it
draws owns the cursor (multi-list `Tab`-cycling is a non-goal). Cursor
state lives in `(modaliser list-cursor)`; the focused row is marked
`.is-focused` (accent bar + tint) — see [theming.md](theming.md).

---

## Dispatch atoms

The behavioural surface — unchanged by the layout inversion, because
these forms *are* the operational IR. A `panel`/`screen` is built
*around* them; they decide what a key does.

### `(key K L body [keyword value]...)`

The core binding form. `K` is the key string (single character like
`"a"` or a named key like `"F1"`); `L` is the label shown in the
overlay; `body` is what the binding does.

**Dispatch.** `key` is a `syntax-rules` macro that pattern-matches on
the *shape* of `body`:

| Body shape | Behaviour |
|---|---|
| `(lambda formals body…)` | Treated as the action thunk. Bound to `K`/`L` as a command. |
| `(λ formals body…)` | Same — `λ` is the Unicode alias for `lambda`. |
| `(fn arg …)` | Evaluated at config-load. If the result is a procedure, it's the action thunk; if it's a node alist (a pair), the node is decorated with `K`/`L`. |
| bare identifier | Evaluated at config-load; same procedure-vs-pair dispatch. |

The application-form branch is the trap: bare side-effecting calls fire
at config-load instead of at key press. The fix is to wrap in `(λ () …)`
explicitly.

```scheme
;; Correct — thunk fires on key press
(key "b" "Browser" (λ () (launch-app "Safari")))

;; Correct — selector factory returns a node, decorated with key/label
(key "g" "Google" (web-search:google))

;; WRONG — launch-app fires once at config-load and never again
(key "b" "Browser" (launch-app "Safari"))
```

Optional trailing keywords:

| Keyword | Type | Description |
|---|---|---|
| `'next` | symbol \| `'self` \| procedure | Declares this leaf's post-action transition (ADR-0015) — lowers to the leaf's one **auto edge** in the FSM graph. The scope id of a tree in the configuration is a **cross edge** (push the caller, switch into the target); the literal `'self` is a **cyclic edge** (re-arm the containing collection in place, no push); a 0-arg procedure is a **dynamic edge**, resolved at fire time to a symbol or `#f`. Declaring `'next` makes the leaf non-Terminal — capture stays live through the action instead of being released before it — and the overlay paints a `↻` marker on the cell. Omitting `'next` makes the leaf **Terminal**: capture releases *before* the action runs, so the action can safely hand the keyboard elsewhere (a dialog, an external prompt). See [state-machine.md](state-machine.md#the-next-edge-and-terminal-nodes). |
| `'hidden` | `#t` \| procedure | **Presentation only**: keeps the row out of the overlay while the value holds. `#t` hides it always; a 0-arg predicate is resolved at *render* time, so the row can come and go without a relaunch. Dispatch is untouched — a hidden key still fires when pressed. This is how a configuration authors a one-shot setup row that retires itself once its library-side gate reports done. |

```scheme
(key "p" "Pane Mode" (λ () (if #f #f)) 'next 'iterm-panes-focus)

;; Shows only while iTerm lacks the provisioned bindings; disappears on
;; the next overlay open once `configure!` has written them.
(key "C-I" "Configure iTerm" iterm:configure! 'hidden iterm:configured?)
```

### `(keys KEYLIST LABEL ACTION-FN [keyword value]...)`

Multi-key binding — one labelled row in the overlay, multiple
dispatch keys. `ACTION-FN` is called as `(action-fn matched-key index
keylist)` so the action can branch on slot without closing over the
list.

`KEYLIST` accepts literal lists plus two shorthands:

| Form | Meaning |
|---|---|
| `'("a" "b" "c")` | Literal list. |
| `'("a" .. "z")` | Inclusive single-char code-point range. |
| `'("1" ..)` | Open-end digit range — expands to `("1" "2" … "9")`. |

The display key in the overlay is derived:

| Keylist shape | Display key |
|---|---|
| Contiguous single chars | `"<first>..<last>"` (e.g. `"a..c"`) |
| Digit range ending at `"9"` | `"<first>.."` (e.g. `"1.."`) |
| Anything else | `"/"`-joined keys (e.g. `"a/c/e"`) |

Optional keyword:

| Keyword | Type | Description |
|---|---|---|
| `'display-key` | string | Override the computed display key. |

```scheme
(keys '("1" ..) "Switch Space"
      (λ (k i ks) (send-keystroke '(ctrl) k)))

(keys '("a" .. "p") "Focus Pane"
      (λ (k i ks) (iterm-focus-pane! i)))
```

A literal `(key K L …)` sibling always wins over a `keys` slot that
includes `K` — letting one binding carve a slot out of a range.

### `(key-range DISPLAY LABEL KEYS ACTION-FN)`

Lower-level form behind `keys`. `DISPLAY` is the literal overlay
string (purely cosmetic — dispatch uses `KEYS`); `KEYS` is a
non-empty list of single-char strings; `ACTION-FN` is `(lambda (k) …)`
— gets only the matched key, no index.

Reach for `key-range` when you want a custom display string and don't
need the index argument. Otherwise prefer `keys`.

### `(group K L [keyword value]... . children)`

A plain nested submenu — typing `K` from the parent descends into a tree
of `children`. Unlike `open`, a `group` renders through the **default
list renderer** (a single multi-column list, not a grid of panels), so
reach for it for a quick flat drill-down where a full sub-screen would be
overkill — directional split/move clusters, Walks. Keywords:

| Keyword | Type | Description |
|---|---|---|
| `'on-enter` | thunk | Fires when modal navigates *into* this group (only if the overlay is open). |
| `'on-leave` | thunk or 1-arg procedure | Fires when modal navigates *out*. If it declares an argument it receives the **exit reason** — `'navigate` (moved elsewhere) \| `'confirm` (Return) \| `'cancel` (Escape, leader, unknown key under `'exit-on-unknown`) \| `'exit` (any other end). See [state-machine.md](state-machine.md#the-exit-reason). |
| `'exit-on-unknown` | boolean | Unknown keys exit the modal. Inherited by descendants. |
| `'provider` | procedure | An FSM edge provider — a **1-arg** procedure run each time the group comes to rest, returning extra edges/states valid for that Visit only (see [state-machine.md](state-machine.md#edge-providers-provider)). Its argument is **the id of the state it was lowered onto** (`"scope/k"` here), which a provider minting a narrowing prefix state needs for that state's own id and `'up` target. Unlike `'on-enter`/`'on-leave`, not presentation-gated. |
| `'entry` | thunk or 1-arg procedure | Fires unconditionally at Visit come-to-rest, regardless of whether the overlay ever displays — unlike `'on-enter`, which is presentation-gated (see [state-machine.md](state-machine.md#unconditional-hooks-entry--exit)). An argument, if declared, receives the **arriving key** (a dispatch key string, or `#f` when no keypress led here). |
| `'exit` | thunk or 1-arg procedure | Fires unconditionally at Visit end (navigate-away or modal-exit) — the `'exit` counterpart to `'entry`, mirroring `'on-leave`'s pairing with `'on-enter`. An argument, if declared, receives the same **exit reason** `'on-leave` gets, on every visit end rather than only the displayed ones. |

A group carries no latching flag of its own — a command leaf at or
below it cycles only if it individually declares `'next 'self` (see
`key` below); a group is a **Walk** when it has one or more such
members, but that's derived from the leaves, never declared on the
group itself.

Unknown keyword/value pairs pass through as opaque alist entries on the
group — an escape hatch for a library that needs to carry its own datum
on a node. Presentation is *not* one of those: it rides the single
`'display` entry, attached by
[`with-display`](#the-bare-authoring-surface) (or by the sugar).

```scheme
(group "f" "Files"
  (key "n" "New"    (λ () (run-shell "touch ~/Desktop/untitled.txt")))
  (key "o" "Open"   (launcher:find-file))
  (key "h" "Home"   (λ () (reveal-in-finder "~"))))
```

`(group …)` returns a node alist; in a `screen` body it renders as a
drill-in row. Use `open` instead when you want the destination to be its
own grid of panels.

### `(selector [keyword value]...)`

A fuzzy-finder chooser. Returns an **undecorated** node — wrap with
`(key K L (selector …))` to bind it. Keywords:

| Keyword | Type | Description |
|---|---|---|
| `'prompt` | string | Prompt shown in the chooser input field. |
| `'source` | procedure | Item source. Called once when the chooser opens. Return a list of items (strings or alists). For a static list, wrap with `(lambda () my-list)`. |
| `'on-select` | procedure | `(lambda (item) …)` — fires when the user picks an item with Return. |
| `'dynamic-search` | procedure | `(lambda (query) …)` — replaces fuzzy filtering with a per-query call (e.g. for HTTP search). |
| `'file-roots` | string list | Restricts file-source matches to these roots. |
| `'actions` | action list | Extra actions exposed via the Tab-toggled action panel. See `(action …)` below. |
| `'remember` | boolean | If `#t`, the chooser remembers the last selection across opens. |
| `'id-field` | symbol | When items are alists, the field used to identify items for `'remember` and selection state. |

```scheme
(key "s" "Select Window"
     (selector 'prompt "Select window by name…"
               'source list-windows
               'on-select focus-window))
```

### `(action NAME [keyword value]...)`

Extra action for a selector's Tab panel. Used in a selector's
`'actions` list. Keywords:

| Keyword | Type | Description |
|---|---|---|
| `'description` | string | Label shown next to the key shortcut. |
| `'key` | `'primary`, `'secondary`, or string | The key that fires this action in the chooser. `'primary` = Return; `'secondary` = Cmd-Return; a literal key string binds a custom shortcut. |
| `'run` | procedure | `(lambda (item) …)` — receives the currently selected chooser item. |

```scheme
(selector 'prompt "Pick file…"
          'source list-files
          'actions (list
            (action "reveal"
              'description "Reveal in Finder"
              'key 'secondary
              'run (lambda (path) (reveal-in-finder path)))))
```

### `(walk MODE-ID DISPLAY-NAME ['order 'keys|'declared] key…)`

Define a reusable **"act + latch"** navigation set once and splice it
into many parents (DRY) — the DSL-level packaging of a **Walk**
(CONTEXT.md): a collection whose members cycle via `'next 'self`. Pure
like every other form, it builds two things from the one key list:

1. **A mode tree** under `MODE-ID` (with `'exit-on-unknown #t` and
   `'display-name DISPLAY-NAME`) holding the SAME keys, each decorated
   `'next 'self` — a cyclic edge, so firing one re-arms the collection
   in place. This is the latch target the walk repeats in. The tree is
   *carried inside* the returned splice node; the `configuration` merge
   hoists it into the tree set, so the same walk spliced into two
   screens contributes its mode tree once (identity dedup) — a walk is
   mentioned only where it is used.
2. **The splice's children**: the same keys again, each decorated
   `'next MODE-ID` — a cross edge.

A splice node is **fully transparent**: it survives construction as
data, and the downstream expansions (the dispatch walk, the renderer)
expand its children in place, so the result is identical to writing
those entry keys inline. So one key list supplies
both the mode tree *and* every entry point, each copy decorated for
its own edge (cyclic for the mode members, cross for the entry
splice), with no duplication of the key list itself.

Use individual `(key …)` forms — not `(keys …)` / `(key-range …)` —
because `'next` is a `(key …)`-only keyword.

**Row ordering of the walk.** An optional leading `'order` keyword
(`'keys` | `'declared`, mirroring `panel` / `screen`) tunes how the
**mode tree** — the list you see *after* a key crosses in —
orders its rows. `'keys` (the default) key-sorts them; `'declared`
shows them in declaration order, so a paired set reads grouped (e.g. Focus
`h j k l` then Move `H J K L`) rather than interleaved (`h H j J k K l L`). The
keyword is forwarded only to the mode tree; it never enters the splice,
because the spliced **entry keys** land in their parent's **loose region**,
which is already declaration-ordered. Reach for `'order 'declared` when you want
the walk to match that grouped entry-point order.

```scheme
(define split-nav
  (walk 'iterm-split-walk "Splits"
    (key "h" "Focus Left"  terminal:focus-pane-left)
    (key "H" "Move Left"   terminal:move-pane-left)
    …))

;; Pressing s then h focuses-left AND crosses into 'iterm-split-walk,
;; where hjkl/HJKL keep working. The same split-nav can be spliced into
;; several parents (e.g. a top-level panel and an open sub-screen).
(screen 'com.googlecode.iterm2
  (open "s" "Splits"
    (panel "Walk" split-nav)
    (panel "New"  (group "n" "New Split" …))))
```

A Walk keeps the caller's breadcrumb context: entering one from an
active modal appends `DISPLAY-NAME` to the caller's root segments, so
the title reads e.g. `iTerm ▸ Splits` rather than collapsing to `Splits`.

---

## The bare authoring surface

`(modaliser display-dsl)` is the **canonical** display surface: the
dispatch atoms above compose the structure, then **one explicit step**
attaches the Display value. It is what the sugar compiles onto, and it is
what you reach for when the two layers should be separable — a
programmatically built tree, a display substituted by tooling, a node
whose keys must provably survive a presentation change.

Import it **prefixed** — `panel` deliberately exists on both surfaces:

```scheme
(import (modaliser dsl)
        (prefix (modaliser display-dsl) d:))
```

### `(with-display NODE clause…)`

Pure. Returns `NODE` with the assembled display value attached as its
single `'display` entry. Clause order is free — assembly is always
canonical (`display-name`, `cols`, `layout`, `order`, `embed`, `loose`,
`panels`), so two spellings of the same display can never differ by entry
order. Panel clauses accumulate in the order given, which is grid order.

- **Zero clauses attach nothing** — the empty display value is *identical*
  to no display at all, and the node comes back unchanged.
- **Attaching is once.** A node that already carries a display value is an
  error; wholesale replacement is `node-with-display` from
  `(modaliser fsm)` — the raw accessor tooling uses.
- **References are validated at attach time.** Every ref must resolve one
  level deep against the node's *own* (splice-expanded) children; block
  reference ids must be unique across the value; and an explicit `loose`
  must leave **no child unplaced** — a display may never silently drop a
  live row. (With no `loose` clause the loose region defaults to every
  child no panel references, in declaration order, so nothing can be
  dropped.)

### Clause constructors

Each returns plain printable data — exactly the entry that lands in the
display value — and validates its own argument, so a bad value errors at
the clause, not at render. Where a clause takes **row refs**, a *string*
names a dispatch row by its binding key and `(block ID)` names a block
child by its reference id.

| Clause | Signature | Role |
|---|---|---|
| `panel` | `(panel LABEL clause-or-ref…)` | One panel of the grid. `LABEL` `#f` is **headerless**. Args mix `(span …)` / `(order …)` (at most one each, position-free) with row refs in row order. Span defaults `'narrow`, auto-`'wide` when a block ref is present. At most one block ref per panel. |
| `loose` | `(loose ref…)` | The loose region, in render order. |
| `block` | `(block ID)` | A row ref naming a block child: its explicit `'id` entry, else its `'type`. |
| `span` | `(span 'narrow \| 'wide \| 'full)` | A panel's width. Panel-only — passing it to `with-display` errors. |
| `order` | `(order 'keys \| 'declared)` | Row ordering: inside a `panel` it is that panel's mode; at the top level it is the grid-wide default. |
| `cols` | `(cols N)` | Authored column count (positive exact integer) — pins the track count. |
| `layout` | `(layout 'masonry \| 'grid)` | Panel packing. |
| `embed` | `(embed KEY…)` | The per-edge **embed** choice: each key's edge target renders as an in-place section of this node's display root. Each must name a group child. |
| `display-name` | `(display-name STR)` | Breadcrumb scope override (tree roots). |

### Sugar ≡ bare

The two spellings below produce the *identical* tree contribution — this
is the equivalence the veneer contract pins (`DisplayDslTests`):

```scheme
(define kz (key "z" "Z" act))
(define kc (key "c" "C" act))
(define kB (key "B" "Big" act))

;; Sugar: both layers at once.
(screen 'demo 'cols 2
  kz
  (panel "W" 'span 'wide kc kB))

;; Bare: dispatch structure, then the display attached.
(tree 'demo                             ; from (modaliser configuration)
  (d:with-display (tree-root 'demo kz kc kB)
    (d:cols 2)
    (d:loose "z")
    (d:panel "W" (d:span 'wide) "c" "B")))
```

Note what the bare spelling makes visible: the children are **flat** —
the panel's rows are siblings of the loose row — and the grouping exists
only as a clause naming `"c"` and `"B"`. Blocks work the same way:
authored as a child atom, placed by `(d:block ID)`.

### For tooling

| Export | Description |
|---|---|
| `resolve-display` | `(resolve-display children display)` → render plan. The pure resolution seam: membership, row order, embed-row exclusion and the block partition, resolved to a total alist the overlay only serializes. See [renderer-protocol.md](renderer-protocol.md). |
| `block-ref-id` | `(block-ref-id block-spec)` → the id a display references that block by. |
| `sort-rows` | `(sort-rows rows)` → the canonical row-key sort (`"a A b B …"`), shared with the default list renderer so the two paths can never disagree. |

---

## Nested contexts: the Terminal context map

A **nested context** is an inner terminal tool's tree reachable from a
terminal-like screen — herdr inside iTerm is the shipping example
(CONTEXT.md "Entry point"). You do not wire one. The configuration's
**Terminal context map** — the `(terminal-contexts …)` fragment — maps
the focused pane's foreground exe name to its tree, and activation does
the rest ([ADR-0013](../adr/0013-nested-context-entry-points.md),
[configuration-value spec](../specs/configuration-value.md)):

- A `'local` leader press on a terminal-like screen lands in the
  **innermost mapped** context's tree, with the Return stack seeded one
  frame per outer context — backspace steps outward one boundary at a
  time (tool → mux → host), Escape exits from any depth.
- Every terminal-like screen derives a gated **`.` step-in edge**
  stepping one mapped context inward, computed per visit from the live
  chain. Authored by nobody.

The factory libraries ship the map entries, all four now named
`wiring`: `(herdr:wiring)`, `(tmux:wiring)`, `(zellij:wiring)`,
`(nvim:wiring)`. An entry is itself a fragment — the map entry, plus its
mux backend and digit-jump tree when the tool has pane ops — so
composing an inner tool into *every* terminal-like host at once is one
call inside `terminal-contexts`. No host names an inner tool; no inner
tool names a host.

**None of them carries a tree.** A `wiring` is integration only; the
screen it points at is authored in your configuration, under the scope
the map entry names — `'herdr`, `'tmux`, `'zellij`, `'nvim`
([ADR-0021](../adr/0021-decision-free-libraries.md)). Those scope
symbols are the machinery half of the boundary: rename one and the
configuration fails reference-closure validation at load, loudly, rather
than leaving a dead binding.

```scheme
(configuration
  …
  (iterm:wiring)            ; a terminal-like host's backend + digit tree
  (terminal-contexts        ; works in iTerm, kitty, WezTerm, …
    (herdr:wiring)
    (nvim:wiring))
  iterm-screen              ; (screen 'com.googlecode.iterm2 …)
  herdr-screen              ; (screen 'herdr …)
  herdr-focus-walk          ; (tree 'herdr-panes-focus …)
  nvim-screen)              ; (screen 'nvim …)
```

Note what is *not* there: no line pairs iTerm with herdr. The host's
screen is terminal-like because its scope is the backend record's
match-key; the mux attaches by foreground exe. Adding a second host or a
second mux adds one line, never one per pair.

See [terminal-pane-aware-tree.md](../how-to/terminal-pane-aware-tree.md)
for the full worked example and [ADR-0013](../adr/0013-nested-context-entry-points.md)
for why nesting works this way rather than as a merged variant tree.

### `(step-in key label target-scope gate)`

The explicit, authored form of a gated cross-tree key edge (CONTEXT.md
"Edge gate") — for the rare tree that wants its own jump into another
tree, outside the derived context-map machinery above. Pressing `key`
moves straight to `target-scope`'s root — an ordinary key
edge, not a call (no return-stack push, unlike a `(key … 'next TARGET)`
cross edge), so the target's own up edge is what
backspace follows back out, and the move lands and shows immediately
like any other group descent, with no intermediate command state.

`gate` is a 0-arg predicate. Live only while it holds: gate-filtered out
of dispatch exactly like any other edge gate, and the row is hidden from
the overlay via a `'hidden` thunk derived from the same `gate` — "no
inner context detected" means both no edge and no overlay row.

```scheme
(screen 'com.example.myterm
  (step-in "." "Herdr" 'herdr herdr-detected?)
  …)
```

---

## Helpers

### `(λ formals body…)`

Unicode alias for `(lambda formals body…)`. Useful for keeping inline
thunks compact: `(key "b" "Browser" (λ () (launch-app "Safari")))`.
The `key` macro pattern-matches `λ` the same way it matches `lambda`,
so both forms take the action-thunk fast path.

### `(tree-root scope [keyword value]... . children)`

The pure tree-root builder underneath `screen` and `walk` — what a
library uses for a mode tree that is *not* a panel-grid screen (a
walk's latch target, a digit-jump mode), and the dispatch half of the
[bare surface](#the-bare-authoring-surface). Returns a root node
alist; wrap it in the `tree` contribution constructor (from
`(modaliser configuration)`) to put it in a fragment. Keywords mirror
`group`: `'on-enter` / `'on-leave`, `'entry` / `'exit`, `'provider`,
`'exit-on-unknown`, `'display-name`, `'order`; unknown keywords pass
through as opaque alist entries. The optional arguments mirror `group`
too — `'on-leave` and `'exit` may declare one to receive the **exit
reason**, `'entry` one to receive the arriving key (see
[state-machine.md](state-machine.md#the-exit-reason)).

`'display-name` and `'order` are **display** data, so `tree-root` folds
them into the root's display value rather than leaving them loose on the
node — the only two keywords that cross the layer boundary, kept for the
convenience of `walk` and of libraries building a plain list-rendered
mode. Everything else about presentation goes through
[`with-display`](#the-bare-authoring-surface).

### `(modifier-symbols->mask syms)`

Converts a symbol list like `'(shift ctrl)` to the integer bitmask
expected by native hotkey APIs. Recognised symbols: `'cmd`, `'shift`,
`'alt`, `'ctrl`. Unknown symbols are silently ignored. Mostly
internal — the `leader` constructor already accepts symbol
lists via its `'modifiers` keyword.

---

## See also

- [libraries.md](libraries.md) — bundled `(modaliser …)` libraries and
  their exports.
- [state-machine.md](state-machine.md) — modal lifecycle, the `'next`
  edge, Terminal/Walk semantics, navigation hooks.
- [renderer-protocol.md](renderer-protocol.md) — the render plan and the
  panel-grid payload, the block renderer registry, and how to write
  custom blocks.
- [configuration-value spec](../specs/configuration-value.md) — the
  two-layer node model, the lowering contracts, and the test seams.
- [theming.md](theming.md) — CSS variables and class names consumed by
  the overlay.
- How-to guides — task-oriented recipes:
  [add a binding](../how-to/add-a-binding.md),
  [add a per-app tree](../how-to/add-a-per-app-tree.md),
  [add a fuzzy-finder](../how-to/fuzzy-finder.md),
  [vary the tree by what's in the focused pane](../how-to/terminal-pane-aware-tree.md)
  (the Terminal context map and the pane-detection chain).
