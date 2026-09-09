# vscode-editor-listing

## Problem

The F17 VSCode screen carries a **Project listing** — every open VSCode window
as a labelled row — and the human wants the same affordance one level in: the
**editors** open in the frontmost window, and the **terminals** running in it,
each reachable by a jump label from its own alphabet.

The Project listing had its row source to hand: the window enumeration lists
windows, and a **Project** falls out of a window title. Nothing in reach lists
what is open *inside* a window. VSCode has no scripting dictionary and no IPC
socket, so the source had to be found before either panel could be built, and
the candidates fail in materially different ways — one goes quietly stale, one
sees only what is on screen, one has no names at all.

Separately, a state has **one** `'provider` slot, and the screen is about to
want more than one labelled panel on it. Two providers appending their edge
sets is mechanically fine and silently wrong when it is not, because nothing in
the engine checks.

## Solution

**Editors get a listing now; terminals get one behind a design this spec does
not do.**

The **Editor listing** is the editor tabs of the frontmost VSCode window as
overlay rows, in tab-strip order, each carrying a **Jump label** that activates
that tab. Its rows come from the window's **accessibility tree**, read at
come-to-rest, and pressing a label performs an accessibility **press** on the
very element the row was read from — so the row and what it does come from one
snapshot and cannot disagree, which is the contract the Project listing and the
**Strip listing** already hold.

Terminals are enumerable the same way, but only with the terminal panel
*shown* — and a provider runs before the state it belongs to fires its entry, so
showing-then-enumerating is a sequencing design rather than a detail. It is cut
as its own leaf (`vscode-terminal-listing`) ahead of the panel implementation.
Until it lands the screen keeps focus-then-cycle, the shape editor cycling
already uses. ADR-0026 records the evidence and the trade-off for both halves.

A screen carrying more than one labelled panel composes its providers through a
new merge in `(modaliser jump-list)` that **raises** on a collision the engine
would otherwise resolve first-wins.

## Decisions

### 1. The row source is the accessibility tree, anchored on an absence

Rows are the tab buttons of **every editor tab strip** in the focused VSCode
window. Per tab:

| field | where it comes from |
|---|---|
| description | the tab button's accessibility description, verbatim, empty string when absent |
| title | the tab button's accessibility title, verbatim, empty string when absent |
| detail | the first child group's accessibility description — the file path, tilde-abbreviated under `$HOME`, absolute outside it, with VSCode's own decoration suffixes (` • Deleted`) already appended |
| active | the tab button's `selected` attribute |
| handle | the element itself, round-tripped to Scheme as an integer handle |

**The name is description-then-title, in that order, and never one alone —
and the choice is made in Scheme, not in the walk.** Which of the two carries
the name is not stable: the same tab group, read twice fifteen minutes apart,
put it in different attributes both times. The native side therefore hands both
attributes across *unjoined*; collapsing them below the bridge would put the
rule under the one layer no offline test can reach (see **Test seams**).

**A strip is found by the absence of an aria-label, and there may be more than
one.** Every other tab group in a VSCode window — the panel switcher, the
activity bar, the secondary sidebar, the settings switcher — is a composite bar
and carries the composite bar's own aria-label on its description. An editor tab
strip alone has an empty description. Matching the label's *text* is not an
option: it is localised and resolved from the application's message table at
runtime, so the English string is not a property of the app. **Any future
accessibility anchor in this application is subject to the same rule** —
discriminate on a label's presence, never on its text.

**The absence is not a unique identity, and this was the design's original
mistake.** VSCode renders one tab strip per *editor group*, each built the same
way, so a window with a split editor exposes **two** empty-description tab
groups — observed live on 1.136.2 with an editor split right. A walk that stops
at the first one returns an arbitrary group's tabs and silently drops the rest,
which contradicts the requirement of one row per open editor. So the walk
**collects every** empty-description tab group and concatenates their tab
buttons in tree order.

**Widening the anchor widens the exposure, so the shape is checked too.** The
absence alone would now admit any stray empty-description tab group — a webview
in the secondary sidebar, say — and admitting one would produce *wrong rows*,
which is the one failure this design does not permit (decision 6). A collected
group therefore contributes rows only if its children are tab buttons (the
`AXTabButton` subrole); a group whose children are anything else is skipped
entirely rather than partially read.

**The listing requires the default tab-bar setting, and pins it.**
`workbench.editor.showTabs` set to `single` or `none` renders no editor tab
strip at all — live 1.136.2 exposes *no* empty-description tab group in either
mode — so there is nothing to read and the listing is empty. Any configuration
using this listing pins `workbench.editor.showTabs` to `"multiple"` explicitly,
the same way it pins `editor.accessibilitySupport` and the grove-leaf row pins
`explorer.autoReveal`: the default is already the required value, so the pin
costs nothing and stops an unrelated preference change from emptying the panel.

