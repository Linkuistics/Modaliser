# overlay-polish-k19 — brief

## Goal

Three overlay refinements the user flagged after seeing the shipped
cheat-sheet overlay rendered live (2026-06-24, once the host was reinstalled
on this branch). All are presentation polish on the panel-grid overlay; the
interaction model is unchanged. Designs were settled in a brainstorming pass
the same day — each leaf carries its full, approved design.

## Children (independent — any order)

1. **masonry-layout-k20** — panel packing via CSS Grid Lanes (masonry) +
   an opt-in `'layout 'grid` screen keyword.
2. **footer-applicability-k21** — generic greying of inapplicable footer
   command hints (e.g. `choose`/`select` in a 0-result chooser).
3. **diagram-bare-panel-k22** — render a window-diagram's host panel
   background-transparent so proportions read and alignment is clean.

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

- After all three retire, this node has no live leaf → the grove root re-checks
  → the deferred **Finish** cycle runs (held since k9/k16/k17/k18). At k18's
  retirement `main` was at the branch point; **re-check**
  `git merge-base --is-ancestor main visual-refresh` before merging.
- Verify live in the real app per change (`./scripts/install.sh` then Relaunch);
  the host is on the branch binary now. The bundled `default-config.scm` is the
  panel-model exemplar for sanity-checking renders.
