# Dialog-raising commands release modal capture first and never block the Scheme thread

## Status

accepted

## Context

Some command leaves need the user's keyboard *outside* Modaliser: the herdr
rename tab / rename workspace / new-worktree prompts (`prompt-text`), the
worktree-remove confirm (`confirm-dialog`), and the error dialogs in the
iTerm / Kitty / Alacritty backends. All of them raise an AppleScript
`display dialog` via a **synchronous** `run-shell` (`osascript`), from inside
the command's action thunk.

That interacts fatally with two deliberate pieces of the dispatch design:

1. `modal-handle-key` (`state-machine.sld`) runs a command's action **before**
   the transient `modal-exit` — required so an action can call `(enter-mode!
   …)` and push the still-live calling context. So while the dialog is up, the
   modal is still active and the **catch-all key handler is still registered**.
2. The CGEvent tap runs on its **own thread** (`KeyboardCapture.swift`), so it
   keeps dispatching while the Scheme thread is blocked in `run-shell`'s
   `waitUntilExit`. Every key typed into the dialog reaches the catch-all,
   which calls into the blocked Scheme engine: the keystroke is swallowed and
   the tap callback stalls until macOS force-disables the tap by timeout
   (`.tapDisabledByTimeout`; the tap re-enables itself, but the typed keys are
   lost). Observed as: the rename dialog appears, typing goes nowhere.

Releasing capture alone is not enough: with the Scheme thread still blocked
for the dialog's lifetime, a leader press while a dialog is up would stall the
tap the same way (the leader hotkey handler also evaluates Scheme).

## Decision

Dialogs move to a shared portable library, `(modaliser dialogs)`, with two
invariants the library itself owns:

1. **Release before show.** Every dialog call's first step is a guarded
   `modal-exit` (no-op when no modal is active), unregistering the catch-all
   before the dialog process is spawned. Callers cannot forget the dance.
2. **Never block.** The dialog runs through `run-shell-async`; the follow-on
   work (e.g. `herdr tab rename …`) happens in the callback,
   continuation-passing style. The Scheme thread returns to idle immediately,
   so the leader and every hotkey stay live while a dialog is up.

The library also owns the two escaping layers the blocking helpers carried
(AppleScript double-quoted-literal escaping, then POSIX single-quote escaping
of the whole `osascript -e` program), and routes all execution through one
R7RS parameter — `current-dialog-runner`, default the real `run-shell-async`
path — as the single test seam.

The `modal-handle-key` action-before-exit ordering is **kept**: it exists for
`enter-mode!`, and its guards (`modal-active?` + root-identity) already
tolerate an action that exits the modal itself. No state-machine change, no
per-command DSL annotation.

## Consequences

- Workspace/tab rename, the new-worktree prompt, and the remove confirm
  actually receive typing; the modal overlay is gone before the dialog shows.
- Dialog-raising commands are CPS-shaped: the code after the dialog lives in a
  callback, not on the next line. That is the accepted cost of an unblocked
  Scheme thread.
- A future dialog site must use `(modaliser dialogs)` — raising a dialog (or
  any user-interactive process) via synchronous `run-shell` from an action
  thunk reintroduces this bug. That is the reason this ADR exists.
- `(modaliser dialogs)` imports `(modaliser state-machine)` for `modal-exit`;
  it stays inside the portable tree (no LispKit-specific imports).
