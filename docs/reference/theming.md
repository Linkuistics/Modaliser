# Theming

The overlay and chooser are HTML rendered into WKWebView panels. All
visuals come from CSS — there's no native styling layer. Theming
ranges from a one-line variable override to wholesale custom CSS.

The default look is the **cheat-sheet** style: white panel cards on a
tinted body, banded panel headers, soft mono keycaps, an indigo accent
with amber group-opens, a separated footer strip, and frameless live lists.
Type is **IBM Plex Sans** (labels) + **IBM Plex Mono** (keys/paths/
footer), bundled locally — the WebView needs no network.

User CSS lives in `~/.config/modaliser/theme.css`. The file is
auto-loaded at startup and concatenated into the cascade *after*
`base.css` and all block-supplied stylesheets, so user declarations win
on equal specificity. Edit the file, relaunch Modaliser, done.

Source files:

- [`base.css`](../../Sources/Modaliser/Scheme/base.css) — root
  variables, overlay container, panel grid, embedded live list, keycaps,
  chooser, footer sigils, chip.
- [`blocks/window-list.css`](../../Sources/Modaliser/Scheme/lib/modaliser/blocks/window-list.css)
- [`blocks/iterm-panes.css`](../../Sources/Modaliser/Scheme/lib/modaliser/blocks/iterm-panes.css)
- [`blocks/window-diagram.css`](../../Sources/Modaliser/Scheme/lib/modaliser/blocks/window-diagram.css)

CSS load order (last wins on equal specificity):

1. `base.css`
2. Each block library's CSS (registered via
   `(add-overlay-asset-file! 'css PATH)`) in import order.
3. `~/.config/modaliser/theme.css` (your user CSS).

## CSS variables

### Surfaces (`:root` in `base.css`)

| Variable | Default | Description |
|---|---|---|
| `--overlay-bg` | `#ffffff` | Outer card background. |
| `--overlay-body-bg` | `#f6f7fa` | Tinted grid behind the panels (makes white panels pop). |
| `--overlay-border` | `#e2e4ea` | Card border. |
| `--overlay-radius` | `10px` | Card border-radius. |
| `--overlay-padding` | `0` | The card is edge-to-edge; the band, body, and footer strips own their own padding. Kept as a token for configs that still reference it. |
| `--overlay-width` | `320px` | Minimum card width (the card auto-grows to fit its content). |
| `--overlay-shadow` | layered | Drop shadow. |

### Typography

| Variable | Default | Role |
|---|---|---|
| `--font-family` | `"IBM Plex Sans", system-ui, sans-serif` | Labels / body. |
| `--font-mono` | `"IBM Plex Mono", "SF Mono", monospace` | Keys / paths / footer. Symbol glyphs absent from IBM Plex (escape/backspace/return/arrow/modifier sigils) fall through to SF Mono. |
| `--font-size` | `14px` | Base size; most secondary text is `calc(var(--font-size) - Npx)`. |
| `--line-height` | `1.55` | |

### Accents

| Variable | Default | Used for |
|---|---|---|
| `--accent` | `#4f46e5` (indigo) | Keys in lists, focus, selection, panel-header text, list-row focus bar. |
| `--color-group` | `#c2700f` (amber) | Group-opens (`›` drill-in rows), sticky-target markers (fallback). |
| `--live` | `#23c161` (green) | The live-list "live" dot. |

### Panels

| Variable | Default | Role |
|---|---|---|
| `--panel-bg` | `#ffffff` | Panel card background. |
| `--panel-border` | `#e7e9ee` | Panel border (also `--color-separator`). |
| `--panel-radius` | `8px` | Panel card border-radius. |
| `--panel-head-bg` | `#eef0fb` | Banded panel-header background. |
| `--panel-head-fg` | `#3b3fb6` | Banded panel-header text (eyebrow-cased label). |
| `--panel-shadow` | `0 1px 2px rgba(17,20,36,0.05)` | Panel lift. |

Panel-grid layout knobs (set on `.panel-grid`; the renderer pins
`--panel-grid-cols` inline when a `screen`/`open` authors `'cols N`):

