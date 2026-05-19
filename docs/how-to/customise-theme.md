# How to customise the overlay theme

All Modaliser visuals — overlay, chooser, chips on screen — come from
CSS. Your customisations live in `~/.config/modaliser/theme.css`,
which is auto-loaded at startup and concatenated after `base.css` in
the cascade. There's no Scheme setter; edit the file and relaunch.

## You'll need

- A colour or two you want everywhere.
- For the full variable inventory and class list:
  [reference/theming.md](../reference/theming.md).

## Steps

1. **Open or create `~/.config/modaliser/theme.css`.** Modaliser
   reveals the config dir from the menu bar icon's **Settings…** item.

2. **Set the host theme — the single biggest-effect change.** One
   colour pair recolours the overlay header, the chooser header, the
   sticky-mode border accent, sticky-target markers, and every chip on
   screen (window-list chips, iTerm pane chips). All those visuals
   `var(--color-host-*)` through to these declarations:

   ```css
   :root {
     --color-host-bg: dodgerblue;
     --color-host-fg: white;
   }
   ```

3. **Tweak overlay colours** with the per-role variables. These don't
   inherit from `--color-host-*` — they're independent slots:

   ```css
   :root {
     --color-key:      #5b9bd5;        /* key glyphs in entries     */
     --color-label:    #232323;        /* entry labels              */
     --color-group:    #d68a2d;        /* labels that open submenus */
     --color-category: #2f6b80;        /* category labels           */
   }
   ```

4. **Recolour chips independently of the host theme.** Chips inherit
   `--color-host-*` by default; override the `.chip` rule directly if
   you want them to stand apart:

   ```css
   .chip {
     background: tomato;
     color: white;
     border-radius: 12px;
     font-size: 48px;
   }
   ```

5. **Save and relaunch.** Modaliser doesn't watch the file — the menu
   bar icon's **Relaunch** picks up your edits.

## Verify it worked

Tap F18 — the overlay header should show your new colour. Open a
window-list overlay (`w` in the seeded config) — chip backgrounds
should match. If a chip looks wrong, remember chips are resolved at
boot via a hidden probe WebView; *theme changes always require a
relaunch*, even when overlay edits would work in a hypothetical hot
reload.

## A worked dark theme

```css
/* ~/.config/modaliser/theme.css */
:root {
  --overlay-bg:        rgba(28, 28, 30, 0.96);
  --overlay-border:    rgba(255, 255, 255, 0.18);
  --color-key:         rgba(120, 170, 240, 1);
  --color-label:       rgba(230, 230, 230, 1);
  --color-group:       rgba(240, 175, 80, 1);
  --color-category:    rgba(130, 180, 210, 1);
  --color-arrow:       rgba(140, 140, 140, 1);
  --color-header:      rgba(170, 170, 170, 1);
  --color-separator:   rgba(255, 255, 255, 0.10);
  --chooser-input-bg:  rgba(40, 40, 40, 1);
  --chooser-input-border:  rgba(255, 255, 255, 0.15);
  --chooser-selected-bg:   rgba(120, 170, 240, 0.18);
  --chooser-action-bg:     rgba(36, 36, 38, 1);
}
```

Same CSS applies to overlay, chooser, and every bundled block —
they all consume the same `--color-*` vocabulary.

## Notes

**Cascade order.** `base.css` first, then each block library's CSS in
import order, then your `theme.css`. So your declarations always win
at equal specificity.

**Class overrides beat variable overrides** when you need shape
changes (typography, spacing, custom widgets):

```css
.overlay {
  backdrop-filter: blur(20px);
  background: rgba(40, 40, 40, 0.85);
}
.entry-key { font-weight: 700; }
.overlay-footer { display: none; }
```

The class inventory is in [reference/theming.md](../reference/theming.md).

**Removed Scheme setters.** If you find old config snippets calling
`(set-overlay-css! …)`, `(set-host-header! …)`, or passing
`'chip-options` / `'hint-options` to block constructors, those APIs
are gone. Rewrite against CSS — `--color-host-bg`, `.chip`, and the
`--color-*` variables cover the cases those setters used to handle.
The migration section of [reference/theming.md](../reference/theming.md)
has direct old → new mappings.

## Related

- [reference/theming.md](../reference/theming.md) — full variable
  inventory, class list, chip-probe internals.
- [reference/renderer-protocol.md](../reference/renderer-protocol.md)
  — for theming custom block renderers.
