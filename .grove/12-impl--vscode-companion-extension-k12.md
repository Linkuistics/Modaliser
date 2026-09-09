# vscode-companion-extension-k12

## Goal

Build the peer, and the one Scheme call that reaches it. Two halves of one
vertical slice, and the slice is demoable on its own — *Modaliser can ask the
frontmost VSCode window what is open in it, and get an answer*:

- **The VSCode extension.** A TypeScript extension, one instance per VSCode
  window, holding a Unix-domain socket and serving three methods: `parts` — one
  query, answered — plus `focus-terminal` and `focus-editor`, which are
  **notifications it answers nothing to**. Plus the last-focused pointer file it
  writes, and a script that installs it.
- **The Scheme transport half.** In `(modaliser apps vscode)`:
  `current-vscode-socket-pointer-path`, `current-vscode-query-runner`,
  `current-vscode-notify-runner`, and `(vscode-parts)` — the one round-trip, its
  `focused` gate and its protocol check. Plus the `root.scm` line that installs
  the real pointer path at boot.

**Not the panels.** No row joins, no providers, no blocks, no screen changes.
Those are `vscode-part-panels-k7`, which runs immediately after this leaf and
builds on `(vscode-parts)` as a working call.

## Context

**The design is `docs/specs/vscode-window-parts.md`, ADR-0026 and ADR-0027**,
produced by `vscode-terminal-listing-k10` and then repaired by the review
`vscode-terminal-listing-k13` and its integration `vscode-terminal-listing-k14`,
which is where the peer field, the notification shape, the read budget and the
actionable-tab-kind table below come from. Decisions 1–5 of the spec are this
leaf's whole brief; decisions 6–9 are k7's. Read them as they stand — ADR-0026 was
reworked in place and reversed its previous decision, so anything you remember
about the accessibility tree is the rejected option now.

**Six things the review settled that the extension has to carry**, and each one is
a property that has to be *structural* rather than asserted — that is what the
review kept catching:

- **The reply names the peer.** `parts` carries `peer`, the socket path this
  instance is listening on, and Modaliser binds every row to it. Actions arrive
  addressed to that path, so a peer is never handed a token another window minted
  (spec decision 4, ADR-0027). Without this field, window A's token `3` and window
  B's token `3` are the same address and a press after a focus change activates the
  wrong tab.
- **An action is refused while this window is not focused.** `window.state.focused`
  false at the moment a notification arrives ⇒ do nothing. The check is here
  because only here is it atomic against the window's own state; Modaliser cannot
  make check-and-use atomic from outside.
- **`focus-terminal` / `focus-editor` reply with nothing at all.** No `{"ok": …}`,
  no error envelope — the caller sends and returns (ADR-0014, spec decision 2).
  Log the refusal reason on your own side; that log is the only trace a refused
  press leaves.
- **`workspace` is `null` in a folderless window, and the window still listens.**
  No folder is not a reason to be silent; it is a reason for one field to be null
  (spec decision 3).