| Variable | Default | Role |
|---|---|---|
| `--panel-grid-cols` | `auto-fit` | Track count. Default flows panels into as many tracks as fit; an authored `'cols` pins an explicit count. |
| `--panel-min-width` | `184px` | Minimum panel track width (the auto-fit `minmax`). |
| `--panel-grid-max-width` | `760px` | Caps the grid width so it wraps rather than stretching to one row. |
| `--panel-gap` | `10px` | Gap between panels. |

Panels pack as **masonry** by default (`.panel-grid` uses `display:
grid-lanes`) — each panel drops into the shortest lane. A `screen`/`open`
authoring `'layout 'grid` sets `data-layout="grid"` on the `.panel-grid`,
which the `.panel-grid[data-layout="grid"]` rule switches to an aligned
`display: grid` (with `grid-auto-flow: dense`). Both modes honour `'cols`
and the panel `'span` classes.

### Keycaps

The keycap is the shared key vocabulary across panels, embedded lists,
and the chooser. A soft mono pill; the **accent
variant** (numeric keys inside live lists and the chooser) re-maps the
three keycap vars on a scoped selector, so one `.entry-key` box rule
paints both.

| Variable | Default | Role |
|---|---|---|
| `--keycap-bg` | `#f4f5f7` | Soft keycap fill (static command keys). |
| `--keycap-border` | `#e3e5ea` | Soft keycap border. |
| `--keycap-fg` | `#4b5563` | Soft keycap glyph colour. |
| `--keycap-accent-bg` | `rgba(79,70,229,0.09)` | Accent keycap fill (live-list / chooser digits). |
| `--keycap-accent-border` | `rgba(79,70,229,0.22)` | Accent keycap border. |

### Embedded live list

An embedded list renders **frameless** — directly in the panel card, with no
tinted/bordered/rounded inset (the card already frames it). It anchors with a
uniform gap under whatever precedes it (header or key-rows), so the gap reads the
same across panels. (The former `--list-bg` / `--list-border` inset tokens were
retired with the frame.)

| Variable | Default | Role |
|---|---|---|
| `--list-focus-bg` | `rgba(79,70,229,0.07)` | Selection-cursor row tint. |
| `--list-focus-bar` | `var(--accent)` | Selection-cursor row left bar. |

`--list-focus-bg` / `--list-focus-bar` are the **single selection knob**
shared by the embedded lists *and* the chooser's selected result — one
variable pair recolours the cursor everywhere. (There are no longer
chooser-specific `--chooser-selected-*` tokens; the chooser's selected
row is a `.list-row.is-focused`.)

### Footer strip

| Variable | Default | Role |
|---|---|---|
| `--footer-bg` | `#f5f6f8` | Footer (and chooser action panel) background. |
| `--footer-border` | `#e3e5ea` | Footer top rule. |

### Text

| Variable | Default | Role |
|---|---|---|
| `--color-label` | `#374151` | Entry labels, body text, list titles. |
| `--color-arrow` | `#b6bcc7` | Key → label connector glyph (muted). |
| `--color-header` | `#6b7280` | Breadcrumb / footer / caption / subtext (muted). |
| `--color-separator` | `var(--panel-border)` | Header / footer / chooser rules. |

### Live-list key alias

`--color-key` is the accent colour for the numeric keys in the live-list
blocks (`window-list` / `iterm-panes` / `iterm-tabs` / `window-diagram`),
until those blocks converge on the `.list-*` row vocabulary.

| Variable | Default | Role |
|---|---|---|
| `--color-key` | `var(--accent)` | Numeric keys in the live-list blocks. |

### Default list renderer

The plain-`(group …)` fallback list flows into a CSS Grid with
**CSS-intrinsic auto-fit columns** — as many `--overlay-entry-min-width`
tracks as fit, capped by `--overlay-entries-max-width`. No column count
is computed in Scheme.

| Variable | Default | Role |
|---|---|---|
| `--overlay-entry-min-width` | `200px` | Minimum track width for the auto-fit list grid. |
| `--overlay-entries-max-width` | `620px` | Caps the list width so it wraps rather than stretching to one row. |

### Host theme

| Variable | Default | Used for |
|---|---|---|
| `--color-host-bg` | unset | Overlay/chooser header band background, sticky-mode border, sticky-target marker, **chip background**. |
| `--color-host-fg` | unset | Overlay/chooser header text, chip foreground. |
| `--color-host-sep` | unset | Breadcrumb separator colour. Falls back to `--color-host-fg` then `--color-arrow`. |

