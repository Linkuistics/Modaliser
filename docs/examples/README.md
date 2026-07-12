# Example configurations

Real-world `config.scm` snapshots, kept for reference. These are *not* loaded
by the app — they show how the bundled libraries compose in practice.

## `config.scm`

A working user config (snapshot 2026-06-20). Notable patterns:

- **Inlined per-app trees** (iTerm, Dia) alongside the global tree, rather than
  via the `register!` factories — easier to tweak in place.
- **Dia browser tree** (`company.thebrowser.dia`): a `t` Tabs group (new tab +
  an AppleScript-backed fuzzy tab chooser) and an `r` **Recent Tabs** Walk
  that drives Dia's ctrl-tab MRU switcher — holding control across the
  Walk and committing on Return / cancelling on Escape via the `on-leave`
  exit reason. See
  [`../specs/2026-06-19-keystroke-modifier-release-and-down-up.md`](../specs/2026-06-19-keystroke-modifier-release-and-down-up.md)
  for the mechanics.
- **iTerm tree** with pane focus/split/move, a tab sub-screen (`open`), and
  the pane-list block.
- **Window-manager drill-down** (`open`), launcher selectors, and web-search
  bindings.
