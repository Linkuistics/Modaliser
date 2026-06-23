# DSL reference

Every form exported from `(modaliser dsl)`, plus the related setters
from `(modaliser leader)` and the top-level UI helpers. Signatures are
ground-truthed against
[`dsl.sld`](../../Sources/Modaliser/Scheme/lib/modaliser/dsl.sld),
[`state-machine.sld`](../../Sources/Modaliser/Scheme/lib/modaliser/state-machine.sld),
and [`leader.sld`](../../Sources/Modaliser/Scheme/lib/modaliser/leader.sld).

## You author a layout, not a command tree

Modaliser's overlay is a **dynamic cheat-sheet document** — a grid of
panels you read like a reference card. You author it directly: a config
is a **layout spec**, a tree of **screens**, each an implicit grid of
**panels** ([ADR-0011](../adr/0011-presentation-first-layout-spec-lowers-to-operational-node-tree.md),
[ADR-0012](../adr/0012-layout-dsl-surface-screen-panel-open-over-unchanged-atoms.md)).

That layout **lowers** — at config-load, the moment each form is
evaluated — to the **operational node-tree**, the `(kind . group)` /
`(kind . command)` alist the modal state machine dispatches. The
operational tree is now an **intermediate representation (IR)**, a
compile target, not a thing you write by hand. The dispatch engine
(sticky modes, transparent grouping, digit-jump, selectors) reads that
IR exactly as before; the **panel-grid renderer** reads the presentation
metadata (`panel`, `span`, `screen`) the lowering annotates onto it.

The practical consequence: the four **layout forms** (`screen`, `panel`,
`open`, `fragment`) shape *presentation*, and the **dispatch atoms**
(`key`, `keys`, `key-range`, `group`, `selector`, `sticky-set`) shape
*behaviour* — and because the atoms *are* the IR, they are unchanged. A
panel is a transparent visual card: it groups rows without changing the
keys beneath it.

## Imports

The common case is one import:

```scheme
(import (modaliser dsl))
```

That surfaces the layout forms `screen`, `panel`, `open`, `fragment`;
the dispatch atoms `key`, `keys`, `key-range`, `group`, `selector`,
`action`, `sticky-set`; the helper `λ`; and the configuration setters
`set-leader!`, `set-overlay-delay!`, `set-theme!`,
`modifier-symbols->mask`. The bundled seed config also pulls
in `(modaliser leader)` (for `set-leaders!`) and a handful of native
libraries (`(modaliser app)`, `(modaliser keyboard)`, etc.).

---

## Configuration setters

### `(set-leaders! [keyword value]...)`

From `(modaliser leader)`. Registers both global and local leader
hotkeys in one call.

Keywords:

| Keyword | Type | Description |
|---|---|---|
| `'global-keycode` | integer | Keycode for the global leader (e.g. `F18`). Omit to skip. |
| `'local-keycode` | integer | Keycode for the app-local leader (e.g. `F17`). Omit to skip. |
| `'modifiers` | symbol list | Required modifiers, e.g. `'(shift)` or `'(cmd alt)`. |
| `'arm-when-frontmost` | string list | Bundle IDs that suppress leader arming while frontmost — useful for remote-desktop viewers whose modifiers should pass through. |

```scheme
(set-leaders! 'global-keycode F18
              'local-keycode  F17
              'arm-when-frontmost '("com.p5sys.jump.mac.viewer"))
```

For scope-asymmetric options use `(set-global-leader! …)` and
`(set-local-leader! …)` directly. Both delegate to `set-leader!` below.

### `(set-leader! mode keycode [keyword value]...)`

The single-scope primitive. From `(modaliser dsl)`. `mode` is
required and must be `'global` or `'local` — there is no modeless
form. `'global` always opens the global tree. `'local` opens the
focused app's per-app tree, and does nothing if that app has no
tree — it does *not* fall back to the global tree. Keywords:

| Keyword | Type | Description |
|---|---|---|
| `'modifiers` | symbol list | Required modifiers, e.g. `'(shift ctrl)`. |
| `'arm-when-frontmost` | string list | Bundle IDs that suppress arming while frontmost. |

```scheme
(set-leader! 'global F18)
(set-leader! 'local  F17 'modifiers '(shift))
```

### `(set-overlay-delay! seconds)`

How long after leader arm before the overlay appears. Zero shows
immediately. Typical values 0.3–1.0. Quick muscle-memory keypresses
produce no UI when the delay is non-zero — the modal still dispatches
the key.

```scheme
(set-overlay-delay! 0.3)
```

### Theming

All visual customisation — colours, fonts, spacing, host-theme
variables (`--color-host-bg`, `--color-host-fg`, …), chip styling —
lives in `~/.config/modaliser/theme.css`. Modaliser auto-loads that
file at startup. No Scheme setter for CSS is involved.

See [theming.md](theming.md) for the full variable inventory and
worked examples.

### `(set-theme! …)`

Deprecated no-op stub. Theming moved to CSS — edit
`~/.config/modaliser/theme.css`.

---

## Layout forms