The walk that finds the strips **prunes**: it never descends a list, text area,
text field, table, outline, toolbar or scroll bar. It no longer exits at the
first match — it must see every candidate group — so the cost figures in
decision 7, which were measured against an early-exiting walk, do not describe
it.

### 2. The native surface: two procedures, no VSCode knowledge in Swift

`(modaliser accessibility)` gains two procedures. Neither knows anything about
VSCode; the app-specific composition stays in Scheme, as that library's header
already promises.

- **`(ax-tab-rows BUNDLE-ID)`** → a list of alists, one per tab button of every
  *unlabelled* tab group of the focused window, in tree order:
  `((handle . N) (description . STR) (title . STR) (detail . STR)
  (selected . BOOL) (index . N))`, or the empty list when the app is not
  running, has no focused window, or the window has no qualifying tab group.
  Refreshes its own handle cache, so handles from a previous call go stale.
  `index` is the 0-based position in the concatenated row list.

  **`description` and `title` arrive separately and unjoined** (decision 1).
  Swift performs no name selection: it copies both attributes, substituting the
  empty string for an absent one. A row where both are empty is still a row —
  the Scheme join decides what to show, and the walk does not editorialise.

- **`(ax-press-handle HANDLE)`** → performs the accessibility press action on
  the handle's element, returning `#t` on success and `#f` on a stale handle or
  a refused action. This is **not** `ax-click-handle`, which synthesises a mouse
  click at the element's centre; that one needs the element on screen and moves
  the cursor, and it stays for the cases it was written for.

"Unlabelled tab group" is the anchor from decision 1 — both halves of it, the
absence and the tab-button shape — stated once, in the one place that walks the
tree.

**The handles must not be `ax-find-elements`' handles, and this is the one
place the design could go silently wrong.** That procedure allocates small
integers from 1 and **resets the counter on every call**
(`AccessibilityLibrary.swift:71`, `:98`), its own header saying handles stay
valid only until the next call. So a second accessibility read between the
gather and the press — another panel's provider on the same screen, a chip
paint, a hint overlay — would leave handle 3 pointing at a different element,
and the press would activate the wrong thing. That is precisely the failure this
whole design exists to avoid, arriving through the back door.

So `ax-tab-rows` keeps its elements in a **dictionary of its own**, which
`ax-press-handle` alone resolves against, and which `ax-find-elements` does not
clear. That much is obvious; the part that is not, and that the design first got
wrong, is what makes the two spaces **disjoint**.

**Two dictionaries do not make two handle spaces.** Two independently allocated
integer counters both hand out 3, so the same integer can be a live key in both
maps at once, and `ax-press-handle` handed an `ax-find-elements` handle would
resolve it — to an unrelated element — rather than refusing it. Separate maps
give separate *lookups*, not separate *values*, and the "right target or no
target" invariant needs the values.

So **the whole library allocates from one never-reset counter**, shared by both
maps. `ax-find-elements` keeps clearing *its* map on every call — its callers
rely on that — but it no longer restarts the numbering, so an integer names at
most one element for the lifetime of the process. Three consequences, and they
are the actual contract:

- a handle can **never** be recycled onto a different element, so a press is
  either right or a no-op;
- a handle whose element has gone away, or whose map was cleared, resolves to
  `#f`, and `ax-press-handle` returns `#f` rather than pressing something else;
- a handle belonging to the *other* space is not found in this one's map, so it
  is refused for the same reason a stale handle is — one code path, not a
  special case, and testable offline (see **Test seams**).

`ax-find-elements` and `ax-click-handle` keep their existing invalidate-on-call
behaviour, which their callers rely on; what they lose is the counter reset,
which nothing relied on.

### 3. The Scheme surface in `(modaliser apps vscode)`

Following the shape `project-provider` / `project-listing` established:

- **`(editor-tabs ROWS)`** — *pure*. Native rows → **Editor target**s, in strip
  order, each `((text . NAME) (detail . PATH) (active . BOOL) (handle . N))`.
  **This is where description-else-title is applied** (decision 1): `text` is
  the row's `description` when that is non-empty, else its `title`. Placing the
  join here rather than in the walk is what makes the rule testable — a fixture
  can carry one description-shaped row and one title-shaped row, which it cannot
  do if the two have already been collapsed below the bridge.
  Strip order is preserved and never re-sorted: unlike the Project listing,
  whose window enumeration returns stacking order and therefore had to be
  sorted to be learnable, the tab strip's order is the order the user sees and
  the order VSCode's own index commands use. Where a window holds several
  editor groups the rows are those strips concatenated in tree order
  (decision 1), so the sequence is still the on-screen one — left group's tabs,
  then the next — and the listing does not say where one group ends and the
  next begins (**Out of scope**).
