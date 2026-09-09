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
one hands the extension back a **token** the extension itself minted when it
drew the row, so the row and what it does come from one snapshot and cannot
disagree — the contract the Project listing and the **Strip listing** already
hold.

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
| a terminal's cwd | `Terminal.shellIntegration.cwd`, `null` when shell integration has not reported one |
| an editor's label | `Tab.label` |
| an editor's path | `Tab.input.uri.fsPath` where the input carries a URI, else `null` |
| an editor's active flag | `Tab.isActive` |
| an editor's group | `Tab.group.viewColumn` |
| the window's focus | `window.state.focused` |
| the window's workspace | `workspace.workspaceFolders[0].uri.fsPath` |

**A terminal moved into the editor area is a terminal, not an editor.** VSCode
lets a terminal be dragged into the editor grid, where it appears both in
`window.terminals` and as a tab whose `input` is a `TabInputTerminal`. Listed
naively it would take two rows and two jump labels for one thing. So a tab whose
input is a `TabInputTerminal` is **excluded from the editor listing**; it is
already in the terminal listing, where the action works.

**A tab that cannot be focused is listed without a token.** A tab whose input
carries no URI — a webview, a settings editor, an input kind this extension does
not know — is a real open editor and is shown, but it gets `token: null` and no
action. That is `jump-list`'s own existing test for whether a row earns an edge:
the row still renders and still consumes its label, so an unfocusable tab cannot
renumber the labels below it. Listing it and refusing to act is honest; omitting
it would make the panel disagree with the tab strip the user is looking at.

### 2. The wire protocol: three methods, and no command passthrough

Newline-delimited JSON over a Unix-domain stream socket, one request per
connection, the peer closing after it responds — the model ADR-0020 established
and `unix-socket-request` already implements, framing included.

The envelope is herdr's, because Modaliser's JSON handling is already shaped for
it: a request is `{"id": N, "method": STRING, "params": OBJECT}` and a reply is
`{"id": N, "result": …}` or `{"id": N, "error": {"message": STRING}}`.

**`parts`** — params `{}` — returns the whole window in one reply:

```json
{ "protocol": 1,
  "focused": true,
  "workspace": "/Users/…/Modaliser",
  "terminals": [ {"token": 12, "name": "zsh", "cwd": "/Users/…", "active": true} ],
  "editors":   [ {"token": 13, "label": "fsm.sld", "path": "/Users/…/fsm.sld",
                  "active": true, "dirty": false, "group": 1} ] }
```

`terminals` is in `window.terminals` order. `editors` is in group order and then
tab order within a group, which is the order the tab strips show — so the
sequence is the on-screen one, and the listing does not mark where one group
ends (see **Out of scope**, and note `group` is carried per row for a renderer
that wants it).

**`focus-terminal`** and **`focus-editor`** — params `{"token": N}` — return
`{"ok": true}` or `{"ok": false}`. `focus-terminal` resolves the token to the
live `Terminal` and calls `Terminal.show(false)`. `focus-editor` resolves the
token to the live `Tab`, **verifies it is still present in
`window.tabGroups.all`**, and then reveals it by its URI in its own view column;
a tab that has gone is `{"ok": false}` and nothing is focused.

**There is deliberately no method that runs a workbench command.** A
`executeCommand` passthrough would be one line in the extension and would turn
the socket into a remote control for everything VSCode can do. With the bounded
set, what an attacker who can dial the socket gets is the list of open editors'
paths and the ability to switch tabs. That is a real exposure — the socket is
reachable by anything running as the user, exactly as herdr's is — and it is
accepted with the surface kept as small as the feature allows, not waved away.

**The reply carries a protocol version and Modaliser checks it.** Modaliser and
the extension are installed separately and can skew. A `protocol` that is not
the version this Modaliser understands is treated as an unreachable peer: empty
listing, log line, no attempt to interpret fields whose meaning is not agreed.

### 3. Reaching the right window: a last-focused pointer file

The extension host is **per-window**, and `window.terminals` is that window's
terminals — so Modaliser has several peers and must pick one.

**Each window's extension writes its own socket path into one well-known file
when its window takes focus.** The extension subscribes to
`window.onDidChangeWindowState` and, on becoming focused, atomically replaces
the contents of `<socket-dir>/focused` with its own socket path. Modaliser reads
that one file with the `read-file-text` it already has (`util.sld:95`), and
dials what it names.

