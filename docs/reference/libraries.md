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
| `actions` | `(actions [keyword value]...)` | Group node — already decorated with `'key` and `'label`. Drop loose into a `screen` body (renders bare), or splice into a `(panel …)`. |

**Options:**

| Keyword | Default | Description |
|---|---|---|
| `'key` | `","` | Leader key for the group. |
| `'label` | `"Settings"` | Overlay label. |
| `'config-path` | `"$HOME/.config/modaliser/config.scm"` | Path opened by Edit. |
| `'editor` | `"Zed"` | App used for Edit; falls back to the OS default opener. |
| `'extra-bindings` | `'()` | Additional DSL nodes appended after Reload. |

```scheme
(screen 'global
  (settings:actions)   ; loose — renders bare in the loose region
  …)
```

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
| `display-list-block` | `(display-list-block 'chips? #t ['labels '(…)] ['corner 'top-right])` | Display-chip block with move/focus dispatch keys lifted. |
| `move-focused-window-to-display` | `(move-focused-window-to-display id)` | Proportional move of the focused window to display `id`. |
| `remap-frame` | `(remap-frame win src tgt)` | Pure: `(newX newY newW newH)` for the proportional remap (exported for tests). |

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
| `tree` | `(tree [keyword value]...)` | List of nodes — splice into a `(panel …)` of your own `(screen 'com.apple.Safari …)`. |
| `register!` | `(register! [keyword value]...)` | Calls `(screen 'com.apple.Safari (tree opts…))`. |

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

iTerm dynamic-pane tree, Walk focus mode, and context-suffix handler.
More involved than safari/chrome because the tree is rebuilt on every
leader press to track the live pane layout.

**Imports:**

```scheme
(import (prefix (modaliser apps iterm) iterm:))
```

**Exports:**

| Export | Description |
|---|---|
| `register!` | One-stop convenience — rebuilds the iTerm tree, registers the Walk focus mode, installs the context-suffix handler. Pass `'install-context-suffix? #f` if you compose your own handler. |
| `rebuild-tree!` | Rebuild and re-register the `'com.googlecode.iterm2` tree from the current pane layout. Called per leader press by the context-suffix handler. |
| `focus-mode-register!` | Register the `'iterm-panes-focus` Walk. |
| `focus-mode-tree` | The bindings inside the Walk (hjkl Cmd+Alt focus moves, each cycling via `'next 'self`). Splice into your own custom mode if you need a different focus-mode-id. |
| `context-suffix-handler` | The bundle-id → variant suffix function (`"/nvim"`, `"/zellij"`, `"/zellij+nvim"`). Install via `(set-local-context-suffix! …)` from `(modaliser event-dispatch)`. |
| `default-pane-labels` | `("1" "2" … "9" "0")` — default pane-label list. |
| `configure-entry` | A `(key …)` node for the one-shot **Configure iTerm** action (`Ctrl+Shift+I`). Splice into your iTerm tree; it auto-hides once iTerm is configured. |
| `iterm-configured?` | `#t` when iTerm already carries the eight provisioned key bindings. Drives `configure-entry`'s hidden state. |
| `current-iterm-provision-runner` | The test seam for the provisioning script: a `(lambda (shell-command callback) ...)` matching `run-shell-async`'s shape, mirroring `current-dialog-runner`. Default: the real `run-shell-async`. |

**`register!` / `rebuild-tree!` options:**

| Keyword | Default | Description |
|---|---|---|
| `'pane-labels` | `("1"…"9" "0")` | Labels assigned to panes in walk order. |
| `'pane-range-label` | `"Focus Pane <n>"` | Label for the auto-generated digit range. |
| `'focus-mode-id` | `'iterm-panes-focus` | The mode-id of the focus Walk. |
| `'install-context-suffix?` | `#t` | (`register!` only) Whether to install the context-suffix handler. |

Pane-chip styling is no longer threaded through the registration. The
chips read from the same `.chip` CSS rule the window-list block uses;
edit `~/.config/modaliser/theme.css` to customise.

```scheme
(iterm:register!)
```

The transient iTerm tree is a `(screen 'com.googlecode.iterm2 …)` whose
panels hold `c` (Copy Mode), `z` (Toggle Zoom), a `(panel "Focus" …)`
wrapping the four hjkl focus moves (each carries
`'next 'iterm-panes-focus` — a cross edge — so the first press lands the
user in the Walk), and an `x` split subgroup. The panel is rendered as a
banded card but stays transparent for dispatch, so the keys still fire as
direct children of the tree. The focus Walk (`'iterm-panes-focus`) holds
only the four hjkl Cmd+Alt focus moves, each carrying `'next 'self` (a
cyclic edge back to itself), and uses `'exit-on-unknown #t` so typing any
non-binding key returns control to iTerm.

**Configure iTerm.** The split, swap, copy-mode and zoom keys fire
iTerm keyboard shortcuts that are not all iTerm defaults. The
`configure-entry` node — bound to `Ctrl+Shift+I`, labelled "Configure
iTerm" — provisions them. It is hidden via `iterm-configured?`, so it
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

---

## Blocks

Block constructors return alist specs (`'type SYM 'block-children (…)
…`) consumed by the panel-grid renderer when embedded as a panel's live
list. The full protocol is documented in
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

Terminal-introspection helpers used by `iterm`'s context-suffix
handler. Notable export: `focused-terminal-foreground-command` — the
command line of the foregrounded process in the focused terminal pane.

### `(modaliser event-dispatch)`

| Export | Description |
|---|---|
| `set-local-context-suffix!` | Install a `(lambda (bundle-id) …)` that returns a variant suffix (e.g. `"/nvim"`) to refine the dispatched scope. |

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
| `current-dialog-runner` | parameter | The test seam: a `(lambda (shell-command callback) ...)` matching `run-shell-async`'s shape. Default: the real `run-shell-async`. |
| `sq-escape` | `(sq-escape str)` | POSIX single-quote escaping (the `'\''` idiom) for safe interpolation inside a single-quoted shell word — the one canonical implementation shared by callers with their own shell-quoting needs. |

Used by `(modaliser apps iterm)`, `(modaliser apps kitty)`, and
`(modaliser apps alacritty)` for their configure-entry confirm dialogs.

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
| `(modaliser input)` | Keystroke synthesis: `send-keystroke`, `send-key-down`, `send-key-up`. |
| `(modaliser shell)` | Shell execution: `run-shell`, `run-shell-async` (non-blocking; ADR-0014), `modaliser-tool-path`. |
| `(modaliser pasteboard)` | Clipboard: `set-clipboard!`, `read-clipboard`. |
| `(modaliser http)` | HTTP requests used by web-search. |
| `(modaliser lifecycle)` | `relaunch!`, `after-delay`. |
| `(modaliser accessibility)` | AX tree introspection used by ax-hints. |
| `(modaliser hints)` | On-screen hint chips, keyed by group: `hints-show`, `hints-show-in`, `hints-hide`, `hints-hide-in`. |
| `(modaliser fuzzy)` | Fuzzy matching engine used by the chooser. |
| `(modaliser clipboard-history)` | Clipboard history accessor for the chooser. |
| `(modaliser webview)` | WebView management for the overlay/chooser panels. |
| `(modaliser dom)` | DOM push-update helpers used by `ui/overlay.scm`. |
| `(modaliser library-path)` | `prepend-library-path!`. |

Canonical reference: the Swift sources under `Sources/Modaliser/`.

See also: [portability.md](portability.md) for which libraries are
pure-Scheme (portable) vs. native (host-specific).
