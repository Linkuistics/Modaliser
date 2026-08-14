# measure-hot-scan-k2

## Goal

Name the string. Stop deducing which scan costs 27 s and take a reading.

The mechanism is settled (root brief): `string-ref` is Θ(n) per character, so
some Scheme loop is scanning something large. Deduction narrowed the size to
~100–400 KB and eliminated the obvious sources, but three outside-in capture
attempts could not catch the press. Instrument instead.

## Context

Read the root `BRIEF.md` first — especially the **Disconfirmed** list, so no
time goes back into the fork, the socket, AX or paneru.

Reproduce with: local leader (F17) while a **herdr** pane is focused. The
iTerm local tree is fast, so it is a ready control.

The profile also showed a `ShellLibrary.runShellFunction` costing ~1 s in the
*same* handler. A shell-out is the natural source of a several-hundred-KB
string, so log the command and its output length alongside the timings — but
note the searches so far found no unfiltered `ps`/`lsof` on this path, so do
not assume it.

## Done when

- The hot call site is identified by a **reading**, not an argument: which
  Scheme procedure, over which string, of what length, how many times per
  press.
- The same instrument answers the second symptom: is the window overlay's
  slowness the same scanner, a different one, or unrelated?
- Numbers are taken from a **release** build. `strip-parse-cost-k10` recorded
  that a debug measurement misattributed this exact cost once already; anyone
  re-running without `-c release` re-derives the wrong answer.
- A per-stage timing log around the leader-press path survives as a
  diagnostic if it earns its place (it is the instrument ADR-0014's contract
  deserves), or is removed deliberately if it does not.
- `k3`'s brief is updated with what was found, so the fix session starts from
  a fact.

## Notes

- The user's outstanding question, which this leaf can now answer empirically
  instead of asking: does the stall happen at ~3 panes, or only with many?
  At the time of profiling the socket reported 1 workspace / 1 tab / 3 panes,
  and the total payload was 4.3 KB — which is ~4 ms, not 27 s. If it stalls at
  that size, the scanned string is a large **constant**, not a payload that
  grows with herdr.
- `log-line` (`LogLibrary.swift`) routes to `os.Logger` at `.notice`; read it
  back with
  `log show --predicate 'subsystem == "dev.antony.Modaliser"' --style compact`.
  NSLog is invisible from an installed `.app`, so use `log-line`.
- Scratch instruments from the requirements session, if useful: a socket
  prober, a `sample` wrapper and a subprocess watcher, under this session's
  scratchpad. They are disposable — the durable instrument is the timing log.
