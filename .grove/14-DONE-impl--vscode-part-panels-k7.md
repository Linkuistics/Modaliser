# vscode-part-panels-k7

## Goal

Two more jump-label panels on the F17 VSCode screen, beside the Projects panel
that `vscode-project-panel-k4` shipped:

- **Terminals** — one row per open terminal in the frontmost window, labels
  from `t y u i o`. **Both panels are being built**: `vscode-terminal-listing-k10`
  settled the row source and the terminal panel is in.
- **Editors** — one row per open editor in the frontmost window, labels from
  `h j k l ;`.

Each with its own alphabet, exactly as the Projects panel has its own — the
human's words were *"a separate set of shortcut keys for each (i.e. the same as
the projects)"*.

The panels displace two rows: **`t` (Terminal) and `i` (Editor) come off the
screen**, which is what frees `t` and `i` for the terminal alphabet. The human
asked for that explicitly. Which keys the screen carries is still the human's
call (ADR-0021), so put the final row set to them rather than deriving it.

## Context

**This leaf builds; it does not decide.** The design is
`docs/specs/vscode-window-parts.md` with ADR-0026 and ADR-0027, produced by
`vscode-part-enumeration-k6`, corrected by the review
`vscode-part-enumeration-k8` and its integration `vscode-part-enumeration-k9`,
then **reversed on its central question** by `vscode-terminal-listing-k10`, and
then reviewed and repaired again by `vscode-terminal-listing-k13` /
`vscode-terminal-listing-k14` — which is where the peer-bound targets, the
fire-and-forget actions, the actionable-tab-kind table and the composition's
shape below come from. **Read the spec and both ADRs as they stand now** — not
k6's commit, not k9's, and not k10's.

**The row source is no longer the accessibility tree.** k10 found that VSCode's
extension API carries exactly what these panels want — `window.terminals` and
`window.tabGroups`, from the model rather than from rendered DOM — and the
human chose it for both panels. Both listings now come from a **companion
VSCode extension** over a Unix socket, built by
`vscode-companion-extension-k12`, which runs immediately before this leaf and
leaves you `(vscode-parts)` as a working call.

**What that deletes from this leaf.** Four of the five repairs k9 made were
about reading the accessibility tree, and **none of them is work any more** —
if you find yourself doing one of these, you are building the rejected design:

- every-tab-strip walking, the empty-description anchor, and the
  tab-button subrole check;
- pinning `workbench.editor.showTabs` and `editor.accessibilitySupport`;
- `ax-tab-rows` handing `description` and `title` across unjoined, and the
  description-else-title rule in `editor-tabs`;
- **the one-never-reset-counter change to `AccessibilityLibrary`, and its
  cross-space refusal test.** That change existed only because `ax-tab-rows`
  would have opened a second handle space in that library. There is no second
  reader now, so `ax-find-elements` is again the only space and its reset harms
  nothing. The invariant itself did not die — it moved into the extension, as
  the token counter — but it is `k12`'s to hold, not yours.

**What survives untouched, and it is the hard part:**

- **`jump-list-compose-providers` takes *named* contributors** and validates
  against the owner state's static edges and the registered state ids as well as
  against the other providers. Checking only the provider results misses the
  likelier collision — a promoted leader landing on one of the screen's own
  keys — which the engine resolves first-wins in the static edge's favour. This
  is source-independent and is spec **decision 7** (it was decision 5 before the
  rework).

  **Its shape changed after the design review, and the change is the point.** The
  exported procedure takes **no** `'known-edges` / `'known-state-ids` arguments: it
  queries `fsm-state-edges` / `fsm-state-ids` itself, and the testable half is a
  *pure* `jump-list-validate-composition` taking those facts as data. The earlier
  draft's optional readers were a documented off-switch on the invariant — a user
  config is Scheme and can call the same export with two empty readers — which is
  the asserted-not-structural shape this whole leaf is guarding against. Do not put
  them back for testability; the validator is the seam.

