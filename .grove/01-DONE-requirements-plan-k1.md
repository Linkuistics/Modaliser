# plan-k1

## Goal

Establish what should be built to fix the leader-press stall: pressing the
local leader (F17) with herdr focused locks the keyboard for ~30 s before the
overlay appears. Reported alongside a second symptom — the window overlay that
paints chips "really slows down with a lot of panes/windows".

## Context

### Measured, this session

Instrument: `sample` on the running installed app (`/Applications/Modaliser.app`,
4.0.0, PID 3417), 240 s at ~1.14 ms/sample, spanning two reproductions.

Collapsing the main thread to frames over 800 samples leaves **one** hot path:

```
47378  KeyboardLibrary.fireHotkeyHandler         <- the F17 press
47378   Evaluator.execute -> VirtualMachine.apply
45952    VirtualMachine.invoke -> StringLibrary  <- 97% of the press
30014     stringRef +76   (NSString -> Swift String bridge)
15903     stringRef +148  (UTF-16 breadcrumb index)
  894  ShellLibrary.runShellFunction             <- ~1 s, same handler
```

~54 s of CPU across the window, ~27 s per press, ~97 % of it in LispKit's
`string-ref`.

**Mechanism — confirmed against LispKit's source**, not inferred from the
stack. `Expr.swift:43` stores Scheme strings as `case string(NSMutableString)`,
and `asString()` is `res as String` — a full bridge on every call. So:

```swift
func stringRef(expr, index) {                    // StringLibrary.swift:184
  let str = try expr.asString().utf16            // Θ(n) bridge + allocation
  let i = str.index(str.startIndex, offsetBy: k) // Θ(k) walk
  return .char(str[i])
}
func stringLength(expr) {                        // StringLibrary.swift:164
  return .fixnum(Int64(try expr.asString().utf16.count))   // Θ(n), also bridges
}
```

`string-ref` is **Θ(n + k)** per character and `string-length` is **Θ(n)**.
The two sample buckets map exactly onto the two lines: `stringRef +76` is the
bridge (30 014 samples), `stringRef +148` the index walk (15 903).

So the standard Scheme scanner shape used throughout the tree —

```scheme
(let loop ((k 0))
  (when (< k (string-length s))   ; Θ(n) — full bridge
    (let* ((c (string-ref s k))   ; Θ(n + k) — another full bridge
```

— performs **two whole-string bridges per character**, each allocating a fresh
copy: one scan copies ~2n^2 bytes. This is a cliff, not a constant factor. At
4 KB it is ~4 ms and invisible; the 27 s press implies a scanned string of
roughly **100–400 KB** (the range spans plausible transcode rates), or an
equivalent number of repeated scans over a smaller one.

**Why the keyboard dies, not just the overlay.** The scan runs inside
`fireHotkeyHandler` -> `Evaluator.execute`, synchronously on the main thread
that owns the CGEvent tap. This is the stalled-tap failure mode ADR-0014
exists to prevent; the herdr socket's 1000 ms timeout was written with exactly
this ceiling in mind, but a Scheme-side scan has no such bound.

### Disconfirmed (do not re-investigate)

- **The herdr fork.** `linkuistics-herdr 0.7.5-linkuistics.3` is installed and
  is the running server. Fork-only `ui.layout` answers in 0.1 ms with a full
  envelope. All seven read methods reply in 0.1–0.6 ms, newline-terminated.
- **Socket transport / payload size.** The seven reads one come-to-rest makes
  total **4.3 KB** (1 workspace / 1 tab / 3 panes). By the paneru grove's own
  release measurement that parses in ~4 ms.
- **iTerm AppleScript.** `focused-pane-id`'s exact script runs in 80 ms.
- **AX tree walk.** `canvas-frame-probe` / `ax-find-elements-named` does not
  appear anywhere in the profile.
- **paneru.** Not installed on this machine (`command -v paneru` fails), so
  `windows-screen` resolves to `layout-windows-screen`; the paneru strip parse
  is not on any live path here.
- **The simplify-project commit** (vpnkvzxunyzs, 2026-08-13) is docs-only.
- **The media-key work** (lzpvrwktsymu / nwpmvuzmkvuy) is confined to
  `MediaKeyEmitter.swift`, `InputLibrary.swift` and one default-config binding.

### Prior art in-tree

- `strip-parse-cost-k10` (onwkwpqzyrny, 2026-08-04) already fought this cost
  class in `json.sld` and recorded that a native substring search "is not
  reachable" under the portability contract.
- `escape-string` (`util.sld:170`) is the idiomatic O(n) shape already used
  here: one `string->list`, then walk the list — no `string-ref` at all.
- Known naive scanners: `string-index-of` / `string-contains?`
  (`util.sld:95-137`, documented "naive O(n*m) ... fine for the short strings
  we split on"), `write-json-string` (`json.sld:341`), `json-parse`
  (`json.sld:90`, 24 `string-ref` sites).

### Open

1. **Which string.** 4.3 KB does not cost 27 s; the quadratic implies
   ~100–400 KB scanned (or the equivalent in repeated scans). Not identified.
   Ruled out so far as the source: no `ps -A` anywhere in the tree (every `ps`
   is narrowed by `-t <tty>` or `-p <pid>`); `correlate-mux-client-to-host-tty`
   and `list-nvim-sockets` pipe `lsof`/`pgrep` through `awk`, so Scheme
   receives only a pid or a socket path. `overlay-base-css` (43 KB) is read
   once and cached, and `escape-string` walks a list, not `string-ref`.
   Remaining `string-ref` loops, in descending suspicion: `json-parse` and
   `write-json-string` (`json.sld`, 24 sites), `string-index-of` /
   `string-split` / `string-trim` (`util.sld:95-168`), then `dsl.sld`,
   `web-search.sld`, `activation.sld`, `display-actions.sld`, `chooser.scm`.
2. **What made it a step change.** The install spanned 2026-07-27 -> 08-13.
   Not the JSON rewrite (the old reader indexed with `string-ref` too), not
   the media keys, not the simplify pass.

The cheapest way to close (1) is to stop deducing and measure: a timing log
around the herdr on-enter stages turns "which string" into a reading. This is
the first thing the next leaf should do.

## Done when

Shared understanding reached on scope and approach, and the tree grown (or a
`planning` leaf added).

## Notes

- Grilling question outstanding: how large is herdr (panes / tabs / Spaces)
  when the stall reproduces? Decides whether the payload-size theory survives.
- User's proposal on the table: "move that code to Swift, or find some
  optimisations." Pushback owed: the profile shows the chip/AX code is not hot,
  so moving *that* to Swift fixes nothing; and `escape-string` shows O(n) is
  reachable in portable Scheme without a native seam (ADR-0023 /
  `check-portable-surface.sh`).
