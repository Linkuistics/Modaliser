# bare-loose-rows-k23

**Kind:** work

## Goal

Two related overlay refinements the user settled live on 2026-06-24, after
seeing the masonry overlay (k20) in the real app. Both are presentation-only;
the interaction model is unchanged.

1. **Drop the "General" panel.** A screen's loose top-level rows (a `(key …)`
   not wrapped in a `(panel …)`) currently collect into a leading **"General"**
   card. Instead, render them as a **bare, header-less row block at the top of
   the screen body** — like a plain `(group …)` / the Settings overlay
   (`settings-menu.sld`, reached via `,`), whose Edit/Reload rows sit directly
   on the overlay body with no card. Real panels masonry-pack as cards beneath.

2. **Fold top-level opens into the loose block.** A **top-level** `(open …)`
   (a direct screen child) currently renders as its own one-row card whose only
   row is its drill-in affordance — wasteful. Render it instead as a
   **"→ Label" drill row among the loose rows** (still navigable: pressing its
   key drills into its sub-screen exactly as today). Its label is the row
   label, so nothing is lost (the approved trigger was **"single-element opens
   only"** — see Design).

3. **Loose top-level blocks render bare (added 2026-06-24).** After seeing the
   bare diagram from `diagram-bare-panel-k22` rendered live, the user asked that
   the **Windows (`w`) overlay** carry **no subpanels and no "Layout" title** —
   and clarified this is a **configuration** decision, not a hardcoded renderer
   choice. So the renderer must let a config express a flat screen by placing a
   **block** — a `(window:layout-block …)` diagram or a `(window:list-block …)`
   live-list — **loose at the top level** (not wrapped in a `(panel …)`), and
   render it **bare** alongside the loose rows. Then **migrate the bundled
   `default-config.scm` Windows overlay** to the flat/loose form: drop the
   `(panel "Layout" …)` / `(panel "Select" …)` / `(panel "Windows" …)` wrappers
   so the diagram, the `s`/`r` keys, and the live windows list render flat — no
   subpanel cards, no "Layout" title. k22 stays the (config-independent)
   capability for configs that *do* panel-wrap a diagram; this leaf delivers the
   loose path + the config migration that realizes the user's flat overlay.

## Design (settled 2026-06-24, approved)

Approved interactively against the live iTerm screen (`com.googlecode.iterm2`),
whose top level is: loose `c`/`z`/`configure` rows + a top-level `(open "t"
"Tabs" …)` + `(panel "Splits" …)` + `(panel "Panes" (iterm:pane-list-block))`.

- **Loose block, not a "General" card.** `lower-panel-grid-body` (dsl.sld)
  today buckets loose atoms into `(make-panel-node "General" …)`. Change it to
  emit the loose atoms as a **distinct bare-row block**, separate from the
  panel cells. Dispatch is unchanged — loose keys already dispatched at the
  screen root (the General category was transparent); only the *rendering*
  changes. **No `make-panel-node "General"` is created.**

- **Trigger for the fold = top-level opens only** (the approved option, over
  "any single-row cell" and "opt-in keyword"). Every top-level `(open …)`
  contributes exactly one grid row (its drill-in), and its label travels with
  it as the row label — so it folds cleanly into the loose block with no name
  loss. **NOT folded** (stay as cards): multi-row panels; list-bearing panels
  (auto-`wide`); single-**key** panels like `(panel "Danger" (key "x" "Wipe"))`
  — a single-key panel carries *two* names (header + row), so folding would
  drop the header (the "ambiguous name" case the user's wording guards). An
  `open` declared **inside** a panel is untouched — it already renders as an
  accent group-row in that panel, not its own cell.

- **Layout = bare block at top, grid below** (approved over "header-less cell
  in the grid"). The loose rows render as a full-width header-less list
  spanning the top of the screen body; the masonry panel grid renders beneath.
  Loose items stay prominent and never reflow below a panel.

  ```
  ┌─ iTerm screen ────────────┐
  │ c  Copy Mode              │  ← bare loose rows (no card/header),
  │ z  Toggle Zoom            │    folded top-level opens included
  │ t  → Tabs                 │
  ├───────────────────────────┤
  │ ┌ SPLITS ┐  ┌ PANES ┐     │  ← real panels, masonry grid
  │ │ h Left │  │ (list)│     │
  │ └────────┘  └───────┘     │
  └───────────────────────────┘
  ```

- **Payload.** `panel-grid-payload-json` (overlay.scm) gains a sibling to
  `panels`, e.g. `"loose":[<row>,…]`, using the **same** entry-row shape
  (`entry->row-json`) the panel rows use. Folded opens serialize as drill rows
  (`isGroup` true → accent + arrow). `overlay.js` renders a header-less
  `.panel-loose` block **above** the `.panel-grid`. Both initial paint and
  push-update route through the one renderer (no divergence), as today.
  - Loose-only screen (no real panels) → just the bare row list (visual parity
    with a plain group / the Settings overlay).
  - Panel-only screen (no loose atoms) → just the grid, no empty loose block.

- **CSS.** A `.panel-loose` block: bare rows on the body, no card chrome,
  reusing the keycap/arrow/label row vocabulary; spacing/separator before the
  `.panel-grid`.

## Done when

- A screen's loose top-level rows render bare (no "General" header or card) at
  the top of the body; real panels masonry-pack beneath. **Verified live.**
- A top-level `(open …)` renders as a "→ Label" drill row among the loose rows
  and still drills in on its key. **Verified live.**
- A **loose top-level block** (a `(window:layout-block …)` diagram or a
  `(window:list-block …)` live-list placed directly under a `screen`/`open`, not
  in a `(panel …)`) renders **bare** in the loose region — no card, no header.
  The bundled `default-config.scm` **Windows (`w`) overlay is migrated** to this
  flat/loose form: diagram + `s`/`r` keys + live windows list, **no subpanels and
  no "Layout" title**. **Verified live.**
- Multi-row panels, list (auto-`wide`) panels, and single-key panels still
  render as cards; an `open` nested inside a panel is unchanged.
- A loose-only screen renders like a plain group list; a panel-only screen
  renders just the grid (no empty loose block).
- Dispatch unchanged: loose keys and folded-open keys resolve as before.
- Bundled `default-config.scm` migrated — the explicit `(panel "General" …)`
  cards become loose top-level rows; each screen re-checked for readability.
- `swift build` + layout/renderer suites green; `check-portable-surface.sh`
  green.

## Notes

- Files: `lib/modaliser/dsl.sld` (`lower-panel-grid-body`: loose → bare block,
  fold top-level opens; drop the `make-panel-node "General"` path — and
  `collect-panel-list-blocks` still must gather list blocks from real panels
  only); `ui/overlay.scm` (`panel-grid-payload-json` emit `loose`;
  `grid-cell->json` no longer single-cells a top-level open); `ui/overlay.js`
  (render `.panel-loose` above the grid); `base.css` (`.panel-loose`);
  `default-config.scm` (un-wrap "General" panels).
- **Existing tests assert the OLD behaviour — update them:**
  `LayoutDslTests.screenPacksLooseKeysIntoGeneralPanel` /
  `screenWithoutLooseKeysHasNoGeneralPanel`,
  `PanelGridRendererTests.looseKeysFormLeadingGeneralPanel` /
  `topLevelOpenRendersAsSingleRowPanel`. New cases: no "General" node emitted;
  loose block present in payload; a top-level open folds into the loose block
  (not a card) yet still dispatches; nested-in-panel open unchanged.
- Docs/glossary: `docs/reference/dsl.md` (screen/open body: loose-block +
  open-fold, replacing the "General panel" description), `renderer-protocol.md`
  (payload `loose`), `theming.md` (`.panel-loose`), `CONTEXT.md` (retire the
  "General panel" notion; the loose rows are the screen's own inline rows). The
  design spec §4–§5 if it still enumerates the General-panel behaviour.
- TDD: DSL/renderer tests first, then JS/CSS, then the config migration;
  confirm live (`./scripts/install.sh` + Relaunch) before retiring.
- Independent of footer-applicability-k21 / diagram-bare-panel-k22; any order.
  ADR-0011/0012 lowering contract is the reference.