**Two better-sounding schemes were rejected on the same constraint.** A socket
path derived from the workspace folder needs the same function computed on both
sides, and scanning the socket directory needs a directory listing. **The
portable tree can do neither.** There is no directory listing at all — R7RS file
ports are the whole file surface. And while `(modaliser util)` does re-export
SRFI 69's `string-hash`, it is the wrong tool by construction: it is a
hashtable hash, implementation-defined and pinned by nothing, so a TypeScript
side could not reproduce it and a LispKit upgrade could silently change every
socket name. A path-sanitising scheme that avoids hashing altogether then runs
into macOS's 104-byte `sun_path` limit on a deep worktree path. So the two
alternatives cost new native surface to buy nothing, while the pointer file
needs nothing that does not already exist.

**Modaliser discards a reply whose `focused` is false.** That is the "row and
action come from one snapshot and cannot disagree" contract applied to *window*
identity: a stale pointer — a window that closed, a race — yields an empty
listing rather than a neighbouring project's terminals.

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

**Lifecycle.** The extension unlinks a stale socket path before binding, and
unlinks its own on `deactivate`. A host that crashed leaves a socket file that
refuses connections, which `unix-socket-request` reports as `#f` — the same
empty listing as every other miss.

### 4. Identity across the read→act gap is a never-recycled token

The extension allocates tokens from a **per-window counter that is never reset**
and keeps token → live object.

**A `parts` call prunes the map; it never replaces it.** On each call the
extension mints tokens for objects it has not seen, keyed on object identity, and
drops only the entries whose object is no longer among the window's terminals or
tabs. Replacing the map wholesale would be wrong for a reason that is invisible
until two panels exist: the screen's two providers each call `parts`, so the
second call would invalidate the tokens the first panel's rows were just drawn
with, and every label on that panel would silently do nothing. Pruning leaves a
live object's token alone however many times `parts` is called, and still lets a
closed tab's token go stale — which is the behaviour the requirements ask for.

Three consequences, and they are the contract:

- a token can **never** be recycled onto a different terminal or tab, so an
  action is either right or a no-op;
- a token whose object has gone away is not in the map, and the action returns
  `{"ok": false}` rather than acting on something else;
- terminals and editors allocate from the **same** counter, so a terminal token
  handed to `focus-editor` is not found and is refused for the same reason a
  stale token is — one code path, not a special case.

This is the invariant the accessibility design reached for its element handles,
carried across unchanged, and it is worth restating why the third bullet is not
pedantry: two independently numbered spaces both hand out `3`, so the same
integer would be live in both at once and the wrong-target failure would arrive
through the back door. Separate maps give separate lookups, not separate values.

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
  taking `(method params)` and returning a parsed reply or `#f`. A test installs
  a canned runner here and the whole surface above it is exercised offline.
- **`(vscode-parts)`** — impure: one `parts` round-trip, returning the parsed
  reply, or `#f` on an unreachable peer, a protocol mismatch, or a reply whose
  `focused` is false.
- **`(terminal-rows PARTS)`** and **`(editor-rows PARTS)`** — *pure*. Parsed
  reply → **Terminal target**s / **Editor target**s. This is where every
  behavioural test of either listing lands, and where the presentation rules go:
  which fields become `text` and which `detail`, path shortening, and the
  `TabInputTerminal` exclusion and `token: null` rules from decision 1.
- **`(terminal-source)`** / **`(editor-source)`** — impure, each
  `(… -rows (vscode-parts))`.
- **`(focus-terminal! target)`** / **`(focus-editor-tab! target)`** — impure:
  one `focus-terminal` / `focus-editor` round-trip on the target's token.
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
accepted shape.** Each provider calls `'enumerate` for itself; nothing memoises
the reply across them. A shared per-visit cache would need either a visit
generation the engine does not expose or a cell whose invalidation nothing
naturally drives, and it would buy back a round-trip that herdr's comparable
wire time puts at 0.1–0.6 ms — against the 8–29 ms warm accessibility sweep the
Projects panel already runs on the same screen. **Reopen if** a measured
come-to-rest says otherwise; the `parts` reply already carries both listings, so
the memo can be added later without a protocol change.

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
source. Note the paths are now real `fsPath` strings rather than the
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

**`(jump-list-compose-providers NAME PROVIDER … ['known-edges FN]
['known-state-ids FN])`** → one provider. Names are strings and the trailing
keywords are symbols, so the two halves of the argument list cannot be confused
for one another.  It calls each provider with the owner
id it was given, appends their `'edges` and `'states` in argument order, and
**raises** if two edges share a key trigger or two states share an id.

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
`fsm-state-edges` on the owner id, `fsm-state-ids` — reached through the two
optional seams `'known-edges` and `'known-state-ids`, which default to those
queries and are overridden in tests. An owner id that names no registered state
contributes no static edges, so a screen built entirely from provided states is
not a special case.

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
- **The window has no folder open.** A folderless window has no workspace, and
  the extension does not listen for one — there is nothing for a row's path to be
  relative to and nothing for the human to have meant.
