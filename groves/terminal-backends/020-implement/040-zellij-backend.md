---
kind: work
---

# 040 — Build the zellij backend

## Goal

New module `(modaliser muxes zellij)` exporting `zellij:register!`
(and `zellij:backend` for testing). Internal backend record
implements all 14 ops via `zellij action` CLI. Multi-session-local
via the same tty-correlation machinery as tmux.

## Context

- Recovery notes: `groves/terminal-backends/done/010-recover-design/
  notes/zellij.md` — op recipes, the `new-pane -d` documentation
  bug (`--help` lies; all four directions work), the first-run
  "About Zellij" floating overlay gotcha, pane-id sparseness.
- ADR-0006 — multi-session local; same tty-correlation pattern as
  tmux.
- ADR-0007 — `toggle-pane-zoom` semantics; zellij implementation is
  `action toggle-fullscreen` (verify exact action name during
  implementation — notes/zellij.md doesn't pin it).
- zellij is **already installed** on the user's machine (zellij
  0.44.3 retained from recovery probe per recent root BRIEF).
  No fresh install needed.

## Done when

- New module `(modaliser muxes zellij)` exports `zellij:register!`
  and `zellij:backend`.
- Internal record fields populated:
  - All 14 ops via recipes in notes/zellij.md.
  - `focused-pane-id` from the `terminal_<id>` field returned by
    `action list-panes -j -a` filtered for `is_focused: true,
    is_plugin: false, is_floating: false`.
  - `detect-foreground-command` returns `pane_command` from the
    same JSON.
  - `configured?` returns `#t` (no provisioning required).
- Multi-session-local handled via shared tty-correlation helper
  from façade leaf 010.
- Hand-verify same as tmux: iTerm + zellij in focused pane, all 14
  ops route correctly; multi-session case (two iTerm panes each in
  different zellij sessions) targets the right session.
- Daily-driver verify: the user's existing zellij usage continues
  to work — `(iterm:register!)` + `(zellij:register!)` together,
  with the user's existing context-suffix flow returning
  `"/zellij"` for the variant tree.

## Notes

- The "About Zellij" overlay only appears on a fresh install. The
  user's existing zellij won't show it; first-time users would.
  Production code filters `is_plugin: true && is_floating: true`
  per notes/zellij.md.
- Pane IDs are sparse — treat as opaque. Don't assume contiguity.
- zellij is fast enough that the tty-correlation walk + JSON parse
  per leader press is fine. If it isn't, the cache from façade 010
  saves it.
- This leaf is short because zellij's mechanism mirrors tmux's
  almost exactly. If a generalisation lands as the tmux and zellij
  backends converge — e.g. a `<mux-backend>` helper that reduces
  duplication — fold it back to façade leaf 010 (or a new utility
  module) rather than carrying parallel code in both leaves.