- **`(editor-source)`** — impure: `(editor-tabs (ax-tab-rows bundle-id))`.
- **`(focus-editor-tab! target)`** — impure: presses the target's handle.
- **`(editor-provider 'single-alphabet … 'leader-alphabet … 'second-alphabet …
  ['panel-label STRING] ['enumerate THUNK])`** — the **Edge provider** a screen
  binds on its `'provider` slot. All three alphabets come from the user and none
  is defaulted (ADR-0021). `'enumerate` is the test seam, defaulting to
  `ax-tab-rows` on VSCode's bundle id.
- **`(editor-listing)`** — the block spec, closed over the per-**Visit**
  snapshot the provider took.

**State ids are namespaced `vscode-editor-target/…`**, followed by the handle,
which is unique across live rows by construction. Three namespaces are already
taken — `vscode-project-target/`, `paneru-strip-target/` and
`herdr-jump-target/`, enumerated out of the library tree rather than recalled,
which is how the third one was found. Enumerate them again before adding a
fourth; a collision here is silently last-wins (decision 5).

**A row with no handle has no action**, which is `jump-list`'s own test for
whether a row earns an edge: it still renders and still consumes its label, so a
transient miss cannot renumber the labels below it.

### 4. The row renderer is a judgement call, not a foregone one

The **Editor listing**'s content is a filename plus a long path — two columns
with very different lengths — where the **Project listing**'s is one long name
in the full width. That is closer to the **Strip listing**'s multi-column grid
than to `blocks/project-list`. Decide by looking at it, and apply the rule k4
recorded: **share machinery, duplicate presentation** — duplicated machinery
drifts silently, duplicated presentation drifts visibly. Whichever way it goes,
the lowering stays shared.

If the path is shown at all, it should be shown **shortened relative to the
window's Workspace**, since every row in a one-window listing shares that
prefix and the prefix is the least informative part of a forty-character path.

### 5. Several panels, one `'provider` slot: merge, and the merge must check

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

### 6. Degradation: an empty listing is the honest answer

Every miss produces **no rows**, never wrong rows. The cases, all of them
observed:

- **VSCode not running, or no focused window** — the native call returns empty.
- **A modal is up.** A window sitting behind a modal renders only the modal, so
  the tree holds only the modal. The workspace-trust prompt on a fresh folder is
  the one met here; a newly opened window can therefore answer nothing for as
  long as its prompt is up.
- **The tab bar is turned off.** `workbench.editor.showTabs` set to `single` or
  `none` renders no tab strip, so there is nothing to read — observed live on
  1.136.2 in both modes. A configuration using this listing pins the setting to
  `"multiple"` (decision 1), which is the default, so this case is reachable
  only by an explicit change the user made.
- **The anchor stops matching** — a future VSCode giving the tab strip its own
  aria-label. The listing goes empty rather than wrong, which is the right
  direction to fail, and no fixture test will catch it.
- **`editor.accessibilitySupport` is not `"off"`.** Reading the tree is what
  makes Chromium build one; under the `"auto"` default VSCode would then flip
  the editor into screen-reader-optimised rendering. Any configuration using
  this listing pins the setting explicitly, the same way the grove-leaf row
  pins `explorer.autoReveal` rather than resting on its default. The tab strip
  does not depend on the editor being accessible — with the pin in place the
  editor's own text area reports itself unavailable while the strip is fully
  populated — so the pin costs nothing.

What the screen does about an empty listing is the screen's call, and the screen
is the user's. A panel that renders no rows is the default; a configuration that
would rather say so can put a notice in the row source it composes.

### 7. Cost, and the `'next 'self` ruling stands

**What was measured, and by what.** A standalone `swiftc -O` walker run against
the live application on the focused window, repeated fifteen minutes apart with
the same result:

| | first call | median warm | nodes visited |
|---|---|---|---|
| pruned, early-exit walk | 28–32 ms | **3.1 ms** | 80 |
| whole-window walk, same windows | — | 12–80 ms | 291–2013 |

**Read that as a bound on the raw walk, and as nothing else.** Three gaps
separate it from the shipping path, and the design overstated the conclusion by
ignoring all three:

