# vscode-window-parts

## Problem

The F17 VSCode screen carries a **Project listing** — every open VSCode window
as a labelled row — and the human wants the same affordance one level in: the
**editors** open in the frontmost window, and the **terminals** running in it,
each reachable by a jump label from its own alphabet.

The Project listing had its row source to hand: the window enumeration lists
windows, and a **Project** falls out of a window title. Nothing Modaliser can
reach from outside lists what is open *inside* a window. VSCode ships no
scripting dictionary, and the IPC socket its own CLI uses is private and
unversioned, so the source had to be found before either panel could be built.

Separately, a state has **one** `'provider` slot, and the screen is about to
want more than one labelled panel on it. Two providers appending their edge
sets is mechanically fine and silently wrong when it is not, because nothing in
the engine checks.

## Solution

**Both listings come from a companion VSCode extension that Modaliser talks to
over a Unix-domain socket.**

Everything Modaliser wants to know is in VSCode's extension API and nowhere
else it can reach: `window.terminals` gives every terminal with its name whether
or not the panel is shown, and `window.tabGroups` gives every editor tab with
its label, its real URI and its group. So Modaliser stops trying to read VSCode
from outside and instead runs a small peer *inside* it, answering a bounded set
of questions over the transport ADR-0020 already built for herdr.

The **Editor listing** is the editor tabs of the frontmost VSCode window as
overlay rows, in on-screen order. The **Terminal listing** is that window's
terminals, in VSCode's own order. Each row carries a **Jump label**; pressing
one hands **back to the peer that drew the row** a **token** that peer minted,
so the row and what it does come from one snapshot and cannot disagree — the
contract the Project listing and the **Strip listing** already hold. Both halves
of that are load-bearing: the token says *which part*, and the peer says *which
window*, and a target that carried only the token would be an integer several
windows answer to.

ADR-0026 records why this source and not the accessibility tree, the stored
editor state, or numbered slots — and what would reopen each.

A screen carrying more than one labelled panel composes its providers through a
new merge in `(modaliser jump-list)` that **raises** on a collision the engine
would otherwise resolve first-wins.

## Decisions

### 1. The row source is a companion extension, and it reads the model

The extension is the source for **both** listings. It is not a fallback, a
supplement, or a second opinion: the accessibility tree is not read for either
panel, and neither of the two accessibility procedures an earlier draft of this
spec specified is built.

What that buys is one property with many consequences: **the extension reads
VSCode's model, where the earlier design read a rendering of it.** Concretely,
none of the following is part of this design, and every one of them was part of
the accessibility design:

- pinning `workbench.editor.showTabs`, `editor.accessibilitySupport`, or
  `terminal.integrated.tabs.hideCondition`, purely so that the thing to be read
  gets drawn;
- showing the terminal panel before the terminals can be listed — and therefore
  the whole two-step-op-versus-engine-ordering question, which does not arise
  when nothing has to be drawn;
- anchoring on the *absence* of an aria-label, and the empty listing that
  follows a future VSCode labelling the strip;
- choosing between two accessibility attributes whose contents swap at runtime;
- answering nothing while a modal is up;
- treating editor *group* identity as out of reach.

**What the reply carries, and where each field comes from.** All from the
shipped `vscode.d.ts` (VSCode 1.136.2), not from documentation:

| field | source |
|---|---|
| a terminal's name | `Terminal.name` |
| a terminal's cwd | `Terminal.shellIntegration?.cwd?.fsPath` — `null` when shell integration is absent *or* has reported no cwd, which are two distinct optionals and one `null` |
| a terminal's active flag | identity against `window.activeTerminal`. Read its declaration before trusting the name: it is the terminal that has focus **or most recently had focus**, so it is non-`undefined` even with the panel hidden, and it is *not* the same predicate as `Tab.isActive`. A renderer may show it; nothing in the design depends on it |
| an editor's label | `Tab.label` |
| an editor's path | `Tab.input.uri.fsPath` for the input kinds that carry a single `uri`, else `null` — the diff kinds carry `original` and `modified` and **no** `uri` at all (decision 1's table) |
| an editor's active flag | `Tab.isActive` |
| an editor's dirty flag | `Tab.isDirty` |
| an editor's group | `Tab.group.viewColumn` |
| the window's focus | `window.state.focused` |
| the window's workspace | `workspace.workspaceFolders[0].uri.fsPath`, `null` in a window with no folder open |
| the peer's own identity | the socket path this extension instance is listening on |

**A terminal moved into the editor area is a terminal, not an editor.** VSCode
lets a terminal be dragged into the editor grid, where it appears both in
`window.terminals` and as a tab whose `input` is a `TabInputTerminal`. Listed
naively it would take two rows and two jump labels for one thing. So a tab whose
input is a `TabInputTerminal` is **excluded from the editor listing**; it is
already in the terminal listing, where the action works.

**A tab that cannot be focused is listed without a token.** Such a tab is a real
open editor and is shown, but it gets `token: null` and no action. That is
`jump-list`'s own existing test for whether a row earns an edge: the row still
renders and still consumes its label, so an unfocusable tab cannot renumber the
labels below it. Listing it and refusing to act is honest; omitting it would make
the panel disagree with the tab strip the user is looking at.

**Which tabs those are is decided per input kind, and the decision is the
activation operation — not the presence of a URI.** `TabGroups` offers `close`
and nothing else: there is no reveal-this-`Tab` call, so activating a tab means
naming a *per-kind* API operation, and a kind with no operation that reaches the
tab it was pressed on cannot honour the SHALL that a label activates its own part
or nothing. So a token is minted only for the kinds whose activation is both specified and
identity-preserving:

| input kind | `path` | `token` | activation |
|---|---|---|---|
| `TabInputText` | `uri.fsPath` | yes | `window.showTextDocument(uri, {viewColumn: LIVE.group.viewColumn, preview: LIVE.isPreview})` |
| `TabInputNotebook` | `uri.fsPath` | yes | `workspace.openNotebookDocument(uri)` then `window.showNotebookDocument(doc, {viewColumn: LIVE.group.viewColumn})` |
| `TabInputCustom` | `uri.fsPath` | yes | `commands.executeCommand("vscode.openWith", uri, LIVE.input.viewType, {viewColumn: LIVE.group.viewColumn, preview: LIVE.isPreview})` |
| `TabInputWebview` | `null` | no | no resource of any kind to name |
| `TabInputTextDiff`, `TabInputNotebookDiff` | `null` | no | two URIs and no single one; reopening would need `vscode.diff`, which constructs a new comparison rather than revealing this tab |
| `TabInputTerminal` | — | — | not an editor row at all (below) |
| an input kind this extension does not know | `null` | no | unknown by construction |

**`LIVE` is the `Tab` object the token resolved to, read at activation time, and
that word is doing all the work.** Both operations reveal a *resource in a column*
rather than a tab, so the column has to identify the pressed tab at the moment the
call is made — and `ViewColumn` is an **ordinal position**, not a group's identity:
closing a group, adding one to the left, or moving a group renumbers the columns
under a snapshot that has already been taken. A recorded column is therefore a
coordinate that goes stale in a way that fails *invisibly*: with the same file open
in two groups, the pressed row's column can now hold the other group — activating
the other row's tab — and with the recorded column gone entirely,
`showTextDocument` creates the column and a new editor in it, activating a part
that did not exist when the rows were drawn. Reading `LIVE.group.viewColumn`
through the resolved `Tab` costs nothing and closes both: `Tab.group` is a live
reference, and one URI cannot be open twice in one group, so *(resource, current
group)* names exactly the pressed tab.

