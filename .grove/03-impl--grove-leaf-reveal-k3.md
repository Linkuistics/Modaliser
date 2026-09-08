# grove-leaf-reveal-k3

## Goal

Deliver requirement 5: from the F17 VSCode screen, open the live grove task file
belonging to *this window's* worktree, with the explorer landing on it.

The human runs several groves at once — one VSCode window per worktree — and
currently opens each grove's live leaf by hand. "This window's worktree" is the
whole point: the operation must resolve the worktree from the window it was invoked
from, not from a configured path and not from whichever grove ran last.

## Context

Read the root brief's "Contracts settled with the human" and "Test seams" first.
Both were agreed with the human in `plan-k1`; the seam in particular is not a
suggestion to re-derive.

**The chain this leaf builds**, each link already decided:

1. **Frontmost VSCode window → folder path.** Join the window's title to VSCode's
   own state file: `windowsState.openedWindows[].folder` carries an exact `file://`
   URI per open window, and the title's last em-dash segment is that folder's
   basename. The state file is authoritative for the path; the title only matches
   against it.
2. **Folder path → live leaf path.** `(modaliser tools grove)` asks `grove-llm`,
   through the portable shell seam. Grove's own CLI is the authority on which verb
   answers "the next live leaf" and what it prints — read its `--help` rather than
   trusting a transcription. It exits zero with an empty result when a tree has no
   live leaves, and the directory may not be a grove at all; both are ordinary
   outcomes to handle, not errors to surface.
3. **Leaf path → open and reveal.** Hand the path to the `code` CLI, then send one
   chord to focus the explorer. `explorer.autoReveal` is true, so the file is
   already selected in the tree by the time the explorer takes focus.

**Two things to establish empirically rather than assume**, both flagged during
requirements and neither settled:

- Whether the `code` CLI reliably opens the file in the window that owns its folder,
  or in the last-focused window. If it is the latter, focus the target window first
  — Modaliser can already focus a window by id.
- Whether the state file is fresh enough at press time. It is written on window
  state change rather than continuously, so a window opened seconds ago may not be
  in it yet. Decide what the operation does when the front window has no entry: say
  nothing, or say something.

**Pin the setting you depend on.** Set `explorer.autoReveal` explicitly to true in
the human's VSCode settings rather than resting on an inherited default. Their
settings file contains trailing commas and comments — it is JSON-with-comments, so
edit it as such.

## Done when

- `(modaliser tools grove)` exists, resolving a worktree to its live leaf path via
  `grove-llm` through the portable shell seam, and handling both "not a grove" and
  "no live leaves" as ordinary results.
- `(modaliser apps vscode)` gains the workspace resolver: a **pure** function over
  the state-file *text* returning the open workspaces (folder path and name), with
  the file read a single call no test exercises.
- The composition is bound on the F17 VSCode screen in the human's config, and
  appears in `examples/vscode.scm`.
- Pressing the key in a VSCode window whose folder is a grove worktree opens that
  grove's live leaf and leaves the explorer focused on it — verified against at
  least two concurrently-open worktrees, since resolving the *right* one is the
  requirement.
- Tests drive the parser from a fixture captured from a real state file, and drive
  anything that spawns through a canned runner on the shell seam. Nothing runs
  `grove-llm` or `code` for real under `swift test`.
- `swift build` and `swift test` green; `./scripts/check-portable-surface.sh` and
  `./scripts/check-decision-free.sh` both pass.
- The new library is documented alongside its peers in `docs/reference/libraries.md`.

## Notes

- **Neither library imports the other.** The composition lives in user config. A
  grove reference inside the VSCode library, or a VSCode reference inside the grove
  library, is the thing this factoring was chosen to prevent.
- **Capture the fixture from real data, then treat it as frozen.** Its value is
  that it is a real state file's shape; a hand-written approximation tests the
  approximation.
- **The state file's format is undocumented and can change across VSCode releases.**
  That risk was accepted with eyes open. Put the reasoning in the library header
  the way `dia.sld` and `nvim.sld` carry theirs. The `plan-k1` assessment is that
  this does *not* earn an ADR — it fails the hard-to-reverse limb, being one pure
  function behind a seam — but disagree explicitly if you find otherwise, rather
  than re-deriving it.
- The human's config is a separate tree at `~/.config/modaliser/` with its own
  `CLAUDE.md` scoped to editing configuration. Changes there are not carried by
  this repo's commit.