**What is new for you, from the extension source:**

- **A row can be inert by design.** A tab of a kind with no specified activation
  is listed with `token: null` and has no action — `jump-list`'s existing "no
  handle, no edge" contract, now reachable in normal use rather than only on a
  race. The set is decided per input kind in spec decision 1's table (text and
  notebook tabs are actionable; webview, custom-editor and both diff kinds are
  not), because `TabGroups` has no reveal call and "carries a URI" turned out not
  to mean "can be activated".
- **A target is `(peer, token)`, not a token** (spec decision 4). Rows carry the
  socket path the `parts` reply named, and `focus-*` addresses *that* peer —
  never the pointer file a second time. Two windows' counters both hand out `3`,
  so a target that carried only the integer would be an address several windows
  answer to.
- **The actions are fire-and-forget** (spec decision 2): `unix-socket-send`, no
  reply, nothing to check. An action's failures are all the peer's to refuse, and
  a refused press looks exactly like a delivered one from here — which is fine,
  and is the reason `jump-list`'s `'action` returning a thunk needs no result
  handling. Do log the send's own `#f`, though: that one means the bytes reached no
  socket at all, which is the only action failure visible from this side.
- **No offline seam proves an activation happened** — every seam here asserts the
  call, and the effect is VSCode's. Two cases have to be driven by hand on the
  human's machine because a fake passes them and a real window does not: the same
  file open in two editor groups (rows must not swap after a group reorder), and a
  preview tab that is already active (pressing it must not pin it).
- **A folderless window is an ordinary listing**, with `workspace: null` and paths
  shown unshortened (spec decisions 3 and 6). It is not an empty-listing case; do
  not let the shortening code assume a workspace, and do not let it assume a path
  lies under one.
- **Rows carry their editor group** (`group`, from `viewColumn`), so a renderer
  may show it. The listing still offers no way to focus a group as such.
- **Paths are real `fsPath` strings**, not rendered labels: no ` • Deleted`
  suffix, and a dirty marker comes from the row's `dirty` field.
- **Two panels means two `parts` round-trips per come-to-rest**, deliberately
  un-memoised but **bounded**: the read timeout is 200 ms, so the screen's
  worst-case blocked eval thread is 400 ms rather than the 2 s two of herdr's
  1000 ms ceilings would cost (spec decision 2). Do not add a cache without the
  measurement decision 5 names as its reopen condition — and if a *third* panel
  lands here, the answer is one shared read, not a shorter timeout.

**Everything downstream of the row source already exists**, and this is the
third caller of it, which is the point:

- `(modaliser jump-list)` — `jump-list-provider-result` lowers an assignment
  onto the FSM. Three injected functions and nothing else crosses the boundary:
  `'state-id` (namespace it per panel — `vscode-project-target/…` is taken),
  `'action` (returns a thunk, or `#f` for an inert row — there is deliberately
  no separate focusability predicate), `'block` (pairs → block spec, whose
  `'type` is read back out).
- `(modaliser jump-labels)` — `jump-labels-assign`, targets × three alphabets →
  prefix-free labels, escalating into leaders only as needed.
- `(modaliser blocks project-list)` — a label · arrow · name row. **Judge
  whether it fits before copying it.** It was written for one long name with no
  competing column; a terminal row may want its cwd or its shell as trailing
  detail, in which case `blocks/paneru-strip`'s four-column grid is the closer
  shape. k4's recorded rule decides this: share machinery, duplicate
  presentation — duplicated machinery drifts silently, duplicated presentation
  drifts visibly.
- `(modaliser apps vscode)` — `project-provider` / `project-listing` are the
  worked pattern to follow, including the per-Visit snapshot cell that makes the
  drawn rows and the live labels provably the same assignment.