The presentation-first surface. Four forms — `screen`, `panel`, `open`,
`fragment` — that **lower to the operational IR** at config-load. They
own *layout*; the dispatch atoms they contain own *behaviour*.

### `(screen scope [keyword value]... . panels)`

Registers a command tree under `scope` and renders it as a **grid of
panels** — the top-level layout form. `scope`
is a symbol (or string) like `'global`, `'com.apple.Safari`, or
`'iterm-panes-focus`; symbols and strings are equivalent.

The body is an **implicit grid**: each `(panel …)` is a grid cell, each
`(open …)` a drill-in cell. **Loose top-level atoms** (a `(key …)` not
wrapped in a panel) collect into one leading **"General"** panel — so a
flat config still renders as a single tidy card.

```scheme
(screen 'global
  (panel "General"
    (key "," "Settings" (settings:actions))
    (key "/" "Help"     (λ () (open-help))))

  (open "w" "Windows"           ; drill-down → its own grid of panels
    (panel "Layout" (window:layout-block …))
    (panel "Select" (window:list-block 'chips? #t)))

  (panel "Applications"
    (key "b" "Browser"  (λ () (launch-app "Safari")))
    (key "t" "Terminal" (λ () (launch-app "iTerm")))))
```

Optional leading keywords:

| Keyword | Type | Description |
|---|---|---|
| `'cols` | integer | Authored column count. Default is CSS-intrinsic auto-fit (panels flow into as many tracks as fit the width). Pins an explicit track count instead. |
| `'on-enter` | thunk | Runs when the modal navigates into this screen. Composed with any embedded live-list hooks. |
| `'on-leave` | thunk | Runs when the modal navigates out. |
| `'sticky` | boolean | If `#t`, firing a command leaf resets to this screen's root instead of exiting. |
| `'exit-on-unknown` | boolean | If `#t`, unrecognised keys exit the modal instead of being swallowed. Inherited by descendants. |
| `'display-name` | string | Overrides the breadcrumb scope segment. Useful for mode-id scopes (e.g. `'iterm-panes`) where the auto-resolved app name doesn't make sense. |

A `screen` lowers to a tree-root group carrying `'renderer 'panel-grid`
(plus `'cols` when authored), so the panel-grid renderer draws it. The
live-list `'on-enter-fn` / `'on-leave-fn` of any panel-embedded block
compose with the user hooks supplied to the `screen`.

### `(panel label [span value] . children)`

A **transparent visual card** in a screen's grid — one declared
grouping of rows, with a banded header carrying `label`. Transparent
means it **never changes the keys beneath it**: a child `(key "b" …)`
dispatches at `b` whether or not a panel encloses it. (A panel lowers to
a `category` node, which the state machine descends through as if its
children were hoisted into the parent.)

`children` are dispatch atoms (`key`/`keys`/`group`/`selector`/…) plus
**at most one** embedded live-list block. Splices (`fragment` /
`sticky-set`) hoist in place.

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

