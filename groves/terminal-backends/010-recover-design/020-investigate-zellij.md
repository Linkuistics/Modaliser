---
kind: work
---

# 020 — Investigate zellij

**Surface:** full (13 ops + detection).
**Install state:** present today (`zellij 0.44.3` at `/opt/homebrew/bin/zellij`).
No install / uninstall needed.

## Probe — operations

zellij ops are issued via `zellij action`:

- `zellij action move-focus left|right|up|down`           → focus-pane-{h,j,k,l}
- `zellij action new-pane --direction down|right`         → split-pane-{j,l}
  (probe whether splits in the other directions need a different
  command or aren't possible — zellij may not natively support
  split-up or split-left)
- `zellij action move-pane --direction left|right|up|down` → move-pane-{h,j,k,l}
  (verify direction support)
- `focus-pane-by-digit` — zellij has `zellij action focus-next-pane`
  but not focus-by-index out of the box; check whether
  `zellij action go-to-tab` or `focus-pane <id>` exists in 0.44.x.
  Chip rendering: zellij plugins can paint floating overlays;
  a simpler alternative is sending ANSI escapes to each pane's tty
  (the prior investigation likely chose one of these — try both).

## Probe — detection

Phase-1 docs claim zellij exposes no per-pane tty/command query.
User recall contradicts this — solutions were found. Candidates to
probe in order:
- `zellij action dump-screen <file>` — does it expose anything
  useful in the dump that identifies the focused pane's process?
- `zellij list-clients` / `zellij list-sessions` — what's in JSON?
- `lsof` on the zellij process — its file descriptors include the
  ptys of each pane; the *focused* one can sometimes be picked by
  read-write activity.
- A zellij plugin (Rust/WASM) that exposes focus state via shared
  file. Heavier; only if the lighter approaches fail.

## Safety

`zellij action` targets the active session. Use a dedicated test
session — `zellij --session probe-pane-backends` — and tear down
with `zellij kill-session probe-pane-backends` at the end.

## Capture

Write `notes/zellij.md` with:
- Version probed (`zellij --version`).
- One Scheme snippet per op (or `;; unsupported by zellij` if no
  workaround found).
- Detection recipe.
- Limitations: which ops degrade, which are exact, which require a
  plugin or hack.
- Capability matrix row.
