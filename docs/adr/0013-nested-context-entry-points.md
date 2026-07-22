# Nested terminal contexts enter the FSM at inner entry points, not merged trees

When the frontmost iTerm pane runs an inner context (the herdr client), leader
activation does not swap in a merged variant tree; it activates the navigation
FSM at the inner context's **entry point** — the herdr entry node — exactly as
though the outer iTerm node were active and its standardised **step-in key
`.`** pressed. Backspace from the inner entry node walks to the outer iTerm
node along an ordinary edge, so the outer surface (splits drill, copy mode,
zoom) is never duplicated into a variant tree. The `.` edge is gated on
detection: no inner context running in the focused session → no edge, no
overlay row.

## Why it binds

- **Contexts compose by edges instead of multiplying by trees.** The retired
  model needed one registered variant screen per combination (`/herdr`,
  `/herdr+split`, and eventually × every mux); nesting needs one node per
  context and lets detection pick the entry point. The replace-vs-augment
  classifier (a tab-scoped AppleScript split count paid on every leader press
  while herdr was focused) is retired with it — nothing counts splits to pick
  a tree.
- **Backspace acquires a global meaning: step outward.** Entry lands at the
  innermost detected context; each backspace crosses one containment boundary.
  This is deliberately richer than the second-leader convention used for Jump
  Desktop (leader again = outer context), which toggles between contexts
  rather than walking a hierarchy.
- **Backend-DIRECT ops still bind per context node, never the
  `(modaliser terminal)` façade.** With herdr focused the façade's
  `active-backend` resolves to herdr, so façade pane ops on the *iTerm* node
  would drive the wrong layer. This survives from the variant-tree era: it is
  a property of two live backends in one window, not of tree merging.

## Considered options

1. **Merged variant trees** (replace `/herdr` vs augment `/herdr+split`,
   chosen per press by current-tab split count) — the previous decision here.
   Rejected: surface duplication, per-press classifier queries, and a
   registered screen per context combination. Reopened by: nothing — entry
   points strictly subsume it.
2. **Second-leader toggling** (the Jump Desktop convention generalised).
   Rejected: it relates exactly two contexts and carries no hierarchy;
   backspace already means "up", and nesting makes that meaning global.
   Reopened by: genuinely *peer* (non-nested) contexts, where "step out" has
   no meaning and a toggle is honest.

## Consequences

- Requires FSM support for activating at a named entry point with the
  outward edge in place (the explicit-FSM refactor; this grove). Cutover
  retires the variant-screen suffix path (`resolve-app-tree` + `/herdr`
  screens) and its split-count classifier; the composed context-suffix hook
  slims to pure detection/gating.
- Citations of this ADR in code and docs written against the variant-tree
  model (herdr/iTerm libraries, tests, terminal docs) are reconciled by the
  cutover leaf that retires that machinery.
- Augment-mode's known chip limitation (host frame takes the first
  `AXScrollArea`, wrong split possible in multi-split tabs) stops being a
  tree-model concern and becomes a plain geometry concern of the pane-chip
  pipeline.
