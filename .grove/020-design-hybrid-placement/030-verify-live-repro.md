# 030-verify-live-repro

**Kind:** work

## Goal
Verify the strong invariant live: reproduce the original same-app symptom
that started this grove and confirm it is gone — all chips distinct and
aimable — closing the root brief's "Done when".

## Context
- Root brief "Done when" + the 010 reproduction (two iTerm windows; two Dia
  windows, top-left aligned/stacked). Design: `docs/specs/window-chip-
  placement-design.md` §"Verification".
- Trigger: `(window:list-block 'chips? #t)`, bound under `w` in
  `default-config.scm`.

## Done when
- Source changes from leaves 010/020 are installed with `./scripts/install.sh`
  (NOT just "Relaunch" — that restarts the stale bundle; see memory).
- Reproduce live: two overlapping iTerm windows AND two overlapping Dia
  windows on one space; invoke the window-chip overlay.
- Confirm and capture (screenshot or chip-rect dump via `os.Logger`):
  - no two chips overlap (including the fully-stacked case);
  - every window has exactly one chip and typing its digit focuses it,
    including a fully-occluded back window.
- Sanity-check the punted disambiguation: confirm the row list (label + app
  + title) lets the user pick the right same-app window. If it does **not**,
  add a follow-up leaf rather than silently accepting it.
- Evidence recorded in the grove (append to this node's BRIEF or a
  `docs/` note) so the grove can finish.

## Notes
- This is the gate before `grove finish`: only retire the grove once the
  live symptom is confirmed fixed.
- Don't mutate the user's live windows destructively while testing (see
  memory: never chain a destructive op after a fallible one).