`LIVE.isPreview` is the same discipline applied to a smaller thing. A hard
`preview: false` would *pin* a preview tab, so pressing the label of a row that is
already active would change the workbench — which the requirements say it must
not. Passing the tab's own current state activates without editing it.

**A custom editor was ruled out here and is now in, and the build is what
changed it.** This table read `TabInputCustom` → no token for two revisions, on
the reading that `vscode.openWith` *opens by resource and view type* rather than
revealing the pressed tab. Both halves of that turned out to be wrong on
contact:

- **The reopen condition was already met, and unmissably.** It was written as
  "if a custom editor is ever something the human keeps on screen and wants a
  label for". The human's own `settings.json` carries
  `"workbench.editorAssociations": {"*.md": "vscode.markdown.preview.editor"}`,
  so **every markdown file is a `TabInputCustom`** — including every grove task
  file, which is the case the Editor listing most exists to reach. Built to the
  old table, the panel's headline case was a panel of inert rows; that is how
  this was found, on the first `parts` reply off a real window.
- **The objection does not survive the shipped registration.**
  `vscode.openWith(resource, viewId, columnOrOptions)` takes the same
  `TextDocumentShowOptions` object `showTextDocument` does — read out of
  `extensionHostProcess.js` (1.136.2), not from documentation. So it is
  identity-preserving by *exactly* the argument that admitted text tabs: one
  `(resource, viewType)` pair cannot be open twice in one group, so *(resource,
  viewType, current group)* names the pressed tab, and `LIVE.isPreview` rides
  along the same way. The `LIVE` discipline below therefore applies to all
  three actionable kinds, unchanged.

It is also the "bounded internal call to one named command per kind" this
paragraph contemplated rather than the prohibited generic passthrough — and the
extension keeps that structural rather than promised: the seam its activation
code calls is `openWith(uri, viewType, options)`, not `executeCommand(id,
…args)`, so there is no shape a command id could be routed through. The wire's
method set is still three methods; ADR-0026's enumeration of the exposure is
unchanged except that "activate a tab" now reaches one more kind of tab.

**Reopen if** a *diff* is ever something the human keeps on screen and wants a
label for — that one is still out, and for the reason that has not changed:
`vscode.diff` constructs a new comparison rather than revealing this tab.

### 2. The wire protocol: one query, two notifications, and no command passthrough

Newline-delimited JSON over a Unix-domain stream socket, one message per
connection — the peer closing after it responds, or after it reads a message that
expects no response — the model ADR-0020 established and `unix-socket-request` /
`unix-socket-send` already implement, framing included.

The envelope is herdr's, because Modaliser's JSON handling is already shaped for
it: a request is `{"id": N, "method": STRING, "params": OBJECT}` and a reply is
`{"id": N, "result": …}` or `{"id": N, "error": {"message": STRING}}`.

**`parts`** — params `{}` — returns the whole window in one reply, whose `result`
is:

```json
{ "protocol": 1,
  "focused": true,
  "peer": "/Users/…/…/vscode-3f9c.sock",
  "workspace": "/Users/…/Modaliser",
  "terminals": [ {"token": 12, "name": "zsh", "cwd": "/Users/…", "active": true} ],
  "editors":   [ {"token": 13, "label": "fsm.sld", "path": "/Users/…/fsm.sld",
                  "active": true, "dirty": false, "group": 1} ] }
```

`peer` is the socket path this extension instance is listening on, and it is what
binds every row of this reply to the window that minted it (decision 4).
`workspace` is `null` in a window with no folder open; every other field is
present in every reply.

`terminals` is in `window.terminals` order. `editors` is `window.tabGroups.all`'s
order, and within each group its own `tabs` order.

**That is a stable order, and it is only *approximately* the on-screen one — say
so rather than promising more.** Within a group, `tabs` is the strip the human is
looking at, and that is the half that matters for learnability. Across groups,
`tabGroups.all` carries no documented ordering guarantee at all, and for a grid
layout there is no left-to-right sequence for it to have: a 2×2 arrangement has no
honest linearisation. So the requirement's "on-screen order" is exact within a
group and is the API's own group order between them; a reader who needs to know
which group a row is in has `group` on the row (see **Out of scope**). **Reopen if**
the human ever works in a grid and the ordering reads as arbitrary — the fix is a
renderer that groups visibly, not a re-sort of a sequence the API does not
describe.

**`focus-terminal`** and **`focus-editor`** — params `{"token": N}` — are
**notifications: they are sent, not asked, and the peer answers nothing.**
Modaliser puts the line on the socket with `unix-socket-send` and returns
immediately. That is ADR-0014's rule rather than a preference: no caller consumes
an acknowledgement — the FSM tears the modal down *before* it invokes a Terminal
state's action — so waiting for one would spend the eval thread's time, and the
tap's, on a value that is discarded.

Each notification is delivered to the peer named by the target's own `peer` path,
never to whatever the pointer file currently says (decision 4). The peer decides,
and it refuses three ways, all silently:

- **its window is not the focused one** — `window.state.focused` is false when the
  notification is handled, so a peer switch between the read and the press focuses
  nothing rather than acting in a window the human has left. This narrows the
  window in which acting is wrong; it does not close it (decision 4);
- **the token is not in its map**, or is in it but names an object the window no
  longer holds — a closed tab or terminal;
- **the token names the other kind** — the map's entries carry their kind, and the
  method checks it, so this is one lookup and the same code path as a stale token
  (decision 4).

**Both methods verify membership, and for the same reason.** `focus-editor`
resolves the token to a `Tab` and checks it is still present in
`window.tabGroups.all`; `focus-terminal` resolves the token to a `Terminal` and
checks it is still present in `window.terminals`, then calls `Terminal.show(false)`.
The check cannot be skipped on either side, because the map is pruned only when
`parts` is called (decision 4) and a press arrives with no `parts` in between — so
between the read and the press a closed part's token is still mapped, and "not in
the map" is not yet the same thing as "gone". The shipped API promises nothing
about `show()` on a disposed terminal, so resting on it would be resting on
unspecified behaviour rather than on a contract. `focus-editor` then runs the
resolved tab's kind-specific activation from decision 1's table.

**Refusal is silent by construction, and that is the cost of the shape.** Nothing
comes back, so a refused press is indistinguishable to Modaliser from a delivered
one; the extension logs its reason on its own side. This is the same bargain
`jump-list`'s inert rows already make — the requirement is that a label activates
its own part *or nothing*, and both halves of that are satisfied without a reply.

**There is deliberately no method that runs a workbench command**, and what the
bounded set does expose — every field of the reply above, plus the ability to
focus a terminal or activate a tab in the focused window — is enumerated and
accepted in ADR-0026. The spec's normative share of it: three methods, this exact
set, and the directory holding the sockets and the pointer file is created mode
`0700`.

