# vscode-terminal-listing-k10

## Goal

Decide how the F17 VSCode screen lists the frontmost window's **terminals**, so
that `vscode-part-panels-k7` can build a Terminal panel beside the Editor panel
without reopening a source or sequencing question. Deliver the decision as an
edit to `docs/specs/vscode-editor-listing.md` and a rework of ADR-0026 in place
— not a second spec and not a second ADR.

## Context

**This leaf exists because a review overturned a "blocked" ruling.**
`vscode-part-enumeration-k6` recorded three independent, individually fatal
blockers against a terminal listing. `vscode-part-enumeration-k8` showed they
are one premise restated three times — *the terminal panel stays hidden and a
terminal is reached by keybinding* — and that the tree half is simply false once
that premise is dropped. `vscode-part-enumeration-k9` corrected the record and
cut this leaf rather than designing here, because what is left is a real design
with a UX cost rather than a repair.

**What is already established, so you do not re-derive it.** All of this is in
ADR-0026 and confirmed live on VSCode 1.136.2:

- With the terminal panel **shown** and two terminals running, the window's
  accessibility tree carries an `AXList` described `Terminal tabs`, row groups
  named `Terminal 1 zsh` / `Terminal 2 zsh`, and an `AXPress`-able descendant
  per row. Pressing one moves the live selection. That is the same shape the
  Editor listing is built on, and `ax-press-handle` is the same primitive.
- With the panel **hidden**, there is nothing — AX mirrors *rendered* DOM.
- `terminal.integrated.tabs.hideCondition` defaults to `singleTerminal`, so a
  window with one terminal renders no tab list even with the panel shown.
- `workbench.action.terminal.focusAtIndex1..9` ships with `primary: 0` — no
  keybinding on any platform — so the numbered-slot shape is not available here
  the way it is for editors.
- The disk source is structurally dead for terminals: `layoutInfo` carries
  persistent-process ids, and the names live in the pty host (ADR-0026).

**The one real question is sequencing.** A state's provider runs *before* that
state's entry fires — `classify-and-snapshot` is called inside `move-to!` ahead
of the entry (`fsm.sld:751`, `:873`) — so "show the panel, then enumerate it"
does not fall out of the current state shape. Price at least these, and say
which and why:

- **A two-step op.** An `entry` on some state shows the terminal panel; the
  listing happens at the *next* come-to-rest. Costs the user a step and puts a
  visible panel on screen as a side effect of asking what is open.
- **Changing the ordering** so a state's entry can run before its provider.
  Cheap-looking and the most dangerous: `classify-and-snapshot` is on every
  dispatch path of every screen, and the paneru and Projects panels depend on
  the current order. This is a change to the engine's contract, not to a screen.
- **Pinning `hideCondition` to `always`** so a single terminal still renders a
  row. A settings pin is the established idiom here (`explorer.autoReveal`,
  `editor.accessibilitySupport`, `workbench.editor.showTabs`), but this one
  changes what the human *sees* in VSCode rather than only what Modaliser reads.
- **Not building the panel**, and saying so with the evidence. The interim
  answer — a strict-focus chord then `focusNext`/`focusPrevious` — is real and
  already on the screen. If the two-step is worse than that in use, this is the
  honest outcome, and it is a decision rather than the mistaken impossibility
  ADR-0026 used to record.

**Show-the-panel is itself a side effect with a toggle hazard.** VSCode's
`ctrl-`` ` is a toggle and *hides* the panel when the terminal already has
focus (BRIEF.md, On the horizon), so whatever shows the panel must be a strict
show, not that chord.

**The human asked for this panel by name**, and for `t` and `i` to come off the
screen to free their letters for two alphabets (k7). If the design lands on
"no panel", say what happens to that request.

## Done when

- `docs/specs/vscode-editor-listing.md` carries the terminal decision beside the
  editor one — its own decision section, requirements, and test seams — or
  records the rejection with the evidence that settles it.
