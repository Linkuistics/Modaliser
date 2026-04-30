# Host header for the overlay and chooser

## Problem

Modaliser supports guarded invocation: a single user can drive multiple
Modaliser instances simultaneously, including one running on a remote host
viewed through a remote-desktop client (Jump Desktop, etc.). When the
overlay or chooser appears, there is currently no visual cue identifying
which host it belongs to. A keystroke meant for the local Modaliser can
trigger the remote one (or vice versa) without the user noticing, because
both windows look identical.

A second, smaller issue: the breadcrumb header for an app-local tree shows
the bare bundle identifier (`com.apple.Safari`) instead of the user-visible
app name (`Safari`). This is hard to read and not what the user expects.

## Goals

1. Optionally identify the host an overlay/chooser belongs to with a
   user-configured name, prepended to the breadcrumb as the leftmost
   segment.
2. Optionally recolour the breadcrumb (background and foreground) to make
   the host distinction unmissable, e.g. red for production, green for
   local.
3. Replace the bundle ID in the breadcrumb with the resolved app display
   name.
4. Render variant trees (`com.googlecode.iterm2/nvim`) as separate
   breadcrumb segments (`iTerm > nvim`) instead of a single slash-joined
   string.
5. Make the chooser identify the host the same way the overlay does.

## User-facing API

A single new function in `core/state-machine.scm`, called from
`~/.config/modaliser/config.scm`:

```scheme
(set-host-header!
  'name       "my-server"      ;; required: any expression evaluating to a string
  'background "#7a1f3d"         ;; optional: any CSS colour value
  'foreground "#ffffff")        ;; optional: any CSS colour value
```

- `'name` is the only required keyword. Its value can be any Scheme
  expression — a literal, the result of `(run-shell "hostname -s")`,
  conditional logic, etc. Because `set-host-header!` is a regular function
  and the config is loaded once at startup, the expression is evaluated
  exactly once at the call site.
- `'background` and `'foreground` are passed through verbatim as CSS
  values — any valid CSS colour string works (`#rgb`, `#rrggbb`,
  `rgb(...)`, `rgba(...)`, named colours).
- If `set-host-header!` is never called, the breadcrumb behaves exactly as
  today: no host segment, no recolouring.

Conditionality is the user's job:

```scheme
(set-host-header!
  'name       (if (file-exists? "/etc/remote-marker")
                (run-shell "hostname -s")
                "local")
  'background "#7a1f3d"
  'foreground "#ffffff")
```

Re-calling `set-host-header!` overwrites the previous values (consistent
with `set-leader!`, `set-overlay-delay!`).

## Behavioural specification

### Breadcrumb composition

The breadcrumb root segments are computed at modal entry time as:

```
[host?]   +   [scope-segments]   +   [navigation-path]
```

where:

- `host?` is `host-header-name` if set, otherwise empty
- `scope-segments` for the global tree is `("Global")`
- `scope-segments` for an app-local tree is `(app-name)` or
  `(app-name variant)` if the registered scope contains a `/` suffix
- `app-name` is resolved at modal entry time via Launch Services. If
  unresolvable (uninstalled, malformed bundle ID), the bare bundle ID is
  used as the segment

Examples:

| Host set    | Scope                           | Path     | Breadcrumb                                |
|-------------|---------------------------------|----------|-------------------------------------------|
| no          | `global`                        | `()`     | `Global`                                  |
| no          | `global`                        | `(w)`    | `Global > w`                              |
| no          | `com.apple.Safari`              | `(t)`    | `Safari > t`                              |
| no          | `com.googlecode.iterm2/nvim`    | `(p h)`  | `iTerm > nvim > p > h`                    |
| `my-server` | `global`                        | `(w d)`  | `my-server > Global > w > d`              |
| `my-server` | `com.googlecode.iterm2/nvim`    | `(t n)`  | `my-server > iTerm > nvim > t > n`        |
| `my-server` | unresolvable bundle ID          | `()`     | `my-server > com.example.unknown`         |

### Colour application

When `'background` or `'foreground` is set, a `:root` block defining
`--color-host-bg` and/or `--color-host-fg` is injected into the WebView's
style block (in addition to `base.css` and any user `set-overlay-css!`
content). Both the overlay header and the chooser header reference these
variables with fallbacks:

```css
.overlay-header,
.chooser-header {
  background: var(--color-host-bg, transparent);
  color: var(--color-host-fg, var(--color-header));
}
```

When neither variable is defined, the fallbacks reproduce today's
appearance exactly. When one is set and not the other, only the
corresponding property changes.

### Chooser DOM

The chooser today renders `<div class="chooser-prompt">Find app…</div>`
above the search input. This is replaced with a `<header
class="chooser-header"><span class="breadcrumb">…</span></header>`
element using the same DOM structure as the overlay's header.

The chooser's existing `'prompt` field becomes the trailing segment of
the breadcrumb:

```
my-server > Global > Find app…
```

The chooser breadcrumb is set once at panel open and is not updated
afterwards (the chooser does not navigate the command tree).

### Resolution timing

App-name resolution happens at modal entry time, in
`compute-root-segments`, which is called by `modal-enter`. The result is
stored in a new `modal-root-segments` state variable in
`state-machine.scm` and consumed by both the overlay and the chooser
during rendering. One Launch Services lookup per leader press; no
per-keystroke or per-render cost.

The host name is resolved once at startup (in `set-host-header!`) and
cached in module-level state.

## Implementation outline

### Swift (1 file)

**`Sources/Modaliser/AppLibrary.swift`** — add one Procedure:

```swift
self.define(Procedure("app-display-name", appDisplayNameFunction))

