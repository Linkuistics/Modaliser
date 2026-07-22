# Mini-chip geometry comes from a forked herdr's ui.layout API

Mini-chips (jump chips over herdr's sidebar Spaces/Agents entries and tab
titles) need the *drawn* cell-rect of each entry. herdr's socket API exposes
pane rects (`pane.layout`) but no sidebar or tab-bar geometry, and several
inputs to the drawn layout — the spaces/agents section split ratio, each
list's scroll offset, group collapse, the agents sort mode — are UI state the
API does not expose. (That state lives server-side, in the same process that
answers API requests and composes every frame — which is what makes an API
method reporting drawn geometry feasible at all.) Decision: **fork
`ogulcancelik/herdr`, add a `ui.layout` method** reporting drawn entry rects
(visible entries only) keyed by `workspace_id` / `pane_id` / `tab_id` in cell
coordinates, run the fork locally, and propose it upstream. The agreed wire
contract is `docs/specs/herdr-ui-layout.md`. Modaliser consumes it through
one geometry-contract function per kind, scaling cells→pixels exactly as pane
chips do today. Against a herdr without `ui.layout`, mini-chips simply do not
paint — jump keys and drills are unaffected.

## Considered options

1. **Replicate herdr's drawing arithmetic in Modaliser** (the "it's a TUI,
   compute from cell size" instinct). Rejected: under-determined, not merely
   fragile — scroll offset, divider ratio, collapse, and sort mode are not
   exposed, so no computation from snapshot data can be correct in general;
   entry heights are additionally config-token-driven (multi-row entries).
   Reopened by: nothing — if herdr ever exposed that UI state, `ui.layout`
   itself would still be the better surface.
2. **A herdr plugin.** Rejected on evidence: herdr's plugin surface is "the
   entire herdr CLI" — manifest-declared actions/events/panes plus the same
   socket API; no introspection of the rendered UI. Reopened by: a plugin API
   gaining UI-layout access, at which point the fork retires in favour of a
   plugin or plain API call.
3. **Upstream-first** (wait for the PR before building). Rejected: blocks the
   grove on third-party review latency. The fork is the unblock; the PR was
   the intended exit. The upstream path is **parked** (2026-07-22): the
   proposal (Discussion ogulcancelik/herdr#1474, posted 2026-07-16) drew no
   maintainer response in six days, while upstream `master` stayed active
   daily and no recent community discussion was being answered either —
   silence, not rejection. The fork plus the `linkuistics-herdr` formula is
   the ongoing mechanism. Reopened by: the maintainer responding to #1474
   (GitHub notifies) or upstream shipping any `ui.layout`-shaped surface —
   either way the fork retires to stock and this ADR is edited to record
   the stock surface.
4. **Gate Modaliser's own feature work on the upstream PR being accepted**
   (i.e. treat "PR merged" as a precondition for `top-level-nav`/`mini-chips`,
   not just for the ADR's own exit). Rejected 2026-07-17: the PR's review
   latency is third-party and open-ended; the fork already delivers
   `ui.layout` today. Reopened by: nothing — the upstream PR remains wanted
   for its own sake (see option 3's exit) but never again gates other work.

## Consequences

- The local herdr install moves from the Homebrew binary to a locally-built
  fork until the PR lands (a guided transition — the running server and its
  live workspaces must be handed over deliberately). Self-updates
  (`herdr update`) are restored via the `linkuistics-herdr` Homebrew formula
  (interim distribution mechanism, `homebrew-publish-k20`) rather than lost
  for the duration — the formula tracks the fork branch and is retired the
  same day the upstream PR merges.
- The `ui.layout` schema is designed to be upstreamable: drawn/visible
  entries only, cell coordinates consistent with `pane.layout`, no
  Modaliser-specific vocabulary.