- **The instrument is not the implementation.** The figures come from a
  standalone binary that was not committed and cannot now be re-run. The
  shipping path is a native procedure marshalling alist rows into Scheme, on the
  main queue, under the eval lock, with the Scheme provider and `jump-list`
  lowering on top. None of that is in the number.
- **The walk being priced is not the walk being specified.** These runs
  early-exited at the first matching tab group; decision 1 now requires the walk
  to see every candidate group. The pruning is what bought the order of
  magnitude and it is unchanged, but the figure is a floor, not the cost.
- **"First call" is not cold.** The application had been running with its
  windows on screen for hours. A genuinely cold case — VSCode just launched, or
  its window parked on another space — is **not measured**.

So the claim this section previously made — that the Editor listing is cheaper
than the panel already on the screen, and that two panels stay inside one
panel's old budget — is **withdrawn**: it compared an instrument to two in-app
figures. What survives is that a pruned AX walk of this window can be cheap
enough to be uninteresting, and that pruning is worth roughly an order of
magnitude. **A build session measures the composed screen's own come-to-rest on
the shipping path before treating the cost as settled**, and a bad number there
is a finding worth its own leaf rather than something to absorb.

That does not reopen `'next 'self`, which is independent of all of the above.
The ban is not about the size of one gather; it is that keyboard capture filters
no auto-repeat, so a held key queues gathers faster than they drain. Compose the
ops on this screen **without** `'next 'self`, exactly as the paneru reference
composition does.

### 8. Terminals: not in this increment, and not for the reason first given

**A terminal listing is possible, and this design was wrong to call it
blocked.** The original ruling rested on three claims held out as independent
and individually fatal: no name on disk, nothing in the accessibility tree, and
no default-bound index command. They are not independent — all three are
premised on leaving the terminal panel *hidden* and reaching a terminal by
keybinding — and the middle one is false once that premise is dropped. With the
panel shown and two terminals running, live 1.136.2 exposes an `AXList`
described `Terminal tabs`, row groups named `Terminal 1 zsh` and
`Terminal 2 zsh`, and an `AXPress`-able descendant in each row; pressing the
first row's moved the live selection to it. That is the same shape the Editor
listing is built on. The disk-name blocker only bites a reader that was going to
read disk, and the unbound-index blocker only bites the numbered-slot option; on
an AX-press design neither applies.

**What is genuinely unresolved is sequencing, and it is a design question this
spec did not do.** A provider runs *before* the state it belongs to fires its
entry — `classify-and-snapshot` runs inside `move-to!` ahead of the entry call
(`fsm.sld:751`, `:873`) — so "show the panel, then enumerate it" does not fall
out of the current state shape. It needs either a two-step op (an entry that
shows the panel, and a second come-to-rest that lists it) or a change to that
ordering, and it needs a decision about
`terminal.integrated.tabs.hideCondition`, which defaults to `singleTerminal` and
so renders no tab list at all for a lone terminal. Pricing that is a leaf, not a
paragraph: see `vscode-terminal-listing`, which is cut ahead of the panel
implementation for exactly this reason.

**Until that lands, the screen keeps focus-then-cycle**, which needs no new
library surface: bind a strict-focus chord for the terminal — VSCode's own
`ctrl-\`` is a *toggle* and hides the panel when the terminal already has
focus, which is why a hand-bound strict-focus command is the right one — then
`focusNext` / `focusPrevious` to cycle. Both cycle commands are gated on the
terminal already having focus, so focus-then-cycle is one op in exactly the
sense editor cycling is.

**Which keys the screen carries is the user's call and is not settled here.**
The `t` and `i` rows were to come off to free their letters for two panel
alphabets; with the terminal panel deferred, whether `t` stays is a question for
the configuration rather than a consequence of this design (ADR-0021).

## Requirements

### Requirement: the Editor listing lists the frontmost window's tabs

The Editor listing SHALL contain one row per editor tab of the frontmost VSCode
window — across every editor group in it — in on-screen order, and no rows from
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

#### Scenario: the tab bar is turned off
- **WHEN** `workbench.editor.showTabs` is `single` or `none`
- **THEN** the listing is empty and no error is raised

### Requirement: a label activates the tab its row was read from

Pressing a row's **Jump label** SHALL activate the editor whose tab that row was
read from, or nothing at all. It SHALL never activate a different editor,
whatever has changed in the window since the rows were drawn.

#### Scenario: press a label
- **WHEN** the user presses the label on the row reading `beta.txt`
- **THEN** `beta.txt` becomes the active editor in that window

#### Scenario: the row is already active
- **WHEN** the user presses the label of the row that is already active
- **THEN** nothing changes and nothing is reported