**The reply carries a protocol version and Modaliser checks it.** Modaliser and
the extension are installed separately and can skew. A `protocol` that is not
the version this Modaliser understands is treated as an unreachable peer: empty
listing, log line, no attempt to interpret fields whose meaning is not agreed.

**The read has a per-request timeout of 200 ms, and the budget that matters is the
whole come-to-rest.** Only `parts` waits, so a screen's exposure is
`panels × 200 ms` — 400 ms for the two panels here — and that total, not the
per-request number, is what has to stay inside the keyboard tap's tolerance
(ADR-0014's stalled-tap failure mode, and the reason the herdr transport chose a
number at all). herdr's own 1000 ms is the right ceiling for a peer Modaliser
launched and can be sure of; it is the wrong one here, because two of them in a
row is two seconds of a blocked eval thread and because this peer's event loop is
shared with every other extension in the window (decision 9). 200 ms is ~300×
herdr's measured wire time, so a healthy peer never notices it, and a wedged one
costs a bounded fraction of a press.

**A screen that grows a third panel re-opens the total, not the per-request
number.** The `parts` reply already carries both listings, so the answer at that
point is one shared read rather than a shorter timeout — see decision 5 for why
that memo is not built yet and what it would take.

### 3. Reaching the right window: a last-focused pointer file

The extension host is **per-window**, and `window.terminals` is that window's
terminals — so Modaliser has several peers and must pick one.

**Each window's extension writes its own socket path into one well-known file
when its window takes focus.** The extension subscribes to
`window.onDidChangeWindowState` and, on becoming focused, atomically replaces
the contents of `<socket-dir>/focused` with its own socket path. Modaliser reads
that one file with the `read-file-text` it already has (`util.sld:95`), and
dials what it names.

**And it writes the pointer at activation if its window is already focused,
because the event fires on *change*.** `onDidChangeWindowState` is declared to fire
when the state changes; a window that is focused when `onStartupFinished` runs has
nothing to change, so a design that only subscribes never writes a pointer for it.
That is not an edge case — it is the ordinary case for a single window, for every
window after an extension-host restart, and for the first run after installing the
extension, and its symptom is both panels empty until the human clicks away and
back, with no error anywhere. So: write on activation when `window.state.focused`
is true, and write from the handler **only on a focus gain**. The guard matters
because the same event also fires for `active` — the recent-interaction flag — and
an unguarded handler would let an unfocused window claim the pointer.

The socket path itself is the peer's own business — a name unique per extension
instance, short enough for macOS's 104-byte `sun_path` limit — because nothing on
Modaliser's side ever has to *derive* it. ADR-0027 records why the two
better-sounding schemes (a path computed from the workspace folder, a scan of the
socket directory) were both rejected, and on what constraint.

**Per-*instance*, not per-window, and that is load-bearing rather than
incidental.** A target carries a socket path (decision 4), so a path that came back
into service under a *new* instance would be an address that outlived the thing it
addressed: a row drawn before a window reloaded would reach the reloaded window,
whose own counter starts again from the same place, and the token would resolve —
to a different tab. An extension host restart is an ordinary event — an extension
update, *Restart Extension Host*, a crash and auto-restart — and the window keeps
focus throughout, so every other guard in this design passes while the wrong tab is
activated. A name no instance ever reuses makes a stale target's notification
arrive nowhere instead, which is the outcome the requirements ask for.

**"Unique" here means cannot-recur, not unlikely-to-recur.** A short random suffix
is a birthday problem, not a guarantee, and this is a property the whole read→act
contract rests on: include something monotonic that a restart cannot repeat, and do
not bind a name that already exists. Note what this rules out — the tidy
unlink-a-stale-path-then-bind idiom, which under recurring names is either dead
code or a *hijack*: a second instance unlinks a live peer's socket, the first keeps
listening on an unlinked inode where nothing can reach it, and the path now resolves
to a different token space.

**Every window listens, whether or not it has a folder open.** The pointer file
carries a socket path and nothing workspace-derived, so a folderless window is an
ordinary peer: it writes the pointer when it takes focus, answers `parts` with
`workspace: null`, and lists its editors and terminals like any other. Only path
*rendering* degrades (decision 6). The requirements say every editor tab and every
terminal of the frontmost window, unqualified, and this is what makes that
true rather than nearly true.

**The pointer file is consulted to start a read and is never consulted again.**
Modaliser dials it for `parts`; every action goes to the `peer` path the reply
itself carried (decision 4). A pointer that moves between the read and the press
therefore cannot redirect an action — the failure it *could* cause is the one thing
this whole area exists to exclude.

**Modaliser discards a reply whose `focused` is false.** That is the "row and
action come from one snapshot and cannot disagree" contract applied to *window*
identity: a stale pointer — a window that closed, a race — yields an empty
listing rather than a neighbouring project's terminals.

**What the gate therefore requires is that VSCode is the frontmost application,
and that is a property the screen already has rather than a restriction this
adds.** `window.state.focused` is false in *every* VSCode window while another
application is frontmost, so neither listing answers and no action is accepted from
outside VSCode. The F17 screen these panels live on dispatches on the frontmost
app, so it is only reachable while VSCode is frontmost in the first place; the
overlay preserves that focus (below) but could never manufacture focus VSCode did
not have. The consequence worth naming is the one already on the grove's horizon
list: reaching a VSCode terminal from *another* app is two steps, and closing that
would need a row on the global screen rather than anything here.

**The gate rests on a structural fact, and the fact is named here so it is not
rediscovered.** The overlay panel is created **non-activating**
(`ui/overlay.scm:1053`, `'activating #f`), so VSCode keeps window focus for the
whole modal and `state.focused` stays true at every come-to-rest. The chooser
panel *does* activate (`ui/chooser.scm:321`). A screen that rendered these rows
through the chooser instead of the overlay would take focus from VSCode and the
gate would reject every reply — an empty panel, with nothing in the protocol to
explain it.

**The extension must run on the UI side.** It declares `extensionKind: ["ui"]`,
so a window connected to an SSH host, a container or WSL runs it locally rather
than on the remote, where its socket would be on the wrong machine. It activates
on `onStartupFinished`, so the socket exists from window start rather than
waiting for a first request that has nothing to arrive on.

**Lifecycle.** The extension unlinks its own socket on `deactivate`. A host that
crashed leaves a socket file behind that refuses connections, which
`unix-socket-request` reports as `#f` — the same empty listing as every other
miss — and because names are never reused, the tidy-up is a **sweep** rather than
an unlink-before-bind: on activation the extension removes each socket in its
directory whose **connect is refused**, which is the kernel's own answer for a
bound path with no listener behind it. Refused, specifically — not "did not reply",
because a wedged extension host still has a listening socket and its own window's
rows are still valid; a liveness probe that waited for an answer would delete a
peer that is merely busy. The sweep is the extension's because it needs a directory
listing, which Node has and the portable tree does not.

### 4. Identity across the read→act gap is a peer plus a never-recycled token

**A target's identity is the pair `(peer, token)`, never the token alone.** The
counter is per-window and every window has its own, so the integer `3` is live in
as many windows as are open; a target carrying only the integer is not an address.
So the `parts` reply carries the peer's socket path, every **Terminal target** and
**Editor target** built from that reply carries it, and the notification a label
sends goes to *that* socket. A row can therefore only ever reach the window that
drew it, whatever the pointer file has done in between — the read and the act name
the same peer because the act's address came out of the read.

