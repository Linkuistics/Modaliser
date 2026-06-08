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

## Verification outcome (2026-06-08 — CONFIRMED for the strong invariant)

The original same-app symptom is **fixed**. Evidence:

- **Live repro, user-confirmed.** Built + installed via `./scripts/install.sh`
  (stable "Modaliser Dev" cert → TCC preserved). Two overlapping iTerm
  windows and two overlapping Dia windows on one space; `w` overlay
  invoked. User observation: all chips distinct, no two overlapping, and
  every window (incl. the occluded back windows) aimable by digit —
  "that works".
- **Unit tests green** (the algorithmic proof of the invariant):
  `SameAppChipCollisionTests` (7, incl. `fullyStackedFrames…`,
  `collectedOccludersRelocateBackChip_noOverlap`) and the Stage-B suite
  `tenFullyStackedSameApp_allDistinctAllPresent` + the two-iTerm symptom
  `twoVisibleChipsSameCorner_deCollided`.
- **Durable evidence channel added.** `HintsLibrary.hints-show` now dumps
  the final painted chip rects via `os.Logger`
  (subsystem `dev.antony.Modaliser`, category `chip-placement`) and
  self-checks pairwise overlap: clean run → `.notice`, any overlap →
  `.error`. Read with:
  `log show --last 10m --info --predicate 'subsystem == "dev.antony.Modaliser"'`.
  (Not captured *this* run: the tested process predated the `.notice`
  build — `.debug` is memory-only. The user's direct observation + green
  tests are sufficient for the original invariant; future runs persist.)

## Follow-up surfaced (→ leaf 040)

During verification the user requested a **placement-quality refinement**,
not a disambiguation gap: a *fully-occluded* window's cascade chip should
stay **within that window's own bounds** (drawn over the occluder, still
faded) rather than being flung to free screen space. The row list itself
was *not* reported insufficient, so the punted disambiguation stays
punted. The refinement is grown as sibling leaf `040-in-bounds-cascade`
(design approved; spill-off-window when a small stacked cluster overflows).
