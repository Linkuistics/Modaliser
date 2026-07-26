# herdr is driven over its Unix socket (JSON-RPC), not the `herdr` CLI

## Status

accepted

## Context

Modaliser drives every terminal backend by shelling out (`run-shell "herdr …"`,
`run-shell "tmux …"`, …) and parsing stdout. For **herdr** specifically this is
a poor fit, exposed in 2026-07 when the user merged herdr 0.7.5 upstream and
top-level pane jumps "stopped working":

- The jump space assigns a label to every pane in the tab and focuses the
  chosen one via `focus-pane-by-id` → `herdr agent focus <pane_id>`. In 0.7.5
  `agent focus` only resolves **agent** panes; a non-agent pane (a plain shell,
  a file browser) returns `{"error":{"code":"agent_not_found"}}`, swallowed by
  the backend's `2>/dev/null`. Dispatch, the provider, and chip painting were
  all verified sound — only the focus verb was wrong.
- herdr 0.7.5's **CLI has no by-id pane focus** (`pane focus` is directional;
  `--pane` is the *origin*). The **socket** does: `pane.focus {pane_id}` focuses
  any pane, confirmed live.

More broadly, herdr is **socket-native** — its CLI is a thin wrapper over a
JSON-RPC Unix socket (`$HERDR_SOCKET_PATH`, `~/.config/herdr/herdr.sock`).
Shelling out therefore pays a `fork`+`exec` per call on a hot path (the jump
provider and live-lists re-query on every come-to-rest), inherits the GUI PATH
fragility that ADR-0017 exists to paper over, and discards structured errors
into `2>/dev/null`. tmux and zellij, by contrast, are genuinely CLI-native.

## Decision

**Route all herdr interaction through the socket; leave tmux/zellij on the CLI.**

- **Transport: connect-per-request.** herdr closes the connection after one
  response (verified on both `herdr.sock` and `herdr-client.sock`), so the
  transport is *connect → send one JSON line → read one JSON line → close*, per
  call. No connection pool, no request multiplexing, no id correlation to track
  (one request per connection is trivially one-to-one). A socket round-trip is
  still orders of magnitude cheaper than a process spawn.
- **The transport is inert until the host installs a socket path.**
  `current-herdr-socket-path` defaults to **`#f` — "no herdr socket
  configured"** — and both transports refuse to dial without one, returning the
  same `#f` an unreachable socket returns (logged, never raised). The live path
  is installed by the app bootstrap: `root.scm` calls
  `(current-herdr-socket-path (herdr-default-socket-path))`, alongside the
  arity predicates it installs into `(modaliser fsm)` and the chooser push it
  installs into `(modaliser web-search)`. The *policy* — `$HERDR_SOCKET_PATH`,
  else `$HOME/.config/herdr/herdr.sock` — stays in the herdr library as that
  pure procedure; only the decision to go live is the host's.

  Resolving the path at library-load time instead made every herdr caller live
  the moment the library was imported — including inside `swift test`. A full
  green run was putting nineteen requests on the developer's own running herdr:
  not only reads, but `pane.focus_direction`, `pane.focus`, `workspace.focus`
  and `pane.swap`, the last of which rearranges a live pane layout. Most came
  from tests with no herdr-I/O intent at all — a backend-record shape check,
  the detection chain walk, a Move-walk re-arm — so stubbing the runner seams
  test-by-test could not have fixed it: the tests that leak are the ones with
  no reason to think about sockets. Making the safe value the default moves the
  guarantee from habit to construction, since a bare `SchemeEngine()` never
  runs `root.scm` and the parameter is the only thing either transport dials.
  The CLI-native backends were left exposed here and closed the same way
  afterwards — ADR-0023 holds that half, where the audit found **419** leaked
  commands and the shape generalised into a single shell seam.