The remaining gap is not addressing but time: the human may have moved to another
VSCode window between the read and the press, and focusing a tab in the window
they left is wrong even though it is the window the row came from. That check is
the **peer's**, because the peer is the only party that can read the window's own
focus state at all — the notification is refused when `window.state.focused` is
false (decision 2).

**The check narrows the race; it does not close it, and the design says so rather
than claiming atomicity it does not have.** Three gaps survive, none of them
Modaliser's to close: the extension host reads a `window.state` replica pushed to
it from the renderer, so the boolean can be briefly stale in either direction; the
socket read is a callback on the event loop decision 9 describes as shared and
unboundedly delayable, so *arrives* and *is handled* are not the same instant; and
the activation itself is asynchronous, so focus can move between a true check and
the reveal that follows it. The worst outcome of losing that race is a **focus
steal** — a window the human has just left pulling itself forward — which is
recoverable, visible, and something the human can only cause by switching windows
in the same tenth of a second as their own keypress. What the check does buy is the
elimination of the *systematic* case: a modal left open across a deliberate window
switch no longer acts in the abandoned window. Note the residue is strictly
smaller than the one Modaliser could achieve on its own, which is why the check
still belongs here.

Within one peer, the extension allocates tokens from a **counter that is never
reset** and keeps token → live object.

**A `parts` call prunes the map; it never replaces it.** On each call the
extension mints tokens for objects it has not seen, keyed on object identity, and
drops only the entries whose object is no longer among the window's terminals or
tabs. Replacing the map wholesale would be wrong for a reason that is invisible
until two panels exist: the screen's two providers each call `parts`, so the
second call would invalidate the tokens the first panel's rows were just drawn
with, and every label on that panel would silently do nothing. Pruning leaves a
live object's token alone however many times `parts` is called, and still lets a
closed tab's token go stale — which is the behaviour the requirements ask for.

**Pruning keys on object identity, and for `Tab` that rests on an implementation
detail rather than on the API.** `Terminal` is a stable object and the API says as
much. For `Tab` the shipped declarations promise only that `close()` invalidates
one; nothing there says a `Tab` object survives a structural change to the tab
model. It does in the pinned version — the extension host memoises each API `Tab`
and reconciles by a stable internal tab id, so dirty, pinned, active and moved
updates reuse the wrapper, which the review chain verified in that version's
source. Treat it as a **stated assumption with a fallback**, not a guarantee: if a
future VSCode re-materialises `Tab` objects, identity-keyed pruning drops live
entries on the next `parts` and *the second panel's labels stop working* while
nothing else looks wrong. The fallback is to key on a value rather than a
reference — the tab's URI plus its group — and the extension's own fixtures are
where this is pinned, because it is invisible from Modaliser's side.

Four consequences, and they are the contract:

- a token can **never** be recycled onto a different terminal or tab *of that
  window*, so an action is either right or a no-op;
- a token whose object has gone away is refused: the map is pruned on the next
  `parts`, and until then the *membership check* on the way to acting catches it
  (decision 2) — "not in the map" alone would be a claim about a map that is only
  swept when something else happens to call it;
- terminals and editors allocate from the **same** counter and share one map, so a
  terminal token handed to `focus-editor` resolves — and is refused because each
  entry carries its **kind** and each method checks it. One counter, one lookup,
  one refusal path, and a kind tag: the tag is what makes cross-kind refusal the
  same code path as a stale token rather than a claim that the lookup will
  helpfully fail;
- a peer is never *handed* a token another window minted, because the address
  came out of the same reply as the token — which is why the counter needs no
  global uniqueness, and equally why widening it to a UUID would not have been a
  fix: the defect a bare token has is that it is not an address, not that it is
  short.

This is the invariant the accessibility design reached for its element handles,
carried across unchanged. Why the third bullet is not pedantry: the alternative
was two independently numbered spaces, both handing out `3`, so the same integer
would be live in both at once and a kind confusion would land on a real object of
the other kind instead of being refused. One counter removes the *collision*; the
kind tag is what turns a wrong-kind token into a refusal.

**A consequence outside this spec:** the one-never-reset-counter change to
`AccessibilityLibrary` that the earlier design required is **not needed**. It
existed only because a second reader would have opened a second handle space in
that library; with no such reader, `ax-find-elements` is again the only space and
its reset harms nothing.

### 5. The Scheme surface in `(modaliser apps vscode)`

Following the shape `project-provider` / `project-listing` established, and the
seam shape `(modaliser muxes herdr-socket)` established for a socket peer.

- **`(current-vscode-socket-pointer-path)`** — a parameter whose default is
  `#f`, "no VSCode extension configured". **The host installs the real path at
  boot** (`root.scm`), exactly as it installs the herdr socket path. This is
  what keeps `swift test` structurally inert (ADR-0023): under test the
  parameter is `#f`, so there is no path by which a suite could dial a live
  editor.
- **`(current-vscode-query-runner)`** — the one seam every reader goes through,
  taking `(socket-path method params)` and returning a parsed reply or `#f`. The
  path is an argument rather than something the runner resolves, because the
  reader resolves the pointer once and every *action* addresses a peer the reply
  named (decision 4). A test installs a canned runner here and the whole surface
  above it is exercised offline.
- **`(current-vscode-notify-runner)`** — the seam the actions go through, taking
  `(socket-path method params)`: the fire-and-forget half, `unix-socket-send` under
  the app and a recorder under test. Two seams rather than one for the reason
  `(modaliser unix-socket)` has two primitives — a deliberately abandoned reply must
  not be indistinguishable from a timeout — and it is what lets a test assert the
  bytes an action puts on the wire without a peer. **Nothing acts on its result and
  the failure is still logged.** `unix-socket-send` returns `#f` when the bytes
  never reached a socket at all, which is precisely the dangling-path case a stale
  target produces; discarding that would leave "the peer refused this" and "there
  was no peer" indistinguishable even in Modaliser's own log, for nothing. One log
  line, no behaviour.
- **`(vscode-parts)`** — impure: resolves the pointer path, one `parts`
  round-trip, returning the parsed reply, or `#f` on an unreachable peer, a
  protocol mismatch, or a reply whose `focused` is false.
- **`(terminal-rows PARTS)`** and **`(editor-rows PARTS)`** — *pure*. Parsed
  reply → **Terminal target**s / **Editor target**s, **each carrying the reply's
  `peer` path alongside its token**. This is where every behavioural test of
  either listing lands, and where the presentation rules go: which fields become
  `text` and which `detail`, path shortening, and the `TabInputTerminal` exclusion
  and `token: null` rules from decision 1.
- **`(terminal-source)`** / **`(editor-source)`** — impure, each
  `(… -rows (vscode-parts))`.
- **`(focus-terminal! target)`** / **`(focus-editor-tab! target)`** — impure:
  one `focus-terminal` / `focus-editor` **notification** to the target's own peer,
  carrying the target's token. Nothing is waited for and nothing is returned; a
  target whose token is `null` has no action at all (decision 1).