These are *unset by default* — declare them in your `theme.css` to
adopt a host theme:

```css
:root {
  --color-host-bg: dodgerblue;
  --color-host-fg: white;
}
```

A single colour pair recolours the overlay header band, the chooser
header, the sticky-mode border accent, sticky-target markers, and every
chip on screen — every visual that consumes `var(--color-host-*)`.

### Chooser (also in `base.css`)

| Variable | Default | Description |
|---|---|---|
| `--chooser-width` | `500px` | Fixed chooser width. |
| `--chooser-max-height` | `400px` | Vertical cap. |
| `--chooser-input-bg` | `#ffffff` | Input background. |
| `--chooser-input-border` | `#d8dbe2` | Input border. |
| `--chooser-input-focus-border` | `var(--accent)` | Input border on focus. |
| `--chooser-match-color` | `var(--accent)` | Fuzzy-match highlight colour. |
| `--chooser-match-weight` | `700` | Fuzzy-match font weight. |
| `--chooser-action-bg` | `var(--footer-bg)` | Tab-panel background. |

The chooser's selected result row is themed by the shared
`--list-focus-bg` / `--list-focus-bar` (see *Embedded live list*) — there
are no `--chooser-selected-*` tokens.

### Window-diagram (per-block)

From `blocks/window-diagram.css`:

| Variable | Default |
|---|---|
| `--diagram-line` | `rgba(0, 0, 0, 0.65)` |
| `--diagram-cell-bg` | `#ffffff` |
| `--diagram-panel-w` | `102px` |
| `--diagram-panel-h` | `60px` |

### Chip (window-list + iTerm hint chips)

`base.css` declares the `.chip` rule + positioning vars:

| Property / variable | Default | Notes |
|---|---|---|
| `.chip { color }` | `var(--color-host-fg, white)` | Inherits the host header foreground; falls back to white. |
| `.chip { background }` | `var(--color-host-bg, dodgerblue)` | Inherits the host header background; falls back to dodgerblue. |
| `.chip { font-size }` | `56px` | |
| `.chip { padding }` | `16px` | |
| `.chip { border }` | `1px solid black` | |
| `.chip { border-radius }` | `8px` | |
| `.chip.faded { background }` | `#6f8baa` | Occluded windows in the window-list block paint with this. |
| `--chip-offset-x-frac` | `0.02` | Chip top-left x-offset, as a fraction of the host element's width. |
| `--chip-offset-y-frac` | `0.02` | y-offset, fraction of host height. |

Chips inherit the host theme automatically when `--color-host-bg` is
declared in your `theme.css` — setting that one variable recolours
the header band *and* every chip on screen. Override the `.chip` rule
directly (see "Customising chips" below) when you want chips to look
unlike the host header.

## Class inventory

### Overlay structure

| Class | Where |
|---|---|
| `.overlay` | Outer card. |
| `.overlay.sticky` | Modifier on `.overlay` when navigation is inside a sticky tree/subgroup. |
| `.overlay-header` | Breadcrumb / app-context band at the card top. |
| `.overlay-header .breadcrumb-sep` | `›` separator between breadcrumb segments. |
| `.overlay-custom-body` | Container for a custom-renderer body. `data-renderer` attribute = `"panel-grid"` or `"blocks"`. The `panel-grid` variant carries the tinted `--overlay-body-bg`. |
| `.overlay-footer` | Separated footer strip (tinted background + top rule). |
| `.overlay-footer-root` | Modifier at the root of a tree (no back-hint shown). |
| `.footer-hint` | One footer command hint (sigil + label). Shared by the overlay and chooser footers. |
| `.footer-hint--disabled` | Modifier greying a hint whose command can't act in the current context (e.g. `⏎ choose` with zero chooser results, or the cursor-nav hints over an empty live list). Dimmed in place, never hidden. |
| `.sigil`, `.sigil-back`, `.sigil-return`, `.sigil-escape`, `.sigil-arrows`, `.sigil-mod` | Footer keyboard glyphs + in-key modifier sigils. |

### Panel grid (layout DSL renderer)

