# configuration-design-k5


## Goal

Synthesize the three surveys into a coherent exploratory design for user-owned
layout and configuration over app-control facilities. Write
`docs/specs/configuration-exploration.md`, clearly marked **proposed/exploratory**.



## Context

Read the shared context and `docs/research/layout-controls-a.md`,
`docs/research/app-facilities-a.md`, and
`docs/research/configuration-runtimes-a.md`. The user's decisions are in
`configuration-exploration-k1`. This is an agreement artifact to discuss, not an
accepted implementation specification.

## Done when

- Present two or three coherent overall approaches with a provisional
  recommendation and evidence that could change it.
- Show how each addresses an editor list grouped with previous/next controls,
  independently placed other commands, and stable groups under wider list titles.
- Define the conceptual interface between app Facilities, user Decisions,
  Configuration value/dispatch, and Display value/layout. Keep semantic grouping
  distinct from navigation and key ownership.
- Make responsive sizing, wrapping/truncation, dynamic snapshots, callback
  ownership, errors, compatibility, and runtime lifecycle concrete enough to
  compare; describe validation obligations without claiming they were tested.
- Compare both front-end-only change and runtime replacement. Give a reasoned
  language shortlist while preserving the user’s choice and identifying costs.
- Resolve contradictions between surveys; retain material uncertainty rather
  than silently selecting favorable claims. Cite survey evidence near conclusions.
- Record a short list of unresolved user choices and future experiments; neither
  runnable experiments nor implementation planning are authorized in this Grove.
- Existing accepted ADRs and current behavior documentation are not rewritten as
  though the proposal has been accepted. Only exploration documents change.

## Notes

Do not ask again whether to compare both runtime approaches or whether list
contents may rearrange groups: both are settled. Propose wrapping/truncation as
user controls. A real design review may be added if the resulting artifact earns
one; it remains documentation-only. Do not create implementation leaves, invoke
an implementation plan workflow, or perform a prototype.
