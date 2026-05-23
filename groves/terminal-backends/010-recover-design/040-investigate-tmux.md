---
kind: work
---

# 040 — Investigate tmux

**Surface:** full (13 ops + detection).
**Install state:** not installed. `brew install tmux`, probe,
`brew uninstall tmux` at the end.

## Probe — operations

tmux's CLI is the cleanest of any backend. Confirm each:

- `tmux select-pane -L|-R|-U|-D` → focus-pane-{h,j,k,l}
- `tmux split-window -h|-v` → split-pane (horizontal/vertical);
  `-b` flag to put the new pane *before* the current one →
  controls h vs l, j vs k. Map carefully.
- `tmux swap-pane -t :.{up-of}|{down-of}|{left-of}|{right-of}` →
  move-pane-{k,j,h,l}. Verify the exact selectors.
- `focus-pane-by-digit`: **tmux has `tmux display-panes` built in**
  — it overlays a digit on each pane and accepts the digit to focus
  it. Try delegating to this directly; if its UX (e.g. timeout,
  styling) doesn't fit Modaliser's chip story, fall back to:
  `tmux list-panes -F '#{pane_index} #{pane_left},#{pane_top}
  #{pane_width}x#{pane_height} #{pane_tty} #{pane_current_command}'`
  for enumeration + position, render chips via `tmux send-keys`
  (or by writing to each pane's tty).

## Probe — detection

`tmux display-message -p '#{pane_current_command}'` for the
focused-pane command; `'#{pane_tty}'` for its tty. Phase-1 docs
already showed this.

## Big question

Is delegating `focus-pane-by-digit` to native `tmux display-panes`
acceptable? Pros: tmux's overlay is exact, no chip-positioning
work. Cons: tmux owns the UX, it's not part of Modaliser's overlay
system.

## Safety

tmux's CLI targets the default session if you're not inside one.
Use a dedicated test session: `tmux new -d -s probe-pane-backends`,
attach to probe, `tmux kill-session -t probe-pane-backends` at end.

## Capture

Write `notes/tmux.md` with:
- Version (`tmux -V`).
- One Scheme snippet per op.
- Whether `display-panes` won or we built our own chip renderer.
- Capability matrix row.