- **`(terminal-provider …)`** / **`(editor-provider …)`** — the **Edge
  provider**s a screen binds, each taking `'single-alphabet`, `'leader-alphabet`
  and `'second-alphabet` from the user with **none defaulted** (ADR-0021), an
  optional `'panel-label`, and `'enumerate` — the test seam, defaulting to
  `vscode-parts`.
- **`(terminal-listing)`** / **`(editor-listing)`** — the block specs, each
  closed over the per-**Visit** snapshot its provider took.

**State ids are namespaced `vscode-editor-target/…` and
`vscode-terminal-target/…`**, followed by the token, which is unique across live
rows by construction. Three namespaces were already taken —
`vscode-project-target/`, `paneru-strip-target/` and `herdr-jump-target/`,
enumerated out of the library tree rather than recalled, which is how the third
was found. Enumerate them again before adding a fifth; a collision here is
silently last-wins (decision 6).

**Two panels means two `parts` round-trips per come-to-rest, and that is the
accepted shape — bounded rather than memoised.** Each provider calls `'enumerate`
for itself; nothing memoises the reply across them. A shared per-visit cache would
need either a visit generation the engine does not expose or a cell whose
invalidation nothing naturally drives, so what makes the un-memoised shape safe is
not the healthy-path number — 0.1–0.6 ms of herdr-comparable wire time, against
the 8–29 ms warm accessibility sweep the Projects panel already runs on the same
screen — but the **200 ms per-request timeout** of decision 2, which puts the
worst case at 400 ms of blocked eval thread rather than at whatever a wedged
extension host feels like. A healthy-path measurement could never have
established that bound, which is why the timeout is the decision and the
measurement is a separate question (decision 9). **Reopen if** a measured
come-to-rest says otherwise, or a third panel lands on this screen; the `parts`
reply already carries both listings, so the memo can be added later without a
protocol change.

### 6. The row renderers are judgement calls, not foregone ones

The **Editor listing**'s content is a filename plus a long path — two columns
with very different lengths — where the **Project listing**'s is one long name
in the full width. That is closer to the **Strip listing**'s multi-column grid
than to `blocks/project-list`. The **Terminal listing**'s is a short name plus a
cwd, which is the same shape again. Decide by looking at them, and apply the
rule k4 recorded: **share machinery, duplicate presentation** — duplicated
machinery drifts silently, duplicated presentation drifts visibly. Whichever way
each goes, the lowering stays shared.

If a path is shown at all, it should be shown **shortened relative to the
window's Workspace**, since every row in a one-window listing shares that prefix
and the prefix is the least informative part of a forty-character path. The
`parts` reply carries `workspace` precisely so the shortening needs no second
source — and it is `null` in a folderless window, where the fallback is the
absolute path unshortened. A path that does not lie under the workspace at all —
an editor opened from elsewhere — takes the same fallback, so the rule is *shorten
where the prefix matches* rather than *assume it matches*.

Note the paths are now real `fsPath` strings rather than the
accessibility tree's rendered labels, so they carry no ` • Deleted` decoration
and a renderer that wants a dirty marker takes it from `dirty`.

### 7. Several panels, one `'provider` slot: merge, and the merge must check

The engine will not catch a collision, and this was verified rather than
assumed:

- a provider's edges are folded in with the state's own by plain append, with
  no duplicate check over the result;
- a key is resolved by finding the **first** matching live edge, so a duplicate
  trigger silently dispatches to whichever contributor came first;
- provided states are installed into a table keyed by id, so a duplicate state
  id is silently last-wins;
- the duplicate-edge check *does* run inside `provided-state`, so a single
  narrowing prefix state's own second-key edges are checked — but nothing checks
  across two provider results.

So `(modaliser jump-list)` gains:

**`(jump-list-compose-providers NAME PROVIDER …)`** → one provider. It calls each
provider with the owner id it was given, appends their `'edges` and `'states` in
argument order, and **raises** if two edges share a key trigger or two states
share an id.

**The public operation takes no switch that can weaken its own invariant.** It
queries the owner's static edges and the registered state ids itself, from
`(modaliser fsm)`, with nothing a caller can pass to replace them. An earlier
draft exposed those two readers as optional arguments so a test could supply
them, which meant a user's config — Scheme code, calling the same exported
procedure — could hand in two empty readers and turn the collision check off
while still appearing to compose safely. That is the *asserted rather than
structural* shape this whole decision exists to remove; a check with a documented
off-switch is discipline wearing a check's clothes.

So the surface splits at the purity line instead:

**`(jump-list-validate-composition MERGED CONTRIBUTOR-NAMES OWNER-EDGES
REGISTERED-STATE-IDS)`** — *pure*, and raising, taking every fact as data. This is
where all four collision cases are tested, from synthetic input, with no graph
installed.

`jump-list-compose-providers` is then the thin impure wrapper: call the
providers, append, ask the FSM the two questions, hand the lot to the validator.
Nothing in the wrapper is worth a seam of its own, which is the point — the part
worth testing is pure and the part that cannot be is trivial.

**Contributors are named, because an ordinal cannot repair a configuration.**
The merge receives opaque procedures; nothing recoverable from a closure tells a
user which of their panels owns the colliding key. So each provider is paired
with a name at the call site — the panel's own, from the user's config — and the
raise quotes both. "Editor and Terminal both claim `j`" is a repair;
"provider 1 and provider 2" is a puzzle. The names are the caller's, so the
library still authors no label (ADR-0021).

**The validation surface is wider than the provider results, and this is where
the first design fell short.** Checking only what the providers returned leaves
two collision sources the engine has, uncovered:

- **the owner state's own static edges.** `classify-and-snapshot` appends
  provider edges to the state's declared edges with no duplicate check
  (`fsm.sld:751`), and a key is resolved by finding the *first* live match. So a
  promoted leader that happens to equal a screen key — `e`, `p`, `/` on the
  VSCode screen — dispatches to the static edge and the row's label silently
  does the wrong thing. This is exactly the failure the merge exists to catch,
  and it is *more* likely than a panel-panel collision, because the screen's own
  keys are already spoken for.
- **permanently registered states.** A provided state shadows a permanent state
  of the same id, first-lookup-wins (`fsm.sld:640`), with nothing checked.

So the merge validates the merged edge list against **the owner's static edges
as well**, and the merged state ids against **the registered state ids as
well**. Both come from `(modaliser fsm)`'s existing query surface —
`fsm-state-edges` on the owner id, `fsm-state-ids` — called by the wrapper
itself. An owner id that names no registered state contributes no static edges, so
a screen built entirely from provided states is not a special case.

Edges are plain alists (`fsm.sld:358`), so reading a trigger needs no new export
from `(modaliser fsm)`; the merge stays inside the portable surface.

Raising rather than dropping, because a dropped edge is a dead key with no
diagnostic: the key still works, bound to whichever panel contributed first, so
the user presses a terminal's label and focuses a project. That is a silent
wrong dispatch, which is the failure this whole leaf exists to avoid.

**A raise at come-to-rest releases the keyboard on both dispatch paths, and
one of the two leaves state behind.** The provider runs inside the leader
handler on the press that opens the screen, and inside the catch-all handler on
every press after that. The host wraps both, but not equally:

