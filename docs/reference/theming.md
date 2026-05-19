# Theming

The overlay and chooser are HTML rendered into WKWebView panels. All
visuals come from CSS — there's no native styling layer. Theming
ranges from a one-line variable override to wholesale custom CSS.

This page inventories the **current** CSS surface. A refactor moving
inline block options (chip colours, font sizes) into CSS classes is
planned as a separate slice; until that lands, some block styling is
controlled via block-constructor options instead of CSS variables.

Source files:

- [`base.css`](../../Sources/Modaliser/Scheme/base.css) — root
  variables, overlay container, chooser, footer sigils.
- [`blocks/which-key.css`](../../Sources/Modaliser/Scheme/lib/modaliser/blocks/which-key.css)
- [`blocks/window-list.css`](../../Sources/Modaliser/Scheme/lib/modaliser/blocks/window-list.css)
- [`blocks/window-diagram.css`](../../Sources/Modaliser/Scheme/lib/modaliser/blocks/window-diagram.css)

CSS load order (last wins on equal specificity):

1. `base.css`
2. Each block library's CSS (registered via
   `(add-overlay-asset-file! 'css PATH)`) in import order.
3. The dynamic `:root { … }` block emitted by `set-host-header!`.
4. User CSS from `(set-overlay-css! "…")`.

## CSS variables

### Overlay container (`:root` in `base.css`)

| Variable | Default | Description |
|---|---|---|
| `--overlay-bg` | `rgba(253, 247, 237, 1)` | Panel background. |
| `--overlay-border` | `rgba(153, 153, 153, 1)` | Panel border. |
| `--overlay-radius` | `8px` | Border-radius. |
| `--overlay-padding` | `12px` | Inner padding. |
| `--overlay-width` | `320px` | Minimum panel width (panel auto-grows to fit). |
| `--overlay-shadow` | `0 4px 20px rgba(0,0,0,0.15)` | Drop shadow. |
| `--overlay-cols` | computed | CSS multi-column count picked by `overlay-column-count` to hit `set-overlay-aspect-ratio!`. |

### Typography

| Variable | Default |
|---|---|
| `--font-family` | `"Menlo", "SF Mono", monospace` |
| `--font-size` | `14px` |
| `--line-height` | `1.6` |

### Colour vocabulary

| Variable | Default | Used for |
|---|---|---|
| `--color-key` | `rgba(33, 97, 186, 1)` | Key glyphs in entries and chooser actions. |
| `--color-label` | `rgba(56, 56, 56, 1)` | Entry labels, body text. |
| `--color-group` | `rgba(204, 115, 25, 1)` | Group labels (commands that *open* a sub-overlay or chooser). |
| `--color-category` | `rgba(70, 105, 130, 1)` | Category labels and their underline. |
| `--color-arrow` | `rgba(128, 128, 128, 1)` | Key → label arrow glyph. |
| `--color-header` | `rgba(128, 128, 128, 1)` | Breadcrumb default colour, footer text. |
| `--color-separator` | `rgba(204, 204, 204, 1)` | Header / footer rules. |

### Host header (set via `(set-host-header! …)`)

| Variable | Set by | Description |
|---|---|---|
| `--color-host-bg` | `'background` | Header strip background. |
| `--color-host-fg` | `'foreground` (defaults to `"white"` when bg is set) | Header text. |
| `--color-host-sep` | `'separator-color` | Breadcrumb separator. Falls back to `--color-host-fg` then `--color-arrow`. |

These variables also drive the sticky-mode border accent
(`.overlay.sticky` border-color) and the `'sticky-target` cell marker
(`.entry-sticky-marker` color) — so threading a single colour through
`set-host-header!` recolours both the chrome and the persistent-mode
visual cues.

### Chooser (also in `base.css`)

| Variable | Default | Description |
|---|---|---|
| `--chooser-width` | `500px` | Fixed chooser width. |
| `--chooser-max-height` | `400px` | Vertical cap. |
| `--chooser-input-bg` | `rgba(255, 255, 255, 1)` | Search input background. |
| `--chooser-input-border` | `rgba(180, 180, 180, 1)` | Input border. |
| `--chooser-input-focus-border` | `rgba(33, 97, 186, 1)` | Input border on focus. |
| `--chooser-selected-bg` | `rgba(33, 97, 186, 0.1)` | Highlighted result background. |
| `--chooser-selected-border` | `rgba(33, 97, 186, 0.4)` | Highlighted result left bar. |
| `--chooser-match-color` | `rgba(33, 97, 186, 1)` | Fuzzy-match highlight colour. |
| `--chooser-match-weight` | `700` | Fuzzy-match font weight. |
| `--chooser-action-bg` | `rgba(245, 242, 235, 1)` | Tab-panel background. |

### Window-diagram (per-block)

From `blocks/window-diagram.css`:

| Variable | Default |
|---|---|
| `--diagram-line` | `rgba(0, 0, 0, 0.65)` |
| `--diagram-cell-bg` | `#ffffff` |
| `--diagram-panel-w` | `102px` |
| `--diagram-panel-h` | `60px` |

## Class inventory

### Overlay structure

