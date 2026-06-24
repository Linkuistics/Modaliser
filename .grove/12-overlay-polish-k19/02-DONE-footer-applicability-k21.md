# footer-applicability-k21

**Kind:** work

## Goal

Grey out footer command hints that can't act in the current context — e.g. a
chooser with zero results should dim `⏎ choose` and `↑↓ select` (nothing to
choose / select), keeping `⎋ exit` live. Make it a **generic** mechanism, not a
one-off for the chooser (user: "the graying-out should be generic").

## Design (settled 2026-06-24, approved)

- A footer is a list of `(sigil, label, applicable?)` hints; a shared
  `.footer-hint--disabled` (muted/greyed) class is applied wherever
  `applicable?` is false. Each hint becomes its own span — today the chooser
  hints are one concatenated string, so split them.
- Applicability is computed per context, all feeding the one mechanism:
  - **Chooser:** `choose` / `select` applicable iff result count > 0; `exit`
    always.
  - **Overlay cursor-nav:** `↑↓` / `⏎` applicable iff the active embedded
    live list has > 0 entries; `back` iff not at root (an `overlay-footer-root`
    state already exists); `exit` always.
- Both footer renderers are **mirrored** and must be edited together:
  `chooser-footer-html` (`ui/chooser.scm`) + `chooserFooterHtml`
  (`ui/chooser.js`); the overlay footer via `footer-html-for-path`
  (`ui/overlay.scm`) + its apply path (`ui/overlay.js`).
- Visual: greyed / dimmed, **not hidden**.

## Done when

- Chooser footer dims `choose`/`select` at 0 results — on both the initial
  render and the JS dynamic-update path — and restores them at ≥1 result;
  `exit` always live.
- Overlay cursor-nav hints dim when the embedded live list is empty.
- The Scheme and JS footer templates stay in sync (they are mirrored by
  contract).
- `base.css` carries `.footer-hint--disabled`; `swift build` + chooser/overlay
  render suites green.

## Notes

- The chooser footer already receives `item-count`, so the applicability data
  is present; the work is (a) restructuring hints into per-command spans, (b)
  the disabled class, (c) computing applicability for the overlay live-list
  case.
- Files: `ui/chooser.scm`, `ui/chooser.js`, `ui/overlay.scm`, `ui/overlay.js`,
  `base.css`. Tests: ChooserRender / OverlayRender coverage for the 0-result
  dimmed state (and the ≥1 restored state).