- **The leader path is clean.** `modal-activate!` runs `fsm-activate!` — and so
  the provider, and so the raise — *before* it registers the catch-all or shows
  the overlay (`fsm.sld:1930`), and the Swift wrapper logs the error and
  finalises the capture regardless (`KeyboardLibrary.swift:185`), re-injecting
  the buffered keys and releasing the tap. Nothing was registered, nothing was
  shown: the screen simply fails to open.
- **The catch-all path releases the keys and nothing else.** On error it
  assigns `catchAllHandler = nil` (`KeyboardLibrary.swift:300`) and stops.
  It does not run `modal-exit`, halt or reset the FSM, or hide the overlay. So
  ordinary keys pass through again — capture is not wedged, which was the claim
  worth checking — but the overlay can be left on screen over live Scheme modal
  state until the next activation resets it.

That second path is reachable here, and pretending otherwise would be the
easier lie: a collision between two panels' *promoted leaders* is
data-dependent (below), so the first press that raises may well be a later
come-to-rest inside the modal rather than the one that opened it.

**The trade-off is accepted rather than solved.** Raising still beats a silent
wrong dispatch, and the residue — a stale overlay after a config error, cleared
by the next activation — is a worse-looking failure, not a worse one. Repairing
the catch-all teardown is a host change with its own blast radius across every
modal screen, so it is its own leaf rather than a rider on this design, and the
sentence this spec previously carried — that both paths fail visibly and
"nothing wedges" — was too broad to be worth keeping. `/usr/bin/log` is also
not user-visible feedback; on this path the visible signal is the overlay that
stops responding.

Note what this is **not**: ADR-0022 is about a config that fails to *load*, and
is sequenced by the host across two top-level evaluations. A provider raising on
a keypress is a different path with a different guard, and the guard above is
what makes raising the affordable policy. The condition itself is still a config
error — two of the user's alphabets overlapping — and it fails on every press of
that screen until it is fixed, which is the correct blast radius for a broken
screen.

The check is not free but it is small: it is over the merged edge list, which is
one entry per labelled row, not per key press.

**The disjointness a screen has to keep is wider than it looks, and it cannot be
checked statically.** A panel's edges on the owner state are one per surviving
single-key label *plus one per promoted leader*, so the pool two panels must
keep disjoint is `single-alphabet ∪ leader-alphabet`, not the single alphabets
alone. And leader promotion is **data-dependent**: label assignment escalates
into leaders only when a panel has more rows than its single alphabet covers.
So two panels can share a leader key, coexist happily for months, and collide
the first time one of them grows past its singles. That is exactly why the check
belongs at the merge, at come-to-rest, rather than as a config-load validation —
at load there is no row count to check against.

### 8. Degradation: an empty listing is the honest answer

Every miss produces **no rows**, never wrong rows. The source change moves the
cases without changing the contract, and there are more of them now, because the
peer is a separate installed artifact:

- **The extension is not installed, or is disabled for this profile.** No socket,
  so the pointer file names nothing or names a path that refuses connections.
- **VSCode is not running, or the pointer file has never been written.**
  `read-file-text` returns `#f` on a file that is not there.
- **The pointer is stale.** The reply's `focused` is false and Modaliser
  discards it (decision 3).
- **The protocol versions disagree.** Treated as unreachable (decision 2).
- **The extension host is wedged or slow.** The read is timeout-bounded at 200 ms
  and returns `#f` (decision 2).
- **The window is connected to a remote host** and the extension somehow ran
  there rather than locally — `extensionKind: ["ui"]` is what prevents this, and
  if it is wrong the socket is on the wrong machine and unreachable, which is
  again empty rather than wrong.

Two cases the accessibility design had are simply gone: a modal being up, and a
setting having been changed away from the value the reading required. And one
case that reads like a miss is **not** one: a window with no folder open lists
normally, with `workspace: null` and unshortened paths (decision 3). An empty
listing there would have been a silent narrowing of the requirements rather than
a degradation.

An action has no failure path of its own to enumerate, because it has no reply:
every refusal — stale token, wrong kind, a window that is no longer focused — is
the peer declining to act, and what the human sees is that nothing happened
(decision 2).

What the screen does about an empty listing is the screen's call, and the screen
is the user's. A panel that renders no rows is the default; a configuration that
would rather say so can put a notice in the row source it composes.

### 9. Cost, and the `'next 'self` ruling stands

**The wire is now measured — see the table below — and the previous
accessibility measurement is withdrawn and now irrelevant.** The 3.1 ms figure this spec once carried came from a standalone
`swiftc -O` accessibility walker that was never committed and cannot be re-run;
it described neither the shipping path nor, now, the source. It is gone rather
than adjusted.

What can be said in advance, and no more: the comparable transport in this
codebase — herdr's socket, same primitive, same envelope — was measured at
**0.1–0.6 ms of wire time per read**, and this design puts two round-trips on a
come-to-rest where the Projects panel already runs an 8–29 ms warm (200 ms cold)
accessibility sweep. So the expectation is that the two new panels are cheaper
than the panel already on the screen. **That is an expectation, not a result.**

**The risk that is genuinely new is not the wire, it is the peer.** An
accessibility read contends with the target application's main thread; a socket
round-trip contends with the extension host's **event loop, which every other
extension in that window shares**. A language server indexing, a large
`onDidChangeTextDocument` fan-out, or a badly-behaved third-party extension can
delay the reply in a way nothing on Modaliser's side can bound. **Nothing about
that risk is a measurement question** — a healthy peer's average says nothing
about a wedged one — so it is answered by the 200 ms budget of decision 2 rather
than by the measurement below, and a timeout that fires shows an empty panel.

**A build session measures the composed screen's own come-to-rest on the
shipping path before treating the cost as settled**, and instruments it with
something committed — `(modaliser instrument)`'s spans are what the herdr
transport already uses, and splitting wire time from parse time is what makes a
bad number diagnosable rather than merely bad. A bad number is a finding worth
its own leaf rather than something to absorb.

**Measured, against four live windows** (`vscode-companion-extension-k12`,
VSCode 1.136.2, `vscode-extension/scripts/measure-parts.js`, 200 iterations
per peer). This is the *peer's whole service time seen from outside* —
connect, request, the extension host scheduling the callback, building the
reply, and the write back:

| | min | p50 | p95 | max | reply |
|---|---|---|---|---|---|
| four peers, 200 reads each | 0.034 ms | 0.041–0.047 ms | 0.097–0.118 ms | 1.20 ms | 298–1225 B |

So a healthy peer answers in **a twenty-fifth of a millisecond**, comfortably
inside the 0.1–0.6 ms herdr order this expected, and two panels' worth of it is
noise beside the accessibility sweep already on the screen. The 200 ms budget
is ~5000× the median.

Three things that number does **not** settle, stated so it is not
over-read. It is measured **from outside Modaliser**, so it excludes
`json-parse` and the eval thread — that is what the committed `vscode-wire` /
`vscode-parse` spans are for, and they cannot report until a screen binds a
panel to `vscode-parts`, which is the next leaf's work. It is a **healthy
peer**, which by the paragraph above is the case that was never in question.
And it is **not the come-to-rest**, which is a composed screen's number and
still owed.


