# Library reference

Every bundled `(modaliser …)` library that user configs are expected
to import directly. Native primitives (Swift-backed libraries like
`(modaliser shell)` or `(modaliser app)`) are listed briefly at the end
— their canonical reference is the source, since signatures track the
host.

## Import conventions

The factory libraries use **bare-name exports** (`register!`, `actions`,
`tree`, `find-application`, …) so call sites read short. To avoid
collisions across libraries, the recommended import style is
**prefix-style**:

```scheme
(import (prefix (modaliser apps iterm)      iterm:)
        (prefix (modaliser apps safari)     safari:)
        (prefix (modaliser apps chrome)     chrome:)
        (prefix (modaliser window-actions)  window:)
        (prefix (modaliser launchers)       launcher:)
        (prefix (modaliser settings-menu)   settings:)
        (prefix (modaliser web-search)      web-search:))
```

Foundational libraries (`(modaliser dsl)`, `(modaliser leader)`,
`(modaliser util)`, `(modaliser ax-hints)`, `(modaliser terminal)`) have
unique long names and are typically imported unprefixed because they're
the vocabulary you use everywhere.

---

## Tree wiring

### `(modaliser leader)`

Conveniences around `set-leader!` from `(modaliser dsl)`.

| Export | Signature |
|---|---|
| `set-leaders!` | `(set-leaders! [keyword value]...)` — both scopes in one call. |
| `set-global-leader!` | `(set-global-leader! keycode [keyword value]...)` |
| `set-local-leader!` | `(set-local-leader! keycode [keyword value]...)` |

