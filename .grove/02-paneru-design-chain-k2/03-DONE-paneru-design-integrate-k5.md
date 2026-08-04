# paneru-design-integrate-k5

**Kind:** integrate-review-design
**Integrates:** paneru-design-review-k4

## Goal

Apply the verified findings from `paneru-design-review-k4` while preserving the reviewed artifact's contract.

## Disposition

Every finding applied; none rejected. The two majors were re-verified against the
code first — the review's mechanism claims all held, and verifying F1 turned up
the cheap fix its own option list had missed.

| # | Applied as |
|---|---|
| F1 | Decision 5 re-decided: the provider calling convention gains the id of the state it is lowered onto, and `open` gains `'provider`. Chosen over the registered-tree, config-authored-id, and no-escalation options, each rejected in the spec with its reason. Decision 4 now states the prefix state's id, up-edge target, payload shape, and its own `'provider` outright. |
| F2 | Two seams, stated honestly. The enumeration is injected as `strip-provider`'s `'enumerate`. The "one seam" claim is retired for the non-shell path and the reason recorded as **determinism**, not isolation. ADR-0024's seam paragraph reconciled in place. |
| F3 | Decision 4 specifies the payload — the two-layer `'children` + `'display` shape, closed over the survivor rows. The panel label rides in from the user as `'panel-label`, keeping ADR-0021 clean where the check script cannot see. |
| F4 | Decision 4 prices the per-press cost, names the two levers already in the design, and puts a measurement obligation on `paneru-strip-list-k7`. |
| F5 | `provider-state-id-k9` created (`leaf-insert`, ahead of the listing) and named in the spec as the owner of the engine change and all three doc sites. |
| F6 | The unreachable degradation row reworded to say what actually happens — the probe fails, row 1 applies, and the paneru screen never composes under `swift test`. |

Also fixed in passing, per the review's "not findings" list: the
`modaliser-tool-path` caller count (six library files, not eight).

## Notes

**F1's resolution came out cheaper than any option the review listed.**
`resolve-state-def` already stamps `(cons 'id id)` onto every state def —
permanent and provided alike — and `def-id` already reads it, so handing a
provider its own id is one call site in `fsm.sld`. Exactly three providers exist
in the whole tree (herdr's root, herdr's per-prefix-state, `activation.sld`'s
step-in wrapper), which is what makes changing the convention bounded rather than
alarming. An explicit argument was preferred to an ambient parameter: the review's
own critique of `%fsm-visit-owner` is a critique of ambient state read at the
wrong moment.

The review's diversity caveat was well aimed — F1–F4 were all places the spec
reasoned from herdr's *shape* without reading herdr's *code*, and reading
`muxes/herdr.sld:820-1030` is what settled all four.
