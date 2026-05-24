---
kind: work
---

# 070 — Build the Ghostty backend

## Goal

New module `(modaliser apps ghostty)` exporting `ghostty:register!`
and `ghostty:backend`. 13/14 ops via AppleScript (no `move-pane-*`
— `move_split` doesn't exist in Ghostty 1.3.1's keybind vocabulary).
No `configure-entry` until upstream adds `move_split`.

## Context

- Recovery notes: `groves/terminal-backends/done/010-recover-design/
  notes/ghostty.md` and `notes/ghostty-current.md` — AppleScript
  surface from 1.3.0+; `split direction <dir>`, `focus <terminal>`,
  `perform action "<keybind>" on <terminal>`; the timing race on
  `working directory`; phantom terminals from prior sessions;
  `name` field unreliability.
- ADR-0005 — no day-one configure-entry for Ghostty.
- ADR-0007 — toggle-pane-zoom via `perform action
  "toggle_split_zoom"`.
- Install pattern: `brew install --cask ghostty`. AppleScript
  probing requires `is running` guard per notes/iterm.md, or
  Ghostty auto-launches via Launch Services.

## Done when

- `brew install --cask ghostty` (record exact cask version; ≥ 1.3.0
  required).
- New module `(modaliser apps ghostty)` exports `ghostty:register!`
  and `ghostty:backend`.
- Internal record fields populated:
  - 9 ops (4 focus, 4 split, focus-pane-by-digit) via AppleScript
    per notes/ghostty-current.md.
  - 4 `move-pane-*` ops = `#f`. `(supports-move-pane?)` reports
    correctly.
  - `toggle-pane-zoom` via `perform action "toggle_split_zoom"`.
  - `focused-pane-id` = id of `focused terminal of selected tab of
    front window`.
  - `detect-foreground-command` derived from the focused terminal's
    `name` (with the unreliability caveat documented in code) OR
    via process-tree walk if `name` is empty.
- The freshly-split timing race handled: ops that read `working
  directory` retry on empty string (up to ~1s).
- Phantom-terminals filter: only enumerate terminals of the current
  tab/window, not all terminals of the application.
- AppleScript `is running` guard on every probe call to prevent
  Ghostty auto-launching during background detection.
- Hand-verify: in real Ghostty, all 13 ops work via the façade.
  `(terminal:supports-move-pane?)` is `#f`. Chip overlay positions
  via AX subview discovery (if it works on Ghostty.app) or
  adjacency-probe BFS as fallback.
- `brew uninstall --cask ghostty` after probe.

## Notes

- Ghostty's AppleScript is the surprise in the recovery phase — 060
  initially missed it; 065 corrected. The implementation must use
  the AppleScript surface, not the lossy keystroke-proxy path 060
  proposed.
- The `working directory` race is real (verified in notes/ghostty-
  current.md). Production code should retry once after ~1s rather
  than failing the op.
- AX-subview discovery on Ghostty.app is the "Open verification
  item" from notes/ghostty-current.md. If it works, chips are
  pixel-exact. If not, adjacency-probe BFS works but means many
  AppleScript calls per render — acceptable for v1; optimise later.
- When Ghostty eventually adds `move_split` (1.4+ per user recall,
  unverified), wire the 4 `move-pane-*` ops via `perform action
  "move_split:<dir>"` and ship a `ghostty:configure-entry` if
  user-keybind provisioning is required.
