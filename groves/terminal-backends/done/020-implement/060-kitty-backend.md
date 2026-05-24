---
kind: work
---

# 060 — Build the Kitty backend

## Goal

New module `(modaliser apps kitty)` exporting `kitty:register!`,
`kitty:configure-entry`, and `kitty:backend`. 13/14 ops via `kitty @`
IPC (no `toggle-pane-zoom` — Kitty has no native single-pane zoom).
Chip geometry uses topology BFS over `neighbors`.

## Context

- Recovery notes: `groves/terminal-backends/done/010-recover-design/
  notes/kitty.md` — full op recipe matrix; the `splits` layout
  requirement; the compose-then-move pattern for split-left and
  split-up; topology-BFS chip geometry; `is_focused` + the
  `foreground_processes[-1]` indexing for fg cmd.
- ADR-0005 — configure-entry writes `allow_remote_control yes` +
  `enabled_layouts splits,...`.
- ADR-0007 — Kitty zoom is `#f`; document why in the backend code.
- Install pattern from notes: `brew install --cask kitty`; do NOT
  touch `~/.config/kitty/kitty.conf` for probing (user has 98 lines
  of A/B-rendering config). For probing, use
  `kitty --override allow_remote_control=yes --listen-on=unix:...`.

## Done when

- `brew install --cask kitty` (record exact cask version).
- New module `(modaliser apps kitty)` exports `kitty:register!`,
  `kitty:configure-entry`, `kitty:backend`.
- `kitty:configure-entry` overlay action:
  - Reads `~/.config/kitty/kitty.conf`.
  - Ensures `allow_remote_control yes` is present (add if missing;
    update if set to `no`).
  - Ensures `enabled_layouts` includes `splits` (add or amend).
  - Writes back with a marker comment so re-runs are idempotent.
  - **Backup the original** to `kitty.conf.modaliser-backup` before
    writing. The user's existing 98-line config is precious.
- Internal record fields populated:
  - 13 ops (4 focus, 4 split with compose-then-move for h/k, 4 move,
    focus-pane-by-digit) per notes/kitty.md.
  - `toggle-pane-zoom` = `#f`. `(supports-zoom?)` reports correctly.
  - `focused-pane-id` from the window with `is_focused: true` in
    `kitty @ ls`.
  - `detect-foreground-command` from `foreground_processes[-1]
    .cmdline[0]`.
  - `configured?` returns `#t` only if `kitty.conf` has the
    required directives (parse the file or shell out to
    `kitty @ get-options`).
- Topology-BFS chip geometry implemented and verified visually.
  Chips land within the correct pane (within ~1 cell-width is
  acceptable per [[feedback_chips_are_overlays]]).
- Hand-verify: with `kitty:configure-entry` run + Kitty restarted,
  all 13 ops via `(terminal:focus-pane-…)` work. Chip overlay
  jumps to the right pane.
- `brew uninstall --cask kitty` after probe.

## Notes

- The `splits` layout requirement is load-bearing. If the user's
  existing config lists `enabled_layouts tall,stack` (no splits),
  Kitty's `launch --location=vsplit` silently falls back to a
  layout-specific behaviour. `configure-entry` MUST add `splits`
  to the enabled_layouts; otherwise the backend is silently broken.
- AX-subview discovery on `kitty.app` is the "Open verification
  item" from notes/kitty.md — if it works, we get pixel-exact chip
  geometry without BFS. Try it during implementation. If it works,
  use it; if not, fall back to BFS. Either way, the backend ships
  with working chips at the end of this leaf.
- The `kitty @ select-window` native overlay is mentioned in
  notes/kitty.md as a fallback. Modaliser chips are `hints-show`
  per [[feedback_chips_are_overlays]] — don't use Kitty's native
  selector even if BFS proves unworkable. Worst case: ship 12/14
  by setting `focus-pane-by-digit` to `#f` and explaining in the
  capability matrix.
