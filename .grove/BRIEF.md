# herdr-triggers-need-to-be-async — brief

## Goal

Dialog commands (CONTEXT.md, ADR-0014) currently raise their osascript
dialogs synchronously from inside `modal-handle-key`, while the modal
catch-all is still registered and the Scheme thread is blocked — so the
dialog never receives typing (observed: herdr workspace rename is
impossible). Fix per ADR-0014: a shared portable `(modaliser dialogs)`
library that (1) does a guarded `modal-exit` before spawning any dialog and
(2) runs the dialog via `run-shell-async`, continuation-passing the follow-on
command.

## Done when

- Renaming a herdr workspace (and tab), the new-worktree prompt, and the
  worktree-remove confirm all receive typing, live, with the leader still
  responsive while a dialog is up.
- The iTerm / Kitty / Alacritty error dialogs go through the same library
  (their Return/OK was swallowed by the same mechanism).
- `scripts/check-portable-surface.sh` passes; tests cover the library through
  the `current-dialog-runner` seam only (no test spawns osascript or herdr —
  see feedback_no_live_env_mutation_in_tests).

## Decomposition

- 02 `herdr-dialogs-async-k2` — build `(modaliser dialogs)` + convert the four
  herdr dialog commands + live verify.
- 03 `error-dialogs-async-k3` — convert the three backend error-dialog sites.

## Pointers

- ADR-0014 (`docs/adr/0014-dialogs-release-capture-and-run-async.md`) — the
  mechanism and both invariants; read it before touching dispatch ordering.
- `muxes/herdr.sld` — `prompt-text`, `confirm-dialog`, `osascript-run`,
  `sq-escape`, `as-escape` (the code the library absorbs), and the four
  dialog commands (~lines 340–510).
- `state-machine.sld` `modal-handle-key` — action-before-exit ordering is
  deliberate (`enter-mode!`); guards already tolerate an action that exits.
- `ShellLibrary.swift` — `run-shell-async` (callback on main queue, optional
  'timeout).
- Test idiom: `ModaliserMuxesHerdrLibraryTests.swift` (`parameterize` +
  `current-frontmost-bundle-id`) — mirror it for `current-dialog-runner`.

## Notes

- The state machine is NOT changed; no per-command DSL annotation (rejected
  during plan-k1 grilling — the async dialog is needed inside regardless).
- Error-dialog sites in `apps/iterm.sld:437`, `kitty.sld:402`,
  `alacritty.sld:224` are info-only (no typed input) — they need the release
  + async treatment but no continuation payload.
