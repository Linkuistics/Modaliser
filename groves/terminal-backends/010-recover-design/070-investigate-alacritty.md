---
kind: work
---

# 070 — Investigate Alacritty

**Surface:** detection only. Alacritty has no IPC, no splits, no
panes by design. Users add tmux / zellij inside for splits.

**Install state:** not installed. `brew install --cask alacritty`,
probe, `brew uninstall --cask alacritty` at the end.

## Probe — detection

One tty per Alacritty window; the canonical
`ps -t <name> -o pgid=,tpgid=,command=` reads its foreground
command directly (the same query `tty-foreground-command` in
`terminal.sld:42-51` already implements).

The interesting part is finding *which* tty for the focused
Alacritty window when more than one is open. macOS doesn't expose
tty-per-window for arbitrary apps. User recall: "indirect and
inexact" — likely one of:
- (a) Single instance assumption: if `pgrep alacritty` returns one
  pid, that's the tty (via `lsof`).
- (b) Frontmost-window correlation: combine `osascript` (which
  Alacritty window is frontmost) with process-tree walking from
  the alacritty pid.
- (c) Activity proxy: among alacritty's ttys, the one with the
  most recent stat-mtime is probably the focused one (hacky but
  often correct).

Probe each; pick the least-bad.

## No operations probe

The locked 13-op surface does not apply. Document this clearly in
notes — users adding a mux inside alacritty must call the mux
backend's ops, not alacritty's.

## Capture

Write `notes/alacritty.md` with:
- Version probed.
- Detection recipe with caveats ("inexact when multiple windows").
- Explicit "detection-only backend; mux-inside for splits" note.
- Capability matrix row.
