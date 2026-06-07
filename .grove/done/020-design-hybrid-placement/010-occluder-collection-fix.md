# 010-occluder-collection-fix

**Kind:** work

## Goal
Make `WindowLibrary.collectOccluderRects` count same-app front windows as
occluders, stopping the front-to-back walk only at the *actual target*
(Cause 1 / ADR-0009). This is Stage A of the design spec.

## Context
- Authoritative: `docs/specs/window-chip-placement-design.md` §"Stage A",
  and `docs/adr/0009-same-app-windows-count-as-occluders.md`.
- Current bug site: `WindowLibrary.swift` `collectOccluderRects` — the
  early `return occluders` on `entryPid == targetPid` (and the matching
  docstring in `findChipPositionFunction`).
- The target rect is already available in `findChipPositionFunction`
  (`wx,wy,ww,wh`) but is **not** passed to `collectOccluderRects` today —
  thread it through so the target can be disambiguated by rect when `wid`
  is unreliable (`_AXUIElementGetWindow` vs `CGWindowList` disagreement).

## Done when
- `collectOccluderRects` (or its replacement) collects every front,
  opaque, non-Modaliser window — *including same-app windows* — until it
  reaches the target.
- Target identification: match by `wid` when `wid > 0` and present; else
  pick the same-PID candidate whose bounds match the target rect (within a
  small tolerance). If neither resolves, keep the bias-to-visible fallback
  (treat as unoccluded — do **not** over-collect).
- The occluder-collection logic is refactored into a **pure, testable**
  function over an injected window-list array + target (so it can be unit
  tested without a live `CGWindowListCopyWindowInfo`).
- Docstrings updated to reflect the reversed rule (no longer "same-app
  windows count as the target, not occluders").
- A unit test drives the pure function: a same-app back window now yields
  `occluders = [front]` (was `[]`); the buggy assertion in
  `SameAppChipCollisionTests` that fed `occluders=[]` is updated/retired to
  match real behaviour.
- `swift build` / `swift test` green.

## Notes
- Don't touch Stage B here — a fully-occluded window correctly flipping to
  `chipPosition == nil` is expected and is handled by leaf 020.
- Keep the alpha<1 skip and the Modaliser-own-PID skip unchanged.
