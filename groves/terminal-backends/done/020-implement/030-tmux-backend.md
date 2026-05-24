---
kind: work
---

# 030 — Build the tmux backend

## Goal

New module `(modaliser muxes tmux)` exporting `tmux:register!` (and
`tmux:backend` for testing). Internal backend record implements all
14 ops via tmux CLI. Multi-session-local via tty correlation per
ADR-0006. Chip rendering via host AX frame + cell-pixel dims + tmux
pane coords.

## Context

- Recovery notes: `groves/terminal-backends/done/010-recover-design/
  notes/tmux.md` — full op recipe matrix, multi-session caveat
  (which ADR-0006 now resolves), chip-derivation arithmetic.
- ADR-0006 — multi-session local via tty correlation; SSH'd muxes
  out of scope.
- ADR-0007 — `toggle-pane-zoom` semantics (stateless toggle); tmux
  implementation is `resize-pane -Z`.
- Install pattern from done/.../040-investigate-tmux.md: `tmux new
  -d -s probe-tm` for headless probe; `tmux kill-session -t
  probe-tm` for teardown.

## Done when

- `brew install tmux` (record exact version probed against).
- New module `(modaliser muxes tmux)` exports:
  - `tmux:register!`
  - `tmux:backend` (the populated `<terminal-backend>` record)
  - (No public op exports — they live on the façade per ADR-0003.)
- Internal record fields populated:
  - All 14 ops via the recipes in notes/tmux.md, targeting
    `tmux -t <session>` where `<session>` is resolved by tty
    correlation (focused iTerm pane's tty → matching tmux client
    pid → its session).
  - `focused-pane-id` returns the `%N` pane id from
    `display-message -p '#{pane_id}'`.
  - `detect-foreground-command` returns
    `display-message -p '#{pane_current_command}'`.
  - `configured?` always returns `#t` (no provisioning required).
- Tty-correlation helper (from façade leaf 010) is exercised here;
  if its API needs adjustments, fix in 010 and re-validate.
- Hand-verify: with iTerm + tmux running in the focused pane,
  `(terminal:focus-pane-left)` moves tmux focus; `(terminal:split-
  pane-down)` splits tmux; `(terminal:focus-pane-by-digit)` paints
  chips and jumps. Verify multi-session by attaching two iTerm
  panes to different tmux sessions and confirming each pane's ops
  hit the right session.
- `brew uninstall tmux` after probe (matches recovery-phase
  pattern; the user retains tmux only if they were running it
  already).

## Notes

- The chip rendering for tmux uses *host* cell-pixel dims (not tmux-
  derived). When iTerm is the host, the host-cell-pixel-dims helper
  lands in `(modaliser terminal)` per the PRD — implement enough of
  it here to make tmux chips render acceptably; refine it in later
  per-host leaves if needed.
- The "first-run gotcha" notes from zellij don't apply to tmux —
  no floating overlay pane on first run.
- Multi-session disambiguation is the only architectural novelty
  vs. the recovery notes. Validate that case carefully (the
  recovery-phase probe didn't run the multi-client scenario; it's
  net-new here).
