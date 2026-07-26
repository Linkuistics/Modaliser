# Outward native reach goes through a seam the host installs; the library tree cannot reach out

## Status

accepted

## Context

Two of Modaliser's native capabilities reach outside the process, and both were
reachable from every engine the test suite builds.

**Shelling out.** Every CLI-native backend drives its tool by spawning:
`tmux select-pane -L`, `zellij action move-focus`, `wezterm cli activate-pane`,
`osascript -e 'tell application "iTerm2" …'`, `nvim --server … --remote-send`.
All of it went through one native primitive, `run-shell`, which `SchemeEngine`
registers and imports into the top-level environment of **every** engine —
including the bare `SchemeEngine()` that every test constructs. Fourteen
libraries imported it directly. Nothing stood between a test and the developer's
own running tools.

**Fetching a URL.** `http-get` had the same shape with a different blast radius:
it reaches a third party. One library consumes it — `(modaliser web-search)`,
for Google Suggest — and one test fetched `httpbin.org` on every run, which is
why `--skip HttpLibraryTests` was the standing price of a green suite.

ADR-0020 closed the identical hole for herdr after an audit found nineteen
requests — including `pane.swap`, which rearranges a live layout — on the
developer's socket during a green run. Its note that the CLI-native backends had
the same shape and *less* protection was the lead this ADR followed first.

The audit method that worked, twice: intercept at the one choke point and let
the suite confess. Blocking `run-shell` in Swift and running the suite recorded
**419 commands from a single green run**:

| Reached | × |
|---|---|
| the user's login shell (`/bin/zsh -lc`, running their own `.zprofile`) | 216 |
| live iTerm2, over AppleScript | 28 |
| live Ghostty, over AppleScript | 22 |
| live wezterm (`wezterm cli list`) | 22 |
| live zellij (`zellij action list-panes`) | 12 |
| live kitty (`kitty @ … ls`, each also spawning `/usr/bin/python3`) | 12 |
| live tmux (`display-message -p`) | 12 |
| `command -v` tool probes (ADR-0017 Layer 2) | 82 |
| `pgrep`/`lsof` scans, `~/.config/kitty/kitty.conf`, app xattrs | 13 |

The same instrument on `http-get` recorded **2 requests**, one of them public
(`https://httpbin.org/get?test=hello`; the other `http://localhost:1`, an
invalid-URL test relying on nothing being bound to port 1). A second, blunter
instrument confirmed no third outward surface was hiding: running the suite
under `sandbox-exec` with all remote-IP outbound denied failed *only* the httpbin
test, 1090 others passing.

Three facts decide the shape of the fix.

First, **the suite passed with every one of them blocked** — no failures outside
the primitives' own tests — so not a single test depended on a real shell-out or
a real fetch. All 419 commands were pure leakage, and the one live fetch was
pinning *httpbin.org's* response shape rather than any behaviour of Modaliser's:
it went red on a 503 from that endpoint, not on a bug.

Second, the shell run looks read-only, and that is **luck, not design**: tmux
and zellij simply had no live session that day, while the write ops sit behind
the same unseamed call, and the blocking shim's empty return suppressed the
second-order commands a live session would have unlocked (`nvim --remote-send`
is gated behind a socket list that came back empty). `osascript` is always
present, which is why iTerm2 and Ghostty answered fifty times between them.

Third, the low HTTP count was **the same kind of luck**. Nothing had reached
Google Suggest — but the only reason was that no test had yet called
`web-search-handler` with a query of three characters or more. The threshold,
not any guard, was what stood between the suite and a live search endpoint.

## Decision

**The portable library tree cannot reach outward. It spawns and fetches through
seams that ship with no runner installed, and the host installs them at boot.**

