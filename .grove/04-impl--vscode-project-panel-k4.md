# vscode-project-panel-k4

## Goal

Put the open VSCode projects on the F17 VSCode screen as a **top-level labelled
panel** — one row per project, each reachable by a jump label from an
escalating alphabet (`a s d f g …`, with leader keys past exhaustion) — rather
than only behind the `w` chooser row that `vscode-screen-k2` shipped.

The human asked for this after using the chooser: *"I would rather that project
list at the top level with the standard 'asdfg' extensible shortcut assignment
to select them."* "Standard" is the right word — this is the **Strip listing**
pattern from `wms/paneru.sld`, applied to a different row source.

Whether the `w` chooser row survives beside the panel is the human's call; ask,
and default to keeping it (fuzzy matching over a long worktree name is a
different affordance from a jump label).

## Context

**Everything downstream of the row source already exists**, and
`vscode-screen-k2` shipped the row source itself.

- `(modaliser apps vscode)` exports `windows-of` (pure: enumeration → items,
  each carrying `'text` = project name, `'title` = raw title, `'windowId`,
  `'ownerPid`) and `focus-choice` (pure: item → the alist `focus-window`
  reads). No new VSCode knowledge is needed.
- `(modaliser jump-labels)` `jump-labels-assign` is the label machinery —
  targets × three alphabets → prefix-free one- or two-key labels.
- `(modaliser blocks paneru-strip)` is **already generic**. Its own header
  states it: it takes an `'assigned-fn` thunk returning `((label . target) …)`
  with the target carrying `'app` / `'title` / `'focused`, and "knows nothing
  of paneru". It is a candidate for reuse as-is.

**The one real decision, and it is why this is its own leaf.** Paneru's
`strip-provider` / `strip-provider-result` / `strip-prefix-state` trio is ~120
lines of FSM state-and-edge minting (single-key edges, leader prefix states
that re-mint their own provided states, `'up` edges, the panel-label passed in
from the user under ADR-0021). A VSCode panel needs the same shape over a
different row source. Three ways to go, and the leaf should decide deliberately
rather than reach for the first:

1. **Duplicate the trio into `apps/vscode.sld`.** Cheapest to land, and it
   keeps paneru's tested behaviour untouched — but it is a second copy of the
   subtlest machinery in the tree, and the two will drift.
2. **Extract a shared `(modaliser jump-list)`** carrying the provider trio over
   an injected row source, and re-express paneru's strip-provider on top of it.
   The right shape if a third caller is plausible; it edits a tested,
   load-bearing path, so it wants its own tests green before and after.
3. **Reuse `blocks/paneru-strip` but not the provider** — some middle where the
   block is shared and the provider is not. Note the block's `'type` is
   `'paneru-strip` and its CSS classes carry that name, so a VSCode panel
   rendering through it inherits paneru's name in the DOM; whether that is
   acceptable or wants a renamed generic block is part of the same decision.

**Where the keys and labels go.** The three alphabets and the panel label are
the user's under ADR-0021 — `strip-provider` takes all four as arguments and
defaults none, and the human's `config.scm` already passes
`paneru-label-keys` three times for the paneru strip. Follow that exactly; a
library that defaults an alphabet has authored a key.

**Pointers**

- `~/.config/modaliser/config.scm`, the `paneru-windows-screen` definition —
  the working reference for composing a provider with a listing block, live on
  the human's machine.
- `wms/paneru.sld` from "The Edge provider" to the end of file.
- `docs/specs/paneru-window-management.md` decision 1 and 4, and ADR-0024 — the
  Strip listing's design and the reason a listed row is targeted by a joined
  identity rather than by position.
- `.grove/02-impl--vscode-screen-k2.md`'s decision log for why the item shape
  is what it is (in particular why `'title` is preserved).

**Cost warning from k2's own measurements section:** paneru's provider runs on
the dispatch path at every come-to-rest, measured ~34ms with a subprocess spawn
in it. A VSCode panel has **no subprocess** — it is enumeration + filter +
assign — so it should be materially cheaper, but the enumeration is the same
8-29ms warm / 200ms+ cold AX sweep, and `KeyboardCapture` filters no
auto-repeat. Ship without `'next 'self`, exactly as the paneru reference
composition does, and for the same reason.

## Done when

- The F17 VSCode screen carries a top-level panel listing the open projects,
  each with a jump label that focuses that window, on the human's machine.
- The alphabets and the panel label come from the human's `config.scm`, not
  from any file under `lib/modaliser`.
- Whichever of the three routes above is taken is recorded as a decision with
  its reasoning — and if route 2, paneru's own suite is green before and after.
- `swift build` and `swift test` green; `./scripts/check-portable-surface.sh`
  and `./scripts/check-decision-free.sh` both pass.
- The new surface is documented where `docs/reference/libraries.md` documents
  `(modaliser apps vscode)`'s existing exports.

## Notes

- **Verify against a real VSCode, not against a successful import.** `CLAUDE.md`
  records a shipped library whose primitives all resolved and permanently
  returned null. `vscode-screen-k2` installed the app (`./scripts/install.sh`,
  ~23 min for the release build) and confirmed `config: loaded` in
  `/usr/bin/log show --predicate 'subsystem == "dev.antony.Modaliser"'` before
  asking the human to press the keys. Do the same.
- A shell alias shadows `log` in this environment — use `/usr/bin/log`.
- The human runs four VSCode windows, one per grove worktree, so the folder
  names are long (`grove.add-user-guide-and-code-walkthoughs-for-all-crates`).
  A panel row has to render that legibly, which the chooser did not have to.
