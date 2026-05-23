---
kind: work
---

# 060 — Investigate Ghostty (v1.4+ gate)

**Surface:** full IF v ≥ 1.4 exposes the workaround the prior
investigation used. Otherwise detection-only (and users add a mux
inside).

**Install state:** not installed. `brew install --cask ghostty`,
probe, `brew uninstall --cask ghostty` at the end.

## Verify the 1.4 gate first

`ghostty --version` — confirm ≥ 1.4. If brew's current cask is
< 1.4, this task records the gap and stops; the abstraction treats
Ghostty as detection-only until a newer cask lands.

What 1.4 actually added to enable pane introspection is unknown.
Candidates worth checking against the 1.4 changelog before probing:
- A `ghostty +list-keybinds` / `+list-actions` CLI subcommand.
- A Unix-socket control API.
- Keybinding-triggered query that prints state to stderr.
- A `+show-config` or `+inspect` mode useful externally.

## Probe — operations (if 1.4+ exposes ops)

Default Ghostty keybinds:
- `cmd+alt+arrow` → focus split (keystroke-proxy candidate)
- `cmd+d` / `cmd+shift+d` → split right/down (keystroke-proxy)
- Move-pane: not in default binds; verify whether action keywords
  like `move_split_focus_left` etc. exist.

If Ghostty 1.4+ added a CLI for any of these, prefer it over
keystroke-proxy.

## Probe — detection

If no IPC, the workaround is "find the focused Ghostty window's
tty externally":
- `pgrep ghostty` → process(es).
- `lsof -p <pid>` → ptys held by ghostty.
- Disambiguating *focused* among them: the foreground process group
  of each pty differs; only the focused pane is interactive. May
  require window-position correlation with `osascript` (which
  ghostty window is frontmost / largest).

If 1.4 added a CLI, this gets much simpler — use it.

## Capture

Write `notes/ghostty.md` with:
- Cask version probed and ghostty version.
- Whether 1.4 gate holds in this cask.
- Per-op Scheme snippets (or "unsupported on this version" notes).
- The detection recipe — what 1.4 actually exposes vs the pre-1.4
  fallback.
- Capability matrix row.
- A clear "splitting backend" vs "detection-only" verdict.
