# docs-reference-k7

**Kind:** work

## Goal

Ground-truth the docs to the shipped herdr surface: how-to, reference, and a PRD if it
earns its place.

## Context

Read the root `BRIEF.md`. Runs after the herdr surface is built (leaves 2–6). The
glossary terms (herdr, workspace, worktree, agent status, replace/augment tree) were
already added to `CONTEXT.md` in planning — verify they still match the built surface.

Likely touches:
- `docs/how-to/terminal-pane-aware-tree.md` — add herdr as a worked variant example
  (replace + augment), since it's the first real exerciser of variant trees.
- `docs/reference/terminal-detection.md` — herdr detection (fg-command `herdr`, the
  socket-API focused-pane targeting, the single-client v1 assumption).
- Any backend-surface reference (the deleted `docs/prd/terminal-backends.md` is being
  pruned separately in leaf 8 — coordinate: if a backends reference is still wanted,
  decide its new home here).
- A focused **PRD** for herdr-controls only if it genuinely earns its place (grove
  constraint 4: lazy). `docs/prd/` does not exist yet.

Per CLAUDE.md: `docs/` is the source of truth; update the doc when the surface changes.
Diagrams in Mermaid, never ASCII ([[feedback_diagrams.md]]).

## Done when

Docs accurately describe the shipped herdr controls; how-to has a herdr variant
example; detection reference covers herdr; glossary matches; links resolve.

## Notes