- **The native capability is renamed and quarantined.** `ShellLibrary` becomes
  `(modaliser shell-native)`, defining `run-shell-native` and
  `run-shell-async-native`; `HttpLibrary` becomes `(modaliser http-native)`,
  defining `http-get-native`. The `-native` suffix is the tell: importing such a
  library is a bypass, and `scripts/check-portable-surface.sh` — the same gate
  that keeps `(lispkit …)` out of the tree — fails the build on **any**
  `(modaliser …-native` reference from `lib/modaliser`. The rule is stated over
  the suffix rather than over a list of names, so quarantining the next
  capability is a naming decision and needs no edit to the script.

- **The seams are portable libraries with no native import at all.**
  `(modaliser shell)` defines `run-shell` / `run-shell-async` as dispatch
  through `current-shell-runner` / `current-shell-async-runner`; `(modaliser
  http)` defines `http-get` as dispatch through `current-http-runner`. All
  default to `#f`. Because they import nothing but `(scheme base)`, the
  inertness is not a policy the library chooses — it is a capability the library
  **does not have**.

- **`root.scm` installs the live runners.** The shell block precedes every other
  import in the file, and *that* ordering is load-bearing: `(modaliser
  terminal)` derives `modaliser-tool-path` from a login-shell spawn *at import
  time* (ADR-0017 Layer 1), so an import ahead of the install would silently
  bake the fallback floor into every backend's PATH preamble. The HTTP install
  carries no such constraint — nothing in the tree fetches at import time, and
  the one consumer captures the seam's `http-get`, which dispatches at call
  time — so it sits with the rest of the host wiring, next to ADR-0020's socket
  path.

- **Degradation is the value each caller already handles.** For the shell it is
  the empty string: backends `2>/dev/null` their commands and read `""` as "the
  tool told us nothing" (ADR-0017), so an uninstalled runner degrades exactly
  like a missing binary. This is why that seam dropped under fourteen libraries
  and roughly forty call sites **without editing one of them**. For HTTP it is
  `#f`, which `(modaliser web-search)` already reads as "network error — keep
  showing just the pinned suggestion". The async shell half fires its callback
  with `(-1 "" reason)`, the same shape the native runner uses for a timeout or
  a failed spawn, and the inert `http-get` fires its callback with `#f`, so a
  caller awaiting an answer is answered rather than stranded (ADR-0014).

- **The user-facing surface is unchanged.** `root.scm` imports `(modaliser
  shell)` and `(modaliser http)` at top level, so `run-shell` and `http-get`
  remain visible to `config.scm` exactly as they were — now seamed, and in a
  booted app wired to the real capability.

The guarantee is then structural, not habitual: `swift test` constructs a bare
`SchemeEngine()`, which never runs `root.scm`, so no test can reach a live tmux,
zellij, wezterm, kitty, ghostty, alacritty, nvim, a Mac app over AppleScript, or
any network endpoint — however many `run-shell` or `http-get` calls it makes.

## Considered options

- **Per-backend runner seams** — give tmux and zellij what iTerm's
  `current-iterm-provision-runner` has. Cheaper, and it is the option the
  leaf's own brief weighed. Rejected because it is per-site discipline of
  exactly the kind the evidence refutes: the leaking calls come overwhelmingly
  from tests with no shell-out *intent* — a backend-record shape check, a
  detection-chain walk, a library import — which is precisely the set that
  would never think to stub a runner. Nothing would reopen it as the *primary*
  guard, but the two are not exclusive: a per-backend seam remains the right
  tool for a test that wants to assert one backend's exact command, and iTerm's
  survives for that reason. `(modaliser web-search)`'s `set-web-search-fetch!`
  is the same thing for HTTP and survives on the same terms — it is simply no
  longer what keeps the suite offline.

- **Delete the live-fetch assertion instead of seaming HTTP.** The cheapest fix
  for the network case, ~15 lines, and it would have made a plain `swift test`
  green. Rejected on the third fact above: that test was the *known* leak, not
  the *only* one — deleting it would have left Google Suggest one
  three-character query away, guarded by nothing. Reopen only if HTTP ceases to
  be reachable from the library tree at all, at which point the seam has no work
  to do.