**The composition problem is the real work.** One state, one `'provider` slot,
three panels. The spec's decision 7 answers *how*; expect to be implementing
that merge. Two preconditions the screen already meets and which the
implementation should assert rather than assume: the three key pools are
disjoint (`a s d f g` / `t y u i o` / `h j k l ;`), and state ids are namespaced
per panel. Note that the merge now checks a third thing you cannot assert by
inspection — a promoted leader colliding with a screen key — because leader
promotion is data-dependent and only happens once a panel outgrows its singles.

**Alphabet collisions to check on the whole screen, not just within a panel.**
After k4's late amendment the screen's bound keys are `e p P / L` plus whatever
`vscode-editor-cycling-k5` adds on `[` `]`, and `t`/`i` are leaving. Confirm
`h j k l ;` and `t y u i o` are clear of all of them before shipping — a label
that collides with a bound key loses, silently.

**The `'next 'self` ruling still stands and is now three times heavier.** k4's
provider re-runs at every come-to-rest for an 8-29ms warm (200ms+ cold) AX
sweep, and `KeyboardCapture` filters no auto-repeat. Three providers on one
screen means three gathers per press — one AX window sweep for Projects, and two
socket round-trips for the new pair.

**There is no cost figure to inherit, and that is deliberate.** k6's 3.1 ms came
from a standalone walker that was never committed and measured the source this
design no longer uses; it is withdrawn, not adjusted. The only number worth
carrying is the comparable one: herdr's socket wire time, same primitive and
same envelope, at 0.1–0.6 ms per read. **Measure the composed screen's own
come-to-rest on the shipping path** before treating the cost as settled, and
instrument it with something committed — `(modaliser instrument)` splits wire
time from parse time, which is what makes a bad number diagnosable. If the
number is bad, that is a finding worth a leaf of its own rather than something
to absorb quietly. Note the new risk the socket brings: the extension host's
event loop is shared with every other extension in that window, so a slow reply
is possible in a way nothing on Modaliser's side can bound — which is what the
timeout and the empty-listing degradation are for.

**Pointers**

- `.grove/04-DONE-impl--vscode-project-panel-k4.md`'s decision log — why
  `jump-list` exists, why the block was *not* shared, and the sub-question about
  `'type 'paneru-strip` leaking a name into the DOM (answered: give a panel its
  own block when its content differs).
- `docs/reference/libraries.md` — `(modaliser jump-list)`,
  `(modaliser blocks project-list)`, `(modaliser apps vscode)`.
- `~/.config/modaliser/app-trees/com.microsoft.VSCode.scm` — the live screen.
- `CONTEXT.md`, **Project listing** — the term this leaf extends. **Editor
  tab**, **Editor listing**, **Terminal listing** and **VSCode companion
  extension** are already there, written by k10; append to them rather than
  restating them, and correct any that the build proves wrong.
- `vscode-companion-extension-k12` — the leaf immediately
  before this one, which builds the peer and leaves you `(vscode-parts)`. Its
  decision log is where any protocol detail that moved in the building will be.

## Done when

- Both panels list the frontmost window's parts on the human's machine, each row
  reachable by its own jump label, and pressing a label focuses that part —
  including the two cases only a real window shows: one file open in two editor
  groups after a reorder, and an already-active preview tab.
- The Editor panel lists tabs from **every** editor group in the window, and the
  Terminal panel lists every terminal **with the terminal panel hidden** — the
  case the whole source change was made for.
- The screen's rows and alphabets match what the human asked for, with `t` and
  `i` off the screen.
- All alphabets and labels come from the human's `config.scm`, none defaulted in
  any file under `lib/modaliser` (ADR-0021) — the human restated this
  unprompted: *"this should all be configurable in the user's config."*
- The panels coexist on one screen with no key or state-id collision, and the
  composition is implemented the way `docs/specs/vscode-window-parts.md`
  decision 7 specifies — named contributors, and validation that reaches the
  owner's static edges and the registered state ids, not just the provider
  results.
