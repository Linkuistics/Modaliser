# How to customise the overlay theme

All Modaliser visuals — overlay, chooser, chips on screen — come from
CSS. Your customisations live in `~/.config/modaliser/theme.css`,
which is auto-loaded at startup and concatenated after `base.css` in
the cascade. There's no Scheme setter; edit the file and relaunch.

The default look is the cheat-sheet style: white panel cards on a tinted
body, banded headers, soft mono keycaps, an indigo accent, IBM Plex type.

## You'll need

- A colour or two you want everywhere.
- For the full variable inventory and class list:
  [reference/theming.md](../reference/theming.md).

## Steps

1. **Open or create `~/.config/modaliser/theme.css`.** Modaliser
   reveals the config dir from the menu bar icon's **Settings…** item.

2. **Set the host theme — the single biggest-effect change.** One
   colour pair recolours the overlay header band, the chooser header,
   the Walk border accent, `'next` markers, and every chip
   on screen (window-list chips, iTerm pane chips). All those visuals
   `var(--color-host-*)` through to these declarations:

   ```css
   :root {
     --color-host-bg: dodgerblue;
     --color-host-fg: white;
   }
   ```

3. **Re-accent the cheat sheet.** The indigo `--accent` drives keys in
   lists, focus, selection, and panel-header text. Amber `--color-group`
   marks the `›` drill-in rows. These are independent of the host theme:

   ```css
   :root {
     --accent:      #0ea5e9;   /* keys-in-lists, focus, selection, headers */
     --color-group: #b45309;   /* rows that open a sub-screen              */
     --color-label: #232323;   /* entry + list labels                     */
   }
   ```

4. **Tune the panel cards.** The banded headers, soft keycaps, and tint
   are all variables:

   ```css
   :root {
     --overlay-body-bg: #eef1f6;   /* tint behind the panels */
     --panel-head-bg:   #e7eafc;   /* banded header fill      */
     --panel-head-fg:   #2f339c;   /* banded header text      */
     --keycap-bg:       #eef0f3;   /* soft keycap fill        */
   }
   ```

5. **Recolour chips independently of the host theme.** Chips inherit
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

6. **Save and relaunch.** Modaliser doesn't watch the file — the menu
   bar icon's **Relaunch** picks up your edits.

## Verify it worked

Tap your global leader — the overlay header band should show your new
colour and the panels your new accent. Open the Windows drill-down
(`w` in the seeded config) — chip backgrounds should match the host
theme. If a chip looks wrong, remember chips are resolved at boot via a
hidden probe WebView; *theme changes always require a relaunch*, even
when overlay edits would work in a hypothetical hot reload.

## A worked dark theme

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

  --chooser-input-bg: #2a2a2e;
  --chooser-input-border: rgba(255, 255, 255, 0.15);
}
```

Same CSS applies to overlay, chooser, panels, and every bundled block —
they all consume the same token vocabulary. The chooser's selected row
and the embedded lists' selection cursor share `--list-focus-bg` /
`--list-focus-bar`, so the dark accent carries through to selection too.

## Notes

**Cascade order.** `base.css` first, then each block library's CSS in
import order, then your `theme.css`. So your declarations always win
at equal specificity.

**Class overrides beat variable overrides** when you need shape
changes (typography, spacing, custom widgets):

```css
.overlay { backdrop-filter: blur(20px); }
.panel { border-radius: 12px; }
.entry-key { font-weight: 700; }
.overlay-footer { display: none; }
```

The class inventory is in [reference/theming.md](../reference/theming.md).

## Related

- [reference/theming.md](../reference/theming.md) — full variable
  inventory, class list, chip-probe internals.
- [reference/renderer-protocol.md](../reference/renderer-protocol.md)
  — for theming custom block renderers.
