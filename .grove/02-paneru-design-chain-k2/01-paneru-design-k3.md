# paneru-design-k3

**Kind:** design

## Goal

Write `docs/specs/paneru-window-management.md`: how Modaliser drives paneru, at
the grain the three impl leaves can build from without re-deciding anything.

## Context

Every *decision* is already taken — read the root `BRIEF.md` Notes and ADR-0024
first, and do not reopen them. What is left is genuinely design work, and it is
mostly about **reuse**:

- **Does the strip listing reuse `blocks/window-list`, or is it a new block?**
  The existing block sources rows from `window-list-current-targets`, refreshed
  by its own `on-render-fn`, and carries a digit `key-range`. The paneru listing
  needs a different source (paneru query, joined), different labels (escalating,
  from `jump-labels-assign`), and no chips. That may be parameterisation of one
  block or two blocks sharing a renderer — this is the call to make, and it is
  the largest single question in the workstream.
- **What is the library's exported surface?** Seven ops, an installation
  predicate, and whatever the listing needs. `muxes/zellij.sld` is the shape
  precedent for the file, but paneru is behind no façade, so there is no
  `backend` record and no `wiring` context entry — decide what, if anything,
  replaces them.
- **Where does the JSON parse live?** `(modaliser json)` exists; the parse and
  the join are agreed to be pure functions, so decide their signatures and their
  home.
- **How does the user express the branch?** The predicate is called at config
  load, so sketch the actual `config.scm` fragment a user writes — it is the
  surface everything else serves, and ADR-0021 means the library cannot write it.

## Done when

- `docs/specs/paneru-window-management.md` exists and answers all four questions
  above concretely enough that `paneru-ops-k6` and `paneru-strip-list-k7` can be
  built without further design.
- The spec's `## Test seams` records the agreed seam: `current-shell-runner`
  alone, with parse and join as directly-called pure functions.
- The spec cites ADR-0024, ADR-0023, ADR-0021, ADR-0017, ADR-0018 rather than
  restating them.
- Any term the spec coins that is not already in `CONTEXT.md` →
  **Paneru-window-management domain** is added there.

## Notes

Do not write code in this leaf. If the reuse question cannot be settled without
trying something, say so and leave a note — `paneru-strip-list-k7` can carry a
spike, and a spec that guesses is worse than one that scopes the guess.

A live paneru daemon is available on this machine for reading state
(`paneru query state --json` is read-only). Avoid `send-cmd` — it moves the
user's real windows.
