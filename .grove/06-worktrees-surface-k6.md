# worktrees-surface-k6

**Kind:** planning

## Goal

Design and build the herdr **worktree** surface — git-worktree create / switch /
manage, herdr's tie between a workspace and a body of work.

## Context

Read the root `BRIEF.md`. Depends on the herdr backend + tree content (leaves 2–4).
A **planning** leaf: grill first — the worktree UX and its scope are open.

Data/actions: `herdr worktree …` subcommands (enumerate with `herdr worktree --help`
during grilling), and workspaces bind to worktrees (`herdr workspace create` takes
`--cwd`). Note the glossary distinction: "herdr worktree" is unrelated to Modaliser's
own grove `.grove-worktrees/`.

Open questions:
- Which operations? create-worktree(+workspace), switch, remove, list?
- Where in the tree — a top-level `w`-adjacent key? (careful: `w` is workspaces) a
  drill under workspaces?
- Does creating a worktree imply creating a herdr workspace for it? What's the smallest
  useful gesture (e.g. "new worktree for branch X → workspace")?
- Interaction with a chooser for branch/worktree selection (fuzzy pick).

Decompose into work leaves as the design settles.

## Done when

Grilled to shared understanding; worktree controls designed, decomposed, and (via child
leaves) built + tested; docs/glossary updated.

## Notes