- `swift build` and `swift test` green; `./scripts/check-portable-surface.sh`
  and `./scripts/check-decision-free.sh` both pass.
- `Scheme/examples/vscode.scm` shows the composed screen and still load-tests
  green (`ConfigDslTests.exampleConfigsLoadWithoutErrors`).
- The new surface is documented in `docs/reference/libraries.md` beside its
  peers.

## Notes

- **Verify against a real VSCode, not against a successful import.** Install
  (`./scripts/install.sh`), confirm `config: loaded` in `/usr/bin/log show
  --predicate 'subsystem == "dev.antony.Modaliser"'`, then ask the human to
  press the keys. A shell alias shadows `log` — use `/usr/bin/log`.
- A wedged first launch is a known hazard here and is not your bug: a freshly
  signed bundle can hang pre-`dyld` awaiting Gatekeeper's scan, and
  LaunchServices then routes every later "open" to the stuck process as a reopen
  event that times out. The tell is ~32 KB RSS at 0% CPU.
  `pkill -f "/Applications/Modaliser.app/Contents/MacOS"` and relaunch.
- This is the leaf where a `review-impl` step is most plausibly earned — it is
  the third caller of `jump-list`, it edits a screen the human uses constantly,
  and the composition is new. Cut one as your last act if you judge an
  adversarial read necessary (`references/decompose.md`); k4 judged one
  unnecessary because paneru's own suite pinned the risky half before and after.

## Decisions (running log)

- **The composition lands in `(modaliser jump-list)` as spec decision 7
  specifies, and the split is exactly at the purity line.**
  `jump-list-validate-composition` takes RESULTS (the contributors' results in
  argument order), NAMES parallel to it, OWNER-EDGES and REGISTERED-STATE-IDS —
  every fact as data — and returns the merged result or raises.
  `jump-list-compose-providers` takes alternating NAME/PROVIDER pairs, calls
  each contributor with the owner id the engine handed it, and asks
  `fsm-state-edges` / `fsm-state-ids` itself. No reader is an argument, so a
  user's config cannot pass two empty ones and switch the invariant off.
- **Triggers and state ids are compared with `equal?` and nothing is
  normalised**, because that is exactly what the engine does: the graph's edge
  table and the visit's provided-state table are both plain `equal?`-keyed hash
  tables, so the string `"foo"` and the symbol `foo` are two different states
  there and must be two different states here.
- **All triggers are compared, not just key strings.** `'up` and `'auto` collide
  by the same first-match rule a key does, and no contributor in the tree emits
  either — so including them can only catch a real collision, never invent one.
- **A contributor is checked against itself as well as against its peers.** A
  contributor need not be a `jump-list` result, so an internally-colliding one is
  a real defect; it is reported against its own name.
- **State-id namespaces re-enumerated before adding a fifth**, as spec decision 5
  requires. Grepping `provided-state` and `state-id` across `lib/` finds exactly
  three provider-minted namespaces — `vscode-project-target/`,
  `paneru-strip-target/`, `herdr-jump-target/` — matching what the spec named.
  This leaf adds `vscode-terminal-target/` and `vscode-editor-target/`.
- **One block for both panels, not two.** k4's rule — share machinery,
  duplicate presentation — bought `blocks/project-list` its own existence
  because a Project row is one long name in the full width and a Strip row is
  four competing columns. It buys the opposite here: a Terminal row is a short
  name plus a cwd and an Editor row is a filename plus a workspace-relative
  path, which is *one* presentation with two callers. So
  `(modaliser blocks part-list)` is written once, closer to
  `blocks/paneru-strip`'s four-column grid than to `blocks/project-list`'s
  full-width one, exactly as spec decision 6 predicted.