**Embedding a live list.** A panel may hold one dynamic-list block
(`window:list-block`, `iterm:pane-list-block`, `iterm:tab-list-block`)
among its children. The panel **auto-promotes to `'wide`** when it holds
a list (unless you give an explicit `'span`), since lists want
horizontal room. The block's hidden digit key-range (the `1..` direct-
jump selectors) is lifted into the panel's dispatch children so the
digits resolve transparently; the block itself rides under the panel's
`'list` metadata for the renderer. The embedded list also gains a
**selection cursor** (`↑↓` / `k j` to move, `⏎` to activate) — see
[Live lists & the selection cursor](#live-lists--the-selection-cursor).

It is an error to embed two list blocks in one panel.

### `(open KEY LABEL [keyword value]... . panels)`

A **navigable drill-down** into a sub-screen. Pressing `KEY`
descends into a fresh grid of `panels` (its own screen). `open` is the
*only* navigable layout form; a `panel`, by contrast, is transparent and
never changes key paths.

```scheme
(open "w" "Windows"
  (panel "Layout" (window:layout-block …))
  (panel "Move"
    (key "h" "Left"  (λ () (move-window 'left)))
    (key "l" "Right" (λ () (move-window 'right)))))
```

Its body lowers the same way a `screen` body does (loose atoms → a
"General" panel; nested `open`s drill further). Keywords: `'on-enter`,
`'on-leave`, `'sticky`, `'exit-on-unknown`, `'cols` — **not**
`'display-name` (a breadcrumb-root override a child group has no use
for). An `open` lowers to a navigable `group` carrying
`'renderer 'panel-grid`.

A nested `(open …)` declared *inside* a `(panel …)` renders as an accent
drill-in `›` row in that panel; a top-level `(open …)` directly under a
`screen` renders as its own single-row cell.

### `(fragment child…)`

A reusable, **named chunk of layout** — bind it once to a Scheme
variable and splice it into any number of screens or panels for DRY.
`child`s are panels (for screen-level reuse) or command rows (for
panel-level reuse).

```scheme
(define window-ops
  (fragment
    (key "c" "Center"   center-window)
    (key "m" "Maximise" maximise-window)))

(screen 'global (panel "Windows" window-ops (key "r" "Restore" …)))
(screen 'finder (panel "Layout"  window-ops))
```

A `fragment` is **fully transparent**: the container forms (`screen` /
`panel` / `open` / `group`) hoist its children in place at construction
time via `expand-splices`,
so the lowered tree is identical to writing the children inline —
nothing downstream ever sees the fragment. Nested fragments and
`sticky-set`s compose for free, since `expand-splices` recurses through
splice children.

`fragment` is `sticky-set`'s second half on its own: a transparent
splice node with **no** mode registration and **no** `'sticky-target`
decoration — pure structural reuse. Reach for `sticky-set` when you want
the act-and-latch behaviour, `fragment` when you only want to share
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

Optional trailing keyword:

| Keyword | Type | Description |
|---|---|---|
| `'sticky-target` | symbol | After running the action, transition modal navigation into the tree registered under this mode-id (declarative `(enter-mode! …)`). Overrides the surrounding tree's transient/sticky cleanup; the overlay paints a `↻` marker on the cell. |

```scheme
(key "p" "Pane Mode" (λ () (if #f #f)) 'sticky-target 'iterm-panes-focus)
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
overkill — directional split/move clusters, sticky walks. Keywords:

| Keyword | Type | Description |
|---|---|---|
| `'on-enter` | thunk | Fires when modal navigates *into* this group (only if the overlay is open). |
| `'on-leave` | thunk | Fires when modal navigates *out*. |
| `'sticky` | boolean | If `#t`, firing a command leaf at or below this group returns navigation here instead of exiting. Composes with sticky ancestors: deepest sticky group wins. |
| `'exit-on-unknown` | boolean | Unknown keys exit the modal. Inherited by descendants. |

Unknown keyword/value pairs pass through as opaque alist entries on the
group — this is the pass-through that the layout DSL rides
(`'renderer 'panel-grid`, `'span`, `'cols`).

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

### `(sticky-set MODE-ID DISPLAY-NAME key…)`

Define a reusable **"act + latch"** navigation set once and splice it
into many parents (DRY). It does two things at evaluation time:

1. **Registers a sticky mode tree** under `MODE-ID` (with `'sticky #t`,
   `'exit-on-unknown #t`, and `'display-name DISPLAY-NAME`) holding the
   bare keys — this is the latch target the walk repeats in.
2. **Returns a splice node** carrying the same keys, each decorated with
   `'sticky-target MODE-ID`.

A splice node is **fully transparent**: the container forms (`screen`,
`panel`, `open`, `group`) hoist its children into their own child list at
construction time, so the result is identical to writing those entry keys
inline —
and nothing downstream ever sees the splice. So one key list supplies
both the registered mode *and* every entry point, with no duplication.

Use individual `(key …)` forms — not `(keys …)` / `(key-range …)` —
because `'sticky-target` is a `(key …)`-only keyword.

```scheme
(define split-nav
  (sticky-set 'iterm-split-walk "Splits"
    (key "h" "Focus Left"  terminal:focus-pane-left)
    (key "H" "Move Left"   terminal:move-pane-left)
    …))

;; Pressing s then h focuses-left AND latches into 'iterm-split-walk,
;; where hjkl/HJKL keep working. The same split-nav can be spliced into
;; several parents (e.g. a top-level panel and an open sub-screen).
(screen 'com.googlecode.iterm2
  (open "s" "Splits"
    (panel "Walk" split-nav)
    (panel "New"  (group "n" "New Split" …))))
```

Latched walks keep the caller's breadcrumb context: entering a mode from
an active modal appends `DISPLAY-NAME` to the caller's root segments, so
the title reads e.g. `iTerm ▸ Splits` rather than collapsing to `Splits`.

---

## Helpers

### `(λ formals body…)`

Unicode alias for `(lambda formals body…)`. Useful for keeping inline
thunks compact: `(key "b" "Browser" (λ () (launch-app "Safari")))`.
The `key` macro pattern-matches `λ` the same way it matches `lambda`,
so both forms take the action-thunk fast path.

### `(modifier-symbols->mask syms)`

Converts a symbol list like `'(shift ctrl)` to the integer bitmask
expected by native hotkey APIs. Recognised symbols: `'cmd`, `'shift`,
`'alt`, `'ctrl`. Unknown symbols are silently ignored. Mostly
internal — `set-leader!` and `set-leaders!` already accept symbol
lists via their `'modifiers` keyword.

---

## See also

- [libraries.md](libraries.md) — bundled `(modaliser …)` libraries and
  their exports.
- [state-machine.md](state-machine.md) — modal lifecycle, sticky
  semantics, navigation hooks.
- [renderer-protocol.md](renderer-protocol.md) — the panel-grid payload,
  the two-tier renderer registry, and how to write custom blocks.
- [theming.md](theming.md) — CSS variables and class names consumed by
  the overlay.
- How-to guides — task-oriented recipes:
  [add a binding](../how-to/add-a-binding.md),
  [add a per-app tree](../how-to/add-a-per-app-tree.md),
  [add a fuzzy-finder](../how-to/fuzzy-finder.md).
