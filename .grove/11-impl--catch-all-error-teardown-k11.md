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
`docs/specs/vscode-editor-listing.md` that a provider raise "fails visibly and
nothing wedges" on both dispatch paths, and found the claim too broad for the
catch-all half. The spec now states the actual behaviour and accepts the
residue rather than pretending it away (decision 5, "the trade-off is accepted
rather than solved") — this leaf is where it stops being a residue.

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
