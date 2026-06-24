# responsive-columns-k30

**Kind:** planning

## Goal

Make the overlay distribute content into the *right number of columns for the
available width* — today it can render three columns where two would do. Settle
the design (this is a grilling task), then decompose into the implementation.

Surfaced live by the user on 2026-06-24 while reviewing the shipped overlay
(verbatim):

- "The global overlay has three panels in three columns that could be two
  columns because the Search and AI panels fit on one column."
- "When the elements are at the top level, they should distribute into columns
  if the rest of the overlay is wide enough such that it requires that."

So **both** panels (e.g. Search + AI) **and** loose top-level elements should
pack into fewer/more columns adaptively, driven by overlay width + content size —
not a fixed column count.

## Grill / design questions

- **Bug or new logic?** Is this the existing masonry (CSS Grid Lanes,
  masonry-layout-k20) under-packing, or genuinely new responsive behaviour? Start
  by observing how the current layout decides column count (read overlay.js /
  base.css `.panel-grid`, then look live).
- **What decides "wide enough"?** A width breakpoint, a content-fit measure, or
  Grid-Lanes auto-flow already doing it once spans are right?
- **Interaction with width-span hints** (narrow/wide/full) and the flat/loose
  region (bare-loose-rows-k23) — does a `full`/`wide` hint override packing?
- **Panels vs loose rows** — one mechanism or two? Concern 1 is about panels,
  concern 3 about loose top-level elements; confirm whether they share a solution.

## Done when (planning)

- The adaptive-column behaviour is settled (a Settled-design § here, or an ADR if
  it's a real renderer trade-off), CONTEXT.md updated if terms harden, and the
  tree grown with the implementation child/children.

## Notes

- Surfaced during the focused-window-seed-k29 live review; independent of that
  feature (cursor seed works regardless of column count).
- Pointers: renderer `ui/overlay.scm` (panel-grid payload), `ui/overlay.js` (DOM
  apply), `base.css` (`.panel-grid`); masonry `masonry-layout-k20`; loose rows
  `bare-loose-rows-k23`; DSL spans in `lib/modaliser/dsl.sld`. Design spec:
  `docs/superpowers/specs/2026-06-23-cheat-sheet-overlay-design.md` (§ spans).
- Glossary terms in play: **panel**, **loose region**.
