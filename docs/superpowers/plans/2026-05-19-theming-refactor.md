# Theming refactor — chip styling moves to CSS variables

**Status:** Drafted; awaiting fresh-session execution.

## Goal

Unify the two parallel chip-styling surfaces (the inline `'chip-options`
alist on `window-list` blocks and the inline `'hint-options` alist on
`apps/iterm`) into a single CSS-variable-driven theme. After this
slice, users theme the whole UI through CSS (`set-overlay-css!` + a
small handful of `--chip-*` variables) instead of threading a colour
through three callsites with different keyword names.

This is the slice flagged as a non-goal of the docs restructure
(`docs/superpowers/plans/2026-05-19-docs-restructure.md` § "Non-goals")
and called out in `docs/reference/theming.md` as a future change.

## Current state (so the refactor doesn't re-mislead)

The chip painter is native: `Sources/Modaliser/HintsLibrary.swift` draws
each chip as its own `NSPanel` with an `NSView` + `NSTextField`. It
takes a list of fully-resolved alists from Scheme. Recognised
per-chip keys today: `label`, `x`, `y`, `w`, `h`, `color`,
`background`, `font-size`, `padding`, `corner-radius`, `border-width`,
`border-color`.

The Scheme-side block constructors hold the per-style defaults and
merge user overrides:

- `Sources/Modaliser/Scheme/lib/modaliser/blocks/window-list.sld:45-55`
  defines `default-chip-options`. `make-window-list-block` reads
  `'chip-options` from the user's opts, merges, and threads through
  `paint-and-snapshot!` to `(hints-show …)`.
- `Sources/Modaliser/Scheme/lib/modaliser/apps/iterm.sld:148-159`
  duplicates the same defaults (via `merge-hint-options`) and reads
  `'hint-options` from `rebuild-tree!` / `register!` opts.

Seed config callsites that thread `the-color` through:

- `Sources/Modaliser/Scheme/default-config.scm:101` —
  `(window:list-block 'chip-options ((background . ,the-color)))`.
- `Sources/Modaliser/Scheme/default-config.scm:139` —
  `(iterm:register! 'hint-options ((background . ,the-color)))`.

Both reach the same colour through different keyword names — exactly
what the refactor fixes.

CSS context: `base.css:7-28` already defines a `--color-*` vocabulary
consumed by the overlay and chooser via `var(…)`. Chip styling has no
CSS today.

## Target surface

CSS *is* the authoring surface, and the user authors it in a real
`.css` file — not as a string passed to a Scheme function. Modaliser
auto-loads `~/.config/modaliser/overlay.css` at startup (if present)
and concatenates it into the overlay's CSS stack at the same slot the
current `set-overlay-css!` injection fills (after `base.css` and block
CSS, before `host-header-css`).

`set-overlay-css!` is **deleted**. The migration is: paste the string
content into `~/.config/modaliser/overlay.css`. No backwards-compat
shim — the symbol becomes unbound, configs that referenced it raise
on load.

A transient hidden probe WebView resolves the resulting CSS to
concrete chip values on demand, and the chip painter reads them from a
Scheme cache. The probe only runs once per boot — relaunching is how
you reload theme changes, same as every other config edit (per
`feedback_no_in_place_reload`).

### How the user authors chip styling

In `base.css` (defaults the user inherits):

```css
.chip {
  color: var(--color-host-fg, white);
  background: var(--color-host-bg, dodgerblue);
  font-size: 56px;
  padding: 16px;
  border: 1px solid black;
  border-radius: 8px;
}

.chip.faded {
  background: #6f8baa;
}

:root {
  --chip-offset-x-frac: 0.02;
  --chip-offset-y-frac: 0.02;
}
```

The `var(--color-host-bg, …)` fallback means **chips automatically
inherit the host-header theme** when `(set-host-header! 'background
…)` is called — no extra CSS required for the common case.

The user override path: create `~/.config/modaliser/overlay.css`:

```css
.chip {
  background: tomato;
  border-radius: 12px;
  font-size: 48px;
}

.chip.faded {
  background: #555;
}
```

