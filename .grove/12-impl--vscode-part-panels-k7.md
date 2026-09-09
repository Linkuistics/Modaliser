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
`docs/specs/vscode-window-parts.md` and ADR-0026, produced by
`vscode-part-enumeration-k6`, corrected by the review
`vscode-part-enumeration-k8` and its integration `vscode-part-enumeration-k9`,
and then **reversed on its central question** by `vscode-terminal-listing-k10`.
**Read the spec and the ADR as they stand now** — not k6's commit, and not k9's.

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

**What is new for you, from the extension source:**

- **A row can be inert by design.** A tab whose input carries no URI is listed
  with `token: null` and has no action — `jump-list`'s existing "no handle, no
  edge" contract, now reachable in normal use rather than only on a race.
- **Rows carry their editor group** (`group`, from `viewColumn`), so a renderer
  may show it. The listing still offers no way to focus a group as such.
- **Paths are real `fsPath` strings**, not rendered labels: no ` • Deleted`
  suffix, and a dirty marker comes from the row's `dirty` field.
- **Two panels means two `parts` round-trips per come-to-rest**, deliberately
  un-memoised (spec decision 5). Do not add a cache without the measurement that
  decision names as its reopen condition.

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
three panels. The spec's decision 5 answers *how*; expect to be implementing
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
  reachable by its own jump label, and pressing a label focuses that part.
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
