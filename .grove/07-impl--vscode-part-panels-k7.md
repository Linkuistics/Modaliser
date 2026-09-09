# vscode-part-panels-k7

## Goal

Two more jump-label panels on the F17 VSCode screen, beside the Projects panel
that `vscode-project-panel-k4` shipped:

- **Terminals** — one row per open terminal in the frontmost window, labels
  from `t y u i o`.
- **Editors** — one row per open editor in the frontmost window, labels from
  `h j k l ;`.

Each with its own alphabet, exactly as the Projects panel has its own — the
human's words were *"a separate set of shortcut keys for each (i.e. the same as
the projects)"*.

The panels displace two rows: **`t` (Terminal) and `i` (Editor) come off the
screen**, which is what frees `t` and `i` for the terminal alphabet. The human
asked for that explicitly.

## Context

**This leaf builds; it does not decide.** `vscode-part-enumeration-k6` settles
where the rows come from, what they are called, how stale they are, what they
cost on the dispatch path, and how three jump-label panels share one `'provider`
slot. **Read k6's delivered spec/ADR first and build to it.** If k6 concluded
that enumeration is not viable and the answer is numbered slots
(`workbench.action.openEditorAtIndex1..9`,
`workbench.action.terminal.focusAtIndex1..9`), build *that* — it is a real
answer, not a fallback to improve on.

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
three panels. k6 answers *how*; expect to be implementing a merge of three
provider results plus whatever it says about collisions. Two preconditions the
screen already meets and which the implementation should assert rather than
assume: the three key pools are disjoint (`a s d f g` / `t y u i o` /
`h j k l ;`), and state ids are namespaced per panel.

**Alphabet collisions to check on the whole screen, not just within a panel.**
After k4's late amendment the screen's bound keys are `e p P / L` plus whatever
`vscode-editor-cycling-k5` adds on `[` `]`, and `t`/`i` are leaving. Confirm
`h j k l ;` and `t y u i o` are clear of all of them before shipping — a label
that collides with a bound key loses, silently.

**The `'next 'self` ruling still stands and is now three times heavier.** k4's
provider re-runs at every come-to-rest for an 8-29ms warm (200ms+ cold) AX
sweep, and `KeyboardCapture` filters no auto-repeat. Three providers on one
screen means three gathers per press. Take k6's measurement seriously; if the
composed cost is bad, that is a finding worth a leaf of its own rather than
something to absorb quietly.

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

- Both panels list the frontmost window's parts on the human's machine, each row
  reachable by its own jump label, and pressing a label focuses that part.
- The `t` and `i` rows are gone from the screen.
- All alphabets and labels come from the human's `config.scm`, none defaulted in
  any file under `lib/modaliser` (ADR-0021) — the human restated this
  unprompted: *"this should all be configurable in the user's config."*
- Three panels coexist on one screen with no key or state-id collision, and the
  composition is implemented the way k6 specified.
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