Edit, relaunch, done. The editor gets syntax highlighting and linting
for free.

### The probe WebView

At launch — after `root.scm` has included the user's `config.scm` and
slurped `overlay.css` — Modaliser spawns a hidden probe WebView using
the existing `webview-create` / `webview-set-html!` /
`webview-on-message` bindings:

- Panel positioned far offscreen (e.g. `(-10000, -10000)`), 1×1,
  transparent, no shadow. WKWebView still runs layout and JS when
  the panel is offscreen.
- HTML content is `<style>{all CSS layers concatenated}</style>` plus
  two probe divs: `<div class="chip" id="probe-normal">` and
  `<div class="chip faded" id="probe-faded">`.
- An inline `<script>` reads `getComputedStyle(...)` for each probe,
  pulls `--chip-offset-{x,y}-frac` via `getPropertyValue`, converts
  computed colours to hex (so `HintsLibrary.swift`'s existing colour
  parser handles them without changes), strips `"px"` from lengths,
  and posts the resolved JSON back via
  `window.webkit.messageHandlers.modaliser.postMessage(…)`.
- The Scheme `webview-on-message` handler parses the JSON, caches it
  in a cell, then closes the probe panel.

The probe runs **once per boot**. There is no in-process refresh API:
relaunch is the refresh, same as every other config change in
Modaliser. The cell is seeded with hard-coded defaults matching
`base.css`'s `.chip` declarations so `(current-chip-theme)` calls
before the async probe completes return sane values (no colour pop on
the very first chip paint).

### Resolved theme shape

The cache holds a normal/faded pair:

```scheme
((normal . ((color . "#ffffff")
            (background . "#1e90ff")
            (font-size . 56)
            (padding . 16)
            (corner-radius . 8)
            (border-width . 1)
            (border-color . "#000000")
            (offset-x-frac . 0.02)
            (offset-y-frac . 0.02)))
 (faded  . ((... same shape, different background ...))))
```

Numeric values arrive as numbers (parsed from `"56px"` etc. on the
JS side). Colour values arrive as hex (`#rrggbb` or `#rrggbbaa`),
matching the format `HintsLibrary.swift` already parses.

### Scheme accessor

A single read accessor — the entire public Scheme surface for chip
theming:

```scheme
(current-chip-theme [variant]) → alist
```

Where `variant` is `'normal` (default) or `'faded`. Returns the cached
alist for that variant. Before the probe completes, returns the
seeded defaults; after, returns the resolved values.

No write API. No refresh API. Edit `overlay.css`, relaunch.

### What block constructors lose

