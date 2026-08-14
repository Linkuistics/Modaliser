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

An action that raises user-interactive UI, or that waits on anything whose
completion is not prompt and bounded, must not hold the Scheme thread while it
does so. The hazard is the *blocking*, not the mechanism: a synchronous
`run-shell` is the original offender, but a socket request left waiting on a
peer that answers only after slow work of its own stalls the tap identically.

Two shapes satisfy this, and which one applies depends on whether a result is
consumed:

- **A result is consumed** → go async and put the follow-on work in a callback,
  continuation-passing style: `run-shell-async` for a shell-out, and for
  Modaliser's own dialogs the `(modaliser dialogs)` / `open-chooser-prompt`
  panels, which are CPS by construction.
- **No result is consumed** → do not ask for one. Issue the request and return,
  rather than waiting on an answer that will be discarded — the socket
  transport's `unix-socket-send` (ADR-0020). There is nothing to defer, so no
  callback is warranted.

Either way the Scheme thread returns to idle immediately, so the leader and
every hotkey stay live.

Modaliser-raised dialogs (the backend error/confirm alerts) go through the
shared portable `(modaliser dialogs)` library, which owns the AppleScript
and shell escaping layers and routes execution through one R7RS parameter —
`current-dialog-runner`, default the real `run-shell-async` path — as the
single test seam. The library performs no capture handling: that is
dispatch's job (ADR-0015).

## Consequences

- **herdr raises no UI of its own for these ops.** This was assumed when the
  ADR was written and is false: read against herdr 0.7.5's source, no socket
  method prompts. herdr's branch-name dialog belongs to its TUI key handler,
  which fills the argument in before calling the same API; a `worktree.create`
  arriving without a `branch` makes the server generate one. So the herdr ops
  are not an instance of this ADR's external-UI case at all — they are ordinary
  commands, and what governs them is whether their *reply* can arrive promptly
  (ADR-0020's "sent, not called"). Modaliser omits `branch`/`force`
  deliberately, on their own merits: naming the branch is herdr's business, and
  omitting `force` is what makes git refuse to delete a dirty worktree.
- herdr's tab/workspace rename ops require a label and have no prompt of their
  own to collect it, so they collect it through a Modaliser-owned
  `chooser-prompt` (a text-input continuation panel extending the chooser's
  activating-WebView machinery — CPS-shaped like `dialog-confirm`). **That
  prompt is this ADR's real herdr case**: the interactive UI is Modaliser's,
  and the CPS is the prompt's. The command it submits is a plain synchronous
  socket call, answered sub-millisecond.
- Interactive commands are CPS-shaped where a result is consumed: the code
  after the dialog lives in a callback, not on the next line. That is the
  accepted cost of an unblocked Scheme thread.
- A future dialog site must use `(modaliser dialogs)` / `run-shell-async` —
  raising interactive UI via synchronous `run-shell` from an action thunk
  reintroduces the stalled-tap bug. That is the reason this ADR exists.
- The same bar applies to a *blocking* call that raises no UI at all. A
  synchronous socket request is fine when the peer answers promptly (herdr's
  queries and its rename commands measure sub-millisecond) and not fine when it
  answers only after work of its own — the timeout then becomes a routine
  stall, not a pathological one.
- `(modaliser dialogs)` stays inside the portable tree (no LispKit-specific
  imports).
- **One native site currently violates this and is known to.**
  `AppLibrary.resolveApplicationURL` (`AppLibrary.swift:284`) spawns `mdfind`
  and `waitUntilExit`s with no timeout, on the thread the caller is on — the
  exact shape this ADR exists to prevent, arrived at from the Swift side where
  neither `run-shell-async` nor the portability contract was in view. It is
  narrow: it is the *fallback* leg of app resolution, reached only when
  `urlForApplication(withBundleIdentifier:)` has already failed, and a
  Spotlight query normally answers in milliseconds. It is still unbounded —
  `mdfind` against a rebuilding index is not prompt, and both callers
  (`AppLibrary.swift:104`, `:118`) are launch actions running on the Scheme
  thread, so a slow answer stalls the tap and macOS force-disables it. Recorded
  rather than fixed because it has not been observed to bite; the fix, when it
  is worth taking, is the async shape this ADR already prescribes.
