# How-to guides

Goal-oriented recipes for specific Modaliser tasks. Each page assumes
you've completed the [quickstart](../quickstart/index.md) and know
when to reach for the [reference](../reference/) for form-by-form
detail.

If you want to *learn the system*, work through the quickstart first;
if you want to *look something up*, the reference is exhaustive. The
how-tos sit between those — short walkthroughs for problems users hit
once their config grows past the seeded defaults.

If you'd rather *learn the system* through a worked example before
reaching for recipes, start with the tutorial:
[Modal Thinking — build a window-manager leader](../tutorials/modal-thinking.md).

## Configuration basics

- [Add a binding to the global tree](add-a-binding.md) — the smallest
  edit, end to end: open `config.scm`, drop a `(key …)`, relaunch.
- [Add a per-app tree](add-a-per-app-tree.md) — wire the local leader
  (F17) to fire app-specific bindings while a given app is frontmost.
- [Split your config across files](split-your-config.md) — pull
  bindings out of `config.scm` into your own `.sld` libraries under
  `~/.config/modaliser/`.

## Terminal integration

- [Vary the terminal tree by what's in the focused pane](terminal-pane-aware-tree.md)
  — make F17 show different bindings depending on whether nvim, a
  git TUI, or a plain shell is running in the focused iTerm split.

## Modal navigation

- [Set up a sticky mode](sticky-mode.md) — a focus-movement mode where
  `hjkl` keep moving without re-pressing the leader.

## Selectors and search

- [Add a fuzzy-finder for a custom data source](fuzzy-finder.md) —
  build a chooser over your own list of items, with primary and
  secondary actions.

## Theming

- [Customise the overlay theme](customise-theme.md) — recolour the
  overlay, chooser, and chips by editing
  `~/.config/modaliser/theme.css`.

## Operational

- [Debug "my binding does nothing"](debug-binding.md) — the checklist
  for the five most common reasons a binding silently no-ops.
- [Use Modaliser over a remote desktop](remote-desktop.md) — the
  pass-and-arm mechanism for when a host and a remote machine both
  run Modaliser and see the same trigger keys.