See [dsl.md](dsl.md#set-leaders-keyword-value) for the keyword set.

```scheme
(import (modaliser leader))
(set-leaders! 'global-keycode F18 'local-keycode F17)
```

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

Settings group: edit `config.scm`, relaunch.

**Imports:**

```scheme
(import (prefix (modaliser settings-menu) settings:))
```

**Exports:**

| Export | Signature | Returns |
|---|---|---|
| `actions` | `(actions [keyword value]...)` | Group node — already decorated with `'key` and `'label`. Splice directly into a `define-tree`. |

**Options:**

| Keyword | Default | Description |
|---|---|---|
| `'key` | `","` | Leader key for the group. |
| `'label` | `"Settings"` | Overlay label. |
| `'config-path` | `"$HOME/.config/modaliser/config.scm"` | Path opened by Edit. |
| `'editor` | `"Zed"` | App used for Edit; falls back to the OS default opener. |
| `'extra-bindings` | `'()` | Additional DSL nodes appended after Reload. |

```scheme
(define-tree 'global
  (settings:actions)
  …)
```

---

## Window manager

### `(modaliser window-actions)`

High-level block constructors for the windows overlay. The bundled seed
uses `layout-block` + `list-block` together inside a single `(overlay
…)` to produce the canonical Windows view.

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
Override `.chip` / `.chip.faded` in `~/.config/modaliser/overlay.css` to
customise; relaunch picks up the changes.

```scheme
(key "w" "Windows"
  (overlay
    (window:layout-block
      (("d" "f" "g"))
      (("D" "F" "G") ("C" "V" "B"))
      (("e" "e" #f))
      ((#f "t" "t"))
      (("m"))
      (center "c"))
    (key "s" "Select Window"
         (selector 'prompt "Select window by name…"
                   'source list-windows
                   'on-select focus-window))
    (key "r" "Restore" (λ () (restore-window)))
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

(Native library — exact surface is implemented in Swift. See the source
under `Sources/Modaliser/` for the canonical list.)

---

## Per-app trees

### `(modaliser apps safari)`

Minimal Safari tree (Tabs, Browser).

**Imports:**

```scheme
(import (prefix (modaliser apps safari) safari:))
```

**Exports:**

| Export | Signature | Description |
|---|---|---|
| `tree` | `(tree [keyword value]...)` | List of nodes — splice into your own `(define-tree 'com.apple.Safari …)`. |
| `register!` | `(register! [keyword value]...)` | Calls `(define-tree 'com.apple.Safari (tree opts…))`. |

**Options:**

| Keyword | Default | Description |
|---|---|---|
| `'extra-bindings` | `'()` | Additional DSL nodes appended after the defaults. |

```scheme
(safari:register!)                                  ; defaults

(safari:register!
  'extra-bindings (list (key "/" "Search"
                          (λ () (send-keystroke '(cmd) "f")))))
```

### `(modaliser apps chrome)`

Same shape as `(modaliser apps safari)`. Registers under
`'com.google.Chrome`. Bindings: same tabs + browser groups.

```scheme
(import (prefix (modaliser apps chrome) chrome:))
(chrome:register!)
```

### `(modaliser apps iterm)`

iTerm dynamic-pane tree, sticky focus mode, and context-suffix handler.
More involved than safari/chrome because the tree is rebuilt on every
leader press to track the live pane layout.

**Imports:**

```scheme
(import (prefix (modaliser apps iterm) iterm:))
```

**Exports:**

| Export | Description |
|---|---|
| `register!` | One-stop convenience — rebuilds the iTerm tree, registers the sticky focus mode, installs the context-suffix handler. Pass `'install-context-suffix? #f` if you compose your own handler. |
| `rebuild-tree!` | Rebuild and re-register the `'com.googlecode.iterm2` tree from the current pane layout. Called per leader press by the context-suffix handler. |
| `focus-mode-register!` | Register the sticky `'iterm-panes-focus` mode. |
| `focus-mode-tree` | The bindings inside the sticky mode (hjkl Cmd+Alt focus moves). Splice into your own custom mode if you need a different sticky-id. |
| `context-suffix-handler` | The bundle-id → variant suffix function (`"/nvim"`, `"/zellij"`, `"/zellij+nvim"`). Install via `(set-local-context-suffix! …)` from `(modaliser event-dispatch)`. |
| `default-pane-labels` | `("1" "2" … "9" "0")` — default pane-label list. |

**`register!` / `rebuild-tree!` options:**

| Keyword | Default | Description |
|---|---|---|
| `'pane-labels` | `("1"…"9" "0")` | Labels assigned to panes in walk order. |
| `'pane-range-label` | `"Focus Pane <n>"` | Label for the auto-generated digit range. |
| `'sticky-mode-id` | `'iterm-panes-focus` | The mode-id of the sticky focus tree. |
| `'install-context-suffix?` | `#t` | (`register!` only) Whether to install the context-suffix handler. |

Pane-chip styling is no longer threaded through the registration. The
chips read from the same `.chip` CSS rule the window-list block uses;
edit `~/.config/modaliser/overlay.css` to customise.

```scheme
(iterm:register!)
```

The transient iTerm tree gets `c` (Copy Mode), `z` (Toggle Zoom), a
`(category "Focus" …)` wrapping the four hjkl focus moves (each
carries `'sticky-target 'iterm-panes-focus` so the first press lands
the user in the sticky mode), and an `x` split subgroup. The
`category` is rendered as a labelled column but stays transparent for
dispatch, so the keys still fire as direct children of the tree. The sticky focus mode (`'iterm-panes-focus`) holds only the
four hjkl Cmd+Alt focus moves and uses `'exit-on-unknown #t` so typing
any non-binding key returns control to iTerm.

---

## Blocks

Block constructors return alist specs (`'type SYM 'block-children (…)
…`) consumed by the block-list renderer. The full protocol is
documented in [renderer-protocol.md](renderer-protocol.md).

### `(modaliser blocks which-key)`

Already covered in [dsl.md](dsl.md#which-key-block-children) —
`which-key-block` is exposed there because it's the most common block
form. The library is auto-loaded transitively via `(modaliser dsl)`.

| Export | Signature |
|---|---|
| `which-key-block` | `(which-key-block . children)` |

### `(modaliser blocks window-list)`

Low-level window-list block. The high-level wrapper is
`(window:list-block …)` from `(modaliser window-actions)`; reach for
the lower-level form only when composing a custom block.

| Export | Description |
|---|---|
| `make-window-list-block` | `(make-window-list-block [keyword value]...)` — accepts `'chips? #t` to enable chip painting. Returns a block spec. |
| `window-list-current-labels` | The label sequence the last render painted (for custom dispatch handlers). |
| `window-list-current-targets` | Alist of `label → window` from the last render. |

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
| `read-file-text` | Read a file's contents into a string. |
| `log` | Append a line to the Modaliser log. |

### `(modaliser keymap)`

Modifier predicates for keystroke handlers and AX listeners.

| Export | Returns |
|---|---|
| `has-cmd?`, `has-shift?`, `has-alt?`, `has-ctrl?` | Boolean predicates over the modifier mask integer. |

### `(modaliser theming)`

Resolves the live `.chip` / `.chip.faded` CSS rules to a concrete alist
of pixel/colour values. Used by `(modaliser blocks window-list)` and
`(modaliser apps iterm)` at chip-paint time so chip styling tracks
whatever the user puts in `~/.config/modaliser/overlay.css`.

| Export | Signature | Description |
|---|---|---|
| `current-chip-theme` | `(current-chip-theme [variant])` | `variant` is `'normal` (default) or `'faded`. Returns an alist with keys `color`, `background`, `font-size`, `padding`, `corner-radius`, `border-width`, `border-color`, `offset-x-frac`, `offset-y-frac`. Colours are hex (`#rrggbb` / `#rrggbbaa`); numeric values are bare ints/floats. |

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

Terminal-introspection helpers used by `iterm`'s context-suffix
handler. Notable export: `focused-terminal-foreground-command` — the
command line of the foregrounded process in the focused terminal pane.

### `(modaliser event-dispatch)`

| Export | Description |
|---|---|
| `set-local-context-suffix!` | Install a `(lambda (bundle-id) …)` that returns a variant suffix (e.g. `"/nvim"`) to refine the dispatched scope. |

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
| `(modaliser input)` | Keystroke synthesis: `send-keystroke`. |
| `(modaliser shell)` | Shell execution: `run-shell`, `modaliser-tool-path`. |
| `(modaliser pasteboard)` | Clipboard: `set-clipboard!`, `read-clipboard`. |
| `(modaliser http)` | HTTP requests used by web-search. |
| `(modaliser lifecycle)` | `relaunch!`, `after-delay`. |
| `(modaliser accessibility)` | AX tree introspection used by ax-hints. |
| `(modaliser hints)` | On-screen hint chips: `hints-show`, `hints-hide`. |
| `(modaliser fuzzy)` | Fuzzy matching engine used by the chooser. |
| `(modaliser clipboard-history)` | Clipboard history accessor for the chooser. |
| `(modaliser webview)` | WebView management for the overlay/chooser panels. |
| `(modaliser dom)` | DOM push-update helpers used by `ui/overlay.scm`. |
| `(modaliser library-path)` | `prepend-library-path!`. |

Canonical reference: the Swift sources under `Sources/Modaliser/`.

See also: [portability.md](portability.md) for which libraries are
pure-Scheme (portable) vs. native (host-specific).
