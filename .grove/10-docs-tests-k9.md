# docs-tests-k9

**Kind:** work

## Goal

Reconcile the source-of-truth **docs** to the layout DSL + panel-grid renderer,
close the **portability** gate, and round out the **cross-cutting tests**. This is
the final sweep before the grove finishes.

## Context

- `docs/reference/{dsl,theming,renderer-protocol,libraries}.md` +
  `docs/how-to/customise-theme.md` are ground-truthed against the `.sld` sources.
- The committed design spec
  `docs/superpowers/specs/2026-06-23-cheat-sheet-overlay-design.md` §4–§5 describe
  the **old** operational-first / auto-layout primacy; the planning commit added
  only a pointer to **ADR-0011** — this leaf reconciles §4–§5 in full.
- `CONTEXT.md` gained the **Overlay-presentation domain** terms (panel / screen /
  layout spec / operational IR / span / live list) during planning — verify they
  still match the shipped surface.
- `scripts/check-portable-surface.sh` must stay green; **prose** in `lib/modaliser`
  must avoid the literal `(lispkit ` string (write "the LispKit … library").
- Repo convention: behavioural `.sld` changes need tests — most land in their
  feature leaf; this leaf catches the cross-cutting snapshot / EndToEnd coverage.
- Audience: docs assume **external readers** (public release ~2026-W21 — see
  project memory), not future-self.

## Done when

- `dsl.md` documents the layout DSL (screens / panels / spans / live-list /
  fragments) and notes the operational tree is now an **IR**.
- `renderer-protocol.md` documents the `panel-grid` payload + the two-tier
  renderer registry.
- `theming.md` + `customise-theme.md` document the new token vocabulary.
- The design spec §4–§5 reconciled to the inversion; `CONTEXT.md` terms verified.
- `check-portable-surface.sh` green; an EndToEnd **panel** snapshot/dispatch test
  exists for the global tree + an app tree.

## Notes

- After this leaf retires, the grove root has **no live leaf** → trigger the
  **Finish** cycle (promote ADR-0011 / docs / glossary already live; delete
  `.grove/`; merge `visual-refresh` → `main`).
- Token-vocabulary cleanup carried over from [[chooser-restyle-k7]]: the chooser
  no longer defines `--chooser-selected-bg` / `--chooser-selected-border` — its
  selected result row is now a shared `.list-row.is-focused`, themed by
  `--list-focus-bg` / `--list-focus-bar` (one selection knob across the chooser
  and the embedded live lists). Drop those two rows from the `theming.md` token
  table + the `customise-theme.md` examples and document `--list-focus-*` /
  `--list-bg` / `--list-border` instead.