- **A recording shim earlier on `PATH`, as the audit instrument.** Rejected in
  favour of the choke point: `path-prefix` composes its own PATH ahead of the
  inherited one (ADR-0017), so a shim can silently lose and yield a
  falsely-clean run, and the AppleScript-driven backends have no binary to
  shadow at all. Nothing would reopen it — the choke point sees strictly more.

- **Refuse to reach out unless running from an `.app` bundle**
  (`isProductionBundlePath`). Rejected: it buries a test-versus-production
  branch inside a native primitive, and `swift run` of the dev binary is a
  legitimate live use that this would break. Reopen only if the host bootstrap
  ever stops being the single place that knows the app is live.

- **Leave `run-shell` native and neutralise the tool path instead.** Rejected
  as ineffective: `osascript`, `pgrep`, `lsof` and `/bin/zsh` resolve from
  absolute paths or the hardcoded floor, and the 216 login-shell spawns do not
  consult the tool path at all.

- **A localhost HTTP server as the native fetch's test double.** Rejected as
  unnecessary machinery: `URLSession` resolves `data:` and `file:` URLs through
  the same code path without leaving the machine, and that drives the whole
  primitive — argument validation, the round trip, marshalling bytes into a
  Scheme string, the main-queue-plus-eval-lock hop to the callback. A listener
  would add port allocation, lifecycle and flake in order to cover Foundation's
  HTTP stack, which is not ours to test.

## Consequences

- 419 leaked commands and 2 leaked requests per green run become **zero**,
  measured the same way they were found. `swift test` needs no `--skip`.
- Both cutovers touched **zero call sites**, for the same structural reason:
  `run-shell` degrading to `""` is already every backend's "the tool told us
  nothing" path (ADR-0017), and `http-get` calling back with `#f` is already web
  search's "network error, keep showing the pinned row" path. So 14 libraries
  and ~40 shell sites, plus web search's one fetch, were re-seamed without an
  edit. Generalising: **when a seam can reuse a degradation value its callers
  already handle, the cutover is free** — look for that value before designing a
  new one, because the alternative is touching every call site.
- **Auditing this class needs two instruments answering different questions.** A
  recorder installed on the choke point (`run-shell`, `http-get`) answers *what
  leaks*, exactly — but only for the surface you have already found. A
  process-boundary denial answers *is that all*, which is what licenses a claim
  about the number of surfaces: `sandbox-exec` refusing remote-IP outbound while
  allowing localhost failed only the one httpbin test. It costs an extra suite
  run and a four-line profile, and needs `swift test --disable-sandbox`, since
  SwiftPM sandboxes its own manifest compile and nested `sandbox_apply` is
  refused. The recorder's count is never the finding on its own — as the two
  luck-not-design findings above show, ask what the *next* test would reach.
- The suite stops paying 216 login-shell spawns (~50–150ms each, ADR-0017), and
  stops executing the developer's `.zprofile` as a side effect of testing.
- A green run no longer depends on a third party being up. The skip existed
  because `httpbin.org` answers 503 often enough to matter.
- In any engine without a runner, `modaliser-tool-path` degrades to ADR-0017's
  floor. That is correct under test and irrelevant there; in production it is
  `root.scm`'s install ordering that keeps it correct, which is why that
  ordering is documented at the install site rather than left to inference.
- ADR-0017's Layer 2 `command -v` probes now also route through the seam, so a
  backend-health probe cannot spawn from an unbootstrapped engine either.
- A missing HTTP install would fail *quietly* — web search would return only its
  pinned row, raising nothing — so the install is pinned by a test that reads
  `root.scm` textually, as the shell ordering is.
- This ADR covers the two outward reaches that leave the process. Keystroke
  emission (`send-keystroke`) and window manipulation reach outward *within* the
  session, without a subprocess or a socket, and are **not** seamed. Checked
  while auditing: neither leaks today — the keystroke tests all pass
  `"nonexistent_key"`, so key resolution throws before any CGEvent is posted,
  and the window tests only read. That is discipline holding, not construction
  preventing, and it is the next place this class would surface.
