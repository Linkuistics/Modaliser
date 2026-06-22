# plan-k1

**Kind:** planning

## Goal

Turn the committed cheat-sheet overlay design spec into an **ordered
implementation task tree** of work leaves, and settle the one open
implementation-architecture fork. The deliverable is *more tree* (work leaves
grown under the grove root), not code.

## Context

Beyond the brief chain, this task in particular needs:

- The spec, end to end:
  `docs/superpowers/specs/2026-06-23-cheat-sheet-overlay-design.md`. §11 (decisions
  already made — do **not** re-litigate), §12 (non-goals + the open details to
  resolve here), §13 (file map).
- The renderer surfaces the work hinges on:
  `Sources/Modaliser/Scheme/ui/overlay.scm` (`block-list-payload-json`,
  `block-json`, `render-overlay-body`, `push-overlay-update`),
  `Sources/Modaliser/Scheme/ui/overlay.js`,
  `Sources/Modaliser/Scheme/lib/modaliser/blocks/which-key.{sld,js,css}`,
  the dynamic-list blocks (`window-list.*`, `iterm-panes.*`),
  and `Sources/Modaliser/Scheme/base.css`.

## Done when

- The **open architecture fork is decided**: a dedicated `panel-grid` renderer vs.
  evolving the `which-key` block into a per-panel renderer (spec §12). Capture it
  as an **ADR** if it's hard to reverse / a real trade-off.
- The grove root has **ordered child work-leaves** covering the spec's seams
  (visual/CSS, renderer, DSL `category`→panel + spans + embeddable list,
  dynamic-list cursor nav, chooser restyle, IBM Plex bundling, config migration,
  docs/tests), each sized to **one focused session**, sequenced by dependency.
  Grow them with `grove-llm leaf-add . <slug>`.
- `CONTEXT.md` gains the **"panel"** glossary term (and any other terms that
  harden during planning), appended inline.

## Notes

- The design is settled — this is decomposition + the architecture fork, **not** a
  re-grill of look-and-feel. If a genuinely new design question surfaces, grill it
  one question at a time, but expect few.
- Other open details to fold into the right leaves: multi-list cursor ownership
  (which list owns ↑↓ when an overlay has more than one), and confirming the
  indigo accent default against the chip / `--color-host-*` palette.
- Sequencing instinct: the **visual/CSS layer can land first** (it's the lowest-
  risk, highest-signal slice and de-risks the look), but the panel payload it
  consumes depends on the renderer/DSL change — decide in this task whether to
  stage a CSS-over-current-grouping preview or do renderer-first.
