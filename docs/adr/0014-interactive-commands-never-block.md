# Interactive commands never block the Scheme thread

## Status

accepted

## Context

Some command leaves need the user's keyboard *outside* Modaliser: the herdr
rename / new-worktree / remove-confirm verbs (herdr's own UI prompts), and
the error dialogs in the iTerm / Kitty / Alacritty backends. Two things must
hold while such external UI is up: modal capture must be released, and the
Scheme thread must stay free.

The release half is owned by the navigation graph (ADR-0015): these are
terminal leaves, so dispatch releases capture before their action runs.
Release alone is not enough, though. The CGEvent tap runs on its own thread
(`KeyboardCapture.swift`) and keeps dispatching while the Scheme thread is
blocked in a synchronous `run-shell` (`waitUntilExit`): a leader press while
external UI is up would call into the blocked engine, stall the tap callback,
and macOS force-disables the tap by timeout (`.tapDisabledByTimeout`) —
keystrokes are lost. Observed originally as the herdr rename dialog
appearing but receiving no typing.

## Decision

An action that raises user-interactive UI (or any long-running external
process) must not run it through synchronous `run-shell`. It goes through
`run-shell-async`; any follow-on work lives in the callback,
continuation-passing style. The Scheme thread returns to idle immediately,
so the leader and every hotkey stay live while the external UI is up.

Modaliser-raised dialogs (the backend error/confirm alerts) go through the
shared portable `(modaliser dialogs)` library, which owns the AppleScript
and shell escaping layers and routes execution through one R7RS parameter —
`current-dialog-runner`, default the real `run-shell-async` path — as the
single test seam. The library performs no capture handling: that is
dispatch's job (ADR-0015).

## Consequences

- Commands whose UI prompts (herdr rename/create/remove) are plain
  fire-and-forget async commands; the prompting UI is herdr's own.
- Interactive commands are CPS-shaped where a result is consumed: the code
  after the dialog lives in a callback, not on the next line. That is the
  accepted cost of an unblocked Scheme thread.
- A future dialog site must use `(modaliser dialogs)` / `run-shell-async` —
  raising interactive UI via synchronous `run-shell` from an action thunk
  reintroduces the stalled-tap bug. That is the reason this ADR exists.
- `(modaliser dialogs)` stays inside the portable tree (no LispKit-specific
  imports).
