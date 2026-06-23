# visual-skin-k5

**Kind:** work

## Goal

Make the cheat-sheet look the **new default**: restyle `base.css` to the spec §7
token vocabulary, applied to the panel-grid DOM + shared list-row classes.

## Context

- Spec §7 token table: indigo `--accent #4f46e5`, amber `--color-group #c2700f`,
  white `--panel-bg`, tinted `--overlay-body-bg #f6f7fa`, banded `--panel-head-*`,
  soft `--keycap-*`, `--list-*` inset, `--live #23c161`, separated `--footer-*`.
- `base.css` today: cream `--overlay-bg` (10), Menlo (17), `--color-host-*` chip
  fallbacks (469–470). The user-CSS slot (`~/.config/modaliser/theme.css`) is
  concatenated **last** in `overlay.scm` `overlay-full-css` so user declarations
  win — preserve that.
- Structure (spec §7): outer card → app/context **band** → **panel grid** →
  **separated footer strip**. Keycaps soft / mono / single-line; labels
  `white-space: nowrap` + ellipsis — **never wrap** (hard requirement).
- Depends on [[panel-grid-renderer-k4]] (real panel DOM) + [[fonts-k2]]
  (`@font-face` for `--font-family` / `--font-mono`).

## Done when

- `base.css` ships the new default tokens + panel / grid / banded-header / keycap
  / footer / live-list-inset rules; the overlay renders as the spec's panel
  document.
- All tokens overridable from `theme.css` (user-CSS slot stays last in the
  cascade).
- Chip palette still flows from `--color-host-*`; the chip-probe computed-style
  boot path is unaffected.

## Notes

- **Confirm the indigo accent default** against the chip / host palette here —
  recommend keep: the overlay accent and the per-app chip host-color are
  independent surfaces and harmonize (spec §12 open detail).
- Name the **shared list-row classes** so [[chooser-restyle-k7]] reuses the same
  vocabulary (one family across embedded lists + chooser).