- **Only two tab kinds get a token.** `TabInputText` via `showTextDocument` and
  `TabInputNotebook` via `openNotebookDocument` + `showNotebookDocument`; webview,
  custom-editor and both diff kinds are listed with `token: null`. `TabGroups` has
  **no** reveal-this-`Tab` call, so "carries a URI" is not the test — a specified,
  identity-preserving activation operation is (spec decision 1's table).
- **Both activations read `viewColumn` and `isPreview` off the *live* `Tab` at act
  time, never off the snapshot.** `ViewColumn` is an ordinal position: reorder or
  close a group and a recorded column now names a different group — same file in two
  groups then activates the other row's tab, and a column that no longer exists
  makes `showTextDocument` *create* one. `Tab.group` is a live reference, so this
  costs a property read. `preview: LIVE.isPreview` for the same reason: a hard
  `false` pins a preview tab, which the "already active row changes nothing"
  requirement forbids.
- **Both focus methods check membership before acting** — `window.tabGroups.all`
  for a tab, `window.terminals` for a terminal. The token map is pruned only when
  `parts` is called, so between a read and a press a closed part is still mapped;
  `Terminal.show()` on a disposed terminal is unspecified behaviour and not
  something to rest the "closed part activates nothing" requirement on.
- **The map's entries carry their kind, and each method checks it.** One counter and
  one map means a terminal token handed to `focus-editor` *does* resolve — the
  refusal is the kind check, not a failed lookup. Implemented literally as "one
  lookup" it would hand a `Terminal` to `showTextDocument`.
- **The pointer is written at activation too, not only from the event.**
  `onDidChangeWindowState` fires on *change*, so a window already focused when
  `onStartupFinished` runs never writes one — which is the ordinary single-window
  case, every host restart, and every fresh install, and its symptom is two empty
  panels until the human clicks away and back. Write it when `window.state.focused`
  is true at activation, and guard the handler on a focus *gain* (the same event
  fires for the `active` inactivity flag).
- **The socket directory is created mode 0700**, and it holds the sockets and the
  pointer file. That is now in the durable design (ADR-0026), not only in this
  brief.
- **A socket name is never reused**, because a target is a socket path plus a
  token: a path back in service under a new instance is an address that outlived
  what it addressed, and the new instance's counter starts where the old one's did.
  So no unlink-before-bind on a stable name — instead sweep, on activation, the
  sockets in the directory whose **connect is refused**. Refused, not
  "unanswered": a wedged host is still listening and its rows are still valid
  (spec decision 3).

**Why this exists at all, in one line.** VSCode's extension API carries what is
open inside a window — `window.terminals`, `window.tabGroups` — and nothing
reachable from outside VSCode does. Reading a *rendering* of that state through
the accessibility tree was designed, reviewed, and rejected on what the
rendering costs (ADR-0026, considered options).

**The transport is not new and should not be reinvented.** ADR-0020 built it for
herdr: newline-delimited JSON, one `{"id","method","params"}` request per
connection, the peer closing after it responds, `unix-socket-request` owning the
framing in both directions. `(modaliser muxes herdr-socket)` is the worked
model for the Scheme side and is worth reading before writing a line of it —
particularly its parameter-defaults-to-`#f` discipline, which is what keeps
`swift test` structurally unable to dial a live editor (ADR-0023). Copy that
shape; do not invent a second one.

**Three things the spec settles that are easy to get subtly wrong:**

- **Tokens come from one never-reset counter, shared by terminals and editors**
  (decision 4). Two counters would let one integer be live in both maps, so a
  terminal token handed to `focus-editor` would resolve — to the wrong thing.
  One counter makes cross-kind refusal the same code path as stale-token
  refusal, and that is the property the test has to pin.
- **A tab of a kind with no specified activation is listed with `token: null`**
  (decision 1), not omitted. It is a real open editor; omitting it would make the
  panel disagree with the tab strip the human is looking at, and `jump-list`
  already has the contract for an inert row.
- **A tab whose input is a `TabInputTerminal` is excluded from `editors`**
  (decision 1). A terminal dragged into the editor grid is in `window.terminals`
  *and* in `tabGroups`; listed naively it takes two rows and two labels for one
  thing.

**Two facts about the host, both load-bearing.** `extensionKind: ["ui"]`, or a
window connected to SSH/a container/WSL runs the extension on the remote and its
socket is on the wrong machine. `onStartupFinished` activation, or the socket
does not exist until something activates the extension — and nothing will,
because the only thing that would is a request arriving on the socket.

**The `focused` gate rests on the overlay being non-activating**
(`ui/overlay.scm:1053`, `'activating #f`) — VSCode keeps window focus through
the whole modal, so `window.state.focused` stays true at come-to-rest. Spec
decision 3 says why, and why a chooser-rendered panel would break it. You are
not building the panel, but you are building the gate, so the reason it holds
is yours to preserve.

**Pointers**

- `Sources/Modaliser/UnixSocketLibrary.swift` — the primitive, and its contract
  (`#f` on every I/O outcome, raises only on malformed arguments).
- `Sources/Modaliser/Scheme/lib/modaliser/muxes/herdr-socket.sld` — the shape to
  follow: envelope, query-runner seam, host-installed path, instrument spans
  split into wire time and parse time.
- `/Applications/Visual Studio Code.app/Contents/Resources/app/out/vscode-dts/vscode.d.ts`
  — the API surface, shipped inside the application. This repo's standard is to
  read it rather than documentation about it.
- `docs/reference/libraries.md` — where the new Scheme surface gets documented
  beside its peers.

## Done when

- The extension serves all three methods against a real VSCode window, with the
  terminal panel **hidden** and with a single terminal open — the two cases that
  killed the accessibility design and that this source is chosen to survive.
- Tokens are allocated from one never-reset per-window counter, and there is a
  test that `focus-editor` refuses a terminal's token and `focus-terminal`
  refuses an editor's — the test for decision 4's disjointness claim, without
  which the claim is only an assertion.
- `parts` carries `peer`, and there is a test that a notification arriving while
  `window.state.focused` is false is refused — the only test of the read→act gap
  the peer owns.
- The extension's fixtures pin the three properties no Swift test can see: the
  kind check refuses a cross-kind token, the membership check refuses a closed
  part, and an activation's `viewColumn` comes from the live tab (build the fake so
  that a snapshot-derived column would fail it — that is the whole point of the
  test).
