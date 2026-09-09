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
