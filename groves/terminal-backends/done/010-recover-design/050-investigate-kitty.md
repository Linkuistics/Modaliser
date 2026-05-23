---
kind: work
---

# 050 — Investigate kitty

**Surface:** full (13 ops + detection).
**Install state:** not installed. `brew install --cask kitty`,
probe, `brew uninstall --cask kitty` at the end.

## Prerequisite

Kitty's IPC requires `allow_remote_control yes` in
`~/.config/kitty/kitty.conf` (or `--listen-on` at launch). Document
this in the recipe — users must configure once.

## Probe — operations

- Focus directional: `kitty @ focus-window --match
  neighbor:left|right|top|bottom` → focus-pane-{h,j,k,l}.
- Split: `kitty @ launch --location=hsplit|vsplit` creates a new
  window via split → split-pane-{h or j; or l/k via reversal}.
  Map directions carefully.
- Move-pane: kitty doesn't expose a direct "move window left in
  layout" in `@` IPC. Probe whether `kitty @ action move_window_*`
  exists, or whether move-pane has to be keystroke-proxied
  (the user's `kitty.conf` would map e.g. `ctrl+shift+arrow` to
  `move_window left`).
- `focus-pane-by-digit`: `kitty @ ls` enumerates windows; each has
  an `id`. `kitty @ focus-window --match id:N` focuses one. Chip:
  `kitty @ send-text --match id:N "<label>"` paints text inside the
  window (it'll appear at the cursor — coarse but visible).

## Probe — detection

`kitty @ ls` returns JSON: OS windows → tabs → windows; each window
has `is_focused`, `pid`, `cmdline`, and `foreground_processes`
(list of `{cmdline, pid}`). The foreground-processes-list ordering
(outermost vs innermost first) is not verified in phase-1 docs —
check on the installed version.

## Capture

Write `notes/kitty.md` with:
- Version (`kitty --version`).
- One Scheme snippet per op (note where keystroke-proxy was needed
  vs IPC).
- The `allow_remote_control` prerequisite.
- Detection recipe + foreground-processes ordering finding.
- Capability matrix row.
