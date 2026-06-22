# Design: Cheat-sheet overlay — a reference document that happens to be interactive

- **Date:** 2026-06-23
- **Status:** Approved (design); ready for implementation planning
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

**Evolve `category` into the panel** (decision §11). A `category`:

- Remains **transparent for dispatch** — keys keep their paths. (Unchanged semantics; this is why `category` is the right primitive.)
- Renders as a **strongly-separated, banded card** (a "panel").
- Gains an optional **width hint**: `'span 'narrow` (default) | `'wide` | `'full`.
- May **contain a dynamic-list block** (`window-list`, `pane-list`/iTerm panes) among its children, in addition to key rows. A category that contains a list block **auto-promotes** its span to `'wide` unless an explicit `'span` is given.
- May render a **header affordance** for a navigable `group` child surfaced in the panel header (e.g. `s full toolkit ›` on the Splits panel). This is optional polish; a `group` child otherwise renders as an accent `›` row.

**Loose top-level keys** (no enclosing `category`) collapse into one implicit **"General"** panel. Migrated configs name these explicitly.

### Layout: a grid of panels

The overlay body becomes a **CSS-Grid of panels**:

- Each panel maps its width hint to a column span: `narrow` = 1, `wide` = 2 (where the grid is ≥3 wide; falls back to `full` in a 2-col grid), `full` = all columns (decision §11).
- `grid-auto-flow: dense` backfills narrow tiles around wide panels.
- Column count derives from total panel content and the target aspect ratio, reusing the existing `set-overlay-aspect-ratio!` / `overlay-column-count` machinery.
- Panels never split across columns (`break-inside: avoid` equivalent; grid items don't split anyway).

This replaces the current CSS multi-column row flow. CSS Grid (not multicol) is required because multicol cannot span "2 of 3" columns, and the wide-list requirement needs partial spans.

## 5. DSL surface changes

In `(modaliser dsl)`:

- **`category`** gains:
  - `'span 'narrow|'wide|'full` keyword (optional; default `narrow`, auto-`wide` when it holds a list block).
  - Acceptance of a dynamic-list block as a child (today it accepts only key/group nodes).
- **`pack-node-runs` / `flush-node-run`** change from inferring misc/category blocks to a direct **one `category` → one panel** mapping, with loose keys forming the "General" panel. The `which-key` block becomes the per-panel *key-row* renderer rather than the whole-overlay renderer.
- **Dynamic-list blocks** (`make-window-list-block`, `make-iterm-panes-block`) gain a section-embeddable form so they can be a `category` child, not only a top-level overlay block. Their `on-render-fn` return-and-merge protocol (live data injection) is unchanged.
- No change to `key`, `keys`, `group`, `overlay`, `sticky-set`, `selector`, `define-tree` *surface* — though `overlay`/`define-tree` packing now emits panels.

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

**Open details for the implementation plan:**
- Exact block-vs-renderer refactor: whether to introduce a dedicated `panel-grid` renderer or evolve the `which-key` block into a per-panel renderer (the payload/behaviour is fixed above; the code shape is the planner's call).
- Multi-list overlays: which list owns the cursor / whether `Tab` cycles.
- Accent default (indigo) — tunable; confirm against the chip/host-theme palette.

## 13. Files in play

- DSL: `lib/modaliser/dsl.sld` (`category`, `pack-node-runs`/`flush-node-run`).
- Renderer: `ui/overlay.scm` (`block-list-payload-json`, `block-json`, `render-overlay-body`, `push-overlay-update`), `ui/overlay.js`.
- Blocks: `blocks/which-key.{sld,js,css}`, `blocks/window-list.{sld,js,css}`, `blocks/iterm-panes.{sld,js,css}`, `blocks/iterm-tabs.*`.
- Chooser: `ui/chooser.scm`, `ui/chooser.js`, chooser CSS in `base.css`.
- Styling: `base.css` (new default tokens + panel/grid/list/footer rules).
- Fonts: `Contents/Resources` (IBM Plex `.woff2`), `scripts/build-app.sh` (copy step).
- Config: `Sources/Modaliser/Scheme/default-config.scm`, `~/.config/modaliser/config.scm` + `app-trees/*`.
- Docs: `docs/reference/{dsl,theming,renderer-protocol,libraries}.md`, `docs/how-to/customise-theme.md`, `CONTEXT.md`.
- Invariant: `scripts/check-portable-surface.sh` (keep green).
