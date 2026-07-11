# herdr-dialogs-async-k2

**Kind:** work

## Goal

Build the portable `(modaliser dialogs)` library per ADR-0014 and cut the
four herdr dialog commands over to it, so workspace/tab rename, the
new-worktree prompt, and the worktree-remove confirm actually receive
typing.

## Context

Root brief + ADR-0014 carry the mechanism and decisions. The library absorbs
`prompt-text`, `confirm-dialog`, `osascript-run`, `sq-escape`, `as-escape`
from `muxes/herdr.sld` and re-shapes them async:

- `dialog-prompt` (title, continuation receiving typed string or #f on
  cancel), `dialog-confirm` (message, continuation receiving #t/#f),
  `dialog-info` (message, no payload) — exact names/arity to taste.
- First step of every call: guarded `modal-exit` (no-op when inactive).
- Execution only through the `current-dialog-runner` parameter
  (default: `run-shell-async` on the built `osascript -e '…'` command).
- Callers in `herdr.sld`: `rename-focused-tab!`, `rename-focused-workspace!`,
  the worktree-create prompt (~line 468), the worktree-remove confirm
  (~line 506) — follow-on `herdr-cmd` moves into the continuation.

## Done when

- Tests (new `ModaliserDialogsLibraryTests` + touched herdr tests) cover:
  hostile-input escaping via the captured command string; cancel / confirm /
  typed-name plumbing via canned callback stdout; modal exited before the
  runner fires. No test spawns osascript or herdr.
- `swift build` + suite green (skip ModaliserAppsItermLibraryTests +
  HttpLibraryTests per project_iterm_tests_crash); portable-surface check
  passes.
- Live verify via ./scripts/install.sh: rename a herdr workspace end-to-end;
  leader press while the dialog is up still works.
- `docs/reference/libraries.md` (or wherever the portable tree is
  enumerated) gains the new library.

## Notes