| Class | Where |
|---|---|
| `.panel-loose` | The bare, header-less loose region above the grid: a screen/open's loose rows, folded top-level opens, and loose bare blocks (no card). |
| `.panel-loose .wk-row` | A loose key-row (same key / arrow / label mini-grid the panels use). |
| `.panel-loose .panel-list` | A loose bare block (diagram / live list) — additionally zeros the (already frameless) `.panel-list`'s padding so it floats flush on the body tint, like `.panel--bare .panel-list`. |
| `.panel-grid` | The grid container (`screen` / `open` body). |
| `.panel` | A single panel card. |
| `.panel--bare` | A panel hosting a `window-diagram` — card chrome dropped so the diagram floats on the body tint. |
| `.panel-span-narrow`, `.panel-span-wide`, `.panel-span-full` | Span modifiers (1 / 2 / all columns). |
| `.panel-head` | Banded, eyebrow-cased panel header. |
| `.panel-rows` | The panel's key-row column. |
| `.panel-rows .wk-row` | A single key-row mini-grid (key / arrow / label). |

### Keycap and key-row cells

| Class | Where |
|---|---|
| `.entry-key` | The keycap — shared across panels, lists, and the chooser. Soft by default; the accent variant is scoped under `.panel-list`, `.list-row`, and the live-list block rows. |
| `.entry-arrow` | Key → label arrow glyph. |
| `.entry-label` | Label cell (never wraps; truncates with ellipsis). |
| `.entry-label.group-label` | Modifier for rows that *open* a sub-screen / chooser (amber). |
| `.entry-sticky-marker` | `↻` marker on `'sticky-target` cells. |

### Embedded live list — shared list-row vocabulary

The canonical row vocabulary, shared by the embedded pane/window lists
*and* the chooser so they read as one family.

| Class | Where |
|---|---|
| `.panel-list` | The frameless section that hosts a panel's live list (no tint/border/rounded inset; rows sit directly in the card). |
| `.list-caption` | "Panes" / "Windows" eyebrow caption. |
| `.list-live-dot` | The green "live" dot. |
| `.list-row` | One list row (flex: keycap + main + detail). |
| `.list-row.is-focused` | Selection-cursor (highlighted) row — accent inset bar + `--list-focus-bg` tint. |
| `.list-main` | Flexible middle column (stacks title + subtext). |
| `.list-title` | Row title line (never wraps). |
| `.list-subtext` | Second line (path / match text), muted + smaller. |
| `.list-detail` | Right-aligned mono detail tag (e.g. `focused ⌥2`). |

The block renderers currently emit `.wl-row` (window-list) / `.ip-row`
(iterm-panes) / `.it-row` (iterm-tabs) with `.entry-key` / `.entry-label`
inside the section; those are skinned alongside the `.list-*` names, and
`.is-focused` covers all of them.

### Chooser

| Class | Where |
|---|---|
| `.chooser` | Outer panel. |
| `.chooser-header` | Header band (shares the overlay-header rules). |
| `.chooser-search` | Search-input container. |
| `.chooser-input` | The `<input>`. |
| `.chooser-results` | Result `<ul>`. |
| `.list-row`, `.list-main`, `.list-title`, `.list-subtext` | Result rows — the shared list-row vocabulary. |
| `.list-title .match`, `.list-subtext .match` | Fuzzy-match highlight. |
| `.list-title.chooser-dir` | Directory name in file results (semibold). |
| `.chooser-footer` | Separated footer (match count + nav hints). |
| `.chooser-actions` | Tab-panel action list container. |
| `.chooser-action-item` (`.selected`), `.chooser-action-key`, `.chooser-action-label`, `.chooser-action-desc` | Action panel rows. |

### Window-list / window-diagram blocks

| Class | Where |
|---|---|
| `.block-window-list .wl-row` (`.dulled`) | Window row (faded modifier for occluded windows). |
| `.block-iterm-panes .ip-row` | iTerm pane row. |
| `.block-window-diagram .diagram-panel-grid` | The matrix container. |
| `.block-window-diagram .diagram-panel` (`.center`, `.fill`) | A panel cell + centre / maximise modifiers. |
| `.block-window-diagram .diagram-cell` (`.has-key`, `.left-line`, `.top-line`) | Grid sub-cell + modifiers. |

## Customisation paths

### Smallest change: tint the host theme

```css
/* ~/.config/modaliser/theme.css */
:root {
  --color-host-bg: darkorchid;
  --color-host-fg: white;
}
```

The overlay header band, the chooser header, the sticky-mode border,
`'sticky-target` cell markers, **and the chips on every window-list /
iTerm hint overlay** all inherit the colour through
`var(--color-host-*)` references in `base.css`. One declaration,
overlay-wide effect.

