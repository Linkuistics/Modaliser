# herdr-triggers-need-to-be-async — brief

## Goal

Commands whose UI needs the user's keyboard (herdr rename/create/remove
prompts, backend error dialogs) currently fire synchronously from inside
`modal-handle-key` while the modal catch-all is still registered — the
external UI never receives typing. Fix per ADR-0015 + ADR-0014:

1. **Navigation graph (ADR-0015).** All transitions become declared `'next`
   edges; terminal nodes (no outgoing edge) get capture released by dispatch
   *before* their action runs. Stickiness is derived (`walk`s whose members
   cycle); `enter-mode!` becomes framework-internal.
2. **Never block (ADR-0014).** Interactive commands run through
   `run-shell-async`; herdr's worktree create/remove prompts are herdr's own
   UI (Modaliser fires the verb — no missing-argument gap); herdr's
   tab/workspace rename ops collect their label through a Modaliser-owned
   `chooser-prompt` instead, since herdr 0.7.3 has no prompt-on-missing-arg
   feature (`herdr-rename-prompt-ownership-k9`); Modaliser-raised alerts go
   through a slim `(modaliser dialogs)`.

## Done when

- Terminal-node release-before-action is live; the seven
  `focus-pane-by-digit` slots and all sticky groups/walks are migrated;
  `swift test` and `scripts/check-portable-surface.sh` pass.
- The four herdr ops fire their verbs async with capture already released.
  Worktree create/remove fire bare into herdr's own UI (no missing-arg gap,
  so nothing more to verify there); tab/workspace rename collect the label
  through a Modaliser-owned `chooser-prompt` first — real typing lands
  immediately, not gated on unshipped herdr-side prompt-on-missing-arg work
  (`herdr-rename-prompt-ownership-k9`).
- The iTerm / Kitty / Alacritty error dialogs go through the slim dialogs
  library (release now framework-owned; async via `current-dialog-runner`).

## Decomposition

- 02 `capture-release-signal-k4` — planning (done): grilled the static
  capture-release question; produced ADR-0015, reworked ADR-0014, retired
  "sticky" from the UL (CONTEXT.md), reshaped the remaining leaves.
- 03 `navigation-graph-next-edges-k5` — the machinery + migration.
- 04 `herdr-dialogs-async-k2` — the four herdr ops → async fire-and-forget.
- 05 `error-dialogs-async-k3` — the three error-dialog sites + slim dialogs.
- 06 `provision-scripts-async-k8` — surfaced at k3: the post-confirm
  provisioning scripts (iTerm's quit-wait loop especially) still block via
  synchronous `run-shell`, reintroducing ADR-0014's stalled-tap window one
  step later than the dialog itself.
- 07 `herdr-rename-prompt-ownership-k9` — surfaced live-testing k2: herdr's
  rename ops need a label herdr 0.7.3 can't yet prompt for; reopens "herdr's
  own UI" for those two ops only, via a general `chooser-prompt` primitive
  (node — see its `BRIEF.md`).

## Pointers

- ADR-0015 (`docs/adr/0015-navigation-graph-next-edges-terminal-release.md`)
  — the graph model, migration inventory, rejected alternatives.
- ADR-0014 (`docs/adr/0014-interactive-commands-never-block.md`) — the async
  invariant and the stalled-tap failure mode.
- `CONTEXT.md` Modal-dispatch domain — **'next edge**, **Terminal**,
  **Walk**, **Dialog command**.
- `state-machine.sld` `modal-handle-key` + `enter-mode!` + the retired
  sticky walks (`deepest-sticky-on-path`, `in-sticky-context?`).
- `dsl.sld` — `key-cmd` ('sticky-target → 'next), `sticky-set` → `walk`
  (line ~358: already stamps per-leaf edges — the model's existing proof).
- `ShellLibrary.swift` — `run-shell-async` (callback on main queue).
- Test seams (agreed): e2e modal harness for dispatch; parameterized
  captured-command runner for herdr ops (mirror
  `ModaliserMuxesHerdrLibraryTests`'s `current-frontmost-bundle-id` idiom);
  `current-dialog-runner` for the slim dialogs. No test spawns
  osascript/herdr (feedback_no_live_env_mutation_in_tests).

## Notes

- herdr 0.7.3 requires the rename label positionally; prompt-on-missing-arg
  is future herdr-side work. k2 does the Modaliser side only.
- The k2-era CPS draft (osascript dialog-prompt/confirm + herdr conversions)
  was discarded uncommitted at k4; its reusable escaping/CPS snippets are
  embedded in `05-error-dialogs-async-k3.md`.
