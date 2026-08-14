# Measure a leader press

When a leader press feels slow, this is how to find out *where* it went
rather than guessing. The instrument is `(modaliser instrument)`, and it is
already wired into the press path — you turn it on, press once, and read the
log.

## Turn it on

```bash
touch ~/.config/modaliser/instrument
```

Then **relaunch** Modaliser (menu bar → Relaunch). The app never re-reads
anything in place, by doctrine — ADR-0018.

The switch is a file rather than an environment variable because a
GUI-launched `.app` inherits a stripped environment and would never see one
(the same fact ADR-0017's PATH derivation exists for). Boot confirms it:

```
Modaliser: press instrument ENABLED (~/.config/modaliser/instrument)
```

**Measure a release build.** `swift run` and `.build/debug/Modaliser` will
give you a number, and it will be the wrong number attributed to the wrong
place — that has already happened once (`strip-parse-cost-k10`). Use
`./scripts/install.sh` and measure `/Applications/Modaliser.app`.

## Press once, then read

```bash
log show --predicate 'subsystem == "dev.antony.Modaliser"' \
         --style compact --last 5m
```

(`log` is a zsh builtin — write `/usr/bin/log` if your shell shadows it.)

A press emits one bracketed block. The one below is the **historical reading
that found the stall** — 26 seconds in `json-parse` over a 97 KB
`pane.process_info` reply — kept because it is what a bad press looks like.
That particular cliff is fixed (ADR-0025); the same payload now parses in
~186 ms, so a healthy `focused-terminal-path` span is milliseconds, not
seconds.

```
instr: epoch leader-press                       ← the epoch starts; counters cleared
instr: span leader/frontmost-bundle-id 0 ms     ← the four stages of the handler
instr: span leader/focused-terminal-path 26550 ms
instr: span leader/resolve-activation 0 ms
instr: span leader/modal-activate! 26694 ms
instr: report leader-press                      ← the counters, since this press
instr: - json-parse calls 7 total-chars 198702 max-chars 97360
instr: - string-index-of calls 10 total-chars 108 max-chars 21
...
instr: end leader-press
```

The overlay's own work is reported separately, under `delayed-show`, because
on the delayed path it runs from a timer callback rather than inside the
handler. **Its counters are cumulative since the `epoch`, not a fresh
window** — a `max-chars` there that matches the handler's is the same string
carried forward, not a second parse of it. Subtract to see what the overlay
itself added.

For contrast, the same press path measured healthy (2026-08-14, release build,
herdr focused, chain iTerm2 → herdr):

```
instr: span leader/frontmost-bundle-id 1 ms
instr: span leader/focused-terminal-path 490 ms
instr: span leader/resolve-activation 1 ms
instr: span leader/modal-activate! 14 ms      ← 26 694 ms before the chain was pinned
instr: - walk-path/pinned calls 1 total-chars 0 max-chars 0
instr: - json-parse calls 5 total-chars 100468 max-chars 97193
instr: - walk-path calls 1 total-chars 0 max-chars 0
```

Same 97 KB payload, same press, 26 550 ms → 490 ms. `epoch` to `end
leader-press` is 506 ms; the overlay comes to rest 888 ms after the press, of
which 303 ms is the deliberate `delayed-show` timer.

## What the three instruments each tell you

| line | instrument | reads as |
|---|---|---|
| `span <name> <n> ms` | a stopwatch around a coarse stage | where the time went |
| `- <site> calls … max-chars …` | a counter on a hot scanner | how much text it was handed, and how often |
| `big <site> len … head …` | the tripwire | *which* string — a 72-char prefix names the payload |

The prefix is the point. A length says "something big"; `head
{"id":"modaliser","result":{"type":"pane_process_info"` says which socket
method to go and look at.

Two shapes to read for, because they need different fixes:

- **one huge string** — a big `max-chars` at one site. The scanner is on a
  quadratic cliff (`string-ref` is Θ(n) per character in LispKit, so an
  index-based scan copies ~2n² bytes). The fix is to convert once and scan
  the conversion, never to tune the loop — see
  [ADR-0025](../adr/0025-portable-scheme-never-indexes-a-string.md).
- **many small ones** — a large `calls` with a small `max-chars`. Something
  is being re-derived that should have been computed once. `walk-path`'s
  counter exists for exactly this: the chain walk is uncached outside a
  press, and a press that walked twice paid everything twice.

`walk-path` and `walk-path/pinned` are a pair, and reading them together is
what makes the second walk visible:

| reads | means |
|---|---|
| `walk-path calls 1`, `walk-path/pinned calls 1` | healthy — the chain was wanted twice and paid for once (CONTEXT.md "Pinned chain") |
| `walk-path calls 2` | a second read escaped the press extent — the handler no longer brackets it, or the reader runs from a callback |
| `walk-path calls 1`, no `walk-path/pinned` | the landing carries no derived step-in edge (a tree-only context like nvim), so there was only ever one read |

## Two readings already taken, so you don't retake them

Both were measured with this instrument while the quadratic-scan stall was
being chased. Neither has been diagnosed further, deliberately — they are
recorded here so a later reading starts from a number rather than a hunch.

- **The iTerm host leg is the biggest single item in a press, and that is now
  measured rather than projected.** Two `osascript` calls plus a `ps`, ~333 ms
  when first seen. That was 1.2 % of a 53 s press and correctly ignored at the
  time; once the parse cost went from 27.9 s to 186 ms the arithmetic
  inverted, and the leg is paid on every walk. Pinning the chain halves how
  often it is paid, not what it costs — the post-pin reading confirms exactly
  that: **302 ms of a 490 ms walk, 62 %**, split
  `walk/focused-pane-id` 154 ms (one `osascript`) and `walk/detect-fg` 148 ms
  (`osascript` 77 + `ps` 69). It is paid whenever herdr runs inside iTerm2,
  because the chain crosses both backends. Left alone deliberately: the press
  it dominates is 506 ms, and the human it was slow for calls that good enough.
  Attack it only if a press starts feeling slow again — and if you do, the
  target is three subprocess spawns, not a scanning cliff.
- **The window overlay is not the same cliff.** "Slows with a lot of windows"
  measured 133 ms end to end, with no string past the 4 KB tripwire and
  `escape-string` — already O(n) — the only scanner touched. It was never
  reproduced *as a stall*, which is why nothing was diagnosed. If it recurs,
  take a reading at that window count and treat it as its own problem; it is
  not a residue of the parse cost.

## Turn it off

```bash
rm ~/.config/modaliser/instrument
```

and relaunch. With the marker gone every span, counter and tripwire in the
tree is a parameter read and a return.

## Adding a probe point

`instrument-span` around a stage, `instrument-tally!` / `instrument-sample!`
on a scanner. One rule, and it is not stylistic:

**Never let the instrument call `string-length`.** It bridges the whole
string, so an instrument that measured its own input would add a second Θ(n)
cost to the loop it is measuring. Every call site already holds the length —
that is why it is scanning — so it passes it in.

For the same reason, `instrument-tally!` takes no clock: two `current-jiffy`
calls inside a per-character scanner would dominate the thing under
measurement. Duration comes from the enclosing span.
