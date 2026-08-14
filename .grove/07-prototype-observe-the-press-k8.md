# observe-the-press-k8

HITL — this leaf cannot be run AFK. It needs the app installed, a relaunch,
and a human pressing F17 with herdr focused.

## Goal

Take the end-to-end reading that three landed leaves are all still waiting on.
`linear-string-scanning-k3`, `linear-string-scanning-k6` and
`walk-path-press-cache-k5` each shipped with `swift test` green and no
installed-app measurement, so the grove's first "Done when" — *the herdr local
leader comes to rest without a perceptible stall* — is **argued, not
observed**. One press settles all three.

## What to do

`docs/how-to/measure-a-leader-press.md` is the procedure; it is the standing
instrument k2 left behind, and it already carries the release-build warning.
In short:

1. `./scripts/install.sh` — a **release** build. A debug number misattributed
   this cost once already (`strip-parse-cost-k10`); do not measure
   `swift run` or `.build/debug/Modaliser`.
2. `touch ~/.config/modaliser/instrument`, then relaunch from the menu bar
   (no in-place reload, by doctrine — ADR-0018). Boot should print
   `press instrument ENABLED`.
3. Focus herdr. Press F17 once. Read the log block.

## What the reading has to show

| read for | expected | means |
|---|---|---|
| `span leader/focused-terminal-path` | milliseconds, not seconds | k3 landed — the 97 KB `pane.process_info` parse is 186 ms, not 26.2 s |
| `walk-path calls 1` **beside** `walk-path/pinned calls 1` | both present | k5 landed — the chain was wanted twice and paid for once |
| whole press, wall clock | ~0.53 s | k5's halving of the ~1.05 s post-k3 press |

`walk-path calls 2` means a second read escaped the press extent. `walk-path
calls 1` with no `walk-path/pinned` line means the press landed on a
tree-only context (nvim), not a herdr pane — that is a valid press but the
**wrong one for this leaf**; re-press with herdr focused.

The subjective half matters as much as the numbers: does the overlay come to
rest without a perceptible stall, and is the keyboard ever held?

## Done when

- A release-build reading is recorded here, before/after alongside k2's
  historical 26 205 ms, and the three rows above are each answered.
- The subjective question is answered by the human who pressed the key.
- If the reading **disconfirms** any of the three — the stall persists, or a
  second walk is still happening — do not fix it in this leaf. Record what
  was read and `leaf-add` the diagnosis; this leaf is the observation.

## Pointers

- `docs/how-to/measure-a-leader-press.md` — procedure, how to read the three
  instruments, and the two already-taken readings (iTerm host leg ~333 ms;
  window overlay 133 ms) that this press will also touch.
- `CONTEXT.md` — **Pinned chain**.
- ADR-0025 — the rule k3/k6 established; ADR-0018 — why relaunch, not reload.
- Root `BRIEF.md` — the full history and the disconfirmed list. Do not
  re-investigate anything on it.
