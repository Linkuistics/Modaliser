# vscode-part-enumeration-k6

## Goal

Settle **how Modaliser learns what is open inside the frontmost VSCode window** —
which editors (tabs) and which terminals, with names good enough to put on an
overlay row — and whether it can be learned reliably enough to build on at all.

Deliver the decision, its evidence, and the seam it lands behind.
`vscode-part-panels-k7` builds on the answer; this leaf does not build the
panels.

## Context

**Why this is a design leaf and not the first half of the impl leaf.** The
project panel that shipped in `vscode-project-panel-k4` had its row source
already: `list-windows` gives every open VSCode *window*, and a window's project
falls out of its title. Nothing in reach gives the parts *inside* a window.
VSCode has no scripting dictionary and no IPC socket worth the name — that
sentence opens `apps/vscode.sld`'s header and it is exactly the constraint that
made this leaf necessary. So the row source has to be discovered, and the
candidates have materially different failure modes. Choosing between them under
time pressure inside a build session is how a library ships primitives that
resolve and permanently return null (`CLAUDE.md` records the one that did).

### Three candidate sources, and what is already known about each

**1 — The per-workspace state database.** Confirmed present and current during
`vscode-project-panel-k4`, so start here:

    ~/Library/Application Support/Code/User/workspaceStorage/<hash>/state.vscdb

a SQLite file with an `ItemTable` of key/value rows. Two keys look decisive and
both were seen to exist on the human's machine, with the file written minutes
before it was read:

  - `memento/workbench.parts.editor` — the editor part's serialised state,
    which is where open tabs live.
  - `terminal.integrated.layoutInfo` — the terminal layout, tabs and all.

The `<hash>` directory is joined to a workspace by its own `workspace.json`,
which carries the `folder` URI — and `(modaliser apps vscode)` already knows the
frontmost window's folder path (`focused-workspace-path`), so the join key
exists. **The shapes under those two keys were NOT established** — a first look
found the terminal value's `terminals` entries were not the flat objects a naive
read assumed, and the editor memento nests its editors behind serialised inner
JSON. Establishing both shapes is this leaf's main empirical work.

Open questions this source raises, all of which need answering before it can be
chosen: does SQLite reading even exist in reach — is there a native primitive, a
portable seam, or would this mean shelling out to `sqlite3` through
`(modaliser shell)`? How stale is it (the sibling `storage.json` is written on
window state *change*, and k2 accepted that; is this the same)? What does it say
for an unsaved buffer, a diff view, a webview tab, a settings tab?

**2 — The accessibility tree.** VSCode is Electron, so its tabs and terminal
tabs are DOM rendered into an AX tree. Modaliser already has AX machinery and
already knows Electron/Chromium AX is quirky — `CONTEXT.md` and the ADRs
document cold-AX resolution and the EUI flip at length, and `CLAUDE.md` says to
read them before touching `WindowManipulator`. Cost is the concern: k4 measured
the plain window sweep at 8-29ms warm and past 200ms cold, and a deep descent
into one window's tab strip is a different and unmeasured shape. **Measure it in
a release build** — k4's own measurements section records that interpreted
stages inflate 2-5x and mislead about which term dominates.

**3 — Do not enumerate at all.** VSCode ships `workbench.action.openEditorAtIndex1..9`
and `workbench.action.terminal.focusAtIndex1..9`, so a panel could offer
*numbered slots* with no names. This is the honest fallback and it must be
priced rather than dismissed: it needs no source, cannot go stale, and costs
only that the rows say "Editor 3" instead of the filename. If sources 1 and 2
both prove unreliable, this is the answer — and it is a better answer than a
name that is sometimes wrong.

### The architectural question this leaf must also settle

**A state has ONE `'provider` slot, and the VSCode screen is about to want
three jump-label panels on it** — projects (shipped), terminals, editors. This
is not a detail for the impl leaf to discover; it decides what
`(modaliser jump-list)`'s surface has to be.

The shape that looks right, unverified: `jump-list-provider-result` already
returns `((edges . …) (states . …))`, so three results could be merged by
appending both lists, given two preconditions the screen can meet — the key
pools are disjoint (the human has already chosen `a s d f g` / `t y u i o` /
`h j k l ;`) and the state ids are namespaced per caller (they are:
`vscode-project-target/…`, `paneru-strip-target/…`). If that holds, the answer
is a small `provider-compose`-shaped addition, and the leaf should say where it
lives and what it does about a collision — silently dropping a duplicate edge
and raising on one are very different bugs to have.

