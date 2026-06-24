# overlay-polish-k19 — brief

## Goal

Three overlay refinements the user flagged after seeing the shipped
cheat-sheet overlay rendered live (2026-06-24, once the host was reinstalled
on this branch). All are presentation polish on the panel-grid overlay; the
interaction model is unchanged. Designs were settled in a brainstorming pass
the same day — each leaf carries its full, approved design.

## Children (independent — any order)

1. **masonry-layout-k20** — panel packing via CSS Grid Lanes (masonry) +
   an opt-in `'layout 'grid` screen keyword. *(done)*
2. **footer-applicability-k21** — generic greying of inapplicable footer
   command hints (e.g. `choose`/`select` in a 0-result chooser). *(done)*
3. **diagram-bare-panel-k22** — render a window-diagram's host panel
   background-transparent so proportions read and alignment is clean. *(done)*
4. **bare-loose-rows-k23** — drop the "General" panel: loose top-level rows
   render bare at the top of the screen (like the Settings overlay),
   top-level `(open …)`s fold in as drill rows, and loose top-level blocks
   (diagram / live-list) render bare; the bundled Windows overlay migrated to
   the flat/loose form. *(done; carried its full approved design.)*
5. **manual-panel-order-k24** — opt-in to render a panel's entries in
   declaration order instead of key-sorted. *(commissioned 2026-06-24 live.)*
6. **list-cursor-initial-focus-k25** — a live list's selection cursor starts
   on the currently-focused item, not row 0. *(done — iTerm Tab + Panes lists.
   Added the portable `cursor-initial-index-fn` seed mechanism; windows split
   out to k28 as it needs its own focus-detection design.)*
7. **elide-general-panel-k27** — (commissioned earlier; see its leaf).
8. **list-cursor-window-focus-k28** — extend the k25 cursor-seed mechanism to
   the global Windows list (the hard case: spatially sorted, no focus marker,
   no focused-window primitive). *(split out of k25; now a node — design
   settled 2026-06-24, implementation in focused-window-seed-k29.)*

## Context

- Target WebView is **Safari 26.5** (host is macOS 26.5.1); CSS
  `display: grid-lanes` shipped in Safari 26.4. The user confirmed assuming
  recent macOS — **no `@supports` fallback needed**.
- A related **user-config** fix (the iTerm "two Splits panels" → one merged
  "Splits" panel, using an `(open …)` nested in a `(panel …)`) was applied
  directly to `~/.config/modaliser/app-trees/com.googlecode.iterm2.scm`. It is
  **not** part of this node — it's the user's live config, not the app, and the
  bundled `default-config.scm` never had the duplication.

## Pointers

- Overlay renderer: `ui/overlay.scm` (panel-grid payload), `ui/overlay.js`
  (DOM apply), `base.css` (`.panel-grid`, `.panel`, footer, diagram).
- DSL: `lib/modaliser/dsl.sld` (`screen`/`panel`/`open`, `panel-grid-head`).
- Diagram block: `lib/modaliser/blocks/window-diagram.{sld,js,css}`.
- Design spec: `docs/superpowers/specs/2026-06-23-cheat-sheet-overlay-design.md`.

## Notes

- The **Finish** cycle (deferred since k9/k16/k17/k18) is **further deferred**:
  on 2026-06-24 the user commissioned more work while reviewing the overlay
  live — k24/k25 here, plus a root-level `util-extraction-audit-k26`. The grove
  finishes only once all of those retire (and the node has no live leaf). At
  k18's retirement `main` was at the branch point; **re-check**
  `git merge-base --is-ancestor main visual-refresh` before merging.
- Verify live in the real app per change (`./scripts/install.sh` then Relaunch);
  the host is on the branch binary now. The bundled `default-config.scm` is the
  panel-model exemplar for sanity-checking renders.