- **Minimal generic native primitive.** One new native library,
  `(modaliser unix-socket)`, exposes
  `(unix-socket-request path line timeout-ms) → response-line | #f` — Swift
  opens AF_UNIX, sends, reads to newline (or times out), closes — plus its
  no-reply sibling `(unix-socket-send path line timeout-ms) → #t | #f`, which
  stops after the send (see **Sent, not called** below). That is the entire new
  native surface; Swift knows nothing of herdr. Everything else — the
  `{"id","method","params"}` envelope, response parsing, `error` logging,
  the per-method wrappers — is Scheme (ADR-0018 spirit: Swift owns OS
  primitives, Scheme owns logic). Three details of that surface are load-bearing
  for callers:
  - **The primitive owns the newline framing, symmetrically** — it appends the
    terminator on send and strips it on receive, so Scheme deals only in bare
    payload lines and framing is decided in exactly one place.
  - **`timeout-ms` bounds the whole round-trip** (connect + send + read) as
    wall-clock, not each syscall — so the eval thread it blocks is bounded by
    the number the caller passed, which is what makes a hot-path call safe.
  - **`#f` is the only failure value, and the reason still gets out.** Every I/O
    outcome — path too long, connect refused, peer gone, timeout, EOF before any
    byte — returns `#f` without raising; the reason goes to os.Logger rather
    than being discarded the way `2>/dev/null` discarded the `agent_not_found`
    error that hid this bug. Malformed *arguments* do raise: those are
    programming errors, not I/O outcomes.
- **`#f` means herdr did not answer — an `error` reply is an answer.** The
  Scheme layer above the primitive keeps that line: unreachable, timed out or
  unparseable → `#f`; a structured `{"error":…}` → the envelope, logged.
  Collapsing the two would conflate "no answer" with "an answer I don't like",
  and the difference is load-bearing for anything reporting herdr's state to
  the user — `worktree.list` answers `not_git_worktree` whenever the focused
  workspace is not inside a git work tree, an ordinary condition that must not
  read as "herdr is not responding". No caller needs a branch for it: they all
  read `(json-ref j "result")`, which an error envelope has not got, and
  `json-ref` is total, so an error degrades to the same empty each caller
  already handles.
- **The transport is its own library, and reads share ONE seam.** The
  transport — socket path, timeout, envelope, `herdr-socket-request` and
  `herdr-socket-send` — lives in `(modaliser muxes herdr-socket)`, not in the
  backend, because the herdr *blocks* need it too and `(modaliser muxes
  herdr)` imports `(modaliser blocks herdr-list)` for its chip-paint
  pipeline; putting it in the backend would close an import cycle. Above it
  sit three choke points: `herdr-query` (reads, in the transport library) and
  `herdr-cmd` / `herdr-cmd-send` (writes, in the backend). `herdr-query` is
  the **single** read seam for the whole tree — the backend's detection, jump
  and ring queries, `blocks/herdr-list`'s five live lists and two
  chip-geometry queries, and `blocks/herdr-jump-legend`'s three name lookups.
  The list block briefly had a parallel seam of its own because it shelled
  out separately; once both spoke `(method params)` to the same socket they
  were the same operation, and two parameters for one operation is
  complecting — so there is one, and one `parameterize` stubs herdr's entire
  read surface. `focus-pane-by-id` becomes `pane.focus {pane_id}`, which
  focuses any pane.
- **Sent, not called: the ops whose reply must not be waited for.** The CLI era
  routed five ops through `run-shell-async` on the belief that herdr's own UI
  prompts for their arguments (ADR-0014). Read against herdr 0.7.5's source,
  that is not what the API does — **no herdr socket method prompts**. herdr's
  branch-name dialog belongs to its TUI key handler, which fills `branch` in
  *before* calling the same method; a `worktree.create` arriving on the socket
  without one makes the server generate a slug. The five therefore divide by a
  different question — *can the reply arrive promptly?* — into two groups:
  - `tab.rename`, `workspace.rename` are **plain synchronous commands**. Their
    handlers mutate in memory, emit an event and answer at once (measured
    sub-millisecond). No async machinery was ever needed for them.
  - `worktree.create`, `worktree.remove` and `server.stop` go out through
    `unix-socket-send`, which never reads a reply. The worktree pair is answered
    only once a `git worktree add`/`remove` subprocess finishes — bounded, but
    proportional to working-tree size and able to fire the user's `post-checkout`
    hook; `server.stop` is acknowledged by a server that is exiting, a race with
    nothing to win. Waiting on any of them would stall the eval thread for the
    full timeout *routinely*, which is exactly ADR-0014's hazard.

  Abandoning the reply does not abandon the op: herdr performs every effect —
  creating the workspace, switching focus, emitting events — before composing a
  response, and discards that response if nobody is listening. What is given up
  is an acknowledgement no caller consumed even when it was available. This is
  what lets these be plain calls rather than CPS: connect+send is
  sub-millisecond, so there is no stall for a callback to hide.