- ADR-0026 is reworked **in place** to state what now binds; it is one record
  covering both parts of one source-selection question and stays one
  (`ADR-FORMAT.md`). No superseding record.
- The sequencing choice is stated with what it costs, including whether the FSM
  ordering is touched — and if it is, what that does to the paneru and Projects
  panels.
- `vscode-part-panels-k7` is reconciled: it must not have to decide
  anything this leaf was cut to decide.
- Nothing under `lib/modaliser` gains a key, a label or an alphabet as a result
  (ADR-0021), and no `…-native` import (ADR-0023).

## Notes

- **Reading a live VSCode is in scope and is how this gets settled.** k6 and k8
  both drove the app with a scratch window and cleaned up after themselves — a
  temporary folder, the window closed by pressing its close button, the
  `workspaceStorage` directory removed. Do the same. Accessibility reads from a
  shell work on this machine without extra grants; a small `swiftc -O` program
  is the instrument both prior sessions used.
- **Keep the instrument this time.** k6's performance figures came from a
  standalone binary that was never committed and cannot be re-run, which is why
  its cost conclusion had to be withdrawn (`vscode-editor-listing.md`,
  decision 7). If you measure anything, commit what measured it.
- The Editor listing's own design is the shape to follow and to share with:
  `ax-tab-rows` / `ax-press-handle`, the pure row join, the `'enumerate` seam,
  and `jump-list-compose-providers`. A terminal listing that needs a *third*
  native procedure is a smell worth arguing about before writing it.

## Decisions (running log)

### Finding — the FSM ordering question is answerable without touching the engine

The brief's second option (changing provider/entry ordering) does not need to be
priced as an engine change, because the ordering it wants **already exists** in
the state shape. `classify-and-snapshot` returns `'transient` and runs **no
provider** the moment a state carries an `auto` edge (`fsm.sld:752-755`), and
`move-to!`'s transient arm fires that state's `entry` and *then* trampolines to
the auto target, where the target's provider runs (`fsm.sld:884-896`). So a
transient "show the panel" state with an auto edge into the resting listing
state fires entry-before-provider with no engine change and no extra key press.

**This does not rescue the show-then-enumerate design, and the reason matters.**
The obstacle is not ordering inside the FSM; it is that showing the panel is
*asynchronous across a process boundary*. `KeystrokeEmitter.post` is
`CGEvent.post(tap:)` — fire-and-forget — so the entry returns before VSCode has
handled the event, let alone re-rendered, while the provider's accessibility read
is an out-of-band read that does not queue behind the keystroke. The two-step op
is therefore not a UX preference over a cheaper alternative; it is the only shape
that gives VSCode a render window, because the wait has to be a *human* wait.
There is no portable delay: `after-delay` (`LifecycleLibrary.swift:40`) is a
main-queue `asyncAfter`, which cannot block a provider, and blocking the eval
thread on a render is ADR-0014 stalled-tap territory.

### Finding — VSCode's extension API is a live source, and it is in the bundle

Read out of the shipped `vscode.d.ts` (VSCode 1.136.2,
`Contents/Resources/app/out/vscode-dts/vscode.d.ts`), the same instrument k6
used for command registrations:

- `window.terminals: readonly Terminal[]` (`:11164`), each carrying
  `readonly name: string`, `show(preserveFocus?: boolean): void`,
  `processId`, and `shellIntegration.cwd: Uri | undefined`.
- `window.tabGroups: TabGroups` (`:11077`); a `Tab` carries `label`, `input`
  (a `TabInputText` and friends, so a real `uri` rather than a rendered path
  string), `isActive`, `isDirty`, `isPinned`, `isPreview`, and `group`, and a
  `TabGroup` carries `viewColumn` and `isActive`.