Check what `fsm.sld`'s `check-new-edge!` already does about duplicate triggers
before designing around the problem; it may already refuse, in which case the
question is what the composition should do *before* handing it over.

### Contracts a solution has to honour

- **Portability (ADR-0023).** Anything reaching outside the process goes through
  `(modaliser shell)` or `(modaliser http)`, never a `…-native` import. If the
  answer is `sqlite3`, that is a spawn on the dispatch path and its cost is part
  of the decision, not a footnote — k4's provider was accepted partly *because*
  it has no subprocess in it, unlike paneru's ~34ms one.
- **Test seams.** k2 and k4 both put the seam as high as it goes: a pure
  function over the source's *text*, driven from a fixture captured off a real
  file, with the read itself a single call no test exercises. That is what makes
  "`swift test` reaches nothing outside the process" structural rather than
  disciplined. Whatever source wins, place its seam the same way and say so.
- **Decision-free libraries (ADR-0021).** Keys, labels and alphabets are the
  user's. The human said so again in this session, unprompted: *"this should all
  be configurable in the user's config."*

## Done when

- The source for **open editors** and the source for **open terminals** are each
  chosen, with the shapes actually established against real data on the human's
  machine rather than assumed — including what each says for the awkward cases
  (unsaved buffer, diff view, webview, settings tab; a split terminal).
- Its **staleness and failure modes are stated**, in the same eyes-open way k2
  stated `storage.json`'s, along with what the screen should do on a miss.
- The **cost on the dispatch path is measured in a release build**, against k4's
  numbers, with the ruling on `'next 'self` restated or revised.
- The **three-panels-one-provider question is answered**, concretely enough that
  k7 implements rather than redesigns.
- The **test seam is placed** and named.
- Delivered as a spec under `docs/specs/`, an ADR set under `docs/adr/`, or
  both, per `ADR-FORMAT.md`'s when-to-write test. If the answer turns out to be
  candidate 3 — no enumeration, numbered slots — that is a *positive* finding
  and clears the bar: it records what was tried and why it was rejected.
- If the honest answer is that this is not worth building, say so and stop. That
  is a legitimate outcome of a design leaf and cheaper here than in k7.

## Notes

- **Read, don't run** is grove's constraint 2 for bootstrapping, not a ban on a
  spike: establishing a file format needs looking at a real file, and this leaf
  is chartered to do that. Keep the spike out of the library tree — a scratch
  script, not a half-built seam.
- `sqlite3` is on the machine (it was used to list the `ItemTable` keys during
  `vscode-project-panel-k4`). That says the *investigation* is cheap; it does
  not say shelling out at runtime is the right answer.
- The human runs four VSCode windows, one per grove worktree. Whatever is
  chosen must answer for the **frontmost** window specifically — the same
  "*this* window's" requirement `grove-leaf-reveal-k3` met, and it met it by
  joining the window title to the stored state rather than by trusting either
  alone.
- VSCode version at the time of writing is 1.136.2. Cite it in whatever you
  establish, as `apps/vscode.sld`'s header does — these are undocumented
  internals and a version-less claim about them ages badly.

---

## Decisions (running log)

All VSCode facts below are for **1.136.2** (the shipped
`/Applications/Visual Studio Code.app`, `package.json` version read at the
start of the session), established by reading the shipped bundle and by
probing the live app — never from memory or documentation.

### The terminal layout file cannot name a terminal. Established, not assumed.

`terminal.integrated.layoutInfo` was the leaf's most promising lead and it is
a dead end, for a structural reason rather than a formatting one.

The value on this machine, from the live `state.vscdb` of the frontmost
window:

```json
{"workspaceId":"320d…","tabs":[{"isActive":true,"activePersistentProcessId":3,
  "terminals":[{"relativeSize":1,"terminal":3}]}],"background":[]}
```

Every one of the 19 workspaces that has the key has exactly that shape — a
`terminals` array of `{relativeSize, terminal}` where `terminal` is a
**persistent-process id integer**. That is not a sample artefact; it is what
the serialiser emits. From the bundle, `TerminalGroup.getLayoutInfo`:

```js
terminals: t.map(n => ({ relativeSize: …, terminal: n.persistentProcessId || 0 }))
```

The name is never written because it is never the workbench's to write. On
restore the workbench asks the **pty host** for the layout
(`getTerminalLayoutInfo`), and the pty host substitutes a full attach-target
object — title, cwd, icon — for that integer, over IPC. So the names exist
only in a process Modaliser cannot address, and the disk carries the join key
and nothing else.

**Consequence:** a named Terminals panel has no on-disk source. This is the
first of three independent blockers below.