That does not reopen `'next 'self`, which is independent of all of the above.
The ban is not about the size of one gather; it is that keyboard capture filters
no auto-repeat, so a held key queues gathers faster than they drain. Compose the
ops on this screen **without** `'next 'self`, exactly as the paneru reference
composition does.

**One thing the ban does not reach, and it is worth knowing rather than
solving: a held *leader*.** Auto-repeat on the key that opens the screen re-enters
it, and each entry runs the providers — so a wedged peer's 400 ms lands once per
repeat, by the same queue-faster-than-they-drain mechanism the ban exists for, on
the one key the ban cannot cover. This is not new with the socket: the Projects
panel's cold accessibility sweep is the same order and predates it. It is listed
because a reader who finds the screen unresponsive under a held leader should
recognise the mechanism rather than suspect the transport.

## Requirements

### Requirement: the Editor listing lists the frontmost window's tabs

The Editor listing SHALL contain one row per editor tab of the frontmost VSCode
window — across every editor group in it, in on-screen order — and no rows from
any other window.

#### Scenario: several tabs open
- **WHEN** the frontmost VSCode window has three editor tabs open
- **THEN** the listing shows three rows, in the order the tab strip shows them

#### Scenario: the editor is split
- **WHEN** the frontmost window has two editor groups, of two and three tabs
- **THEN** the listing shows five rows — the left group's tabs, then the
  right's — and does not mark where one group ends

#### Scenario: another window has tabs too
- **WHEN** a second VSCode window is open with different tabs
- **THEN** none of that window's tabs appears in the listing

#### Scenario: a terminal has been moved into the editor area
- **WHEN** the frontmost window has two file tabs and one terminal in the
  editor grid
- **THEN** the Editor listing shows two rows, and that terminal appears once,
  in the Terminal listing

#### Scenario: a tab that cannot be focused
- **WHEN** the frontmost window has a webview or a diff tab open
- **THEN** the listing shows a row for it, that row has no action, and the
  labels of the rows below it are unchanged

#### Scenario: the window has no folder open
- **WHEN** the frontmost VSCode window was opened with no folder and has two
  tabs and one terminal
- **THEN** both listings show that window's parts, with paths shown unshortened

### Requirement: the Terminal listing lists the frontmost window's terminals

The Terminal listing SHALL contain one row per terminal of the frontmost VSCode
window, whether or not the terminal panel is shown.

#### Scenario: the terminal panel is hidden
- **WHEN** the frontmost window has two terminals and the terminal panel is
  hidden
- **THEN** the listing shows two rows, and showing them does not open the panel

#### Scenario: one terminal only
- **WHEN** the frontmost window has exactly one terminal
- **THEN** the listing shows one row, whatever
  `terminal.integrated.tabs.hideCondition` is set to

#### Scenario: no terminals
- **WHEN** the frontmost window has no terminals
- **THEN** the listing is empty and no error is raised

### Requirement: a label activates the part its row was read from

Pressing a row's **Jump label** SHALL activate the terminal or editor whose row
it is, or nothing at all. It SHALL never activate a different one, whatever has
changed in the window since the rows were drawn.

#### Scenario: press an editor label
- **WHEN** the user presses the label on the row reading `beta.txt`
- **THEN** `beta.txt` becomes the active editor in that window

#### Scenario: press a terminal label
- **WHEN** the user presses the label on the row reading `zsh`
- **THEN** that terminal is shown and focused

#### Scenario: the row is already active
- **WHEN** the user presses the label of the row that is already active
- **THEN** nothing changes and nothing is reported — including when that row is a
  preview tab, which stays a preview tab

#### Scenario: the same file is open in two editor groups
- **WHEN** one file is open in two groups, both rows are drawn, and the groups are
  then reordered
- **THEN** each row still activates its own tab, and neither activates the other's
  nor opens a new editor

#### Scenario: the part was closed after the rows were drawn
- **WHEN** the user presses the label of a row whose tab or terminal has since
  been closed
- **THEN** nothing is activated and no error is raised

#### Scenario: a token belonging to the other kind
- **WHEN** `focus-editor` is given a token minted for a terminal
- **THEN** it refuses it exactly as it refuses a stale token, and focuses
  nothing

#### Scenario: another window took focus after the rows were drawn
- **WHEN** the rows were read from window A, focus then moved to window B, and
  the user presses a row's label
- **THEN** nothing in window B is activated, whatever tokens window B has minted
  — the notification reaches window A, which refuses it because it is no longer
  focused

### Requirement: a miss produces no rows, never wrong rows

Where the window's parts cannot be read, both listings SHALL be empty.

#### Scenario: the extension is not installed
- **WHEN** VSCode is running without the companion extension
- **THEN** both listings are empty and no error is raised

#### Scenario: the pointer names a window that has closed
- **WHEN** the socket the pointer file names refuses connections
- **THEN** both listings are empty and no error is raised

#### Scenario: the reply is from a window that is not focused
- **WHEN** the peer answers with `focused` false
- **THEN** the reply is discarded, both listings are empty, and no rows from
  that window are shown

#### Scenario: the protocol versions disagree
- **WHEN** the peer answers with a `protocol` this Modaliser does not
  understand
- **THEN** the reply is discarded and both listings are empty

### Requirement: composing providers refuses a collision

Merging two or more **Edge provider**s SHALL raise, naming both contributors,
when two of their edges share a key trigger or two of their states share an id —
and equally when one of their edges collides with an edge the owner state
already declares, or one of their states collides with a registered state id.

#### Scenario: overlapping alphabets
- **WHEN** a screen composes two providers whose alphabets share a key
- **THEN** the composition raises, naming both panels, rather than binding the
  key to one of them

#### Scenario: a promoted leader collides with a screen key
- **WHEN** a panel grows past its single alphabet and promotes a leader whose
  key the owner state already binds
- **THEN** the composition raises, naming the panel and the owner's own edge,
  rather than letting the static edge win the dispatch

#### Scenario: a provided state collides with a registered one
- **WHEN** a provider mints a state whose id a permanently registered state
  already holds
- **THEN** the composition raises rather than shadowing it

#### Scenario: disjoint alphabets
- **WHEN** the alphabets and state-id namespaces are disjoint from each other
  and from the owner's
- **THEN** the merged result is the concatenation of both edge and state lists,
  in argument order


## Test seams

One seam per new surface, each as high as it goes, and none of them reaching a
live VSCode.

- **The row joins are pure and take a parsed reply.** `terminal-rows` and
  `editor-rows` are functions from the `parts` reply to **Terminal target**s and
  **Editor target**s. Every behavioural test of either listing lands there,
  driven from a fixture captured off a real reply — the same placement the
  stored-window-state parser has, and for the same reason: it makes "`swift
  test` reaches nothing outside the process" structural rather than
  disciplined. There is no socket call under test that could reach a live
  editor.
- **`current-vscode-query-runner` is the read side's one impure seam**, installed
  canned in a test exactly as the herdr query runner is. It is what lets a test
  exercise `vscode-parts`' own behaviour — the `focused` gate, the protocol check,
  the `#f` on an unreachable peer — rather than only the pure joins above it.
