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

**Editors get a listing; terminals do not.**

The **Editor listing** is the editor tabs of the frontmost VSCode window as
overlay rows, in tab-strip order, each carrying a **Jump label** that activates
that tab. Its rows come from the window's **accessibility tree**, read at
come-to-rest, and pressing a label performs an accessibility **press** on the
very element the row was read from — so the row and what it does come from one
snapshot and cannot disagree, which is the contract the Project listing and the
**Strip listing** already hold.

Terminals get no listing. Their names are not on disk, their tab list is not in
the accessibility tree in the state where you would want to jump to one, and
their index-focus commands ship unbound. What replaces the panel is the shape
editor cycling already uses: focus the terminal, then cycle. ADR-0026 records
the evidence and the trade-off for both halves.

A screen carrying more than one labelled panel composes its providers through a
new merge in `(modaliser jump-list)` that **raises** on a collision the engine
would otherwise resolve first-wins.

## Decisions

### 1. The row source is the accessibility tree, anchored on an absence

Rows are the tab buttons of the focused VSCode window's **editor tab strip**.
Per tab:

| field | where it comes from |
|---|---|
| name | the tab button's accessibility description, else its title |
| detail | the first child group's accessibility description — the file path, tilde-abbreviated under `$HOME`, absolute outside it, with VSCode's own decoration suffixes (` • Deleted`) already appended |
| active | the tab button's `selected` attribute |
| handle | the element itself, round-tripped to Scheme as an integer handle |

**The name must read description-then-title, in that order, and never one
alone.** Which of the two carries the name is not stable: the same tab group,
read twice fifteen minutes apart, put it in different attributes both times.

**The strip is found by the absence of an aria-label.** Every other tab group in
a VSCode window — the panel switcher, the activity bar, the secondary sidebar —
is a composite bar and carries the composite bar's own aria-label on its
description. The editor tab strip alone has an empty description. Matching the
label's *text* is not an option: it is localised and resolved from the
application's message table at runtime, so the English string is not a property
of the app. **Any future accessibility anchor in this application is subject to
the same rule** — discriminate on a label's presence, never on its text.

The walk that finds it **prunes and exits early**: it never descends a list,
text area, text field, table, outline, toolbar or scroll bar, and it stops at
the first tab group with an empty description. That is the whole of the cost
difference — see decision 7.

### 2. The native surface: two procedures, no VSCode knowledge in Swift

`(modaliser accessibility)` gains two procedures. Neither knows anything about
VSCode; the app-specific composition stays in Scheme, as that library's header
already promises.

- **`(ax-tab-rows BUNDLE-ID)`** → a list of alists, one per tab button of the
  focused window's *unlabelled* tab group, in tree order:
  `((handle . N) (name . STR) (detail . STR) (selected . BOOL) (index . N))`,
  or the empty list when the app is not running, has no focused window, or the
  window has no unlabelled tab group. Refreshes the handle cache exactly as
  `ax-find-elements` does, so handles from a previous call go stale.
  `index` is the 0-based position in the strip.

- **`(ax-press-handle HANDLE)`** → performs the accessibility press action on
  the handle's element, returning `#t` on success and `#f` on a stale handle or
  a refused action. This is **not** `ax-click-handle`, which synthesises a mouse
  click at the element's centre; that one needs the element on screen and moves
  the cursor, and it stays for the cases it was written for.

"Unlabelled tab group" is the anchor from decision 1, stated once, in the one
place that walks the tree.

**The handles must not be `ax-find-elements`' handles, and this is the one
place the design could go silently wrong.** That procedure allocates small
integers from 1 and **resets the counter on every call**, its own header saying
handles stay valid only until the next call. So a second accessibility read
between the gather and the press — another panel's provider on the same screen,
a chip paint, a hint overlay — would leave handle 3 pointing at a different
element, and the press would activate the wrong thing. That is precisely the
failure this whole design exists to avoid, arriving through the back door.

So `ax-tab-rows` allocates from its **own monotonic handle space, never reset**,
and `ax-press-handle` resolves only in that space. Two consequences that are the
actual contract:

- a handle can **never** be recycled onto a different element, so a press is
  either right or a no-op;
- a handle whose element has gone away resolves to `#f`, and `ax-press-handle`
  returns `#f` rather than pressing something else.

`ax-find-elements` and `ax-click-handle` keep their existing recycling
behaviour, which their callers rely on; the two spaces are separate and a handle
from one is never valid in the other.

### 3. The Scheme surface in `(modaliser apps vscode)`

Following the shape `project-provider` / `project-listing` established:

- **`(editor-tabs ROWS)`** — *pure*. Native rows → **Editor target**s, in strip
  order, each `((text . NAME) (detail . PATH) (active . BOOL) (handle . N))`.
  Strip order is preserved and never re-sorted: unlike the Project listing,
  whose window enumeration returns stacking order and therefore had to be
  sorted to be learnable, the tab strip's order is the order the user sees and
  the order VSCode's own index commands use.
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

### 5. Three panels, one `'provider` slot: merge, and the merge must check

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

**`(jump-list-compose-providers PROVIDER …)`** → one provider. It calls each
argument with the owner id it was given, appends their `'edges` and `'states`
in argument order, and **raises** naming both contributors if two edges share a
key trigger or two states share an id.

Raising rather than dropping, because a dropped edge is a dead key with no
diagnostic: the key still works, bound to whichever panel contributed first, so
the user presses a terminal's label and focuses a project. That is a silent
wrong dispatch, which is the failure this whole leaf exists to avoid.

