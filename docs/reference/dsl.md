# DSL reference

Every form exported from `(modaliser dsl)`, plus the related setters
from `(modaliser leader)` and the top-level UI helpers. Signatures are
ground-truthed against
[`dsl.sld`](../../Sources/Modaliser/Scheme/lib/modaliser/dsl.sld),
[`state-machine.sld`](../../Sources/Modaliser/Scheme/lib/modaliser/state-machine.sld),
and [`leader.sld`](../../Sources/Modaliser/Scheme/lib/modaliser/leader.sld).

The DSL splits into three groups:

1. **Configuration setters** — global state (`set-leaders!`,
   `set-overlay-delay!`, `set-host-header!`, …) called once near the
   top of `config.scm`.
2. **Tree definition** — `define-tree` registers a command tree under
   a scope.
3. **Node and block constructors** — `key`, `keys`, `group`, `category`,
   `selector`, `action`, `overlay`, `which-key-block`. The body of every
   tree.

## Imports

The common case is one import:

```scheme
(import (modaliser dsl))
```

That surfaces `key`, `keys`, `key-range`, `group`, `category`,
`selector`, `action`, `overlay`, `λ`, `define-tree`,
`modifier-symbols->mask`, `set-leader!`, `set-theme!`,
`set-host-header!`, `set-overlay-delay!`, and
`set-overlay-aspect-ratio!`. The bundled seed config also pulls in
`(modaliser leader)` (for `set-leaders!`) and a handful of native
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

### `(set-leader! [mode] keycode [keyword value]...)`

The single-scope primitive. From `(modaliser dsl)`. Mode is `'global`,
`'local`, or omitted; when omitted, the handler resolves at trigger
time to the focused app's local tree if one exists, falling back to
the global tree. Keywords:

| Keyword | Type | Description |
|---|---|---|
| `'modifiers` | symbol list | Required modifiers, e.g. `'(shift ctrl)`. |
| `'arm-when-frontmost` | string list | Bundle IDs that suppress arming while frontmost. |

```scheme
(set-leader! 'global F18)
(set-leader! 'local  F17 'modifiers '(shift))
```

### `(set-overlay-delay! seconds)`

How long after leader arm before the which-key overlay appears. Zero
shows immediately. Typical values 0.3–1.0. Quick muscle-memory
keypresses produce no UI when the delay is non-zero — the modal still
dispatches the key.

```scheme
(set-overlay-delay! 0.3)
```

### `(set-overlay-aspect-ratio! ratio)`

Target width-to-height ratio for the overlay's multi-column layout.
The renderer picks the column count that gets closest to this ratio
for the current entry count. `1.0` is square; `1.6` (default) prefers
wider, shorter overlays.

```scheme
(set-overlay-aspect-ratio! 1.6)
```

### `(set-host-header! [keyword value]...)`

Adds an optional banner identifying which Modaliser instance owns the
overlay (useful when running multiple installs across different
machines). Keywords are all optional:

| Keyword | Type | Description |
|---|---|---|
| `'name` | string | Display name. Default: `(run-shell "hostname -s")`. |
| `'background` | CSS colour | Header background. |
| `'foreground` | CSS colour | Header text. Defaults to `"white"` when `'background` is set, otherwise `#f`. |
| `'separator-color` | CSS colour | Override the breadcrumb separator colour. |

All string values are whitespace-trimmed, so `(run-shell …)` outputs
work directly without stripping the trailing newline.

```scheme
(set-host-header! 'background "dodgerblue")
```

Translates to `--color-host-bg`, `--color-host-fg`, and
`--color-host-sep` CSS variables on `:root`. See
[theming.md](theming.md) for the full variable inventory.

### `(set-overlay-css! css-string)`

Inject custom CSS into the overlay. Applied *after* `base.css` and any
block-supplied stylesheets, so user CSS wins on equal specificity.
This is a top-level definition from `ui/overlay.scm`; it does not
require an explicit import.

```scheme
(set-overlay-css! "
  .overlay { backdrop-filter: blur(20px); }
  .entry-key { font-weight: 700; }
")
```

### `(set-theme! …)`

Deprecated no-op stub. Theming moved to CSS — use `set-overlay-css!`
or override CSS variables via `set-host-header!` and block options.

---

## Tree definition

### `(define-tree scope [keyword value]... . content)`

Registers a command tree under `scope` — a symbol (or string) like
`'global`, `'com.apple.Safari`, or `'iterm-panes-focus`. Symbols and
strings are equivalent; `register-tree!` normalises both. The `content` is a list of
node-forms (`(key …)`, `(category …)`, …) and block specs
(`(which-key-block …)`, `(window:list-block …)`, …).

**Auto-pack.** A top-level `define-tree` always renders as a
block-list (`'renderer 'blocks`). Consecutive runs of node-forms in
`content` are collapsed into a single `(which-key-block …)`. Mixed
runs split into TWO blocks — uncategorised entries first, then
categories — so the overlay renders loose bindings as one section,
category columns underneath. Explicit `(which-key-block …)` forms
authored by the user are preserved as-is and never re-shuffled.

Optional leading keywords (same set as `register-tree!`):

