---
kind: work
---

# 050 — Build the WezTerm backend

## Goal

New module `(modaliser apps wezterm)` exporting `wezterm:register!`,
`wezterm:configure-entry`, and `wezterm:backend`. Internal backend
record implements 13/14 ops via `wezterm cli`; the 4 `move-pane-*`
ops come from a keystroke-proxy to keybinds that `configure-entry`
writes into the user's `wezterm.lua`.

## Context

- Recovery notes: `groves/terminal-backends/done/010-recover-design/
  notes/wezterm.md` — full op recipe matrix; the move-pane gap and
  the keystroke-proxy workaround path via `RotatePanes` action;
  JSON shape with `tty_name`, `is_active`, `left_col`, `top_row`,
  `size{rows,cols,pixel_width,pixel_height}`.
- ADR-0005 — configure-entry day-one.
- ADR-0007 — toggle-pane-zoom via `TogglePaneZoomState` action
  (wezterm-lua-side; invoke via existing keybind or write one in
  configure-entry).
- Install pattern: `brew install --cask wezterm`. Headless probe
  via `wezterm-mux-server --daemonize` + `wezterm cli --prefer-mux
  <op>` per notes/wezterm.md.

## Done when

- `brew install --cask wezterm` (record exact cask version).
- New module `(modaliser apps wezterm)` exports:
  - `wezterm:register!`
  - `wezterm:configure-entry` — overlay action that appends to
    `~/.wezterm.lua` (or `~/.config/wezterm/wezterm.lua`) the
    keybinds required for move-pane (and optionally toggle-zoom
    if the user lacks a default). Idempotent — re-running detects
    existing keybinds and skips.
  - `wezterm:configured?` — `#t` if `wezterm.lua` contains the
    move-pane keybinds (parse the file or test for marker comments
    written by configure-entry).
  - `wezterm:backend`
- Internal record fields populated:
  - 9 native ops (4 focus, 4 split, focus-pane-by-digit) via
    `wezterm cli` per notes/wezterm.md.
  - 4 move-pane ops via keystroke-proxy. **Field is `#f` if
    configured? returns `#f`** — capability predicates report
    accurately.
  - `toggle-pane-zoom` via keystroke-proxy to the WezTerm zoom
    keybind. Always-on (`TogglePaneZoomState` is in WezTerm's
    default key layer); no configure-entry contribution.
  - `focused-pane-id` from `pane_id` field of the `is_active` JSON
    entry.
  - `detect-foreground-command` derived from `tty_name` +
    existing `tty-foreground-command`.
- Hand-verify: in a real WezTerm session, all 9 native ops via
  `(terminal:focus-pane-…)` etc. work; before running
  `(wezterm:configure-entry)`, `(terminal:supports-move-pane?)`
  is `#f`; after, `#t` and `move-pane` works via keystroke proxy.
  Chips render in correct positions (WezTerm exposes cell-pixel
  dims directly — should be more accurate than iTerm).
- `brew uninstall --cask wezterm` (matches recovery pattern; user
  doesn't run WezTerm daily).

## Notes

- The `configure-entry` writes user-visible config. Follow the
  iTerm `configure-entry` pattern: show an overlay describing what
  will be added, get explicit confirmation, then write. Don't
  silently modify the user's `wezterm.lua`.
- Pad value for chip-geometry: WezTerm's `window_padding` defaults
  to non-zero. If chips land slightly off, expose padding as a
  Modaliser-side option, or query the live config via the WezTerm
  CLI's config-getter (if one exists — research at probe time).
- The cask hasn't refreshed in ~22 months per notes/wezterm.md
  (Feb 2024 nightly tag). If a newer version is available by the
  time this leaf runs, prefer it. Major-version drift could change
  CLI surface — re-probe before assuming notes/wezterm.md still
  applies.