The extension host is a Node process
(`out/vs/workbench/api/node/extensionHostProcess.js`); shipped extensions use
Node's `net` (`debug-auto-launch`, `js-debug-companion`, `npm`) and
`onStartupFinished` activation (`debug-auto-launch`, `copilot`,
`merge-conflict`). So an extension can hold a Unix-domain socket open from
window start, and `(modaliser unix-socket)`'s `unix-socket-request` is already
the synchronous, never-raising, timeout-bounded round-trip a provider needs —
the transport ADR-0020 established for herdr.

**What this dissolves.** Every terminal obstacle in ADR-0026 is an artifact of
reading *rendered DOM* rather than the model: `hideCondition`, panel-shown,
the sequencing question, and `focusAtIndex1..9`'s missing keybinding (an
extension calls `Terminal.show` directly). It equally dissolves the editor
listing's absence-anchor, its description-vs-title instability, its
`showTabs` and `accessibilitySupport` pins, its modal blindness, its
frontmost-window-only limit, and its out-of-scope ruling on editor group
identity.

**Status: open, put to the human.** This is a source-selection decision of
wider scope than this leaf's brief anticipated, and no code exists on the
accessibility source yet — `ax-tab-rows` and `ax-press-handle` are specified
and unbuilt (`AccessibilityLibrary.swift:89-93` defines five procedures,
neither of them), so the switching cost today is design-only.

### Decision — the source is a companion VSCode extension over a Unix socket

Put to the human with the trade-off, the recommendation and the evidence above;
they chose the extension for **both** panels, and chose to have this leaf design
it while the extension itself becomes its own build leaf before k7.

ADR-0026 is reworked in place to say so — same number, resharpened slug
(`CLAUDE.md`: the number is the stable handle, the slug is the volatile one).
The accessibility tree becomes a considered-and-rejected option rather than the
decision.

### Decision — addressing is a last-focused pointer file, not a derived path

Three candidate ways for Modaliser to reach the *right* window's extension, given
that the extension host is per-window and `window.terminals` is that window's:

- **A socket path derived from the workspace path.** Rejected on a constraint
  that is easy to miss: it needs the same function computed on both sides, and
  **the portable tree has neither a hash nor a directory scan**. `(modaliser
  util)`'s `read-file-text` over R7RS ports is the whole file surface
  (`util.sld:95`); a hash would be new native surface, and a path-sanitising
  scheme without one runs into macOS's 104-byte `sun_path` limit on a deep
  worktree path.
- **Scan the socket directory and ask each peer.** Same blocker — no portable
  directory listing — and N round-trips per come-to-rest.
- **A last-focused pointer file.** Each window's extension writes its own socket
  path into one well-known file when its window takes focus
  (`window.onDidChangeWindowState`, `WindowState.focused` — `vscode.d.ts:11217`),
  atomically. Modaliser reads that one path with the `read-file-text` it already
  has, and dials it. **No new native surface, no hash, no scan, one round-trip.**

Taken. The reply carries `focused`, and Modaliser **discards a reply whose
`focused` is false** — the "row and action come from one snapshot and cannot
disagree" discipline applied to *window* identity, so a stale pointer yields an
empty listing rather than a neighbouring window's terminals.

**That gate rests on a structural fact, checked rather than assumed.** The
overlay panel is created non-activating (`ui/overlay.scm:1053`, `'activating
#f`), so VSCode keeps window focus for the whole modal and `state.focused` stays
true across every come-to-rest. The chooser panel *does* activate
(`ui/chooser.scm:321`), so a screen that rendered these rows through the chooser
instead would break the gate. Named in the spec rather than left to be
rediscovered.

### Decision — identity across the read→act gap is a never-recycled token

The extension mints an integer token per terminal and per editor tab from a
**per-window counter that is never reset**, and keeps token → live object. An
action resolves the token or does nothing. This is ADR-0026's own handle
discipline carried across to the new peer unchanged, and for the same reason: two
independently numbered spaces would let one integer name two things, so a stale
token would resolve to the wrong target instead of to nothing.