- **The pointer is stale.** The reply's `focused` is false and Modaliser
  discards it (decision 3).
- **The protocol versions disagree.** Treated as unreachable (decision 2).
- **The extension host is wedged or slow.** The round-trip is timeout-bounded and
  returns `#f`.
- **The window is connected to a remote host** and the extension somehow ran
  there rather than locally — `extensionKind: ["ui"]` is what prevents this, and
  if it is wrong the socket is on the wrong machine and unreachable, which is
  again empty rather than wrong.

Two cases the accessibility design had are simply gone: a modal being up, and a
setting having been changed away from the value the reading required.

What the screen does about an empty listing is the screen's call, and the screen
is the user's. A panel that renders no rows is the default; a configuration that
would rather say so can put a notice in the row source it composes.

### 9. Cost, and the `'next 'self` ruling stands

**Nothing here is measured, and the previous measurement is withdrawn and now
irrelevant.** The 3.1 ms figure this spec once carried came from a standalone
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
delay the reply in a way nothing on Modaliser's side can bound. That is what the
timeout is for, and a timeout that fires shows an empty panel.

**A build session measures the composed screen's own come-to-rest on the
shipping path before treating the cost as settled**, and instruments it with
something committed — `(modaliser instrument)`'s spans are what the herdr
transport already uses, and splitting wire time from parse time is what makes a
bad number diagnosable rather than merely bad. A bad number is a finding worth
its own leaf rather than something to absorb.


That does not reopen `'next 'self`, which is independent of all of the above.
The ban is not about the size of one gather; it is that keyboard capture filters
no auto-repeat, so a held key queues gathers faster than they drain. Compose the
ops on this screen **without** `'next 'self`, exactly as the paneru reference
composition does.

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
- **WHEN** the frontmost window has a settings or webview tab open
- **THEN** the listing shows a row for it, that row has no action, and the
  labels of the rows below it are unchanged

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
- **THEN** nothing changes and nothing is reported

#### Scenario: the part was closed after the rows were drawn
- **WHEN** the user presses the label of a row whose tab or terminal has since
  been closed
- **THEN** nothing is activated and no error is raised

#### Scenario: a token belonging to the other kind
- **WHEN** `focus-editor` is given a token minted for a terminal
- **THEN** it refuses it exactly as it refuses a stale token, and focuses
  nothing

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
- **`current-vscode-query-runner` is the one impure seam**, installed canned in
  a test exactly as the herdr query runner is. It is what lets a test exercise
  `vscode-parts`' own behaviour — the `focused` gate, the protocol check, the
  `#f` on an unreachable peer — rather than only the pure joins above it.
- **`'enumerate` is each provider's seam**, defaulting to `vscode-parts`, so a
  test drives a whole provider — label assignment, lowering, state ids — from a
  canned reply.
- **`jump-list-compose-providers` is tested by direct call** against synthetic
  providers whose targets are deliberately neither editors nor terminals, so a
  VSCode-shaped assumption cannot leak into the machinery. It is *not* pure — it
  reads the installed graph to widen its validation surface (decision 7) —
  which is exactly why it takes `'known-edges` and `'known-state-ids`: a test
  supplies both and the call is pure again. Four cases, one per raise: panel
  against panel on a key, panel against panel on a state id, panel against the
  owner's static edge, panel against a registered state id. Plus the clean
  merge, and a case asserting the raise names the colliding contributors rather
  than their positions.
- **The extension is tested on its own side**, in its own project, against
  fakes of the two API surfaces it reads. Token allocation, stale-token refusal,
  and **cross-kind refusal** — a terminal token must be refused by
  `focus-editor` and vice versa — are the bookkeeping tests, and that last one
  is the test for decision 4's disjointness claim; without it the claim is only
  an assertion. Nothing in the Swift test suite reaches the extension.
- **The shipped example config is load-tested** by the existing example-loading
  test, so a composed screen that stops composing is a red suite.

**A control the fixtures must supply.** Write the `parts` fixture set with the
awkward rows present, or the rules in decision 1 are untested and an
implementation that ignores them passes everything: a tab whose input carries no
URI (must be listed, must have `token: null`), a `TabInputTerminal` tab (must
not appear among the editors), a terminal with no `cwd`, tabs in two different
`group`s, and a reply whose `focused` is false (must be discarded whole). The
last of those is the one most likely to be left out, because it is the only
fixture whose correct handling is to produce nothing.

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

- ADR-0026 — why a companion extension, what each rejected source cost, and what
  would reopen each.
- ADR-0020 — the socket transport this reuses, and why a socket is an
  integration boundary rather than a workaround.
- ADR-0021 — no library authors a key, a label or an alphabet.
- `docs/specs/paneru-window-management.md` — the **Strip listing**, the first
  labelled listing, and the shape these follow.
