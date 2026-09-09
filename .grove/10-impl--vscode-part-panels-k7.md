# vscode-part-panels-k7

## Goal

Two more jump-label panels on the F17 VSCode screen, beside the Projects panel
that `vscode-project-panel-k4` shipped:

- **Terminals** — one row per open terminal in the frontmost window, labels
  from `t y u i o`. **Build this to `vscode-terminal-listing-k10`'s design**,
  which runs immediately before this leaf and settles the show-then-enumerate
  sequencing k6 got wrong. If that leaf concluded the panel should not be built,
  build the Editor panel alone and leave the screen's terminal row where it is —
  that is a decision, not a gap for this leaf to fill.
- **Editors** — one row per open editor in the frontmost window, labels from
  `h j k l ;`.

Each with its own alphabet, exactly as the Projects panel has its own — the
human's words were *"a separate set of shortcut keys for each (i.e. the same as
the projects)"*.

The panels displace two rows: **`t` (Terminal) and `i` (Editor) come off the
screen**, which is what frees `t` and `i` for the terminal alphabet. The human
asked for that explicitly. If `k10` lands on no terminal panel, `t` has nothing
to make way for and stays — and which keys the screen carries is the human's
call either way (ADR-0021), so put it to them rather than deriving it.

## Context

**This leaf builds; it does not decide.** The design is
`docs/specs/vscode-editor-listing.md` and ADR-0026, produced by
`vscode-part-enumeration-k6`, corrected by the review
`vscode-part-enumeration-k8` and its integration `vscode-part-enumeration-k9`,
and completed for terminals by `vscode-terminal-listing-k10`, which runs
immediately before this leaf. **Read the spec and the ADR as they stand now —
not k6's commit**, which is wrong in seven places the integration repaired.

**Five of those repairs change what you build**, so they are worth knowing
before you open the spec:

- **Editor rows come from *every* editor tab strip in the window**, not the
  first one found. A split editor exposes two empty-description tab groups, and
  the old "stop at the first" walk returned an arbitrary group's tabs. A
  matching group whose children are not tab buttons is skipped.
- **The listing requires `workbench.editor.showTabs` at `"multiple"`** (its
  default) and pins it, alongside `editor.accessibilitySupport`. Under `single`
  or `none` there is no strip to read and the panel is empty.
- **`ax-tab-rows` hands `description` and `title` across separately**, and the
  description-else-title choice is made in Scheme, in `editor-tabs`. Do not
  collapse them in Swift — the whole point is that a fixture can carry both
  shapes, and a fixture that cannot is a test that proves nothing.
- **The accessibility library allocates from one never-reset counter** shared by
  both handle maps. Two independently numbered spaces would let the same integer
  be live in both, and a foreign handle would then resolve to the wrong element.
  `ax-find-elements` still clears its own map every call; it just stops reusing
  numbers. There is a cross-space refusal test to write.
- **`jump-list-compose-providers` takes *named* contributors** and validates
  against the owner state's static edges and the registered state ids as well as
  against the other providers. Checking only the provider results misses the
  likelier collision — a promoted leader landing on one of the screen's own
  keys — which the engine resolves first-wins in the static edge's favour.

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
screen means three gathers per press.

**Do not take k6's cost conclusion — it was withdrawn.** Its 3.1 ms figure came
from a standalone `swiftc -O` walker that was never committed, excluded the
marshalling, the main queue, the eval lock and everything in Scheme, and
early-exited at the first tab group where the specified walk must see them all.
What survives is that a pruned AX walk *can* be cheap and that pruning is worth
roughly an order of magnitude. **Measure the composed screen's own come-to-rest
on the shipping path** before treating the cost as settled; if the number is
bad, that is a finding worth a leaf of its own rather than something to absorb
quietly.

**Pointers**

- `.grove/04-DONE-impl--vscode-project-panel-k4.md`'s decision log — why
  `jump-list` exists, why the block was *not* shared, and the sub-question about
  `'type 'paneru-strip` leaking a name into the DOM (answered: give a panel its
  own block when its content differs).
- `docs/reference/libraries.md` — `(modaliser jump-list)`,
  `(modaliser blocks project-list)`, `(modaliser apps vscode)`.
- `~/.config/modaliser/app-trees/com.microsoft.VSCode.scm` — the live screen.
- `CONTEXT.md`, **Project listing** — the term this leaf extends. If a
  *Terminal listing* and an *Editor listing* harden as their own terms, or if
  one term covers all three, append it there.

## Done when

- Every panel the design calls for lists the frontmost window's parts on the
  human's machine — the Editor panel certainly, the Terminal panel if
  `vscode-terminal-listing-k10` calls for one — each row reachable by its own
  jump label, and pressing a label focuses that part.
- The Editor panel lists tabs from **every** editor group in the window, and
  `workbench.editor.showTabs` is pinned to `"multiple"` beside the
  `editor.accessibilitySupport` pin.
- The screen's rows and alphabets match what the human asked for, with `t`'s
  fate settled by whether a Terminal panel exists.
- All alphabets and labels come from the human's `config.scm`, none defaulted in
  any file under `lib/modaliser` (ADR-0021) — the human restated this
  unprompted: *"this should all be configurable in the user's config."*
- The panels coexist on one screen with no key or state-id collision, and the
  composition is implemented the way `docs/specs/vscode-editor-listing.md`
  decision 5 specifies — named contributors, and validation that reaches the
  owner's static edges and the registered state ids, not just the provider
  results.
- The accessibility handle spaces are disjoint by construction (one never-reset
  counter) and there is a test that each surface refuses the other's handle.
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