#### Scenario: the tab was closed after the rows were drawn
- **WHEN** the user presses the label of a row whose tab has since been closed
- **THEN** nothing is activated and no error is raised

#### Scenario: a handle from the other accessibility space
- **WHEN** `ax-press-handle` is given a handle allocated by `ax-find-elements`
- **THEN** it refuses it exactly as it refuses a stale handle, and presses
  nothing

### Requirement: a miss produces no rows, never wrong rows

Where the tab strip cannot be read, the Editor listing SHALL be empty.

#### Scenario: no focused VSCode window
- **WHEN** VSCode has no focused window
- **THEN** the listing is empty and no error is raised

#### Scenario: the window is behind a modal
- **WHEN** the frontmost VSCode window is showing the workspace-trust prompt
- **THEN** the listing is empty and no error is raised

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

One seam per new surface, each as high as it goes, and none of them reaching the
live application.

- **The row join is pure and takes rows.** `editor-tabs` is a function from the
  native procedure's alist rows to **Editor target**s. Every behavioural test of
  the listing lands there, driven from a fixture captured off a real
  accessibility read — the same placement the stored-window-state parser has,
  and for the same reason: it makes "`swift test` reaches nothing outside the
  process" structural rather than disciplined. There is no accessibility call
  under test that could reach a live VSCode.
- **`'enumerate` is the provider's seam**, defaulting to the native read, so a
  test drives the whole provider — label assignment, lowering, state ids — from
  canned rows.
- **`jump-list-compose-providers` is tested by direct call** against synthetic
  providers whose targets are deliberately not editors, so an editor-shaped
  assumption cannot leak into the machinery. It is *not* pure — it reads the
  installed graph to widen its validation surface (decision 5) — which is
  exactly why it takes `'known-edges` and `'known-state-ids`: a test supplies
  both and the call is pure again. Four cases, one per raise: panel against
  panel on a key, panel against panel on a state id, panel against the owner's
  static edge, panel against a registered state id. Plus the clean merge, and a
  case asserting the raise names the colliding contributors rather than their
  positions.
- **The two native procedures get Swift-level tests only for their own
  bookkeeping** — handle allocation, stale-handle refusal, and **cross-space
  refusal**: a handle minted by `ax-find-elements` must be refused by
  `ax-press-handle` and vice versa. That last one is the test for decision 2's
  disjointness claim, and without it the claim is only an assertion. Their
  tree-walking behaviour is not testable offline and is not claimed to be.
- **The shipped example config is load-tested** by the existing example-loading
  test, so a composed screen that stops composing is a red suite.

**A control the fixture must supply, and the row type must allow.** The
description-else-title rule (decision 1) exists because the attribute the name
lands in varies at runtime. Write the fixture set with **both** shapes present —
one row carrying a description and no title, one carrying a title and no
description, and one carrying both, where the description must win — or the rule
is untested and an implementation reading only one attribute passes everything.
This is possible only because the native row keeps `description` and `title`
apart (decision 2); a row type that had already collapsed them into one `name`
would make the instruction unsatisfiable, which is how the first draft of this
design left it.

## Out of scope

- **A terminal listing** *in this spec*. It is possible and it is wanted; what
  it needs is a sequencing design, cut as `vscode-terminal-listing` ahead of the
  panel implementation. ADR-0026, decision 8.
- **A cross-window editor listing.** The accessibility tree gives a live
  window's rendered state, so there is no cheap way to list another window's
  tabs, and nothing has asked for one.
- **Editor *group identity*.** Every group's tabs are listed (decision 1), but
  the listing does not say which group a row belongs to, does not separate them
  visually, and offers no way to focus a group as such. The stored editor state
  carries the full group grid and the tab strips do not, so group structure is
  not in reach of this source. Nobody has asked for it, and the index-based
  commands are group-relative anyway, so surfacing groups would raise questions
  the current design does not have to answer. Note this is a narrower exclusion
  than the one the first draft wrote, which was being used — wrongly — to excuse
  listing only one group's tabs.
- **Reading the stored editor state at all.** Rejected in ADR-0026 with the
  condition that would reopen it.
- **Doing anything about a tab that has scrolled out of the strip.** All tabs
  are in the tree whether or not they are visible, and pressing one that is off
  screen works, because the press is an accessibility action rather than a
  click.

## See also

- ADR-0026 — why the accessibility tree, what the anchor actually identifies,
  and what is still open for terminals.
- ADR-0021 — no library authors a key, a label or an alphabet.
- `docs/specs/paneru-window-management.md` — the **Strip listing**, the first
  labelled listing, and the shape this one follows.
