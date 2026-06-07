# 010-reproduce-and-confirm-cause

**Kind:** work

## Goal
Reproduce the same-app overlapping-window chip collision and **confirm the
actual cause** with evidence, so leaf 020 designs against a verified fault
rather than a code-reading hypothesis.

## Context
- Hypothesis to test (from a code map, NOT yet verified): in
  `Sources/Modaliser/WindowLibrary.swift`, `collectOccluderRects` stops
  scanning the front-to-back `CGWindowListCopyWindowInfo` order at the *first*
  same-PID entry, so a same-app window in front of the target is never counted
  as an occluder — leaving the target's chip at its natural corner where it
  collides with the front window's chip.
- The two placement stages live in `WindowLibrary.swift` /
  `ChipPlacement.swift` (Swift geometric) and
  `Sources/Modaliser/Scheme/lib/modaliser/blocks/window-list.sld` (Scheme dodge).
- Trigger: `(window:list-block 'chips? #t)`; default binding under `w` in
  `default-config.scm`.
- Build/run: source changes need `./scripts/install.sh` (Relaunch only
  restarts the stale bundle — see memory). Use `os.Logger` for diagnostics,
  not `NSLog` (invisible in unified log).

## Done when
- The collision is reproduced deliberately (e.g. two iTerm windows, or two Dia
  windows, overlapped) and captured (screenshot or chip-rect dump).
- The cause is **confirmed or corrected** with concrete evidence — e.g. logged
  occluder rects / chip positions showing exactly why two chips coincide.
- A short written finding lands in this grove (append to the root BRIEF.md
  Notes, or a `docs/` note) stating the verified cause for 020 to design from.

## Notes
- Verify, don't assume: if the real cause differs from the hypothesis, that
  correction IS the deliverable.
- No fix in this leaf — diagnosis only. Resist the one-line patch even if it
  looks obvious; 020 owns the design.
