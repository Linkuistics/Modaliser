# Modaliser configuration exploration — brief

## Goal

Research and design greater user control over UI layout, a clearer separation
between app-control facilities and user configuration, and alternatives to the
current Scheme configuration language. The candidates explicitly requested are
Racket, Common Lisp on SBCL, TypeScript, and Lua.

This is an exploratory workstream. Produce evidence, alternatives, and a proposed
design for discussion. Do not implement, prototype executable code, install
dependencies, alter the running app or personal configuration, or create
implementation leaves. Do not treat a recommendation as an accepted decision.

## Done when

- A cited layout survey addresses grid, flow, and masonry, nested groupings,
  sizing, overflow, and stable placement as live-list content changes.
- A cited facilities survey compares app-bundled modules, separately delivered
  Swift plugins, and process-separated facilities; it specifies what remains a
  user choice and what an app integration owns.
- A cited language comparison covers all four requested candidates and the
  current LispKit/Scheme baseline, comparing both an alternative configuration
  front end and replacement of the Scheme runtime.
- A proposed design connects those findings using the concrete VS Code scenario
  below, records trade-offs and remaining questions, and distinguishes current
  behavior, proposals, and untested claims.
- The durable documents are usable without this task tree. Only documentation
  and Grove task artifacts have changed.

## Decomposition

The bootstrap establishes the research questions and source baseline. Separate
surveys cover layout, facilities, and language/runtime choices; a design session
then synthesizes them. These are investigations, not authorization to build.

Keep one focused task per fresh session. Reviews are added only when an existing
artifact earns one. Do not convert the exploration into an implementation plan.

Keep the research readable as decision support: prefer a focused comparison of
roughly 2,000–3,000 words per remaining survey, with tables for parallel choices
and primary links beside material claims. Cover each leaf's questions; avoid
full language tutorials, repeated ADR restatements, or exhaustive code inventories.
Record empirical gaps instead of expanding the research to answer questions that
need an experiment. Paraphrase external sources rather than using long quotations.

## Pointers

- `CONTEXT.md`: Configuration and Overlay-presentation domains.
- ADR-0011: disjoint dispatch structure and attached Display value.
- ADR-0012: the existing screen/panel/open authoring surface.
- ADR-0018: one explicit Configuration value, validation, one Handoff; relaunch.
- ADR-0021: libraries hold Facilities; user configuration holds Decisions.
- ADR-0022 and ADR-0023: config-failure recovery and host-installed outward seams.
- `docs/specs/configuration-value.md` and `docs/reference/renderer-protocol.md`.
- `docs/research/configuration-exploration-context.md`: inspected source baseline,
  research questions, and shared scenarios.

## Notes

The user's concrete example is the VS Code screen: split the non-list commands
into separate groups and put the editor list together with its previous/next
controls. They also report that layout changes depending on list widths. Examine
content-driven sizing separately from responsiveness to available screen width.
The user confirmed the desired behavior: "Keep groups stable; wrap or truncate
titles (Recommended)". Stable placement under content-width changes is a
requirement, not an open preference; research how to express it alongside
optional responsiveness to available display width.

The user explicitly confirmed that the language investigation should compare
changing only the configuration language with replacing the Scheme runtime.
Supporting all four languages simultaneously is a question to evaluate, not a
requirement. Swift-based delivery of app support is a candidate, not a settled
plugin ABI or packaging format.

Existing ADRs describe the baseline. Propose changes explicitly; do not silently
rewrite accepted ADRs to make an unapproved exploratory design look settled.
Research findings belong in `docs/research/`. A proposed spec must be clearly
marked exploratory and must not imply permission to implement it.

The codebase-memory CLI failed at bootstrap with an active-generation compatibility
error. No project/generation or coverage result could be obtained. Targeted direct
source reads supply the baseline; this is not a graph audit. Retry graph access
in a fresh session and use source fallback if it is still unavailable.
