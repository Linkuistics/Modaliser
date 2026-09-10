# layout-controls-k2


## Goal

Produce `docs/research/layout-controls-a.md`: a primary-source-backed survey of
layout control suitable for Modaliser, grounded in the editor-list-plus-controls
scenario and the user's requirement that wider list contents do not move groups.



## Context

Read `docs/research/configuration-exploration-context.md`, especially Layout and
Shared scenarios, and verify relevant current code rather than restating comments.
The downstream `configuration-design-k5` needs layout semantics, an authoring
shape, sizing/overflow behavior, and implementation-independent trade-offs.

## Done when

- Existing controls and the current renderer's limits are distinguished from
  proposed controls, including the current aspect-balance sizing policy.
- Grid, flow, and masonry are compared as behaviors; nested groups, stable track
  widths, min/preferred/max sizing, overflow, order, empty/dynamic lists, and
  available-screen-width adaptation are addressed.
- Compare screen-level options, a compositional Display-value layout tree, and a
  renderer/CSS escape hatch. Apply each to the same VS Code example.
- Current official CSS/WebKit deployment support and fallback implications are
  cited, including the supported macOS floor; do not infer support from a comment.
- Relevant prior art has a walk-away check and every attributed failure mode has
  a primary citation. Evidence gaps and untested assumptions are explicit.
- The conclusion gives a provisional direction and questions the design must
  settle, with no app implementation or runnable prototypes.

## Notes

Documentation only. No package installs, app launches, source/test changes, or
personal-config edits. Do not grow implementation or prototype leaves. A solo
survey is sufficient here; no research pair has been commissioned.