### The editor memento is a real source, and it is up to 60 seconds stale

`memento/workbench.parts.editor` does carry everything a listing needs. Its
shape, from the live file (nesting matters, and the leaf was right that a
naive read misses it):

```
editorpart.state
  .serializedGrid.root      recursive {type:"branch"|"leaf"}
     leaf .data.id          the editor GROUP id
     leaf .data.editors[]   {id: <factory id>, value: <JSON *string*>}
     leaf .data.mru[]
  .activeGroup, .mostRecentActiveGroups
```

`value` is serialised inner JSON whose shape depends on the sibling `id`.
Three factory ids appear across the 28 workspaces on this machine:

| factory id | inner keys | where the name is |
|---|---|---|
| `workbench.editors.files.fileEditorInput` | `resourceJSON`, `encoding` | **nowhere** — only the path |
| `workbench.editors.untitledEditorInput` | `resourceJSON`, `encoding` | `resourceJSON.path` = `Untitled-1` |
| `workbench.editors.webviewEditor` | 12 keys incl. `title`, `viewType`, `editorResource` | `title` |

So a reader needs a **per-factory** name rule, and a factory it has never seen
(diff, settings, notebook, merge, custom) degrades to "no name" rather than to
a wrong name. That is survivable.

What is not survivable is the write cadence. The memento is written by
`EditorPart.saveState()`, which is a `Component` hook registered on
`storageService.onWillSaveState`. That event fires from exactly three places:

- `AbstractStorageService`'s idle flush, `DEFAULT_FLUSH_INTERVAL = 60 * 1e3`;
- `hostService.onDidChangeFocus(a => { a || storageService.flush() })` — i.e.
  the window **losing** focus;
- shutdown / profile switch.

A four-minute poll of the live `state.vscdb` (120 samples, 2 s apart) recorded
**zero** writes while the window sat idle, which is consistent: the flush runs
but writes nothing when no value changed.

**So the editor list on disk lags reality by up to a minute**, and the blur
flush cannot rescue the press that needs it — F17 fires while VSCode is still
frontmost, and the provider reads at come-to-rest, before any blur the overlay
might cause.

### The action half is free, which raises the bar rather than lowering it

`workbench.action.openEditorAtIndex1..9`, read off its registration:

```js
for (let e = 0; e < 9; e++) { let t = e, i = e + 1;
  registerCommandAndKeybindingRule({ id: ejo + i, weight: 200, when: void 0,
    primary: 512 | o(i), mac: { primary: 256 | o(i) }, handler: n => s(n, t) }) }
```

`256` is `KeyMod.WinCtrl` — **ctrl-1 … ctrl-9 on macOS, with no `when`
clause**, so the chord is live from anywhere in the workbench. Jumping to the
Nth editor therefore needs no enumeration at all.

Two caveats, both read off the source: the index is **active-group relative**
(`activeEditorPane.group.getEditorByIndex`), and the ids are **not** in the
default `terminal.integrated.commandsToSkipShell` array — unlike
`previousEditor`/`nextEditor`, which are, and which is why k5's `[`/`]` survive
the terminal. So ctrl-3 pressed while the integrated terminal has focus reaches
**zsh**, not the workbench.

This inverts the design question. Enumeration is not needed to *jump*; it is
needed only to *label*. And a label that disagrees with the index beside it is
worse than no label, because the jump still happens — to the wrong file. That
is what rules the 60-second-stale memento out for editors: paired with an index
its failure is a silent wrong jump.

### Editors come from the accessibility tree. Measured: ~3 ms warm.

The AX tree carries the editor tab strip, and the whole listing falls out of
it. Probed with a `swiftc -O` walker against the live app:

- each tab is `AXRadioButton` / **`AXSubrole = AXTabButton`**;
- its name is in `AXDescription` **or** `AXTitle` — the split is *not* stable,
  it varied between two reads of the same tab group ten minutes apart, so a
  reader must take `description` else `title`;
- its first child `AXGroup`'s `AXDescription` is the **path**
  (`~/Development/…/06-design--…md`, tilde-abbreviated under `$HOME`, absolute
  outside it, with decoration suffixes like ` • Deleted` appended);
- `AXSelected` marks the active tab;
- tab order is the tab-strip order, which is the order `getEditorByIndex` uses;
- every tab exposes **`AXPress`**.