- **Verified by hand against a real window, because a fake cannot:** the same file
  open in two editor groups, groups reordered, each row still activating its own
  tab; and a preview tab that is already active staying a preview tab.
- The pointer file exists after a fresh install with **one** window open and no
  window switching — the case an event-only subscription silently misses.
- The two focus methods put nothing on the wire in reply, and `(vscode-parts)`
  reads on a 200 ms timeout (spec decision 2) rather than herdr's 1000 ms.
- A window opened with **no folder** answers `parts` with `workspace: null` and its
  real editors and terminals — not an empty listing.
- The pointer file is written atomically when a window takes focus; the extension
  binds a name no instance reuses, sweeps connect-refused sockets on activation,
  and unlinks its own on `deactivate`.
- `(vscode-parts)` returns a parsed reply against the human's live VSCode, and
  `#f` — never a raise — for an unreachable peer, a protocol mismatch, and a
  reply whose `focused` is false.
- `current-vscode-socket-pointer-path` defaults to `#f` and `root.scm` installs
  the real path at boot, exactly as it does for herdr's socket.
- The extension's own tests run in its own project against fakes of the two API
  surfaces; **nothing in the Swift suite reaches it**.
- `swift build` and `swift test` green; `./scripts/check-portable-surface.sh`
  and `./scripts/check-decision-free.sh` both pass.
- There is a documented way to install the extension — its own script, not a
  step inside `install.sh` (spec, **Out of scope**) — and `docs/` says how.
- The new Scheme surface is documented in `docs/reference/libraries.md` beside
  its peers.

## Notes

- **This is the repo's first TypeScript.** Where the project lives, how it is
  built, and whether the `.vsix` is committed are open and are yours to settle —
  the spec deliberately does not, because they are packaging decisions best made
  with the tooling in front of you. Whatever you choose, note that
  `build-app.sh`'s exact-mirror invariant (ADR-0019) covers `Scheme/` only and
  does not cover this, so nothing will fail the build if the extension goes
  stale. If that worries you, say so rather than quietly adding a check.
- **Measure the round-trip while you are here, and commit the instrument.**
  `(modaliser instrument)`'s spans are what the herdr transport already uses,
  split into wire time and parse time. k6's cost conclusion had to be withdrawn
  because its instrument was a standalone binary that was never committed and
  could not be re-run (spec decision 9) — do not repeat that. herdr's comparable
  wire time is 0.1–0.6 ms; that is the order to expect and not a result.
- **Verify against a real VSCode, not against a successful import.** Install
  (`./scripts/install.sh`), confirm `config: loaded` in `/usr/bin/log show
  --predicate 'subsystem == "dev.antony.Modaliser"'`, then exercise it. A shell
  alias shadows `log` — use `/usr/bin/log`.
- A wedged first launch is a known hazard here and is not your bug: a freshly
  signed bundle can hang pre-`dyld` awaiting Gatekeeper's scan, and
  LaunchServices then routes every later "open" to the stuck process as a reopen
  event that times out. The tell is ~32 KB RSS at 0% CPU.
  `pkill -f "/Applications/Modaliser.app/Contents/MacOS"` and relaunch.
- **A socket is a security surface.** The method set is three methods and must
  stay three; a `commands.executeCommand` passthrough is one line and would turn
  it into a remote control for the workbench (spec decision 2). The socket
  directory is mode 0700 — ADR-0026 enumerates exactly what the surface exposes and
  accepts, so if the building makes that list wrong, the ADR is what has to change.