| Class | Where |
|---|---|
| `.overlay` | Outer panel. |
| `.overlay.sticky` | Modifier on `.overlay` when navigation is inside a sticky tree/subgroup. |
| `.overlay-header` | Breadcrumb container. |
| `.overlay-header .breadcrumb-sep` | `›` separator between breadcrumb segments. |
| `.overlay-entries` | Default list renderer's `<ul>`. CSS multi-column flow. |
| `.overlay-entry` | Default list `<li>`. 3-col mini-grid (key / arrow / label). |
| `.entry-key` | Key column. |
| `.entry-arrow` | Arrow glyph between key and label. |
| `.entry-label` | Label column. |
| `.entry-label.group-label` | Modifier on `.entry-label` for entries that *open* a panel (sub-overlay or chooser). |
| `.entry-sticky-marker` | `↻` marker on `'sticky-target` cells. |
| `.overlay-footer` | Footer band with back-hint / cancel-hint sigils. |
| `.overlay-footer-root` | Modifier on `.overlay-footer` at the root of a tree (no back-hint shown). |
| `.overlay-custom-body` | Container for the block-list renderer's output. `data-renderer="blocks"` attribute. |
| `.block` | Generic block wrapper (used as a `:first-child` selector). |
| `.sigil`, `.sigil-back`, `.sigil-return`, `.sigil-escape`, `.sigil-arrows` | Footer keyboard glyphs (back/return/escape/arrows). |

### Which-key block

| Class | Where |
|---|---|
| `.block-which-key` | Block container. |
| `.block-which-key .wk-columns` | CSS-grid column flow. |
| `.block-which-key .wk-misc` | Misc-segment column. |
| `.block-which-key .wk-category` | Category-segment column. |
| `.block-which-key .wk-category-label` | Category label (small-caps, separator underline). |
| `.block-which-key .wk-row` | Single binding row. |

### Window-list block

| Class | Where |
|---|---|
| `.block-window-list` | Block container. |
| `.block-window-list .wl-row` | Row per window. |
| `.block-window-list .wl-row.dulled` | Modifier for occluded windows (rendered faded). |

### Window-diagram block

| Class | Where |
|---|---|
| `.block-window-diagram` | Block container. |
| `.block-window-diagram .diagram-panel-grid` | The matrix container. |
| `.block-window-diagram .diagram-panel` | A single panel cell. |
| `.block-window-diagram .diagram-panel.center` | Centre-panel modifier (inward-arrows SVG). |
| `.block-window-diagram .diagram-panel.fill` | Maximise-panel modifier. |
| `.block-window-diagram .diagram-cell` | Grid sub-cell inside a panel. |
| `.block-window-diagram .diagram-cell.has-key`, `.left-line`, `.top-line` | Cell modifiers (key-occupied, borders). |

### Chooser

| Class | Where |
|---|---|
| `.chooser` | Outer panel. |
| `.chooser-search` | Search-input container. |
| `.chooser-input` | The `<input>`. |
| `.chooser-results` | Result `<ul>`. |
| `.chooser-row` | Result `<li>`. |
| `.chooser-row.selected` | Highlighted result. |
| `.chooser-row-text`, `.chooser-row-subtext` | Row text / detail line. |
| `.chooser-row-text .match`, `.chooser-row-subtext .match` | Fuzzy-match highlight. |
| `.chooser-dir` | Directory prefix in file results. |
| `.chooser-footer` | Footer (result count + nav hints). |
| `.chooser-actions` | Tab-panel action list container. |
| `.chooser-action-item`, `.chooser-action-key`, `.chooser-action-label`, `.chooser-action-desc` | Action panel rows. |

## Customisation paths

### Smallest change: tint the host header

```scheme
(set-host-header! 'background "darkorchid")
```

`--color-host-bg`, `--color-host-fg` (defaults to white), `--color-host-sep`
(falls through) are set. The overlay header strip, the sticky-mode
border, and `'sticky-target` cell markers all inherit the colour.

### Override variables only

`set-overlay-css!` is the last CSS layer, so an override block sits
cleanly on top:

```scheme
(set-overlay-css! "
  :root {
    --color-key: #5b9bd5;
    --color-group: #d68a2d;
    --color-category: #2f6b80;
    --color-label: #232323;
    --overlay-bg: rgba(255, 255, 255, 1);
    --overlay-border: rgba(60, 60, 60, 1);
  }
")
```

### Override classes

For shape changes (typography, spacing, custom widgets):

```scheme
(set-overlay-css! "
  .overlay {
    backdrop-filter: blur(20px);
    background: rgba(40, 40, 40, 0.85);
  }
  .entry-key { font-weight: 700; }
  .entry-label { font-style: italic; }
  .overlay-footer { display: none; }
")
```

### A worked dark-mode override

```scheme
(set-overlay-css! "
  :root {
    --overlay-bg: rgba(28, 28, 30, 0.96);
    --overlay-border: rgba(255, 255, 255, 0.18);
    --color-key:      rgba(120, 170, 240, 1);
    --color-label:    rgba(230, 230, 230, 1);
    --color-group:    rgba(240, 175, 80, 1);
    --color-category: rgba(130, 180, 210, 1);
    --color-arrow:    rgba(140, 140, 140, 1);
    --color-header:   rgba(170, 170, 170, 1);
    --color-separator:rgba(255, 255, 255, 0.10);
    --diagram-line:   rgba(255, 255, 255, 0.55);
    --diagram-cell-bg: #2a2a2c;
    --chooser-input-bg: rgba(40, 40, 40, 1);
    --chooser-input-border: rgba(255, 255, 255, 0.15);
    --chooser-selected-bg: rgba(120, 170, 240, 0.18);
    --chooser-action-bg: rgba(36, 36, 38, 1);
  }
")
```

The same CSS applies to overlay, chooser, and all three bundled
blocks because every visual class consumes the `--color-*` vocabulary.

## See also

- [renderer-protocol.md](renderer-protocol.md) — how blocks emit HTML
  the CSS targets.
- [dsl.md](dsl.md#set-overlay-css-css-string) — `set-overlay-css!`,
  `set-host-header!`.
