# visual-refresh — brief

## Goal

Reshape Modaliser's overlay (and the standalone chooser) so it reads like a
**dynamic cheat-sheet document** rather than a transient which-key HUD — and ship
it as the **new default**. The interaction model is unchanged; presentation and
the config↔presentation mapping change. The full design, with all resolved
decisions, is the committed design spec (see Pointers).

## Done when

- The overlay renders **one `category` = one panel** (transparent dispatch
  preserved), laid out as a **CSS-Grid of panels** with width-hinted spans
  (`narrow`/`wide`/`full`); panels can **embed a dynamic list** (pane/window).
- Dynamic lists (panes, windows, chooser) support a **selection cursor**
  (↑↓ / k j, ⏎ to activate) alongside the immediate `1–9` selectors.
- New default **`base.css`**: white panels on a tinted body, banded panel
  headers, soft keycaps, indigo accent + amber group-opens, **separated footer**,
  live-list inset. **IBM Plex Sans + Mono bundled locally** (no network).
- The **chooser** is restyled to share the list-row vocabulary.
- Bundled `default-config.scm` + the user config + per-app trees migrated to the
  panel model; reference docs + `CONTEXT.md` ("panel") updated.
- `check-portable-surface.sh` stays green; Scheme behaviour covered by tests.

## Decomposition

Not yet decomposed — that is `plan-k1`'s job. The natural seams the spec implies
(likely child ordering): visual/CSS layer → renderer (panel-grid) → DSL
(`category`→panel, spans, embeddable list) → dynamic-list cursor nav → chooser
restyle → font bundling → config migration → docs/tests. `plan-k1` confirms the
sequencing and settles the one open architecture fork (new `panel-grid` renderer
vs. evolving the `which-key` block).

## Pointers

- **Design spec (read first):**
  `docs/superpowers/specs/2026-06-23-cheat-sheet-overlay-design.md` — full design,
  the visual-token table, the decisions log (§11), non-goals + open details (§12),
  and the file map (§13).
- Reference docs the work touches:
  `docs/reference/{dsl,theming,renderer-protocol,libraries}.md`,
  `docs/how-to/customise-theme.md`.
- Glossary: add the term **"panel"** to `CONTEXT.md` during planning.
- ADRs: none yet (an ADR is likely for the panel-grid renderer decision).
- Brainstorm mockups (git-ignored, reference only):
  `.superpowers/brainstorm/90558-1782166819/content/*.html`.

## Notes

- This grove branched off `main` at the spec commit (`2d1709e`). The design was
  settled through a full brainstorming pass; the spec records the resolved forks
  (category→panel, hint-based spans, cursor+⏎ nav, IBM Plex bundled, chooser in
  scope, **new default**). The grove's job is **implementation**, not re-grilling.
- `main` carries unrelated in-flight changes (`dsl.sld`, `state-machine.sld`) —
  coordinate / rebase if they land before this branch merges, since the DSL work
  here also touches `dsl.sld`. At the **Finish** step re-check
  `git merge-base --is-ancestor main visual-refresh` before merging (promoted up
  from the now-done overlay-polish-k19 brief): if `main` has advanced past the
  branch point, rebase / merge-commit rather than assuming a fast-forward.
