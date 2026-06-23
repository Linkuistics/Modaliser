# fragments-splice-k11

**Kind:** work

## Goal

Add the **`fragment`** form — a reusable, named chunk of layout (panels or command
rows) spliced into multiple screens/panels for DRY — built on the existing
`expand-splices` (state-machine.sld:205), the same splice mechanism `sticky-set`
already uses. Then prove it by DRYing a real shared set. Depends on
[[lowering-k10]] (the new container forms must exist and already run
`expand-splices` over their bodies).

## Done when

- **`fragment`** produces a `'kind 'splice` node (so `expand-splices` hoists its
  children in place — nothing downstream sees the fragment). A `fragment` may
  carry **panels** (for screen-level reuse) or **command rows** (for panel-level
  reuse); both splice transparently where placed.
- A reusable fragment is defined once and spliced into ≥2 sites — DRY a genuine
  shared set (e.g. the `window-actions` key set / a shared apps fragment) rather
  than a contrived example.
- Splices compose with `sticky-set` (both are `'kind 'splice`) inside
  `screen`/`panel`/`open` bodies.
- **Scheme tests**: a fragment splices identically to inline content (node-tree
  equality), at both panel and screen level; dispatch through a spliced fragment
  works (`find-child` reaches a key that arrived via a fragment).
- `check-portable-surface.sh` stays green.

## Notes

- The mechanism already exists — keep this leaf small. The value is the **named,
  reusable surface** + proving DRY on a real set, not new splicing machinery.
- If [[lowering-k10]] already exercised `sticky-set` splices inside the new forms,
  this leaf mostly adds the `fragment` constructor + the DRY application + tests.
