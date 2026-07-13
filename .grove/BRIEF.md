# add-herdr-quit-binding — brief

## Goal

Round out the herdr variant trees' lifecycle surface: a `q` Quit drill for
leaving herdr (detach the client / stop the server), and workspace-local — not
global — tab listing/navigation in the `t` Tabs drill.

## Done when

- Both herdr variant trees (replace + augment) offer `q d` Detach and
  `q s` Stop Server (confirm-gated), with tests through the existing seams.
- The Tabs live-list and its digit-jump show only the focused workspace's
  tabs.

## Decomposition

Two sibling work leaves, one session each — the Quit group, then the tabs
scoping. Grown by plan-k1's grilling (2026-07-13).

## Pointers

- `Sources/Modaliser/Scheme/lib/modaliser/muxes/herdr.sld` — build-herdr-tree,
  the ops, and the seams (`current-herdr-async-runner`, `current-herdr-query-runner`).
- `Sources/Modaliser/Scheme/lib/modaliser/blocks/herdr-list.sld` — the live-list
  block (`kind-spec` for 'tabs; the worktrees kind already reads
  `result.source.source_workspace_id`, the filtering precedent).
- ADR-0013 (variant trees), ADR-0014 (async dialogs; `current-dialog-runner`).
- Glossary: Detach (herdr) vs Stop (herdr server) — added by plan-k1.

## Notes

Decisions from the grill, recorded here (none clear the ADR bar — all easily
reversible):

- "Quit" = **both** ops: `q` opens a Quit group — `d` Detach, `s` Stop Server.
  No double-tap lands anywhere (a fumbled `q q` is a no-op). `d`-means-close
  convention is acceptable here (detach ≈ close the client).
- **The library owns the group** (build-herdr-tree), including the
  keystroke-emitted detach (ctrl+b, q — herdr's default `prefix+q` binding,
  same v1 default-prefix assumption as the config's copy-mode key; document it
  at the detach op). `(modaliser input)` from the portable tree is established
  practice (apps/*.sld).
- Stop Server is confirm-gated via `dialog-confirm` (herdr's CLI stops
  immediately, no herdr-side confirm — unlike worktree remove), then
  `herdr-cmd-async "server stop"` (ADR-0014: never synchronous around a dialog).
- Test seams: **existing only** — `current-dialog-runner` +
  `current-herdr-async-runner` for Stop Server behaviour; detach gets a
  tree-shape assertion only (same trust level as the untested copy-mode key).
  No new keystroke seam.