/// (app-display-name bundle-id) → string or #f
private func appDisplayNameFunction(_ idExpr: Expr) throws -> Expr {
    let bundleId = try idExpr.asString()
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
        else { return .false }
    return .makeString(FileManager.default.displayName(atPath: url.path))
}
```

`FileManager.displayName(atPath:)` is preferred over reading
`CFBundleDisplayName` directly: it respects localization and the user's
"Show file extensions" setting.

### Scheme core (1 file)

**`Sources/Modaliser/Scheme/core/state-machine.scm`**:

- Three new state variables:
  ```scheme
  (define host-header-name #f)
  (define host-header-background #f)
  (define host-header-foreground #f)
  ```
- New `set-host-header!` taking `'name`, `'background`, `'foreground`
  keyword args (mirrors `set-leader!` keyword-arg parsing).
- New `host-header-css` helper returning the `:root { ... }` injection
  block, or `""` when no colours are set.
- Change `register-tree!`: store `(cons 'scope scope-str)` on the root
  node. Drop the `'label` field for root nodes (the `'label` on
  group/key/selector child nodes is unrelated and stays unchanged).
- New `modal-root-segments` state variable (a list of strings).
- New `compute-root-segments` and `resolve-app-segments` (the latter
  splits on `/`, calls `app-display-name`, falls back to the bundle ID).
- `modal-enter` reads `'scope` from the tree and assigns
  `modal-root-segments` accordingly. `modal-exit` resets it to `'()`.

`event-dispatch.scm` does not change. Storing the scope on the root node
means `make-leader-handler` does not need to plumb the matched scope-str
through.

### Scheme UI (3 files)

**`Sources/Modaliser/Scheme/ui/overlay.scm`**:

- `render-breadcrumb` signature changes from `(root-label path)` to
  `(root-segments path)`. The single-segment branch can be folded into
  the general case (`(append root-segments path)` then join with `>`).
- `render-overlay-body` uses `modal-root-segments` instead of
  `(node-label node)` for the root.
- `render-overlay-html` concatenates `(host-header-css)` after `base.css`
  in the style block.
- `push-overlay-update` builds a `rootSegments` JSON array (replacing the
  scalar `label` field) and includes it in the payload to `updateOverlay`.

**`Sources/Modaliser/Scheme/ui/overlay.js`**:

- `updateOverlay` replaces `data.label` with `data.rootSegments`. The
  breadcrumb HTML is built from `data.rootSegments.concat(data.path)`.

**`Sources/Modaliser/Scheme/ui/chooser.scm`**:

- In both `render-chooser-html` and `chooser-load-skeleton`, replace the
  `chooser-prompt` div with a `chooser-header` element containing a
  `breadcrumb` span. Segments are
  `(append modal-root-segments (list prompt))`.
- Both render functions concatenate `(host-header-css)` into the style
  block, parallel to overlay.scm.

### CSS (1 file)

**`Sources/Modaliser/Scheme/base.css`**:

- Add `.chooser-header` rules mirroring the existing `.overlay-header`
  block (border, padding, font sizing).
- Update both selectors to:
  ```css
  background: var(--color-host-bg, transparent);
  color: var(--color-host-fg, var(--color-header));
  ```
- Remove the existing `.chooser-prompt` rules (the element no longer
  exists).

### Config (1 file)

**`Sources/Modaliser/Scheme/default-config.scm`** — add a commented
example near `set-overlay-delay!`:

```scheme
;; Identify this host in the overlay/chooser when running multiple
;; Modaliser instances (e.g. local + remote desktop). Optional.
;; (set-host-header!
;;   'name       (run-shell "hostname -s")
;;   'background "#7a1f3d"
;;   'foreground "#ffffff")
```

## Testing

- **`Tests/ModaliserTests/AppLibraryTests.swift`** — `app-display-name`
  resolves a known bundle ID (`com.apple.Safari` or
  `com.apple.Finder`); returns `#f` for a bogus ID.
- **`Tests/ModaliserTests/OverlayRenderTests.swift`** — existing
  `"Global"` assertions continue to pass (host header is opt-in, off by
  default). New tests:
  - Breadcrumb with host set: `my-server > Global > w` appears in HTML
  - Variant tree segmentation: `iTerm > nvim` rendered as two segments
  - Colour CSS emission: `--color-host-bg` and `--color-host-fg`
    appear in the style block when colours are set, absent otherwise
  - Unresolvable bundle ID falls back to bundle ID
- **`Tests/ModaliserTests/ChooserRenderTests.swift`** — adapt any
  `chooser-prompt` assertions to `chooser-header` / `breadcrumb`. Add
  parallel host-header tests (host segment in chooser breadcrumb;
  prompt rendered as trailing segment).

## Non-goals

- **Dynamic host name.** The name is resolved once at startup. Changing
  it requires restarting Modaliser (consistent with the rest of config).
- **Per-tree colours.** The host colour is global; not configurable
  per-app.
- **Theme presets.** No built-in palette ("production", "staging");
  colours are raw CSS strings.
- **Hot reload.** No mechanism added; restart is the existing pattern.
