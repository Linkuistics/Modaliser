# A VSCode window is found through a pointer file and acted on through the peer that answered

## Context

The VSCode companion extension (ADR-0026) is **per-window**: `window.terminals`
is that window's terminals, `window.tabGroups` is that window's tabs, and every
open window runs its own instance holding its own socket. So the source having
been chosen leaves two questions the source itself does not answer.

**Which peer does a read go to?** Modaliser wants the window in front of the
human, and it has no list of sockets: the portable Scheme tree has no directory
listing at all — R7RS file ports are the whole file surface — so it cannot even
enumerate what is there.

**And which peer does the *press* go to?** A listing is read at one moment and
acted on at another, with a modal in between. Each extension instance allocates
tokens from its own counter starting at the same place, so the integer `3` is live
in as many windows as are open. A target carrying only that integer is not an
address, and the failure that follows is the one this whole area exists to
exclude: the row says `beta.txt` in this window and the press activates something
else in another.

## Decision

**Reads are addressed through a last-focused pointer file. Actions are addressed
through the peer that answered the read.**

- **The pointer file.** Each window's extension writes its own socket path into one
  well-known file when its window takes focus, atomically replacing the contents.
  Modaliser reads that one file with the `read-file-text` it already has and dials
  what it names. The pointer is consulted to *start* a read and never consulted
  again.

- **Every reply names its own peer, and every target carries it.** The `parts`
  reply includes the socket path the answering instance is listening on; the rows
  built from that reply carry it beside their tokens; and a `focus-terminal` /
  `focus-editor` / `close-editor-if-missing` notification goes to that path. The read and the act therefore
  name the same peer *because the act's address came out of the read* — not because
  they agreed to read the same pointer twice.

- **A socket path is never reused.** Because a target *is* a socket path plus a
  token, a path returning to service under a new extension instance would be an
  address that outlived what it addressed — and the new instance's counter starts
  where the old one's did, so an old row's token would resolve there to a different
  part. An extension-host restart is an ordinary event and the window keeps focus
  across it, so every other guard passes while the wrong part is activated; unique
  names make a stale target's message arrive nowhere instead. Unique means
  *cannot recur*, not *unlikely to*. The cost is that crashed hosts leave socket
  files behind, swept by the extension at activation on the only test that
  distinguishes dead from busy — a **refused** connect, which is the kernel's
  answer for a bound path with no listener. Not "did not reply": a wedged host is
  still listening and its own rows are still valid, so a probe that waited for an
  answer would delete a live peer's socket and reintroduce the hijack from the
  other side.

- **The peer refuses an action while its window is not focused.** Peer-bound
  addressing closes the wrong-window hole but not the passage of time: the human
  may have moved to another window between the read and the press, and acting in
  the window they left is wrong even though it is the window the row came from.
  That check belongs to the peer, because the peer is the only party that can read
  the window's focus at all — but it **narrows the race rather than closing it**:
  the host reads a replica of `window.state`, the socket read is a callback on a
  shared event loop, and the activation itself is asynchronous. The systematic
  case — a modal held open across a deliberate window switch — is eliminated; the
  residue is a focus steal on a sub-tenth-of-a-second race the human causes with
  their own keypress, and it is accepted visibly rather than described as
  impossible. Modaliser separately discards a *reply*
  whose `focused` is false, so a stale pointer yields an empty listing rather than
  a neighbouring project's rows.

## Considered options

- **A socket path derived from the workspace folder.** Needs the same function
  computed on both sides — TypeScript and portable Scheme. The one hash the
  portable tree re-exports is SRFI 69's `string-hash`: a hashtable hash,
  implementation-defined and pinned by nothing, so no TypeScript peer could
  reproduce it and a LispKit upgrade could silently rename every socket. Sanitising
  the path instead of hashing it then runs into macOS's 104-byte `sun_path` limit
  on a deep worktree path. It would also address the wrong thing — the human wants
  the focused window, not a named folder — and folderless windows have no key at
  all. **Reopen if** a cross-window listing is ever wanted, where naming a window
  other than the focused one is exactly what is missing.

- **Scanning the socket directory.** Needs a directory listing, which the portable
  tree does not have; adding one is new native surface bought to replace a file
  read that already works. It also does not answer the question — several sockets
  answer, and picking among them means asking each which is focused.

- **Re-reading the pointer at action time** (the shape this record replaces).
  Every action re-resolves "the focused window" and sends the token there. It is
  one line shorter and it is wrong: two windows' counters both hand out `3`, so a
  pointer that moved between the read and the press delivers window A's token to
  window B, where it resolves — to a different tab. Nothing detects it, because
  both sides are behaving exactly as specified.

- **A globally unique token** — a UUID, or a counter seeded per process. Makes the
  cross-window collision improbable rather than impossible, and improbability is
  not the property wanted; more to the point it repairs the *symptom*. The defect
  in a bare token is that it is not an address, and a longer integer is still not
  an address.

- **Acting through a path or an index instead of a token.** Repairs the failure
  mode rather than the addressing: a stale row would reopen the file it names
  instead of jumping to the wrong one. Rejected in ADR-0026 on cost — `code`
  against a running instance was measured at ~1.1 s — and it cannot express
  "this terminal" at all.

## Consequences

- **A refusal is silent.** An action carries no reply (ADR-0026), so a press
  refused for a stale token, the wrong kind, or a window that has lost focus is
  indistinguishable from one that worked, from Modaliser's side. The requirement is
  that a label activates its own part *or nothing*; both halves hold without a
  reply, and the extension logs its reason on its own side.

- **The pointer file is one small piece of shared mutable state**, written by
  whichever window last took focus and outliving the process that wrote it. Every
  way that can go wrong — a window that closed, a crashed host, a file naming a
  socket nothing is listening on, a file that was never written — ends at
  `unix-socket-request` returning `#f`, which is an empty listing. It lives in the
  0700 socket directory, so it is not another user's to read or forge.

- **Modaliser now knows a peer's address without a directory listing**, which is
  what makes a cross-window listing reachable later: what the pointer file cannot
  do is *name* a window other than the focused one, and that is the only missing
  piece.

## See also

- ADR-0026 — why the source is a companion extension at all, and the exposure its
  bounded method set accepts.
- ADR-0020 — the socket transport, and `unix-socket-request`'s never-raising
  contract.
- ADR-0025 — why the portable tree never scans a string by index, which is the
  further cost a path-sanitising socket name would have run into.
- `docs/specs/vscode-window-parts.md` — how the area works: the protocol, the
  Scheme surface, and the test seams that pin the peer binding.
