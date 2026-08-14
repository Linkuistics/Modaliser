# walk-path-press-cache-k5

## Goal

Stop walking the terminal chain twice per leader press. `walk-path`
(`terminal.sld:433`) is uncached, and a press walks it once for the handler's
own `focused-terminal-path` and again inside `modal-activate!`'s visit
snapshot. Everything the walk costs is paid exactly twice.

This is `k3`'s option 2, deferred out of that leaf deliberately: it is a
caching question with a lifetime/invalidation contract, not the scanning-idiom
question k3 owned.

## Why it is worth its own leaf now

Before `k3`, halving a 53-second press still left a 26-second press, so the
memo was rounding error against the cliff. After `k3` it is the largest
remaining lever, and the press budget has changed shape entirely:

| per press, post-k3 | ×1 | ×2 (today) |
|---|---|---|
| iTerm host leg (2 × `osascript` + `ps`) | ~333 ms | ~666 ms |
| herdr `pane.process_info` parse (97 KB) | ~186 ms | ~372 ms |
| herdr `pane.current` parse + wire | ~8 ms | ~16 ms |

So a press is now roughly **1.05 s**, and caching the walk takes it to
~0.53 s. Note the inversion this creates: the iTerm leg, which `k3`'s brief
correctly called "not worth chasing" at 1.2 % of 53 s, is now the single
biggest item. That is a horizon note on the root brief, not this leaf.

## Context

- `walk-path`'s own comment already asks for this: *"Not cached. Future work:
  memoise per leader press once the leader layer exposes a 'press epoch'
  hook."* This leaf is that hook plus the memo.
- The leader layer **does** already bracket a press: `handoff.sld:92-110`
  wraps the whole handler body between `instrument-reset! 'leader-press` and
  `instrument-report! 'leader-press`. That bracket is instrument-only today,
  but it is the exact extent a cache wants, and it is the natural place to
  hang a real one.
- Both call sites are inside that bracket: `focused-terminal-path` at
  `handoff.sld:95`, and `modal-activate!` at `:103`.

## The design question this leaf owns

**Scope the cache to a dynamic extent, not to a global with invalidation.**
The shape to reach for is a `call-with-…` in `(modaliser terminal)` that binds
a fresh empty memo for the duration of a thunk, with `walk-path` consulting it
only when one is bound. Outside that extent there is no cache at all, so every
existing caller — ops, `active-backend`, `in-chain?`, tests — behaves exactly
as today and there is no stale-chain window to reason about. A global cache
with explicit invalidation is the version that goes wrong: the chain changes
whenever the user moves focus, and nothing in this tree observes that.

Things to settle while you are there:

- Which extent, exactly. The whole handler body (one walk per press) is the
  obvious answer; check that nothing inside it *wants* a fresh walk after an
  effect has run. `modal-activate!` takes a snapshot, so it should be reading
  the same chain the handler resolved against — if it isn't, that is a bug the
  cache would paper over, and worth saying so.
- Whether the delayed-overlay path (`fsm.sld:1906`, reported under the
  `delayed-show` epoch) runs outside the extent and therefore still walks.
- LispKit has no `set-car!`/`set-cdr!` (portability.md), so the memo cell is a
  parameter holding a vector or a box, not a mutable pair.

## Done when

- A press walks the chain once, demonstrated by `walk-path calls 1` in the
  instrument's report where it reads 2 today
  (`docs/how-to/measure-a-leader-press.md`).
- The before/after is a **release** reading, per the root brief.
- `swift test` green, both invariant checks green.
- The stale comment at `terminal.sld:432` is gone, replaced by what the extent
  actually is.
- `CONTEXT.md` gains the term for the extent if one earns its place — the
  Terminal-pane domain has no word for "the chain, as resolved once for this
  press" and the next session will need one.

## Notes

- `k3` left `json-parse` linear but `walk-path` untouched, so the two parses
  in the table above are genuinely identical work done twice, not two
  different reads.
- Do not fold the iTerm leg into this leaf. Measure it after the memo lands
  and give it its own if it still bites.

## What was decided, as it landed

**The second walk is conditional, and a test said so before the fix did.**
The brief said a press walks twice; that is true of the press that was
reported, not of every press. `modal-activate!`'s snapshot re-probes only
when the LANDING ROOT carries the derived `.` step-in provider — a
terminal-like host screen, or a **mux-backed** context tree. A press landing
on a tree-only context (nvim's `edit-tree`) already walked once. The herdr
press lands on the mux's own tree, so the reported case is the double-walk
case; the first draft of the regression test landed on `edit-tree`, passed
against the unfixed tree, and is what corrected the reading.

**The extent, exactly: the handler body.** `call-with-pinned-chain` wraps
the `let*` in `make-configured-leader-handler` — from the frontmost-bundle
read through `modal-activate!` — and closes before `instrument-report!`.
Nothing inside wants a fresh walk: the effects in there are graph
activation, key registration and the overlay show, none of which move
terminal focus. The brief's suspicion is resolved in the other direction:
`modal-activate!` was *already* meant to read the chain the handler
resolved against, so sharing one walk is what the doctrine asked for, not
a paper-over. Recorded in `docs/specs/configuration-value.md`'s
chain-staleness doctrine as a refinement in the cheap direction only.

**The delayed-overlay path runs outside the extent** (`fsm.sld:1894`, via
`after-delay`), so it still walks — correctly: a timer callback is a later
instant, and it has its own `delayed-show` epoch precisely because it is
not the press.

**A dynamic extent, not a global.** Per the brief. Nesting joins rather
than re-walking, so a caller can pin without knowing its caller did; a
raising probe pins nothing. The cell is `#(filled? chain)` behind a
parameter — no `set-car!` in LispKit, and `'()` is a legal walk result, so
emptiness could not double as "not yet walked".

**`walk-path/pinned` is a second counter, not silence.** A served read is
tallied under its own site, so the report reads `walk-path calls 1` beside
`walk-path/pinned calls 1` — which distinguishes "pinned, and the second
read happened" from "the second read stopped happening for some other
reason". Table added to `docs/how-to/measure-a-leader-press.md`.

## Verification

- `swift test` — **1179 green**. Both invariant checks green.
  `./scripts/build-app.sh` builds and the bundled-Scheme check passes.
- The count is pinned by tests, not by a log line:
  `ModaliserHandoffLibraryTests/aLocalPressWalksTheChainOnce` (a real
  local press through the real registry: one `detect-fg` per hop) and
  `theNextPressWalksAfresh` (the next press sees a changed chain), plus the
  `pinned chain` suite in `ModaliserTerminalLibraryTests` (sharing, no
  leak across or outside extents, nesting, raising probe). Both press tests
  fail against the unfixed tree with 2 probes per hop.
- **Outstanding, and not AFK-reachable: the release press reading.** The
  count is build-independent, so a release build cannot change it — what a
  release reading would add is the wall-clock halving (~1.05 s → ~0.53 s),
  and that needs the app installed and F17 pressed with herdr focused.
  Same gap `k3` retired with. One install and one press settles both:
  `./scripts/install.sh`, `touch ~/.config/modaliser/instrument`, relaunch,
  press F17 in herdr, then
  `log show --predicate 'subsystem == "dev.antony.Modaliser"' --style compact --last 5m`.
  Expect `walk-path calls 1` + `walk-path/pinned calls 1`, one
  `leader/focused-terminal-path` span, and `leader/modal-activate!` shorter
  than it was by roughly one `pane.process_info` parse plus one iTerm leg.
