# Design: Cheat-sheet overlay — a reference document that happens to be interactive

- **Date:** 2026-06-23
- **Status:** Approved (design); ready for implementation planning
- **Amended by [ADR-0011](../../adr/0011-presentation-first-layout-spec-lowers-to-operational-node-tree.md) / [ADR-0012](../../adr/0012-layout-dsl-surface-screen-panel-open-over-unchanged-atoms.md):** the config↔presentation primacy is **inverted**. The design was originally drafted operational-first — `category` evolving into the panel, the renderer inferring grouping and auto-laying-out. The shipped implementation instead authors a **presentation-first layout spec** (a tree of screens, each a grid of panels) that **lowers to** the operational node-tree IR; a dedicated `panel-grid` renderer reads explicit presentation metadata rather than auto-laying-out. **§4–§5 below have been rewritten to the shipped design** (the original operational-first text survives in git history). The *look*, the visual-token table (§7), the cursor/list behaviour (§6), font bundling (§7), and chooser scope (§8) were unaffected by the inversion.
- **Scope:** One cohesive project — visual restyle + renderer/DSL change + config migration
- **Brainstorm artifacts:** `.superpowers/brainstorm/90558-1782166819/content/*.html` (mockups, git-ignored). The visual language below is captured textually so this spec stands alone.

## 1. Goal

Reshape Modaliser's overlay so it reads like a **dynamic cheat-sheet document** — a calm, typeset reference card — rather than a transient which-key HUD. The interaction model (press leader, type a key, drill down) is unchanged; the *presentation* and the *config↔presentation mapping* change.

This is a **visual restyle** in intent, but achieving the look correctly requires a structural change (panel-per-group) and a config migration, so the project bundles all three.

## 2. Background — current state

- The overlay is a `WKWebView`-backed `NSPanel` rendered entirely from HTML/CSS (`base.css` + block CSS + user `theme.css`). There is no native styling layer; `set-theme!` is already a no-op stub (`dsl.sld:600`).
- Today's look: a warm-cream (`--overlay-bg: rgba(253,247,237,1)`), monospace (`Menlo`), single-panel HUD that shows **one level at a time** and vanishes after a keypress.
- **Grouping is weak because it is inferred.** `(category …)` is *transparent for dispatch* (`dsl.sld:341`) and renders as a column with only a 1px underline under a small-caps label. Loose keys coalesce into a "misc" segment, and `pack-node-runs` (`dsl.sld:553`) splits mixed runs into misc+category blocks. The eye doesn't parse distinct blocks because separation is typographic, not spatial.
- **`category` vs `group` is the load-bearing distinction.** A `group`/`overlay` is *navigable* (own key, descends into a sub-overlay — the `›` rows). A `category` is *visual-only* (keys keep their paths). The panel-per-group model maps to **`category` = panel**, because a panel must not change the keys beneath it.

## 3. Design principles

1. **Document, not HUD.** Editorial typography, spatial grouping, a calm reference surface.
2. **Config isomorphic to presentation.** One declared group renders as one panel. The renderer stops inferring grouping; it renders what the config declares.
3. **Breadth where it helps.** Static command groups are compact tiles that pack into columns; dynamic lists get horizontal room.
4. **Alive in place.** A dynamic list (panes, windows) lives *inside* its group's panel, clearly signalled as live, without leaving the document.

## 4. The panel model

A config is a **layout spec** — a tree of **screens**, each an implicit **grid of panels** — authored directly and **lowered to** the operational node-tree IR at config-load (ADR-0011/0012). A **panel** is the cheat-sheet's grouping unit. It:

- Is **transparent for dispatch** — keys keep their paths. (A panel lowers to a `category` node, which the state machine descends through as if its children were hoisted into the parent.) This is *why* the panel is the right primitive: a grouping that must not change the keys beneath it.
- Renders as a **strongly-separated, banded card**.
- Carries an optional **width hint**: `'span 'narrow` (default) | `'wide` | `'full`.
- May **contain a dynamic-list block** (`window-list`, iTerm panes/tabs) among its children, in addition to key rows. A panel that contains a list block **auto-promotes** its span to `'wide` unless an explicit `'span` is given.
- Renders a nested drill-down (`open`) child as an accent `›` row.

