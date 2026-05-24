# Terminal-backends: pane zoom in the op surface

`toggle-pane-zoom` (a single, non-directional, stateless toggle op)
joins the locked op surface alongside the 12 directional ops and
`focus-pane-by-digit`, bringing the count from 13 to 14. The
capability predicate `(supports-zoom?)` gates it per backend; trees
that span backends include the zoom binding behind the predicate so
backends without zoom simply omit it.

At v1, support is uneven by design:

- **iTerm.** Supported via existing keystroke proxy (the user's tree
  already has "z Toggle Zoom" wired up).
- **WezTerm.** Supported via `wezterm cli zoom-pane --toggle` — a
  CLI subcommand added some time after the ADR's recovery-phase
  notes. The original "via `TogglePaneZoomState` Lua action" plan
  (which would have needed a configure-entry to bind it to a keybind)
  is unnecessary now that the CLI exposes it natively.
- **tmux.** Supported (`resize-pane -Z`).
- **zellij.** Supported (`action toggle-fullscreen` or equivalent).
- **Ghostty.** Supported (`perform action "toggle_split_zoom"`).
- **Kitty.** Not natively supported in the "zoom one pane" sense
  (`(supports-zoom?)` returns `#f`).
- **Alacritty.** Not applicable (no panes).

The trade-off was keeping zoom out of the abstraction (status quo —
users wire keystroke bindings manually) vs. including it with
predicate gating. Including it makes generic trees portable across
backends that *do* have zoom without users hand-wiring keystrokes per
backend; the gating ensures backends without zoom don't pretend.

This is the first non-directional op besides `focus-pane-by-digit`
and the first whose capability predicate is meaningfully `#f` for a
splitting backend (Kitty). It sets the pattern for future
"asymmetric" ops (close, resize, etc.) when those come into scope.