- **Two `part-list` blocks on one screen need explicit `'id`s, and that
  exposed a latent trap in `jump-list`.** A panel's block reference resolves
  through `block-ref-id` — the block's `'id` when it has one, its `'type`
  otherwise — but `jump-list`'s narrowing prefix state built its reference by
  reading `'type` directly. That was right while every caller's block had a
  unique type and becomes a *blank narrowed panel with no error* the moment two
  panels share a type and disambiguate with ids. Fixed at the source:
  `prefix-state` now reads `block-ref-id`, the same accessor the renderer
  reads, so the reference it mints and the lookup that resolves it provably
  agree. `(modaliser display-dsl)` is portable, so the import costs nothing.
- **The Editor row's detail is the whole workspace-relative path, not its
  directory half.** `Tab.label` is usually the basename but VSCode
  disambiguates it when two tabs share one, so a directory-only detail would
  sometimes repeat what the name already said and sometimes be the only thing
  telling two rows apart. The whole path is the same answer every time, and
  the block ellipsizes it.
- **`shorten-path` requires the separator as well as the prefix.** Without it
  a sibling sharing a name prefix has its leading characters sliced off and the
  row names a file that does not exist — which is the ordinary case in this
  very repository, where `Modaliser` and `Modaliser.local-tree-for-vscode` sit
  side by side. Pinned by a test.
- **The providers are one shared body with four per-panel arguments** (which
  join, which state-id namespace, which snapshot cell, which block id). That is
  machinery, and machinery duplicated between two panels drifts silently —
  which is the whole reason `(modaliser jump-list)` exists.
- **`instrument-span` wraps each provider** (`vscode-terminal-provider` /
  `vscode-editor-provider`), composing with the wire/parse spans already inside
  `vscode-socket-request`. Committed rather than throwaway, because k6's cost
  conclusion had to be withdrawn for exactly that reason.
- **A LispKit arity mismatch inside `apply` aborts the process rather than
  raising**, so a whole `swift test` bundle can exit on signal 5 with most of a
  suite already green. Noted because the diagnosis is not obvious from the
  output: run the suite's tests individually to find the one that dies. (Cause
  here was a test calling `fsm-graph-edge!` with an edge spec where it takes
  `trigger` and `target` separately — a test bug, not a library one.)
- **The human confirmed the final row set and the panel order** (they are theirs
  to make, ADR-0021). Screen keys are `e p P / L [ ]`; `t` (Terminal) and `i`
  (Editor) are off. Pools: Projects `a s d f g`, Terminals `t y u i o`, Editors
  `h j k l ;` — pairwise disjoint and disjoint from every screen key. Panel
  order is Terminals, Editors, then Projects: the parts of the window you are
  already in read first, and Projects — which is about leaving this window —
  sits last. Both the shipped example and the human's live config carry this.
- **Every key in the three pools is reachable.** `keyCodeToCharacter` in
  `KeyboardLibrary.swift` maps `;` (41), `[` (33), `]` (30) and `/` (44) as well
  as every letter used, so `h j k l ;` is not a pool with a dead key in it.
- **A `parts` reply read off the human's live window showed the grove task file
  (a markdown tab, and therefore `TabInputCustom` under their
  `workbench.editorAssociations`) as `token: null` — and it is a stale extension
  host, not a defect.** Every running peer's socket dates from 10:41 and the
  installed `tabKind.js` was written at 11:06, so the hosts are running the
  build from *before* `custom` was added to `ACTIONABLE_TAB_KINDS`. The
  signature is exact: the old table gave `TabInputCustom` a `path` and no
  token, which is precisely what came back. Confirmed by reading the installed
  `out/src/tabKind.js`, which *does* list `"custom"`. The fix is a window
  reload, not a code change — recorded because the symptom (headline case is a
  panel of inert rows) is the same one the spec says the custom-editor change
  was made to remove, and the next reader should not chase it twice.