**Finding the editor strip has a clean rule, and it is an absence.** Every
*other* `AXTabGroup` in the window — the panel switcher, the activity bar, the
secondary sidebar — carries `AXDescription = "Active View Switcher"`. That
string is `activityBarAriaLabel` from
`vs/workbench/browser/parts/compositeBar` (found via `out/nls.metadata.json`),
so it is **localised** and matching its text would break outside English.
Matching its *absence* does not: the editor tab strip is the only `AXTabGroup`
with an empty `AXDescription`. Verified in two independent windows.

**AXPress works and switches tabs.** In a scratch window with
alpha/beta/gamma open and gamma active, `AXUIElementPerformAction(tab,
kAXPressAction)` returned `.success` in **0.06 ms** and `AXSelected` moved to
alpha. Pressing the already-selected tab is a no-op, as it should be. This is
not `ax-click-handle`, which synthesises a mouse click at the element's centre
and therefore needs the tab to be on screen and moves the cursor; k7 wants a
new `ax-press-handle` over `AXUIElementPerformAction`.

**Cost, `swiftc -O`, focused window, 15 consecutive runs:** first call
**31.6 ms**, median **3.1 ms**, min 2.7 — visiting **80 AX nodes**. Two things
buy that: pruning (never descend `AXList` / `AXTextArea` / `AXTextField` /
`AXTable` / `AXOutline` / `AXToolbar` / `AXScrollBar`) and early exit on the
first empty-description tab group. Unpruned whole-window walks of the same
windows measured 12–80 ms (median 36 and 78 ms on the two largest), so the
pruning is the whole difference, not a micro-optimisation.

Against k4's baseline — the projects provider's `list-windows` sweep at 8–29 ms
warm and past 200 ms cold — an editors provider is **cheaper than the one
already on the screen**.

### Terminals: no panel. Three independent blockers, any one of which is fatal.

1. **No name on disk** — the layout file finding above.
2. **Nothing in the AX tree, in the state that matters.** AX mirrors the
   *rendered* DOM. All five of the human's windows had `{"terminal":{…,
   "isHidden":true}}`, and a hidden panel contributes nothing. Even shown,
   `terminal.integrated.tabs.hideCondition` defaults to `"singleTerminal"`, so
   the tab list is absent for one terminal — which is every one of the human's
   windows. Forced open with three terminals in a scratch window the list
   *does* appear, as `AXList` with `AXDescription = "Terminal tabs"` (also
   localised: `terminal.tabs` from `terminalTabsList`) holding rows described
   `"Terminal 2 zsh"`, `"Terminal 3 zsh"`, `"Terminal 4 zsh"`. So the source
   exists exactly when the panel is already open and already showing its tabs —
   precisely not the case where you want to jump to a terminal.
3. **No default-bound focus command.** `workbench.action.terminal.focusAtIndex1..9`
   register with **`primary: 0`** — no keybinding at all, on any platform. Same
   trap as `focusActiveEditorGroup` (k2's finding): a synthetic keystroke cannot
   reach an unbound command. `focusNext` / `focusPrevious` exist but are gated
   `when: terminalFocus && !editorFocus`, so they only cycle once the terminal
   already has focus.

**Ruling: k7 does not build a Terminals panel.** The honest replacement is the
k5 shape — the human's `ctrl+alt+t` strict-focus binding, then
`focusNext`/`focusPrevious` — which needs no enumeration, no new library
surface, and nothing that can go stale. If the human later wants numbered
terminal slots, the cost is nine hand-authored `keybindings.json` entries, and
that is their call to make with the price in front of them.

### The `t` row stays on the screen

k7's charter takes `t` (Terminal) and `i` (Editor) off the screen to free those
keys for the terminal alphabet. With no Terminals panel there is no terminal
alphabet, so `t` has nothing to make way for and should stay. Whether `i` goes
depends on whether the human wants `h j k l ;` for the Editors panel; that is a
key, so it is theirs (ADR-0021).

### Three panels, one `'provider` slot: merge, and the merge must check

The engine will not catch a collision. Read out of `fsm.sld`:

- `classify-and-snapshot` folds provider edges in with `(append static-edges
  extra-edges)` and runs **no** `check-new-edge!` over the result;
- `fsm-step!` resolves a key with `find` over `%fsm-visit-live-edges` —
  **first match wins, silently**;
- `install-provided-states!` builds a hash table keyed by id, so a duplicate
  state id is **last-wins, silently**;
- `check-new-edge!` *does* run inside `provided-state`, so a single prefix
  state's own second-key edges are checked — but nothing checks across two
  provider results.

So appending two results' `'edges` and `'states` is mechanically correct given
disjoint key pools and namespaced state ids, and produces a silent
wrong-dispatch when either precondition fails. The composition therefore has to
assert what the engine does not.