**A consequence for k7:** the never-reset counter change to
`AccessibilityLibrary` is no longer needed. It was needed only because
`ax-tab-rows` would have opened a second handle space in that library; with no
`ax-tab-rows`, `ax-find-elements` is again the only space and its reset harms
nothing. k7's Done-when must lose that item or it becomes work nobody needs.

### Decision — a bounded method set, never a command passthrough

Three methods: `parts` (one round-trip returning both listings plus `focused`
and `workspace`), `focus-terminal`, `focus-editor`. Not
`commands.executeCommand`, which would make the socket a remote control for the
whole workbench. The exposure that remains is real and is stated rather than
hidden: anything running as the user can enumerate the open editors' paths and
switch tabs.

### Decision — decision 5 survives the source change untouched

`jump-list-compose-providers` — named contributors, validation against the owner
state's static edges and the registered state ids — is source-independent, and
is most of k7's new machinery. None of it is wasted by this change.

### Correction — a `parts` call prunes the token map, it does not replace it

Caught while assembling the doubts for a reviewer, and fixed here rather than
deferred. The first draft of decision 4 said a `parts` call replaces the token
map's contents. That is wrong the moment there are two panels, which is the case
this design exists to serve: the screen's two providers each call `parts`, so the
second call would invalidate the tokens the first panel's rows were just drawn
with, and every label on that panel would silently do nothing — a whole dead
panel, from a sentence that looks like housekeeping.

The map is pruned instead: mint for objects not yet seen, keyed on object
identity, and drop only entries whose object is no longer among the window's
terminals or tabs. A live object keeps its token however many times `parts` is
called; a closed one still goes stale. Both artifacts corrected.

### Decision — the spec is renamed, and three Done-when items read differently

Three places where what was delivered diverges from the brief's letter, each
deliberate:

- **`docs/specs/vscode-editor-listing.md` is now
  `docs/specs/vscode-window-parts.md`.** The brief said "an edit to
  `vscode-editor-listing.md` … not a second spec", and this is that edit: one
  spec, edited in place, renamed because it no longer describes an editor
  listing. `SPEC-FORMAT.md` requires the set to be current-state and names
  renaming as ordinary maintenance; the three live citations were reconciled.
  Note this is the opposite call from the ADR's, and for the stated reason — an
  ADR is cited by *number* so its slug is free to move, while a spec is cited by
  *path*, so the rename was priced (three citations) before it was made.
- **No live VSCode window was driven, and none was needed.** The brief expected
  a scratch window, as k6 and k8 used. The decision turned on VSCode's *shipped
  API surface* — `out/vscode-dts/vscode.d.ts`, `extensionHostProcess.js`, and
  which shipped extensions use `net` and `onStartupFinished` — which is the same
  evidence class k6 used for command registrations and is read from the bundle.
  Nothing was probed live, so nothing was created and nothing needed cleaning up.
  This is a real limit on the design, not a saving: **every live-behaviour claim
  here is inferred from type declarations**, and it is written into the review
  leaf as a thing to press on.
- **Nothing was measured, so there is no instrument to commit.** The brief's
  "keep the instrument this time" is answered by withdrawing k6's figure rather
  than replacing it: the source it measured is no longer used, so an adjusted
  number would have been worse than none. The obligation moves to the two build
  leaves, which are told to instrument with committed `(modaliser instrument)`
  spans split into wire and parse time.

### Decision — this design earned a review chain, cut ahead of the build

`review-design--vscode-terminal-listing-k13`, inserted at the slot the build
leaf held so it runs first. Earned on three grounds: the design it replaces went
through a review that found seven defects in this same area; this one reverses
that design's central decision, decided and written inside a single session after
a mid-session pivot; and two implementation leaves build directly onto it, so a
defect is paid for twice. Its body names the seven specific doubts this session
could not resolve on itself rather than a generic instruction to review. No
in-session reviewer was spent — once review is escalated to the tree, grove owns
the route (`references/execute.md`).
