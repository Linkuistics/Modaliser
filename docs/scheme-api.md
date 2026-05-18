# Scheme API

Every bundled `(modaliser …)` library and native primitive, grouped by library, with signatures.

For DSL syntax and how to compose these into trees, see [Configuration](configuration.md). For library-system mechanics (lookup order, splitting configs) see [User libraries](user-libraries.md).

Libraries are imported R7RS-style:

```scheme
(import (modaliser dsl)
        (modaliser app)
        (modaliser window))
```

The bundled `(modaliser apps …)` and a handful of helper libraries use bare-name exports (`register!`, `actions`, `tree`, …); import them with `(prefix …)` to disambiguate:

```scheme
(import (prefix (modaliser apps iterm) iterm:))
(iterm:register!)
```

---

## DSL — `(modaliser dsl)`

The surface user configs spell against.

| Function | Description |
|----------|-------------|
| `(key k label action [keyword value]...)` | Define a command. Optional trailing `'sticky-target MODE-ID`. |
| `(key-range display-key label keys action-fn)` | Bind multiple keys to one shared action, displayed as a single overlay row. `action-fn` receives the matched key. |
| `(group k label [keyword value]... children...)` | Define a group. See [Configuration](configuration.md#group--define-tree-keywords) for keyword options. |
| `(category label children...)` | Group children under a render-time label for the which-key block. Transparent to dispatch — keys inside behave identically to direct group children. |
| `(selector k label props...)` | Define a selector. |
| `(action name props...)` | Define a selector action. |
| `(define-tree scope [keyword value]... children...)` | Register a command tree. |
| `(set-leader! [mode] keycode [keyword value]...)` | Set leader key for a mode (older single-leader API). |
| `(set-host-header! [keyword value]...)` | Configure the per-overlay machine-name banner (re-exported from `(modaliser state-machine)`). |
| `(set-overlay-delay! seconds)` | How long to wait before showing the overlay (re-exported from `(modaliser state-machine)`). |
| `(set-overlay-aspect-ratio! ratio)` | Constrain overlay aspect ratio (re-exported from `(modaliser state-machine)`). |
| `(modifier-symbols->mask syms)` | Convert `'(shift ctrl)` to the bitmask `set-leader!` expects. |

Key code constants exported from `(modaliser keyboard)`: `F17`, `F18`, `F19`, `F20`, `ESCAPE`, `DELETE`, `RETURN`, `TAB`, `SPACE`, `UP`, `DOWN`, `LEFT`, `RIGHT`.

## Leader — `(modaliser leader)`

Newer leader configuration that handles both leaders in one call.

| Function | Description |
|----------|-------------|
| `(set-global-leader! [keyword value]...)` | Configure global leader. |
| `(set-local-leader! [keyword value]...)` | Configure local leader. |
| `(set-leaders! [keyword value]...)` | Configure both: `'global-keycode`, `'local-keycode`, `'modifiers`, `'arm-when-frontmost`. |

## State machine — `(modaliser state-machine)`

Modal navigation predicates and introspection.

| Function | Description |
|----------|-------------|
| `(lookup-tree scope)` | Fetch the registered command tree for `scope`. |
| `(modal-active?)` | `#t` while the modal is on. |
| `(modal-current-node)` | The node the user is currently parked at. |
| `(modal-path)` | List of nodes from root to current. |
| `command?`, `group?`, `selector?`, `range-command?` | Node-kind predicates. |
| `(set-host-header! …)`, `(set-overlay-delay! …)`, `(set-overlay-aspect-ratio! …)` | Overlay configuration (re-exported from `(modaliser dsl)`). |

## Event dispatch — `(modaliser event-dispatch)`

| Function | Description |
|----------|-------------|
| `(set-local-context-suffix! proc)` | Install a per-app context handler invoked on every local-leader press. `proc` receives the bundle ID and may rebuild app-specific trees in response. |

## Util — `(modaliser util)`

| Function | Description |
|----------|-------------|
| `(alist-ref alist key default)` | Look up `key` in `alist` or return `default`. |
| `(props->alist . args)` | Convert keyword/value pairs to an alist. |
| `(string-join strs separator)` | Concatenate `strs` with `separator` between each. |
| `(read-file-text path)` | Read a file's contents as a string. |
| `(log fmt . args)` | Format-and-print to Console for debugging. |

## Keymap — `(modaliser keymap)`

| Function | Description |
|----------|-------------|
| `has-cmd?`, `has-shift?`, `has-alt?`, `has-ctrl?` | Predicates on a modifier mask. |
| `MOD-CMD`, `MOD-SHIFT`, `MOD-ALT`, `MOD-CTRL` | Modifier bit constants. |

## App management — `(modaliser app)`

| Function | Description |
|----------|-------------|
| `(find-installed-apps)` | Scan installed apps via Spotlight, returns list of alists. |
| `(activate-app alist)` | Launch/focus app from choice alist. |
| `(launch-app name)` | Launch/focus app by name or bundle ID. |
| `(reveal-in-finder alist)` | Show in Finder from choice alist. |
| `(open-with app-name path)` | Open file with specific app. |
| `(open-url url-string)` | Open URL in default handler. |
| `(focused-app-bundle-id)` | Get bundle ID of the frontmost app. |
| `(index-files root-paths)` | Scan directories, returns list of alists with text/path/kind. |

## Window management — `(modaliser window)`

| Function | Description |
|----------|-------------|
| `(list-windows)` | List visible windows as alists, sorted by focus recency. |
| `(list-current-space-windows)` | List on-screen windows on the current space, sorted by (y, x). |
| `(focus-window alist)` | Focus a window from choice alist. |
| `(center-window)` | Center the focused window. |
| `(move-window x y w h)` | Move to unit rect (0.0–1.0 fractions of screen). |
| `(toggle-fullscreen)` | Toggle fullscreen on focused window. |
| `(restore-window)` | Restore to saved frame. |
| `(primary-screen-size)` | `((w . W) (h . H))` for the primary display in AX coordinates. |
| `(window-visible-at? wid pid x y)` | `#t` if the window owned by `(wid, pid)` is the topmost regular app window at screen point `(x, y)`. Skips translucent overlays. |

## Window actions — `(modaliser window-actions)`

Bare-name exports — import with `(prefix … window:)`.

| Function | Description |
|----------|-------------|
| `(actions [keyword value]...)` | Build the windows group with `'renderer 'blocks` and three stacked blocks: `window-diagram` + `which-key` + `window-list` (with chip-painting). Options: `'key`, `'label`, `'panels`, `'chip-options`. |
| `(register! [keyword value]...)` | Register the actions tree under the given scope (`'tree-scope`, default `'global`). |
| `(divisions matrix)` | Build a `(panel-spec key-node-list)` pair from a matrix of key strings. |
| `(center-panel key)` | Build the center-panel pair for the given key. |

See [Configuration](configuration.md#windows-diagram-overlay) for the full layout walkthrough.

## Apps — `(modaliser apps safari)`, `chrome`, `iterm`

Bare-name exports — import with `(prefix … safari:)` etc.

| Function | Description |
|----------|-------------|
| `(tree [keyword value]...)` | Build the per-app tree node. |
| `(register! [keyword value]...)` | Build + register under the appropriate bundle-ID scope. |
| `(iterm:focus-mode-register!)` | (iTerm only) Register the sticky pane-focus mode for hjkl navigation. |
| `(iterm:context-suffix-handler)` | (iTerm only) Local-context suffix handler that rebuilds the pane tree on every leader press. |

Each app library accepts `'extra-bindings` for layering extra `(key …)` nodes onto the default tree.

## Launchers — `(modaliser launchers)`

| Function | Description |
|----------|-------------|
| `(find-application [keyword value]...)` | Build a selector node for installed-apps fuzzy search. |
| `(find-file [keyword value]...)` | Build a selector node for home-dir file fuzzy search. |

## Web search — `(modaliser web-search)`

| Function | Description |
|----------|-------------|
| `(google [keyword value]...)` | Build a Google search selector (autocomplete + browser open). Default key `"g"`. |
| `(web-search-handler query)` | Dynamic-search callback for Google autocomplete (lower-level). |
| `(web-search-on-select item)` | Open the selected search result in the default browser. |
| `(google-suggest-url query)` | Build Google Suggest API URL. |
| `(google-search-url query)` | Build Google search URL. |
| `(parse-google-suggestions response)` | Parse Google Suggest JSON into a list of strings. |
| `(build-web-search-results query suggestions)` | Build chooser items with pinned search item. |
| `(url-encode str)` | RFC 3986 percent-encoding with UTF-8 support. |

## Space switching — `(modaliser space-switching)`

| Function | Description |
|----------|-------------|
| `(switch-actions [keyword value]...)` | Build a group node binding keys to Mission Control space switches. |
| `(register! [keyword value]...)` | Build + register. |

## Settings menu — `(modaliser settings-menu)`

| Function | Description |
|----------|-------------|
| `(actions [keyword value]...)` | Build the settings group (Edit config, Relaunch, Quit). Default key `","`. |

## Terminal — `(modaliser terminal)`

| Function | Description |
|----------|-------------|
| `(focused-terminal-foreground-command)` | Best-effort guess at the command running in the focused terminal pane. |

## Input — `(modaliser input)`

| Function | Description |
|----------|-------------|
| `(send-keystroke mods key)` | Emit a keystroke. mods: `'(cmd alt shift ctrl)`, key: `"t"`, `"left"`, etc. |

## HTTP — `(modaliser http)`

| Function | Description |
|----------|-------------|
| `(http-get url callback)` | Async HTTP GET. Calls `(callback response-string)` on success, `(callback #f)` on error. |

## Shell — `(modaliser shell)`

| Function | Description |
|----------|-------------|
| `(run-shell command)` | Run via `/bin/zsh -c`, returns stdout. |
| `(run-shell-async command callback)` | Run in background, callback receives `(exit-code stdout stderr)`. |

## Clipboard — `(modaliser pasteboard)`

| Function | Description |
|----------|-------------|
| `(get-clipboard)` | Read clipboard as string. |
| `(set-clipboard! text)` | Write string to clipboard. |

## Clipboard history — `(modaliser clipboard-history)`

The Swift primitives for clipboard history exist but the clipboard monitor is not yet started at runtime. See TODO.md for wiring instructions.

| Function | Description |
|----------|-------------|
| `(get-clipboard-history)` | Get clipboard history entries as alists. |
| `(clear-clipboard-history!)` | Clear all history. |
| `(restore-clipboard-entry! id)` | Restore a history entry to the clipboard. |
| `(set-clipboard-exclude! bundle-ids)` | Exclude apps from clipboard monitoring. |
| `(set-clipboard-history-limit! n)` | Set max history entries. |

## Lifecycle — `(modaliser lifecycle)`

| Function | Description |
|----------|-------------|
| `(set-activation-policy! policy)` | Set app activation policy (`'regular`, `'accessory`, `'prohibited`). |
| `(create-status-item! title menu-items)` | Create a menu bar item. |
| `(ensure-permissions! perms)` | Block until each TCC permission in the list is granted. Pollable permissions (e.g. `accessibility`) surface via an in-app onboarding panel; cached ones (`screen-recording`) hand off to macOS's native prompt. |
| `(relaunch!)` | Relaunch the application. |
| `(quit!)` | Quit the application. |
| `(after-delay seconds callback)` | Call `(callback)` on the main thread after a delay. |

## WebView — `(modaliser webview)`

| Function | Description |
|----------|-------------|
| `(webview-create id options)` | Create a WKWebView-backed NSPanel. |
| `(webview-close id)` | Close and destroy a panel. |
| `(webview-set-html! id html)` | Set full HTML content. |
| `(webview-eval id js)` | Evaluate JavaScript in a panel. |
| `(webview-on-message id handler)` | Register a message handler for JS postMessage. |
| `(webview-set-style! id css)` | Inject or replace a dynamic style block. |

## Hints — `(modaliser hints)`

Generic on-screen labels drawn at arbitrary screen rectangles. Used by iTerm pane chips and the windows-diagram window selector; the library itself is app-agnostic and reusable for any future "pick one of these visible targets" flow.

| Function | Description |
|----------|-------------|
| `(hints-show hint-list)` | Open one transparent floating panel per entry. Each entry is an alist with required `'label`, `'x`, `'y`, `'w`, `'h` (AX coords, top-left origin) and optional `'color`, `'background`, `'font-size`, `'padding`, `'corner-radius`, `'border-width`, `'border-color`. |
| `(hints-hide)` | Close all hint panels. |

## Accessibility — `(modaliser accessibility)`

Wrapper around the macOS Accessibility API for cases where Scheme needs to round-trip element references (e.g. "find these elements, then later click one"). Element pointers are stored in a Swift-side cache keyed by integer handle; each `ax-find-elements` call invalidates prior handles.

| Function | Description |
|----------|-------------|
| `(ax-find-elements bundle-id role)` | Walk the AX tree of `bundle-id`'s focused window. Returns a list of alists `((handle . N) (x . N) (y . N) (w . N) (h . N))` for every descendant whose AXRole equals `role`, sorted top-to-bottom then left-to-right. Returns `()` if the app isn't running. |
| `(ax-click-handle handle)` | Activate the handle's owning app and synthesize a left-click at the centre of the handle's frame. Cursor position is saved and warped back. No-op for stale handles. |

## AX hint flows — `(modaliser ax-hints)`

Generic primitives for "see a chip, type a letter, focus that thing" UX over any AX-introspectable app — used by `(modaliser apps iterm)` and reusable for any other app. End-to-end pattern in [Configuration → AX hint flows](configuration.md#ax-hint-flows).

| Function / Variable | Description |
|---------------------|-------------|
| `(ax-find-labelled bundle-id role labels)` | Probe AX for elements of `role` inside `bundle-id`'s focused window, pair them with `labels` in reading order. Returns `((label . elem-alist) ...)`. Truncates at the shorter of the two lists. |
| `(ax-target-bindings labelled-elements label-prefix action-fn)` | Convert that list into `(key ...)` entries. Each fires `(action-fn handle)` where handle is the AX handle from the elem alist. Display label = `label-prefix ++ label`. |
| `(ax-target-hints labelled-elements opts)` | Convert that list into the alist shape `hints-show` consumes. `opts` is an alist of chip appearance (offset, size, colour, padding, border) — see `default-hint-options` for the shape. |
| `default-hint-options` | Sensible smallish defaults. Override per-tree by passing your own opts alist. |

## Fuzzy matching — `(modaliser fuzzy)`

| Function | Description |
|----------|-------------|
| `(fuzzy-match query target)` | Match query against target, returns `(score (indices...))` or `#f`. |
| `(fuzzy-filter query texts)` | Filter and rank a list of strings by fuzzy match score. |

## Library path — `(modaliser library-path)`

| Function | Description |
|----------|-------------|
| `(prepend-library-path! "/abs/path")` | Prepend a directory to the library lookup path so `(import …)` finds `.sld` files under it. Non-existent paths are silently skipped. |

## Diagram panel — `(modaliser diagram-panel)`

Lower-level primitives behind `(modaliser window-actions)`'s panel layouts. Most users go through `window:divisions` instead.

| Function | Description |
|----------|-------------|
| `(make-grid-panel-spec cols rows cells)` | Build a grid panel-spec. |
| `(make-center-panel-spec key)` | Build a center panel-spec (outer frame + inward arrows + key glyph). |
| `(make-fill-panel-spec key)` | Build a single white-filled cell panel-spec. |
| `(parse-matrix matrix)` | Walk an array-of-arrays of key strings (or `#f` for empty cells), validate, emit a list of cell alists. |

## Block libraries

A group declared with `'renderer 'blocks 'blocks (list block1 block2 …)` stacks each block top-to-bottom in the overlay. Each block ships as a `.sld + .js + .css` trio under `lib/modaliser/blocks/<type>/`; the `.sld` exports the constructor and registers the JS+CSS via `add-overlay-asset-file!`. The blocks-renderer dispatcher in `ui/overlay.scm` serialises each spec to JSON and routes it to `window.overlayBlockRenderers[type]` on the JS side.

A block spec is an alist with:
- `'type` (symbol) — block type tag.
- `'consumed-keys` (list of strings, optional) — keys this block paints; the which-key block excludes these from its rendered entries.
- `'on-render-fn` (thunk, optional) — runs before serialisation on every render; used by `window-list` to refresh the chip snapshot.
- block-specific fields (e.g. `'panels` on window-diagram, `'windows` on window-list).

Procedure-valued keys (like `'on-render-fn`) are stripped from the JSON automatically.

### `(modaliser blocks window-diagram)`

| Function | Description |
|----------|-------------|
| `(make-window-diagram-block panel-specs)` | Build a window-diagram block spec from a list of panel-spec alists (grid/center/fill — same shape `(modaliser diagram-panel)` produces). Sets `'consumed-keys` from the panel cells so which-key skips them. |

### `(modaliser blocks which-key)`

| Function | Description |
|----------|-------------|
| `(make-which-key-block)` | Build a which-key block spec. The payload is derived at render time from the parent group's children, partitioned into misc/category segments preserving source order, excluding keys in any sibling block's `'consumed-keys`. |

### `(modaliser blocks window-list)`

| Function | Description |
|----------|-------------|
| `(make-window-list-block [keyword value]...)` | Build a window-list block spec. Options: `'show-chips BOOL` (default `#f`; when `#t`, attaches an `on-render-fn` that paints labelled chips on each window and snapshots the window list into the rendered payload), `'chip-options ALIST` (merged with defaults — `font-size`, `padding`, `color`, `background`, `faded-background`, `offset-x-frac`, `offset-y-frac`, …). |
| `(window-list-current-labels)` | The list of digit labels assigned to windows by the most recent render. |
| `(window-list-current-targets)` | The current `((label . window-alist) …)` mapping. `window-actions`'s `focus-by-digit` reads this to resolve a pressed digit to its window. |

## Overlay assets — `(modaliser overlay-assets)`

| Function | Description |
|----------|-------------|
| `(add-overlay-asset! kind body)` | Push a CSS or JS string into the overlay's asset registry. `kind` is `'css` or `'js`. |
| `(add-overlay-asset-file! kind relative-path)` | Like the above but reads the asset from a file beside the importing library. |

## Dynamic chooser

Surface for selector callbacks to push results into an open chooser.

| Function | Description |
|----------|-------------|
| `(chooser-push-results items)` | Push a list of item alists to the open chooser. Items received before the chooser opens are queued. |

