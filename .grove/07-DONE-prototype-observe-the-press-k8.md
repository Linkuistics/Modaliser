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

## The reading

Taken 2026-08-14 21:24, release build (`./scripts/install.sh` →
`/Applications/Modaliser.app`, PID 41128), instrument marker present, boot
printed `press instrument ENABLED`. One F17 press with herdr focused. The
chain is **iTerm2 → herdr** — herdr runs inside iTerm2 — so the walk crosses
two backends and both legs are in the number.

| | k2 (historical) | this press | |
|---|---|---|---|
| `span leader/focused-terminal-path` | 26 550 ms | **490 ms** | 54× |
| `span leader/modal-activate!` | 26 694 ms | **14 ms** | the second walk is gone |
| whole handler, `epoch` → `end leader-press` | ~53 s | **506 ms** | ~105× |
| the 97 KB `pane.process_info` parse | 26 205 ms | **183 ms** | k3's 186 ms bench, in the app |

The three rows the leaf asked for, each answered:

1. **`focused-terminal-path` is milliseconds.** 490 ms. **k3 landed** — the
   payload is still 97 193 characters (`big json-parse len 97193 head
   {"id":"modaliser","result":{"type":"pane_process_info"`), and it parses in
   183 ms. The k3 release micro-benchmark predicted 186 ms; the app came in at
   183 ms, so the bench harness was measuring the real thing.
2. **`walk-path calls 1` beside `walk-path/pinned calls 1`.** Both present.
   **k5 landed** — the chain was wanted twice and paid for once. It holds in
   the `delayed-show` report too, so the pinned extent covers the
   timer-driven overlay paint, not just the handler.
3. **Whole press ~0.53 s.** 506 ms, against the ~1.05 s the leaf projected for
   post-k3/pre-k5. k5's halving is observed, not argued.

Press to overlay-at-rest is 888 ms, of which **303 ms is the deliberate
`delayed-show` timer** and 79 ms is the paint itself (`on-enter` 34 ms,
`show-overlay` 47 ms; `escape-string` 55 calls, `max-chars` 950 — nothing near
the 4 KB tripwire). Nothing there is a stall to chase.

**Subjective, from the human who pressed the key:** *"back to 'normal'
responsiveness, which was never perfect, but is good enough."* The keyboard is
not held.

### Where the 490 ms actually goes

| leg | ms | what |
|---|---|---|
| iTerm2 `walk/focused-pane-id` | 154 | one `osascript` |
| iTerm2 `walk/detect-fg` | 148 | one `osascript` (77) + one `ps` (69) |
| herdr `walk/focused-pane-id` | 3 | socket + 699-char parse |
| herdr `walk/detect-fg` | 185 | socket + the 97 KB parse (183) |

**The iTerm host leg is 302 ms — 62 % of the walk, and now the biggest single
item in a press.** `measure-a-leader-press.md` recorded that leg at ~333 ms and
deferred the question *"is the remainder worth attacking?"* to a reading taken
after the pinned chain. This is that reading, and it answers it: the leg did not
change (pinning halves how often it is paid, not what it costs), it is now the
majority, and it is three subprocess spawns deep. Not attacked here — the human
who pressed the key called the result good enough, and this leaf is the
observation.

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