**A raise at come-to-rest is safe on both dispatch paths, and this was checked
rather than assumed.** The provider runs inside the leader handler on the press
that opens the screen, and inside the catch-all handler on every press after
that. The host wraps both: an error from the leader handler is logged and
capture is still finalised, so the buffered keys are re-injected and the tap is
released; an error from the catch-all is logged and the catch-all is
*deregistered* as an explicit stuck-modal recovery. So the screen fails to open,
loudly in `/usr/bin/log` and visibly to the user, and nothing wedges.

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

Measured with an optimised build against the live application, on the focused
window, repeated fifteen minutes apart with the same result:

| | first call | median warm | nodes visited |
|---|---|---|---|
| pruned, early-exit (decision 1) | 28–32 ms | **3.1 ms** | 80 |
| whole-window walk, same windows | — | 12–80 ms | 291–2013 |

Against the Project listing's own source — the window enumeration at 8–29 ms
warm and past 200 ms cold — **the Editor listing is cheaper than the panel
already on the screen**. Two panels together stay inside one panel's old budget.

That does not reopen `'next 'self`. The ban is not about the size of one gather;
it is that keyboard capture filters no auto-repeat, so a held key queues gathers
faster than they drain. Compose the ops on this screen **without** `'next 'self`,
exactly as the paneru reference composition does.

The "first call" figure is for an application that is running with its windows
on screen and has simply not been queried for a while. A genuinely cold case —
VSCode just launched, or its window parked on another space — is **not
measured**, and a build session should not assume the warm number generalises to
it.

### 8. Terminals: no listing, and what goes in its place

ADR-0026 records why. What a screen should do instead needs no new library
surface at all: bind a strict-focus chord for the terminal — VSCode's own
`ctrl-\`` is a *toggle* and hides the panel when the terminal already has focus,
which is why a hand-bound strict-focus command is the right one — and then
`focusNext` / `focusPrevious` to cycle. Both cycle commands are gated on the
terminal already having focus, so focus-then-cycle is one op in exactly the
sense editor cycling is.

**The `t` row therefore stays on the screen.** It was to come off to free `t`
for a terminal alphabet; with no terminal alphabet there is nothing for it to
make way for. Whether `i` comes off depends on whether the user wants a
letter from that region for the Editor listing's alphabet — a key, and so
theirs.

## Requirements

### Requirement: the Editor listing lists the frontmost window's tabs

The Editor listing SHALL contain one row per editor tab of the frontmost VSCode
window, in tab-strip order, and no rows from any other window.

#### Scenario: several tabs open
- **WHEN** the frontmost VSCode window has three editor tabs open
- **THEN** the listing shows three rows, in the order the tab strip shows them

#### Scenario: another window has tabs too
- **WHEN** a second VSCode window is open with different tabs
- **THEN** none of that window's tabs appears in the listing

### Requirement: a label activates the tab its row was read from

Pressing a row's **Jump label** SHALL activate exactly the editor whose tab that
row was read from, regardless of what has changed in the window since the rows
were drawn.

#### Scenario: press a label
- **WHEN** the user presses the label on the row reading `beta.txt`
- **THEN** `beta.txt` becomes the active editor in that window

#### Scenario: the row is already active
- **WHEN** the user presses the label of the row that is already active
- **THEN** nothing changes and nothing is reported

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
when two of their edges share a key trigger or two of their states share an id.

#### Scenario: overlapping alphabets
- **WHEN** a screen composes two providers whose alphabets share a key
- **THEN** the composition raises rather than binding the key to one of them

#### Scenario: disjoint alphabets
- **WHEN** the alphabets and state-id namespaces are disjoint
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
- **`jump-list-compose-providers` is pure** and tested by direct call against
  synthetic providers whose targets are deliberately not editors, so an
  editor-shaped assumption cannot leak into the machinery. Both the merge and
  each raise get a case.
- **The two native procedures get Swift-level tests only for their own
  bookkeeping** — handle allocation, stale-handle refusal — as the existing
  accessibility procedures do. Their tree-walking behaviour is not testable
  offline and is not claimed to be.
- **The shipped example config is load-tested** by the existing example-loading
  test, so a composed screen that stops composing is a red suite.

**A control the fixture cannot supply.** The description-else-title rule (
decision 1) exists because the attribute the name lands in varies at runtime. A
fixture pins whichever one the capture happened to hold, so the test proves
nothing about the other. Write the fixture set with **both** shapes present —
one row named by description, one by title — or the rule is untested.

## Out of scope

- **A terminal listing.** ADR-0026.
- **A cross-window editor listing.** The accessibility tree gives a live
  window's rendered state, so there is no cheap way to list another window's
  tabs, and nothing has asked for one.
- **Editor *groups*.** The stored editor state carries the full group grid; the
  tab strip does not, so a split editor's second group is not distinguished in
  the listing. Nobody has asked for it, and the index-based commands are
  group-relative anyway, so surfacing groups would raise questions the current
  design does not have to answer.
- **Reading the stored editor state at all.** Rejected in ADR-0026 with the
  condition that would reopen it.
- **Doing anything about a tab that has scrolled out of the strip.** All tabs
  are in the tree whether or not they are visible, and pressing one that is off
  screen works, because the press is an accessibility action rather than a
  click.

## See also

- ADR-0026 — why the accessibility tree, and why terminals get nothing.
- ADR-0021 — no library authors a key, a label or an alphabet.
- `docs/specs/paneru-window-management.md` — the **Strip listing**, the first
  labelled listing, and the shape this one follows.