- **The composed screen's come-to-rest is measured on the shipping path, and
  the cost question is settled.** A leader press against the installed `.app`
  with all three panels live (`instr: epoch leader-press`, one terminal and one
  editor in the window, 542-char replies): `vscode-wire` **0 ms** and
  `vscode-parse` **2 ms** for the terminal provider, **0 ms** / **1 ms** for the
  editor provider — `vscode-terminal-provider` **2 ms** and
  `vscode-editor-provider` **2 ms** end to end, inside a
  `leader/modal-activate!` of **36 ms** that also carries the Projects panel's
  accessibility sweep. So the two round-trips this leaf adds are **~4 ms of a
  36 ms come-to-rest**, against a 400 ms worst case the timeout bounds. That is
  in line with herdr's 0.1–0.6 ms wire on the same primitive, and it means the
  socket source costs materially less than the AX sweep already on this screen.
  No cache, and no leaf: the reopen condition stays the one spec decision 5
  names. Note what the split says — the wire is free and the cost is all
  **parse**, so a bad number here would be a JSON-size problem, not a peer
  problem, which is exactly what the committed wire/parse span exists to tell
  apart.
- **The stale-extension-host diagnosis in the entry above is confirmed by the
  fix.** After the window reload a `parts` read off the live peer returns the
  grove task file — a markdown tab, and therefore `TabInputCustom` under the
  human's `workbench.editorAssociations` — as `token: 2`, not `token: null`.
  The headline case the custom-editor change was made for is now verified
  against a real window rather than against the installed source.
- **The state-id namespace enumeration in `apps/vscode.sld` said "Four" and
  listed three.** Corrected to "Three", which is what the grep found and what
  makes "before adding a sixth" on the next line add up. A miscounted
  enumeration is worse than none: the next reader trusts it instead of
  re-running the grep, which is the one thing the comment tells them to do.
- **No `review-impl` leaf, and no in-session reviewer spent.** The leaf named
  itself the most plausible candidate in the tree, so the judgement is recorded
  rather than left implicit. Three things decide it against:
  - **The composition's shape is already a review's output.** The design was read
    adversarially twice (`k8`/`k9`, then `k13`/`k14`), and the very property that
    makes this leaf's hard part hard — no `'known-edges` / `'known-state-ids`
    arguments, a pure `jump-list-validate-composition` as the seam — *is* what
    the second review changed. Re-reviewing it is re-reviewing a finding that has
    already been integrated.
  - **The one change to shared machinery is identity-preserving by
    construction, not merely by a green suite.** `prefix-state` now reads
    `block-ref-id` instead of `'type`, and `block-ref-id`
    (`display-dsl.sld:88`) returns the block's `'id` when it has one and its
    `'type` otherwise. Neither `blocks/paneru-strip` nor the herdr jump block
    carries an `'id`, so for both existing callers the new accessor returns
    exactly what the old field read did. That is a structural argument; a
    regression there would have been the silent kind (a blank narrowed panel,
    no error), which is why it is worth having rather than trusting 1303 green
    tests to have covered it.
  - **The genuinely new logic is pure and directly exercised** — 16 tests over
    the validator, including a contributor colliding with the owner's static
    edge and `compose-providers` reaching the *installed* graph, which is the
    promoted-leader-onto-a-screen-key case at the mechanism level (a promoted
    leader is an ordinary edge by the time the validator sees it, so the
    data-dependence that makes it unreachable by inspection is not a gap in the
    seam).
  k4 declined a review on the same reasoning shape — machinery pinned by a suite
  on both sides — and this leaf has the stronger version of it.
- **The human drove the composed screen and confirmed all of it works as
  intended.** Three panels on one `'provider` slot, each row reachable by its
  own alphabet, and a label press focusing that part — with three terminals and
  the **terminal panel hidden**, and with tabs across **two editor groups**
  including a markdown (custom-editor) tab. That closes the last done-condition,
  and it is the one no offline seam could hold: every seam on this side asserts
  the call, and the effect is VSCode's.