| Keyword | Type | Description |
|---|---|---|
| `'on-enter` | thunk | Runs when the modal navigates into this tree. Composed with any block hooks. |
| `'on-leave` | thunk | Runs when the modal navigates out. |
| `'sticky` | boolean | If `#t`, firing a command leaf resets to this tree's root instead of exiting. |
| `'exit-on-unknown` | boolean | If `#t`, unrecognised keys exit the modal instead of being swallowed. Inherited by descendants. |
| `'display-name` | string | Overrides the breadcrumb scope segment. Useful for mode-id scopes (e.g. `'iterm-panes`) where the auto-resolved app name doesn't make sense. |

```scheme
(define-tree 'global
  (keys '("1" ..) "Switch Space"
        (λ (k i ks) (send-keystroke '(ctrl) k)))
  (key "," "Settings" (settings:actions))
  (key "w" "Windows"  (overlay (window:layout-block …)))

  (category "Apps"
    (key "b" "Browser"  (λ () (launch-app "Safari")))
    (key "t" "Terminal" (λ () (launch-app "iTerm")))))
```

Per-app trees use a bundle-id scope. `(safari:register!)` and friends
call `define-tree` (or `register-tree!`) internally with the right
scope.

---

## Node constructors

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

;; Correct — keystroke returns a procedure that closes over the args
(key "c" "Copy" (keystroke '(cmd) "c"))

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

Nested submenu — typing `K` from the parent descends into a tree of
`children`. Keywords:

| Keyword | Type | Description |
|---|---|---|
| `'on-enter` | thunk | Fires when modal navigates *into* this group (only if the overlay is open). |
| `'on-leave` | thunk | Fires when modal navigates *out*. |
| `'sticky` | boolean | If `#t`, firing a command leaf at or below this group returns navigation here instead of exiting. Composes with sticky ancestors: deepest sticky group wins. |
| `'exit-on-unknown` | boolean | Unknown keys exit the modal. Inherited by descendants. |

Unknown keyword/value pairs pass through as opaque alist entries on the
group — used by renderer extensions like `'renderer 'blocks 'blocks (…)`.

```scheme
(group "f" "Files"
  (key "n" "New"    (λ () (run-shell "touch ~/Desktop/untitled.txt")))
  (key "o" "Open"   (launcher:find-file))
  (key "h" "Home"   (λ () (reveal-in-finder "~"))))
```

`(group …)` returns a node alist; in a `define-tree` body wrap it with
`(key K L (group …))` if you want the wrapping `key` macro to flow
through `K`/`L`. Inline `(group K L …)` works equivalently because
`group` already takes `K`/`L` positionally.

### `(category LABEL . children)`

Visual grouping for the which-key overlay — `children` are rendered as
a labelled column. Categories are **transparent** to the state machine:
typing a child key dispatches as if the children were direct group
siblings. This lets configs add visual grouping without changing key
paths.

```scheme
(category "Search"
  (key "g" "Google"           (web-search:google))
  (key "a" "Find Application" (launcher:find-application))
  (key "f" "Find File"        (launcher:find-file)))
```

Categories may appear anywhere a `(key …)` can. Inside a `define-tree`
or `overlay`, auto-pack splits mixed runs of categorised and
uncategorised entries into two blocks — uncategorised first, then
categories — so the overlay layout is predictable.

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

### `(overlay [keyword value]... . blocks)`

Generic block-list group — renders as a block-list overlay rather than
the default which-key flow. Keywords:

| Keyword | Type | Description |
|---|---|---|
| `'key` | string | Leader key in the parent tree (default `"?"`). |
| `'label` | string | Group label (default `"Overlay"`). |
| `'on-enter` | thunk | User-supplied enter hook. Composed with block-supplied hooks: user hook runs first, then each block's hook in declaration order. |
| `'on-leave` | thunk | User-supplied leave hook. Same composition order. |

After the keywords, every positional argument is content. Mixed
node-forms and block specs are allowed: consecutive node-form runs
auto-pack into a `which-key-block`, while block specs pass through
unchanged.

```scheme
(key "w" "Windows"
  (overlay
    (window:layout-block (("d" "f" "g")) (center "c"))   ; block

    (key "s" "Select Window" (selector …))               ; node — packed
    (key "r" "Restore"       (λ () (restore-window)))    ; node — packed

    (window:list-block 'chip-options `(…))))             ; block
```

`(overlay …)` returns a group node; bind it with `(key K L (overlay …))`
or use `(overlay 'key K 'label L …)` directly. Both styles work because
the wrapping `key` macro decorates the group via `decorate-node`, which
respects existing `'key`/`'label` entries when present.

---

## Block constructors

### `(which-key-block . children)`

Explicit which-key block. Returns a block spec with `'type 'which-key`
and `'block-children` holding the dispatch entries. `define-tree` and
`overlay` auto-pack consecutive node runs into one of these
automatically; reach for the explicit form when you want fine-grained
control over which entries land in which visual block. Authored blocks
are preserved as-is by the auto-packer.

```scheme
(define-tree 'global
  (which-key-block
    (key "a" "First"   (λ () …))
    (key "b" "Second"  (λ () …)))
  (window:list-block …))
```

Imported from `(modaliser blocks which-key)`.

Other block constructors live in their respective libraries:
`window:layout-block` and `window:list-block` from `(modaliser blocks
window-list)` / `(modaliser blocks window-diagram)`. See
[libraries.md](libraries.md) for the bundled block set.

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
- [renderer-protocol.md](renderer-protocol.md) — how to write custom
  blocks.
- [theming.md](theming.md) — CSS variables and class names consumed by
  the overlay.