`(modaliser jump-list)` gains `jump-list-compose-providers`, taking N providers
(each the 1-arg `owner-id → result` procedure a `'provider` slot takes) and
returning one. It calls each with the owner id, appends the `'edges` and
`'states` lists in argument order, and **raises** on a duplicate key trigger or
a duplicate state id, naming both contributors. Raising rather than dropping,
because a dropped edge is a dead key with no diagnostic: the key still works,
bound to whichever panel contributed first, so a terminal's label focuses a
project.

**The ADR-0022 analogy I first reached for is wrong, and checking it is what
made raising affordable.** ADR-0022 is about a config that fails to *load*,
sequenced by the host across two top-level evaluations; a provider raising on a
keypress is a different path with a different guard. The actual guard is in
`KeyboardLibrary`: an error from the leader handler is logged and
`finalizeCapture` still runs, so buffered keys are re-injected and the tap is
released; an error from the catch-all is logged and the catch-all is
*deregistered* as an explicit stuck-modal recovery. So the screen fails to open,
loudly in `/usr/bin/log`, and nothing wedges. Raising is safe because of that,
not because of ADR-0022.

### Where the seam goes

Same shape k2 and k4 placed, one level out. The **pure** function is
`rows → items`: a list of `((name . STR) (detail . STR) (selected . BOOL)
(handle . N))` in, chooser/jump items out, and every test drives that with a
fixture captured from a real AX read. The AX read itself is one native call
(`ax-editor-tabs`) that no test exercises — so "`swift test` reaches nothing
outside the process" stays structural, exactly as ADR-0023 requires. The native
primitive gets its own Swift-level test only for handle bookkeeping, as
`AccessibilityLibrary`'s existing procedures do.

### `editor.accessibilitySupport` is a precondition, and it is already met

Reading VSCode's AX tree is what makes Chromium build one, and VSCode's
`editor.accessibilitySupport: "auto"` would then flip the editor into
screen-reader-optimised rendering. The human's `settings.json` already pins
`"editor.accessibilitySupport": "off"`, and the tree confirms it — the editor's
`AXTextArea` reads *"The editor is not accessible at this time. To enable
screen reader optimized mode…"* while the tab strip is fully populated. So the
tabs do not depend on the editor being accessible, and the pin costs nothing.
It is the same kind of explicit pin k3 made for `explorer.autoReveal`, and the
shipped example must say so.

### Two corrections found by checking, and one hazard found by enumerating

Recorded because each was a confident claim that did not survive its own check,
and because the third is a design hazard rather than a wording slip.

- **The ADR-0022 analogy was wrong** — corrected above, at the decision it
  belongs to.
- **The state-id namespace list was incomplete.** "`vscode-project-target/` and
  `paneru-strip-target/` are taken" is what the leaf's own charter said and what
  I copied. Enumerating the tree instead of sweeping that list found a **third**,
  `herdr-jump-target/`. Nothing would have gone wrong here — the new namespace
  collides with none of them — but the habit is what matters, and a collision in
  this position is silently last-wins.
- **`ax-find-elements`' handles are recycled from 1 on every call**, its own
  header saying so. An editor row's handle taken at come-to-rest would therefore
  be re-pointed at a different element by *any* other accessibility read before
  the press — another panel's provider, a chip paint, a hint overlay — and the
  press would activate the wrong thing. That is the exact failure the whole
  design is built to avoid, arriving through the back door. Not reachable on the
  screen as it stands today (the Projects panel focuses by window id and takes no
  handles), which is why it is latent rather than live, and why it needed
  enumerating rather than noticing. The spec now requires `ax-tab-rows` to
  allocate from its own **monotonic, never-reset** handle space so a handle
  cannot be recycled onto a different element; a dead handle then resolves to
  `#f` and the press is a no-op.

### The disjointness requirement is data-dependent, which decides *where* the check goes

Read out of `jump-labels.sld`: a panel's edges on the owner state are one per
surviving single-key label **plus one per promoted leader**, and leaders are
promoted only when the panel has more rows than its single alphabet covers. So

- the pool two panels must keep disjoint is `single-alphabet ∪ leader-alphabet`,
  not the single alphabets the human named (`a s d f g` / `h j k l ;`);
- and whether they actually collide depends on **how many rows each panel has
  this Visit**.

Two panels sharing a leader key therefore coexist happily until one of them
grows past its singles, and then collide. A config-load validation cannot see
that — at load there is no row count. This is the argument for checking at the
merge, at come-to-rest, and it is stronger than the one I first wrote down.