- **`agent.focus` has no caller left.** `pane.focus` is the universal by-id
  focus, and *every* focus target this backend holds is a pane_id — the agents
  axis reads `sidebar.agents[].pane_id` from `ui.layout`, and next-blocked reads
  `agents[].pane_id` from `agent.list`. `agent.focus {target}` addresses an
  agent, a narrower thing that resolves only panes currently hosting one; that
  narrowness *is* the regression. So the fix is not "use `pane.focus` for the
  panes axis and keep `agent.focus` for the agents axis" — it is that
  `agent.focus` leaves the backend entirely.
- **Every mutating call gets a test seam.** `current-herdr-command-runner` and
  `current-herdr-send-runner` join the query runner. Without them the lowest
  assertable altitude was
  `current-herdr-jump-focus-runner`'s `(kind . id)` pairs — precisely the
  altitude at which `agent focus` and `pane.focus` are indistinguishable, which
  is how this bug shipped past a suite that already tested jump dispatch. The
  pinned regression test captures there.
- **The request line is built with `json-write`, not string-appended.** The
  writer is `json-parse`'s mirror in `(modaliser json)`; escaping is therefore
  decided in one place for every param of every method, and the shell-era
  `sq-escape` single-quoting of user-supplied labels and branch names goes away
  rather than being relocated.
- **Socket-only, and herdr leaves ADR-0017 Layer 2.** No CLI fallback, and no
  backend-health table either: herdr's record carries **no `tool-name`**, so
  nothing probes the tool path on its behalf, at install or lazily. Layer 2
  exists to disambiguate a shell-out's empty stdout, which collapses "binary
  missing", "server down" and "nothing to list" into one empty string and
  recovers the difference by re-probing `command -v`. The socket separates
  those itself: a reachable herdr answers truthily whether it has something
  to list (`{"result":{"panes":[]}}`) or an objection to raise (an `error`
  envelope), while unreachable / timeout / unparseable answer `#f`. So the
  query result **is** the reachability verdict, consumed directly by the one
  caller that surfaces it — `blocks/herdr-list` renders an "herdr is not
  responding" row on `#f`, and that row is now true whenever it shows. Keeping the probe would
  answer the wrong question (a present binary says nothing about socket
  reachability) *and* spawn a subprocess on exactly the path this ADR
  de-subprocesses. Layer 2 stays load-bearing for the CLI-native backends.
  A leader press still never raises. The `current-herdr-*-runner` parameters
  remain the test seams.
- **Subscriptions are out of scope here.** herdr pushes `agent_status_changed`
  / layout events over a persistent connection — that needs an event loop and a
  connection model the connect-per-request transport deliberately does not have.
  It grows as its own leaf when ambient agent-status is on the table.

## Consequences

- The pane-switching regression is fixed at the root: `pane.focus` focuses agent
  and non-agent panes alike.
- The jump/live-list hot path drops its per-call `fork`+`exec`.
- **No herdr code path spawns a process at all** — not the backend, not the
  live-list blocks. `run-shell`, `run-shell-async`, the `path-prefix`
  preamble, and the `modaliser-tool-path` and `sq-escape` imports are gone
  from `(modaliser muxes herdr)` *and* `(modaliser blocks herdr-list)`.
  Escaping is `json-write`'s everywhere; the only remaining keystroke
  emission (Detach) never had a socket verb to begin with.
- **ADR-0017 no longer applies to herdr at all** — not its PATH derivation
  (the socket path is an env var, no binary lookup) and not its Layer 2 tool
  health (no `tool-name` to probe). Both stay load-bearing for tmux/zellij
  and the other CLI backends, so neither `modaliser-tool-path` nor the health
  table is removed.
- **ADR-0014's herdr consequences are corrected, not weakened.** Its rule —
  never raise interactive UI from a blocking call — still holds, and holds
  *better*: the remaining CPS sites are Modaliser's own prompt and confirm
  dialog, which is where the interactivity always actually was. What changes is
  the factual claim that herdr prompts for these arguments; it does not.
- herdr diverges from the other muxes (socket vs CLI). This is justified by
  herdr's nature, not adopted for uniformity's sake; the divergence is confined
  to `(modaliser muxes herdr)` behind the unchanged backend-record surface.
- Modaliser couples to herdr's socket protocol version (18) — no worse than the
  CLI, which speaks the same protocol; herdr negotiates it at handoff.
- **The test suite cannot reach a live herdr by any route**, and needs no
  process-wide environment fixture or per-suite trait to stay that way. Tests
  that want the real transport stand up a throwaway `LineResponderSocket` and
  `parameterize` the path at it, as they already did. The cost is that the one
  install line in `root.scm` is itself untested — as `root.scm`'s three sibling
  installs already are — so the transport logs "no socket configured" loudly on
  every refusal rather than degrading silently.