- **`current-vscode-notify-runner` is the action side's**, and a recording runner
  installed there is how the peer-binding invariant is pinned: build targets from
  a reply whose `peer` is one path, and assert the action was addressed to *that*
  path and no other. Without that assertion the whole of decision 4 is an
  assertion again — the one thing this design has already been caught at once.
- **`'enumerate` is each provider's seam**, defaulting to `vscode-parts`, so a
  test drives a whole provider — label assignment, lowering, state ids — from a
  canned reply.
- **`jump-list-validate-composition` is the composition's seam, and it is pure**
  (decision 7). It is tested by direct call against synthetic edge and state lists
  whose targets are deliberately neither editors nor terminals, so a VSCode-shaped
  assumption cannot leak into the machinery. Four cases, one per raise: panel
  against panel on a key, panel against panel on a state id, panel against the
  owner's static edge, panel against a registered state id. Plus the clean merge,
  and a case asserting the raise names the colliding contributors rather than
  their positions. `jump-list-compose-providers` itself gets one test — that a
  clean composition through a real installed graph produces the merged result —
  and needs no more, because everything that can be wrong in it is in the
  validator.
- **The extension is tested on its own side**, in its own project, against
  fakes of the two API surfaces it reads. Token allocation, stale-token refusal,
  and **cross-kind refusal** — a terminal token must be refused by
  `focus-editor` and vice versa — are the bookkeeping tests, and that last one
  is the test for decision 4's disjointness claim; without it the claim is only
  an assertion. Nothing in the Swift test suite reaches the extension.
- **The shipped example config is load-tested** by the existing example-loading
  test, so a composed screen that stops composing is a red suite.

**What no seam here can reach, stated so nobody mistakes a green suite for a
working panel.** Every offline seam above asserts the *call* — which bytes went to
which peer, which arguments an activation was built from — and none asserts the
*effect*, because the effect is VSCode's. So decision 1's per-kind activation
table, the part of this design most likely to be wrong and the part the review
already caught once, is confirmed only against a real editor. The two cases to
drive by hand, because they are the ones a fake passes and a real window fails:
**the same file open in two editor groups** (each row must activate its own tab,
after the groups have been reordered), and **a preview tab that is already active**
(pressing its label must change nothing, not pin it). Both are in the build leaves'
`Done when`; neither is a suite's to hold.

**Both were driven against a real focused window, and how to do it again.**
Verified 2026-09-10 against VSCode 1.137.0, along with the two focus-gated
claims of decision 3 — the pointer file naming the focused window's socket and
following focus between windows, and `focused` true in exactly the focused
peer's reply and false in every other at the same moment. The two-group case
was checked for a text tab **and** for a markdown tab, which is the
custom-editor (`vscode.openWith`) branch and the common path wherever
`workbench.editorAssociations` maps `*.md` to `vscode.markdown.preview.editor`;
the reactivated markdown tab was confirmed still rendering as Markdown Preview,
so `openWith` preserves the editor's identity rather than falling back to a text
view. Nothing failed, so nothing here changed.

None of it needs the developer's own desktop. A focused window is the one thing
a locked or unattended machine cannot supply — `window.state.focused` is
key-window state, so it reads false for every window while the screen is locked
even though the *application* is still frontmost, and that is a screen-lock
reading (`CGSSessionScreenIsLocked`), not a defect. Driving it inside an
isolated guest VM removes the human from the loop entirely: install the built
extension by copying `package.json` and `out/src` into the guest's
`~/.vscode/extensions/`, disable the editor's AI features (`chat.disableAIFeatures`,
`github.copilot.enable` all-false) or the chat panel swallows the keystrokes, and
probe each peer with `nc -U` exactly as `scripts/measure-parts.js` does.

**The trap in the preview case, which nearly passed as a defect.** A preview tab
is not observable through a `parts` row — `EditorRow` carries `active` and
`dirty`, not `isPreview` — so the check has to be behavioural: a preview tab is
*replaced* by the next file opened into its group, a pinned one is not. Produce
it with a **single click in the Explorer**, never with Quick Open:
`workbench.editor.enablePreviewFromQuickOpen` has defaulted to false since VSCode
1.44, so `cmd-p` yields a pinned tab and the replacement observable silently
stops discriminating. Run the control every time — press nothing, open a second
file, and confirm the first is replaced — because a tab that survives proves the
press pinned it only once you know an untouched tab would not have survived.

**A control the fixtures must supply.** Write the `parts` fixture set with the
awkward rows present, or the rules in decision 1 are untested and an
implementation that ignores them passes everything: an inert tab kind (must be
listed, must have `token: null`), a `TabInputTerminal` tab (must not appear among
the editors), a terminal with no `cwd`, tabs in two different `group`s, a
`workspace` of `null` (paths must come out unshortened rather than crashing or
being dropped), and a reply whose `focused` is false (must be discarded whole).
The last of those is the one most likely to be left out, because it is the only
fixture whose correct handling is to produce nothing.

**And one the extension's own fixtures must supply**, for the same reason: a
notification arriving while `window.state.focused` is false must be refused. That
is the only test of decision 4's remaining gap, and it lives on the extension's
side because the check does.

## Out of scope

- **Any use of the accessibility tree for these listings.** Rejected in
  ADR-0026, which records the evidence for the option and the condition that
  would reopen it. Neither `ax-tab-rows` nor `ax-press-handle` is built, and
  `AccessibilityLibrary` is unchanged by this work.
- **Reading the stored editor state.** Rejected in ADR-0026 with the condition
  that would reopen it.
- **A cross-window listing.** Every window's extension is dialable, so this is
  reachable for the first time — but nothing has asked for one, addressing a
  window other than the focused one would need a way to name it that the pointer
  file does not provide, and the screen is about the window in front of you.
- **Multi-root workspaces.** The extension keys its workspace on
  `workspaceFolders[0]`, and a window opened from a `.code-workspace` file has
  no single folder for Modaliser's stored-state reader to agree with. Such a
  window still lists its parts — the pointer file does not depend on the
  workspace at all — but the `workspace` field, and therefore path shortening,
  degrades to the first folder. Nobody here uses one; revisit if that changes.
- **Editor *group* identity as a navigable thing.** Every group's tabs are
  listed and each row carries its `group`, so a renderer may show it — but the
  listing offers no way to focus a group as such, and does not separate them
  visually unless a renderer chooses to. Note this is narrower than the earlier
  exclusion, which was forced by the source not carrying group structure at all.
- **Anything the extension could do but is not asked to.** Running workbench
  commands, opening files, editing settings, reading document contents. The
  method set is three methods, and it grows only with a reason recorded here.
- **Installing the extension as part of installing Modaliser.** It targets a
  different application, requires that application to be present, and has its
  own upgrade cadence; it gets its own script rather than a step inside
  `install.sh`.

## See also

- ADR-0026 — why a companion extension, what each rejected source cost, what
  would reopen each, and the exposure the bounded method set accepts.
- ADR-0027 — how one window is addressed among several, and why a row is bound to
  the peer that minted it rather than to a pointer read a second time.
- ADR-0020 — the socket transport this reuses, and why a socket is an
  integration boundary rather than a workaround.
- ADR-0021 — no library authors a key, a label or an alphabet.
- `docs/specs/paneru-window-management.md` — the **Strip listing**, the first
  labelled listing, and the shape these follow.
