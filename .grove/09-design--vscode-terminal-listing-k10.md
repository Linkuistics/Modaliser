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
- `10-impl--vscode-part-panels-k7.md` is reconciled: it must not have to decide
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