- `make-window-list-block` no longer reads `'chip-options`. A user
  passing the keyword raises an `error` with a one-line migration
  message pointing at the new `.chip` CSS surface. The block enables
  chip painting iff a new `'chips? #t` keyword is set (replaces
  today's "presence of `'chip-options` enables chips" implicit
  toggle).
- `iterm:register!` / `rebuild-tree!` no longer read `'hint-options`.
  Same migration error.
- `default-chip-options` and `merge-chip-options` are deleted from
  `window-list.sld`; `default-chip-options` and `merge-hint-options`
  are deleted from `iterm.sld`. The single source of truth becomes
  the probe cache.
- `paint-and-snapshot!` (and the iTerm `on-enter` `hints-show` call)
  reads from `(current-chip-theme 'normal)` / `(current-chip-theme
  'faded)` to build the per-chip alists, then forwards to `hints-show`
  as today.

### Native-side change

None. `HintsLibrary` continues to accept per-chip alists with hex
colours and integer dimensions.

## Build sequence

Each stop checks back with the user. None of the steps cross over
into the deferred Phase 2 (how-tos) or Phase 3 (tutorials) work.

### 1. Add `.chip` defaults to `base.css`

- New `.chip { … }` rule in `base.css` with the property set the
  current `default-chip-options` covers. Use `var(--color-host-fg,
  white)` for `color` and `var(--color-host-bg, dodgerblue)` for
  `background` so chips inherit from `set-host-header!` by default.
- New `.chip.faded { background: #6f8baa; }` rule for the occluded
  variant (no host-header inheritance — occluded windows should look
  visually distinct regardless of theme).
- New `:root { --chip-offset-x-frac: 0.02; --chip-offset-y-frac: 0.02; }`
  for the two positioning hints that have no DOM analogue.

**No Scheme changes yet.** This step just bakes the current defaults
into CSS in a form the probe can read.

**Stop.** Confirm `.chip` rule shape (and the `var(--color-host-*)`
inheritance trick) with user before plumbing the probe.

### 2. Plumb `~/.config/modaliser/overlay.css`

- Add a constant `user-overlay-css-path` in `root.scm` next to
  `user-config-path`.
- After the user-config include, slurp `overlay.css` if it exists:
  `(when (file-exists? user-overlay-css-path)
     (set! overlay-custom-css (read-file-text user-overlay-css-path)))`.
- **Delete `set-overlay-css!`** from `ui/overlay.scm`. The variable
  `overlay-custom-css` stays (the CSS stack still needs a slot for
  user content); only the setter goes. Configs that called it raise
  unbound-symbol on load.

**Stop.** Manually create a temporary `overlay.css` with a visible
override (e.g. `body { background: red; }`), relaunch, confirm the
overlay picks it up. Remove the test file. `swift test`.

### 3. Build the probe

A new library — call it `(modaliser theming)` — owns probe creation,
the resolved-theme cache, and the read accessor.

- Use `webview-create` to make an offscreen 1×1 transparent panel
  with id `"chip-probe"`.
- Build the probe HTML: concatenate the same CSS the overlay uses
  (`base.css` + each `add-overlay-asset-file! 'css` contribution +
  `overlay-custom-css` + `host-header-css` — i.e. the exact stack
  `render-overlay-html` emits in `ui/overlay.scm:551-555`), wrap in
  `<style>`, follow with the two probe `<div>`s and an inline
  `<script>` that reads computed styles and posts the resolved JSON
  via `window.webkit.messageHandlers.modaliser.postMessage(…)`.
- Register a `webview-on-message` handler that parses the JSON,
  updates the theme cell, closes the probe panel.
- Export only: `current-chip-theme`.
- The boot-time probe runs from `root.scm` after `overlay.css` is
  slurped (step 2's location).
- Seed the cache with hard-coded defaults matching the new
  `.chip`/`.chip.faded` declarations in `base.css` so
  `(current-chip-theme)` calls that beat the async probe still
  return sane values.

**Stop.** `swift test`. Manually inspect the cache via
`(current-chip-theme 'normal)` / `(current-chip-theme 'faded)` after
boot to verify the probe round-trip works.

### 4. Migrate the blocks

- `blocks/window-list.sld`: remove `default-chip-options`,
  `merge-chip-options`, the `'chip-options` keyword branch in
  `make-window-list-block`. Add the `'chips? #t` toggle. `paint-and-
  snapshot!` builds each chip alist by reading
  `(current-chip-theme 'normal)` and substituting per-chip
  `label`/`x`/`y`/`w`/`h`; the faded variant overrides `background`
  from `(current-chip-theme 'faded)`.
- `apps/iterm.sld`: same shape. `'hint-options` removed;
  `default-chip-options` and `merge-hint-options` deleted. The
  `ax-target-hints` call wires `(current-chip-theme 'normal)` in
  place of the merged options.
- Both add the error-with-migration-message branch for users still
  passing the old keywords. Error text points at the `.chip` CSS
  rule, e.g. `"'chip-options removed — edit .chip in
  ~/.config/modaliser/overlay.css instead"`.

**Stop.** `swift test`, run the app, sanity-check window-list chips
and iTerm pane chips visually.

### 5. Update the seed config

The seed gets *simpler*, not more complex: with `.chip` referencing
`var(--color-host-bg)`, the existing `(set-host-header! 'background
the-color)` call already threads the theme colour into chips for free.

- `default-config.scm`: delete the `'chip-options` keyword/value pair
  from the `window:list-block` call (line 101) and the `'hint-options`
  keyword/value pair from the `iterm:register!` call (line 139). The
  rest stays.
- Mirror the change to `~/.config/modaliser/config.scm` (per
  `feedback_config_sync.md` the user config is canonical; seed is a
  literal `cp` of it).

**Stop.** Run the app from the new seed, confirm chips inherit the
host-header colour. If the user wants per-install chip overrides,
that's what `overlay.css` is for; they don't need to touch
`config.scm`.

### 6. Update docs

- `docs/reference/theming.md`:
  - Major rewrite of the "Customisation paths" section: the canonical
    customisation is now "edit `~/.config/modaliser/overlay.css`."
    Remove `set-overlay-css!` everywhere.
  - New "Chip styling" section explaining the `.chip` / `.chip.faded`
    rule surface plus the two `--chip-offset-{x,y}-frac` variables.
    Show a worked example overriding chip colour and corner radius.
  - Brief "How chip values are resolved" paragraph naming the probe
    WebView for the curious reader (one paragraph; not load-bearing).
  - "Migrating from `'chip-options` / `'hint-options`" subsection
    with a one-line before/after.
  - "Migrating from `set-overlay-css!`" subsection: move the string
    content into `overlay.css`, drop the setter call.
- `docs/reference/libraries.md`:
  - `(modaliser window-actions)` section: drop the chip-options
    defaults table from `list-block`. Document the new `'chips?`
    keyword. Link to `theming.md`.
  - `(modaliser apps iterm)` section: drop the `'hint-options` row
    from the keyword table. Same link.
  - New `(modaliser theming)` section documenting just
    `current-chip-theme`.
- `docs/reference/dsl.md`:
  - **Delete** the `set-overlay-css!` subsection under "Configuration
    setters" entirely.
  - One-line cross-reference under "Configuration setters" pointing
    at theming.md for chip styling.
- `docs/quickstart/index.md`: add a one-line "Theme it" mention in
  the "What's next" section pointing at `overlay.css` (this is the
  cheapest user-facing knob; worth surfacing in the quickstart).

**Stop.** Re-run the link checker, open the rendered markdown.

### 7. Code review + finish

- `superpowers:requesting-code-review` with focus on:
  - Has every `chip-options` / `hint-options` callsite been migrated?
    `grep -nE "chip-options|hint-options"` should return only doc
    references and the error-message strings.
  - Has every `set-overlay-css!` reference been deleted?
    `grep -rn "set-overlay-css" Sources/Modaliser/Scheme/` should be
    empty (or only show the deletion in the diff).
  - Does the migration error for `'chip-options` / `'hint-options`
    actually fire when the old keyword is passed?
  - Is the probe HTML's CSS stack identical to the overlay's? If they
    diverge, computed values diverge.
  - Does the boot-time probe run *after* the user's `config.scm` has
    been included AND `overlay.css` has been slurped?
  - Does `(current-chip-theme)` return sensible defaults before the
    probe completes (cold-start path)?
- `superpowers:finishing-a-development-branch`.

## Verification

- `swift test` (490 baseline) after each step.
- App-level smoke: F18 → "w" overlay → confirm chips paint over
  visible windows; F17 in iTerm → confirm pane chips paint; both
  inherit `--color-host-bg` (the seed's theme colour).
- Probe smoke: after a fresh launch, evaluate
  `(current-chip-theme 'normal)` from a REPL (or temporary log
  statement) and confirm the cached alist matches the resolved
  computed styles.
- File-load smoke: create a temporary `~/.config/modaliser/overlay.css`
  with `.chip { background: tomato; }`, relaunch, confirm chips paint
  tomato. Delete the file, relaunch, confirm chips revert.
- Error path: temporarily pass `'chip-options` from the seed and
  confirm the migration error fires (and the error text mentions
  `overlay.css`). Revert.
- Unbound-symbol path: temporarily add a `(set-overlay-css! "")`
  call to a test config and confirm the load raises. Revert.
- `grep -rE "chip-options|hint-options" Sources/Modaliser/Scheme/`
  should return only the migration-error strings.
- `grep -rn "set-overlay-css" Sources/Modaliser/Scheme/` should return
  zero matches.

## Stopping points / decision gates

1. After step 1 (`.chip` rules in base.css). Confirm class names,
   property set, and the `var(--color-host-*)` inheritance before
   any Scheme touches the probe.
2. After step 2 (overlay.css auto-load + `set-overlay-css!`
   deletion). Manual file-load smoke before downstream work.
3. After step 3 (probe library + cache). REPL inspection of resolved
   values before downstream blocks consume them.
4. After step 4 (blocks migrated). Visual sanity-check before the
   seed config rewrites against the new surface.
5. After step 5 (seed migrated). Before docs updates so any further
   surface tweaks land before the prose freezes.
6. Before the code-review dispatch in step 7.

## Non-goals

- **Moving chip *rendering* into the WebView.** Chips remain native
  NSPanels; only chip *styling resolution* uses a WebView (the probe).
  A WebView-based rendering surface is a much larger slice.
- **Generalising the probe to a "shared theme resolver" library.** The
  probe is chip-specific in this slice. If similar resolution is
  needed later (e.g. for an AX-hints variant block), generalise then.
- **In-process re-probing.** The probe runs once at boot. Relaunch is
  the refresh path, consistent with every other config change in
  Modaliser (per `feedback_no_in_place_reload`).
- **Keeping `set-overlay-css!` as an escape hatch.** Authoring CSS via
  a Scheme string with no editor tooling is exactly the surface this
  refactor removes. A user who needs programmatic CSS generation can
  write a build step that emits `overlay.css` before launch.
- **Multi-file CSS auto-load.** One canonical path
  (`~/.config/modaliser/overlay.css`). Users who want to split their
  CSS can use CSS `@import` inside that file, or symlink it to a
  generated file.
- **Backwards compatibility shim for `'chip-options` /
  `'hint-options`.** Clean break with a clear error pointing at the
  `.chip` CSS rule. The seed config is the migration; user configs
  out in the wild relaunch and discover the error.

## Source-of-truth files to read first

The kickoff prompt will point at these explicitly:

- `Sources/Modaliser/HintsLibrary.swift` — what `hints-show` accepts.
- `Sources/Modaliser/Scheme/lib/modaliser/blocks/window-list.sld` —
  current chip-options flow (default-chip-options, merge-chip-options,
  paint-and-snapshot!).
- `Sources/Modaliser/Scheme/lib/modaliser/apps/iterm.sld` — current
  hint-options flow (merge-hint-options, rebuild-tree!).
- `Sources/Modaliser/WebviewLibrary.swift` — the `webview-create`,
  `webview-set-html!`, `webview-on-message` API the probe will use.
- `Sources/Modaliser/WebViewManager.swift` — panel creation options
  (transparent, position, dimensions). Confirms a 1×1 offscreen
  transparent panel is supported by the existing API.
- `Sources/Modaliser/Scheme/ui/overlay.scm` — CSS load order. The
  probe must concatenate the CSS stack in exactly the same order as
  `render-overlay-body` so resolved values match what a real chip
  would have if it lived in the overlay.
- `Sources/Modaliser/Scheme/base.css` — current defaults to lift into
  `.chip` / `.chip.faded` rules.
- `Sources/Modaliser/Scheme/lib/modaliser/state-machine.sld` — read
  the `host-header-name` / `host-header-css` plumbing as the precedent
  for a mutable cell + thunk-exported accessor.
- `~/.config/modaliser/config.scm` (== `Sources/Modaliser/Scheme/default-config.scm`)
  — the canonical user-facing example.

The current docs landing for this surface:

- `docs/reference/theming.md` — what users see today, will be updated
  in step 5.
- `docs/reference/libraries.md` — chip-options / hint-options keyword
  tables, will be edited in step 5.
