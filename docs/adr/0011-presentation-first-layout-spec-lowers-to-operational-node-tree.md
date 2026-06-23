# Overlay is authored as a presentation-first layout spec that lowers to the operational node-tree

- **Status:** accepted (supersedes the primacy described in the cheat-sheet overlay design spec §4–§5)

We are inverting the config↔presentation pipeline. Today the **operational
command-tree** (`group`/`category`/`key`) is the authored artifact and
presentation is a *derived projection* of it — the renderer infers grouping and
auto-lays-out (aspect-ratio column search, `distribute-which-key-columns`,
misc/category packing). We will instead author a **presentation-first layout
spec** — a tree of named **screens**, each a **grid of panels**; a panel holds
command rows, drill-down affordances, and live lists — and **extract** the
operational model from it. The layout DSL is a *front-end that lowers to the
existing `(kind . group)` / `(kind . command)` node-tree*, annotating nodes with
presentation metadata (`panel`, `span`, `screen`) that a new dedicated
**`panel-grid` overlay renderer** reads. We chose this because it makes
isomorphism *definitional* (the config **is** the document), gives the author
direct layout control instead of fighting an auto-layout heuristic, and reuses
the entire dispatch engine unchanged.

## Considered options

1. **Evolve `category` into a panel; keep operational-first authoring + auto-layout** (the original design spec §4–§5). Rejected: presentation still *chases* the operational model; the auto-layout heuristic fights the author; and a panel that must hold *key-rows **and** an embedded live list* has no clean home — see option 2.
2. **Evolve the `which-key` block into a per-panel renderer** (reuse the `blocks` renderer, grid-ify its container). Rejected: in the block tier each block gets its own `.block` grid cell, so "one category = one panel" where the panel contains rows **and** a live list forces either two cells per category (breaks the invariant) or bloating `which-key` to also render lists; grid concerns (spans, dense flow, column count) smear across the container CSS + per-block payload with no single owner.
3. **Two layers: operational atoms + a layout-over-ops spec referencing them by id.** Rejected: two artifacts to keep in sync; the cleaner "inverse" is a single presentation-first spec from which dispatch is extracted.
4. **Replace the dispatch engine with a layout interpreter.** Rejected: throws away a tested state machine and re-derives solved problems (sticky modal stack, transparent dispatch, race-free digit-jump) for no upside — the existing IR can express the layout's dispatch.

## Consequences

- The operational node-tree becomes an **IR / compile target**, no longer a hand-authored surface. `state-machine.sld` (transparent category dispatch via `flatten-categories`/`find-child`, sticky modes + modal stack, `key-range` digit-jump, `selector`, `block-children` → `children` lifting) is preserved essentially untouched.
- The Scheme-side **auto-layout heuristics are retired**: `overlay-column-count`'s aspect-ratio search, `distribute-which-key-columns`, `partition-which-key-segments`, `segments-row-count`. Layout is explicit (spans) + grid-driven; the absolute column count becomes authored or CSS-intrinsic (settled in the renderer leaf).
- `which-key.js`'s row renderer (`renderRow`/`renderCategory`) survives as the **panel key-row renderer**; its whole-overlay packing is deleted.
- Dynamic-list blocks (`window-list`, `iterm-panes`, `iterm-tabs`) keep their `on-render-fn` return-and-merge + `*-current-targets` plumbing; the layout *places* them inside a panel rather than only at overlay top level.
- **Every config migrates** to the layout DSL (bundled `default-config.scm`, the user config, all per-app trees) — a breaking authoring change, acceptable because Modaliser is pre-release and the user pre-approved it.
- Portability preserved: the layout DSL stays within `(scheme …)` / `(srfi …)` / `(modaliser …)`; `check-portable-surface.sh` stays green.
- The committed design spec (`docs/superpowers/specs/2026-06-23-cheat-sheet-overlay-design.md`) §4–§5 describe the *old* primacy and are superseded here; the docs leaf reconciles them.
