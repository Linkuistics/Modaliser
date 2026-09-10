# catch-all-error-teardown-k11

## Goal

Make the catch-all handler's error path tear down modal state, not just
deregister itself — so a Scheme error raised on a keypress inside a modal leaves
no overlay on screen over live FSM state.

## Context

**The defect, exactly.** `KeyboardLibrary.swift:300`: when the catch-all handler
raises, the host logs it and assigns `catchAllHandler = nil` as a "safety
recovery". That much works — ordinary keys pass through again and keyboard
capture is not wedged. But nothing else happens: `modal-exit` does not run, the
FSM is not halted or reset, and the overlay is not hidden. So the user is left
looking at an overlay that no longer responds, over Scheme modal state that
still thinks it is active, until the next activation resets it.

Contrast the **leader** path, which is correct and is the model:
`modal-activate!` runs `fsm-activate!` — and so any provider raise — *before* it
registers the catch-all or shows the overlay (`fsm.sld:1930`), and the Swift
wrapper logs and finalises the capture regardless
(`KeyboardLibrary.swift:185`). Nothing is registered, nothing is shown, the
screen simply fails to open.

**Where this surfaced.** `vscode-part-enumeration-k8` checked the claim in
`docs/specs/vscode-window-parts.md` that a provider raise "fails visibly and
nothing wedges" on both dispatch paths, and found the claim too broad for the
catch-all half. The spec now states the actual behaviour and accepts the
residue rather than pretending it away (decision 7, "the trade-off is accepted
rather than solved") — this leaf is where it stops being a residue.

**The spec was renamed and its decision renumbered under you, and nothing else
about this leaf moved.** `vscode-terminal-listing-k10` changed the VSCode
listings' row source to a companion extension (ADR-0026), which renamed
`vscode-editor-listing.md` to `vscode-window-parts.md` and pushed the merge
from decision 5 to decision 7. The merge itself — and therefore the raise this
leaf is about — is source-independent and is unchanged.

**Why it is its own leaf rather than a rider.** This is a host change on a path
every modal screen in the app goes through, not a VSCode one. The blast radius
is the reason it was externalised, and it is also the thing to be careful
about: the recovery must not itself raise, must be safe when the modal is
already inactive (`modal-exit` is documented idempotent), and must not deadlock
— the error path is already inside `withEvalLockNonBlocking` on the main queue,
so calling back into the evaluator from there needs the same care every other
re-entrant native callback needs (see `ModaliserContext`'s doc comments).

## Done when

- A raise from the catch-all handler leaves no overlay on screen and no live
  Scheme modal state — the same end state a normal modal exit reaches.
- Keyboard capture is still released, which is what the current code gets right;
  the fix adds teardown rather than replacing the deregistration.
- The recovery is safe when the modal is already inactive, and cannot itself
  raise out of the error path.
- There is a test that a raising handler ends with the modal inactive. If that
  cannot be reached offline, say so and say what was verified instead.
- `swift build` and `swift test` green; `./scripts/check-portable-surface.sh`
  and `./scripts/check-decision-free.sh` both pass.

## Notes

- `/usr/bin/log` is not user-visible feedback, and this leaf does not have to
  make it so. Whether an error deserves a visible signal beyond the modal
  closing is a separate question — raise it rather than absorbing it.
- A shell alias shadows `log`; use `/usr/bin/log` when checking the subsystem
  `dev.antony.Modaliser`.
- If the fix turns out to want a change to how `modal-exit` is reached from
  Swift rather than a call added at the error site, that is fine — but it is the
  kind of thing to state in the commit rather than leave in the diff.

## Decisions (running log)

- **The recovery is registered *with* the handler it recovers, as a second
  argument to `register-all-keys!`** — not reached by Swift looking `modal-exit`
  up by name, and not a separate `set-modal-error-recovery!` hook. Two reasons.
  Structurally, `modal-activate!` is the single call site that registers a
  catch-all, so passing the thunk there makes "a registered catch-all always has
  a recovery" true by construction rather than asserted — the k6 lesson the
  BRIEF flags. Semantically, the decision about *what* teardown means stays in
  Scheme, where `modal-exit`'s idempotency and the overlay hooks live; Swift
  only applies an opaque thunk. The argument is optional, so every existing
  `(register-all-keys! h)` caller and test stub is unchanged.

- **The recovery is `modal-abort!`, not `modal-exit`.** `modal-exit` can itself
  raise: `fsm-halt!` fires the state's `exit` slot and `run-on-leave` fires user
  `on-leave` hooks, both arbitrary user procedures — and a raise there leaves the
  overlay standing, which is the exact defect. `modal-abort!` tries `(modal-exit
  'error)` under `guard` so hooks still get their chance, then applies an
  unconditional floor that cannot raise: `full-deactivate!` (pure `set!`s),
  `unregister-all-keys!` (native), `hide-overlay` (guarded — it is a
  host-injected cell), `sync-modal-state-from-fsm!` (pure on the inactive
  branch). Safe when already inactive because every step is idempotent.

- **A fourth exit reason, `'error`.** Forwarded to `on-leave` hooks and `exit`
  slots like the existing three. Nothing dispatches on reason exhaustively, so
  the addition is additive; documented in `docs/reference/state-machine.md`.

- **Swift deregisters first, then recovers.** `catchAllHandler = nil` before
  applying the thunk, so keys pass through while recovery runs and a recovery
  that itself raises still leaves capture released — the property the current
  code gets right is preserved as the floor, not replaced.

- **`/usr/bin/log` stays the only signal, and that is raised rather than
  absorbed** — see the handback at the end of this file.

- **The deadlock question is answered from LispKit's source, not from
  reasoning.** A second `evaluator.execute` inside the one
  `withEvalLockNonBlocking` acquisition is safe at the pinned revision
  (`Package.resolved`, `08c2fb27`): `Runtime/Evaluator.swift:88` takes
  `mainThread.mutex` only at head and tail, never across the eval, and
  `Runtime/VirtualMachine.swift:214` `onTopLevelDo` resets the machine in a
  `defer` — stack cleared, `sp = 0`, `winders = nil`, `abortionRequested` and
  `executing` false — on *every* exit path including the error one, so the
  second call's `assertTopLevel()` sees a clean machine. Cited at the decision
  site with a re-check-on-bump note.

- **No in-session reviewer spent.** The two claims a reviewer would have been
  asked about are both already covered by stronger instruments: the teardown
  behaviour by an executable seam whose control was *seen to fail* (all four
  assertions, overlay included, fail with the one-line wiring reverted), and the
  re-entrancy by the LispKit source above. The leaf's review allowance is
  unspent and no `review-impl` leaf is cut.

- **The first draft of the regression test was vacuous, and this is why the
  test uses a raising PROVIDER.** With a raising leaf *action*, the overlay
  assertion passed even with the fix reverted: a Terminal leaf's wrapped entry
  fires its pending teardown (`wrap-terminal-command-entry` →
  `fire-pending-teardown-if-armed!`) *before* running the action, so the overlay
  was already down. Only a raise at come-to-rest — a provider — reproduces the
  residue the spec describes. Recorded because the next person to touch this
  test will reach for the simpler shape.
