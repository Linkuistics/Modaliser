The {{NAME}} grove is fully done — all leaves retired into .grove/done/. Wrap it up in this order:

1. Promote anything from .grove/'s briefs that should outlive the grove (an ADR, a doc, a glossary entry).
2. Delete the .grove/ directory in one focused commit ("chore: remove grove scaffolding"). main only ever sees promoted artifacts, never any grove's local state.
3. Merge the branch into the default branch per this project's convention (PR, fast-forward, or squash as preferred).
4. Remove the worktree and delete the branch.