**Loose top-level keys** (a `key` not wrapped in a panel) collapse into one implicit **"General"** panel — the presentation-first analogue of the old misc bucket. Migrated configs usually name these explicitly.

A **screen** is one navigable level; an **`open`** drills into a fresh screen (its own grid of panels) — the presentation-first replacement for the `(key K L (overlay …))` idiom. Reusable layout chunks splice in via **`fragment`**.

### Layout: a grid of panels

The overlay body is a **CSS-Grid of panels** drawn by a dedicated **`panel-grid` renderer** that reads the presentation metadata (`'span`, `'cols`) the lowering annotates onto the screen group — it does *not* infer grouping or auto-lay-out:

- Each panel maps its width hint to a column span: `narrow` = 1, `wide` = 2, `full` = all columns (decision §11).
- `grid-auto-flow: dense` backfills narrow tiles around wide/full panels.
- Column count is **CSS-intrinsic auto-fit** by default (panels flow into as many `--panel-min-width` tracks as fit, capped by `--panel-grid-max-width`), or an **authored `'cols N`** pins an explicit track count. The legacy aspect-ratio search (`set-overlay-aspect-ratio!` / `overlay-column-count`) governs only the default list renderer that plain `(group …)` drill-downs still use.
- Panels never split across columns (grid items don't split).

CSS Grid (not multicol) is required because multicol cannot span "2 of 3" columns, and the wide-list requirement needs partial spans.

## 5. DSL surface changes

In `(modaliser dsl)` — three new **layout container forms** plus a reuse form, over the **unchanged dispatch atoms** (ADR-0012):

- **`screen scope … panel…`** — registers a tree as a grid of panels (the `define-tree` analogue). Body is the implicit grid; loose atoms pack into a leading "General" panel. Lowers to a tree-root group carrying `'renderer 'panel-grid` (+ optional `'cols`).
- **`panel "label" ['span S] child…`** — a transparent banded card. Lowers to a `'kind 'category` node carrying `'span` (+ `'list` when it embeds a live list). Children are dispatch atoms plus at most one dynamic-list block; the block's hidden digit range lifts into the panel's dispatch children, the block rides under `'list` for the renderer.
- **`open KEY LABEL … panel…`** — a navigable drill-down into a sub-screen. Lowers to a navigable `'group` carrying `'renderer 'panel-grid`.
- **`fragment child…`** — a transparent named splice (panels or rows) for DRY, built on the same `expand-splices` `sticky-set` uses.
- **No change to the dispatch atoms** `key`, `keys`, `key-range`, `group`, `selector`, `sticky-set`, `action` — they *are* the IR, so `flatten-categories` / `find-child` / the state machine read the lowered tree untouched.
- **Dynamic-list blocks** (`window-list`, iTerm panes/tabs) gain the section-embeddable form so they sit inside a panel, not only at overlay top level. Their `on-render-fn` return-and-merge protocol (live data injection) is unchanged; the `panel-grid` renderer serializes an embedded list through the **same `block-json` path** the legacy block-list renderer uses.
- **Legacy forms kept, deprecated.** `define-tree` / `category` / `overlay` / `which-key-block` keep working unchanged (some bundled terminal/app libraries still use them) but are deprecated in favour of the layout forms; the docs reconcile this (ADR-0012, no flag-day).

Portability is preserved: all changes stay within `(scheme …)` / `(srfi …)` / `(modaliser …)` (`check-portable-surface.sh` stays green).

## 6. Dynamic lists — navigation

Every dynamic list (embedded pane/window lists **and** the standalone chooser) supports:

- **Selection cursor** moved by `↑`/`↓` (and `k`/`j`), with `⏎` activating the selected row (decision §11).
- **Numeric selectors** `1–9`/`0` remain **immediate** direct-jump shortcuts (existing digit-range dispatch by UUID — race-free, no event injection).
- The **focused/current** row is marked (accent left-bar + tint); a right-aligned **detail column** appears when width allows (e.g. `focused`, `⌥2`).
- The **footer advertises** the available nav keys (`↑↓ move · ⏎ select · 1–9 jump`).

Cursor state lives in the list block (alongside `current-*-targets`) as a selected index; arrow presses dispatch to a handler that updates the index and pushes an overlay update via the existing `push-overlay-update` path. When an overlay contains exactly one list panel, that panel owns the cursor (the common case). *Open detail (§12): multi-list overlays.*

## 7. Visual layer (new default `base.css`)

The new look is the **default** (decision: New default rollout, §11). Token vocabulary (indigo accent, amber group-opens; all overridable in `~/.config/modaliser/theme.css`):

| Token (new/renamed) | Value | Role |
|---|---|---|
| `--font-family` | `"IBM Plex Sans", system-ui, sans-serif` | Labels / body |
| `--font-mono` | `"IBM Plex Mono", "SF Mono", monospace` | Keys / paths / footer |
| `--accent` | `#4f46e5` (indigo) | Keys-in-lists, panel-header text, focus, selection |
| `--color-group` | `#c2700f` (amber) | Group-opens (`›` rows) |
| `--overlay-bg` | `#ffffff` | Outer card |
| `--overlay-body-bg` | `#f6f7fa` | Tinted grid behind panels (makes white panels pop) |
| `--panel-bg` / `--panel-border` | `#fff` / `#e7e9ee` | Panel card |
| `--panel-head-bg` / `--panel-head-fg` | `#eef0fb` / `#3b3fb6` | Banded panel header |
| `--keycap-bg` / `--keycap-border` / `--keycap-fg` | `#f4f5f7` / `#e3e5ea` / `#4b5563` | Soft keycaps |
| `--list-bg` / `--list-border` | `#f7f8fb` / `#ebedf2` | Embedded live-list inset |
| `--live` | `#23c161` | "live" dot |
| `--footer-bg` / `--footer-border` | `#f5f6f8` / `#e3e5ea` | Separated footer strip |

Structure:

- **Outer card** with an app/context **band** at top (`iTerm2` · `F17 local`), the **panel grid** in the middle, a **separated footer strip** (own tinted background + top rule) at the bottom.
- **Panels**: contained card, banded header (Option-2 styling scoped to the panel's own width — this is what reconciles "banded header" with "tiles into columns"), key rows, optional embedded list.
- **Keycaps**: soft, mono, single-line. Labels are `white-space: nowrap; text-overflow: ellipsis` — **never wrap** (per requirement); long titles truncate.
- **Embedded live list**: inset panel with `Panes`/`Windows` caption + green "live" dot, numbered accent keycaps, `proc · cwd` titles, focused-row accent, right-aligned detail column when wide.

### Web font bundling

IBM Plex Sans + IBM Plex Mono `.woff2` are **bundled locally** in the app `Contents/Resources` and loaded via `@font-face` with bundle-relative URLs — the `WKWebView` needs **no network**. `build-app.sh` copies the font files (same pattern as the vendored LispKit libraries). The hidden chip-probe WebView continues to resolve `.chip` computed styles at boot.

## 8. Chooser restyle

The standalone fuzzy-finder chooser (`Select Window`, `Find File`, `Find Application`) adopts the **same** list vocabulary (decision: chooser in scope, §11): header band, IBM Plex, accent-focused input, accent fuzzy-match highlight, selected-row accent bar, separated footer with match count + nav hints. The chooser already supports arrow + type-to-filter; the footer is updated to advertise it. The embedded lists and the chooser **share** the list-row CSS so they read as one family.

## 9. Migration

- **`Sources/Modaliser/Scheme/default-config.scm`** — restructure the global tree into named panels (`General`, `Applications`, `AI`, `Search`) and per-app trees into panels; mark dynamic-list panels `wide`.
- **User config** — `~/.config/modaliser/config.scm` + `app-trees/*.scm` migrated to the panel model (user pre-approved). Keep `config.scm` in sync with the bundled default per existing convention.
- **Docs** (source of truth) — update `docs/reference/{dsl,theming,renderer-protocol,libraries}.md`, `docs/how-to/customise-theme.md`, and add the term **"panel"** to the `CONTEXT.md` glossary.
- **Tests** mirror sources (repo convention) — see §10.

## 10. Testing

Scheme behaviour is exercised through a real LispKit context (repo convention), so behavioural `.sld` changes need matching tests:

- `category` → panel packing (one category = one panel; loose keys = General panel).
- `'span` hint plumbing and auto-`wide` promotion for list-bearing panels.
- A dynamic-list block accepted as a `category` child; live `on-render-fn` merge still emits rows.
- List selection-cursor dispatch (`↑↓`/`k`/`j` move index; `⏎` activates; digits jump) at the state-machine/event-dispatch level.
- Panel-grid payload JSON shape (structure/snapshot).
- Keep `EndToEndSchemeModalTests`-style coverage for the global + an app tree rendering as panels.

## 11. Decisions (resolved during brainstorming)

| # | Decision | Choice |
|---|---|---|
| Aesthetic | Direction | B's banded/sectioned card + D's system-font lightness → converged "panel" look |
| Grouping | Separation strength | Strong (contained panels); banded header scoped per-panel |
| Layout | Engine | CSS Grid with column spans (not multicol) |
| Scope | Project shape | One cohesive project: CSS + renderer/DSL + config migration |
| Chooser | In scope? | Yes — restyle to match |
| Rollout | Default vs theme | **New default** |
| DSL term | Panel primitive | **Evolve `category` into the panel** |
| Span | Wide-panel width | **Hint-based**: `wide`=2 cols, `full`=all; list panels default `wide` |
| List nav | `↑↓` semantics | **Selection cursor + `⏎`**; digits stay immediate |
| Type | Typeface | IBM Plex Sans + Mono, bundled locally |

## 12. Non-goals / open details

**Non-goals:** in-place hot-reload (still relaunch); state-machine dispatch changes beyond the list cursor; native chip-painter redesign (chips inherit the new palette via `--color-host-*`); new block types beyond panel/list needs.

**Open details for the implementation plan (now resolved):**
- ~~Block-vs-renderer refactor.~~ **Resolved (ADR-0011):** a dedicated `panel-grid` renderer reading presentation metadata, not an evolved `which-key` block. See [renderer-protocol.md](../../reference/renderer-protocol.md).
- ~~Multi-list overlays.~~ **Resolved:** the first live list a screen renders owns the cursor; `Tab`-cycling is a non-goal.
- Accent default (indigo) — tunable; shipped as `--accent: #4f46e5`, overridable in `theme.css`.

## 13. Files in play (as shipped)

- DSL: `lib/modaliser/dsl.sld` — the `screen` / `panel` / `open` / `fragment` layout forms lowering to the IR (the legacy `category` / `pack-node-runs` / `flush-node-run` retained, deprecated).
- Renderer: `ui/overlay.scm` (`panel-grid-payload-json`, `renderer-body-json`, `block-list-payload-json`, `block-json`, `render-overlay-body`, `push-overlay-update`), `ui/overlay.js` (the `overlayRenderers['panel-grid']` body renderer).
- Blocks: `blocks/which-key.{sld,js,css}`, `blocks/window-list.{sld,js,css}`, `blocks/iterm-panes.{sld,js,css}`, `blocks/iterm-tabs.*`.
- Chooser: `ui/chooser.scm`, `ui/chooser.js`, chooser CSS in `base.css`.
- Styling: `base.css` (new default tokens + panel/grid/list/footer rules).
- Fonts: `Contents/Resources` (IBM Plex `.woff2`), `scripts/build-app.sh` (copy step).
- Config: `Sources/Modaliser/Scheme/default-config.scm`, `~/.config/modaliser/config.scm` + `app-trees/*`.
- Docs: `docs/reference/{dsl,theming,renderer-protocol,libraries}.md`, `docs/how-to/customise-theme.md`, `CONTEXT.md`.
- Invariant: `scripts/check-portable-surface.sh` (keep green).