### Re-accent the whole surface

The indigo `--accent` drives keys-in-lists, focus, selection, and panel
headers. One override re-accents the cheat sheet:

```css
/* ~/.config/modaliser/theme.css */
:root {
  --accent: #0ea5e9;          /* sky blue */
  --color-group: #b45309;     /* group-opens */
}
```

### Override variables only

User CSS sits *after* `base.css` in the cascade, so a `:root { … }`
override block applies cleanly:

```css
/* ~/.config/modaliser/theme.css */
:root {
  --overlay-body-bg: #eef1f6;
  --panel-head-bg:   #e7eafc;
  --panel-head-fg:   #2f339c;
  --keycap-bg:       #eef0f3;
  --color-label:     #232323;
}
```

### Override classes

For shape changes (typography, spacing, custom widgets), declare them
in the same file:

```css
.overlay { backdrop-filter: blur(20px); }
.panel { border-radius: 12px; }
.panel-head { letter-spacing: 0.12em; }
.entry-key { font-weight: 700; }
.overlay-footer { display: none; }
```

### Customising chips

The `.chip` rule is the chip styling surface. Override it like any other
class:

```css
/* ~/.config/modaliser/theme.css */
.chip {
  background: tomato;
  border-radius: 12px;
  font-size: 48px;
}
.chip.faded { background: #555; }
:root {
  --chip-offset-x-frac: 0.04;
  --chip-offset-y-frac: 0.04;
}
```

Chip values are pulled out of the cascade at boot by a hidden probe
WebView (see "How chip values are resolved" below), so edits to
`theme.css` take effect on the next relaunch — same reload story as
every other Modaliser config change.

### A worked dark theme

```css
/* ~/.config/modaliser/theme.css */
:root {
  --overlay-bg:       #1c1c1e;
  --overlay-body-bg:  #232327;
  --overlay-border:   rgba(255, 255, 255, 0.12);
  --accent:           #818cf8;
  --color-group:      #f0af50;
  --color-label:      #e6e6e6;
  --color-arrow:      rgba(255, 255, 255, 0.30);
  --color-header:     #9aa0ac;

  --panel-bg:         #2a2a2e;
  --panel-border:     rgba(255, 255, 255, 0.10);
  --panel-head-bg:    #2f3060;
  --panel-head-fg:    #c7caff;

  --keycap-bg:        #34343a;
  --keycap-border:    rgba(255, 255, 255, 0.12);
  --keycap-fg:        #d4d4d8;

  --footer-bg:        #242428;
  --footer-border:    rgba(255, 255, 255, 0.10);

  --diagram-line:     rgba(255, 255, 255, 0.55);
  --diagram-cell-bg:  #2a2a2c;

  --chooser-input-bg: #2a2a2e;
  --chooser-input-border: rgba(255, 255, 255, 0.15);
}
```

The same CSS applies to overlay, chooser, panels, and every bundled
block — they all consume the same token vocabulary.

## How chip values are resolved

Chips are painted natively (each chip is its own borderless `NSPanel`
drawn by `HintsLibrary`) — there's no WebView holding the live chip
graphics. But the *appearance* of those chips comes from the same CSS
the overlay uses. To bridge the two, Modaliser spawns a hidden 1×1
offscreen probe WebView at boot, loads the full CSS cascade into it
plus two `<div class="chip">` elements (normal + `.faded`), and reads
`getComputedStyle` from a tiny inline `<script>`. The resolved values
get posted back to Scheme via `webview-on-message` and cached. The
native chip painter reads the cache.

The probe runs once per boot — relaunching is the refresh path for
chip styling, same as every other config change in Modaliser. The
Scheme accessor is `(current-chip-theme)` / `(current-chip-theme
'faded)` — see [libraries.md](libraries.md#modaliser-theming).

## See also

- [renderer-protocol.md](renderer-protocol.md) — the panel-grid payload
  and how blocks emit HTML the CSS targets.
- [libraries.md](libraries.md#modaliser-theming) — `(modaliser theming)`,
  `current-chip-theme`.
- [how-to/customise-theme.md](../how-to/customise-theme.md) — minimal
  recipe for tinting the overlay, recolouring chips, and a worked
  dark-theme template.
