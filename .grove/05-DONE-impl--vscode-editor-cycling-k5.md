# vscode-editor-cycling-k5

## Goal

Put previous/next editor on `[` and `]` on the F17 VSCode screen, each
**focusing the editor first if the editor does not already have focus**.

The smallest of the three leaves the human's "editors and terminals" request
decomposed into, and deliberately first: it depends on nothing the other two
settle, and it is useful the moment it lands.

## Context

**The focus-first clause is the whole of the work.** `[` and `]` on their own
are two chords over two commands VSCode already has —
`workbench.action.previousEditor` and `workbench.action.nextEditor` — and those
are `send-keystroke` one-liners of the kind `examples/chrome.scm` is made of.
What makes this a leaf rather than two lines is that VSCode's editor-cycling
commands act on the editor group **wherever focus currently is**: pressed while
the terminal or the explorer has focus they still switch the editor, leaving
the user looking at a changed tab they cannot type into. "Focus, then cycle" is
the behaviour the human asked for, and it is one op, not two rows.

**Establish the commands against the shipped bundle, not from memory.** k2's
header records what that discipline is worth — all three of VSCode's "obvious"
focus chords turned out to be mis-stated in the folklore, and the finding is
written up in `apps/vscode.sld`'s header under "The three chords, and what they
actually do". Read the shipped registrations
(`/Applications/Visual Studio Code.app/Contents/Resources/app/out/vs/workbench/
workbench.desktop.main.js`) for the exact command ids, their default macOS
bindings, and any `when` clause that gates them. In particular, check whether
`previousEditor`/`nextEditor` wrap at the ends and whether they cross editor
groups — both are user-visible and neither should be guessed.

**Where the focus half comes from.** `(modaliser apps vscode)` already exports
`focus-editor`, a thunk over cmd-1 — but read its own caveat first: cmd-1 is
`workbench.action.focusFirstEditorGroup`, the LEFTMOST group, and the exact
command (`focusActiveEditorGroup`) ships with no default binding at all. The
human's own config does not use that op for this reason: it sends ctrl+alt+i, a
strict-focus command bound by hand in their `keybindings.json`. So the library
op and the human's row differ, and the composition here has to work with both —
which is an argument for the library exporting the *combinator* (focus, then
cycle) parameterised on the focus thunk, rather than a hardcoded pair.

**The `t`/`i` rows are NOT this leaf's to remove.** They are freed by
`vscode-part-panels-k7`'s panels, not by this. Leave them alone.

**Pointers**

- `apps/vscode.sld`'s header, the "three chords" section — what was established
  about VSCode's focus commands and how.
- `~/.config/modaliser/app-trees/com.microsoft.VSCode.scm` — the human's screen.
  Note its header explains why its rows send ctrl+alt+{t,e,i} rather than the
  library ops.
- `Scheme/examples/vscode.scm` — the shipped example, which must stay composing
  (`ConfigDslTests.exampleConfigsLoadWithoutErrors`).

## Done when

- `[` and `]` cycle the editor from the F17 VSCode screen on the human's
  machine, and do so correctly **when the terminal or the explorer had focus**
  — which is the case that distinguishes this from two bare chords.
- The keys and labels are in the human's config, not in any file under
  `lib/modaliser` (ADR-0021). Whatever the library exports is a facility the
  config binds.
- Whether the library gained an op, gained a combinator, or gained nothing at
  all is recorded as a decision with its reasoning.
- `swift build` and `swift test` green; `./scripts/check-portable-surface.sh`
  and `./scripts/check-decision-free.sh` both pass.
- If the library's surface changed, `docs/reference/libraries.md` says so.

## Notes

- **Verify against a real VSCode, not against a successful import.** Install
  (`./scripts/install.sh`), confirm `config: loaded` in `/usr/bin/log show
  --predicate 'subsystem == "dev.antony.Modaliser"'`, then ask the human to
  press the keys. A shell alias shadows `log` — use `/usr/bin/log`.
- A wedged first launch is a known hazard on this machine and is not your bug:
  a freshly signed bundle can hang pre-`dyld` awaiting Gatekeeper's scan, and
  LaunchServices then routes every later "open" to the stuck process as a
  reopen event that times out. The tell is a process at ~32 KB RSS and 0% CPU.
  `pkill -f "/Applications/Modaliser.app/Contents/MacOS"` and relaunch.
- `[` and `]` are punctuation, so they sit outside every jump-label alphabet on
  this screen by construction — no collision to check, unlike the letter rows.

## Decision log

### The commands, established against the shipped bundle (VSCode 1.136.2)

Read out of
`/Applications/Visual Studio Code.app/Contents/Resources/app/out/vs/workbench/workbench.desktop.main.js`,
as k2 established is the only trustworthy source for this app.

| | `workbench.action.previousEditor` | `workbench.action.nextEditor` |
|---|---|---|
| mac primary | `⌥⌘←` (`2575` = CtrlCmd+Alt+LeftArrow) | `⌥⌘→` (`2577`) |
| mac secondary | `⇧⌘[` (`3164` = CtrlCmd+Shift+BracketLeft) | `⇧⌘]` (`3166`) |
| non-mac primary | `2059` = Ctrl+PageUp | `2060` = Ctrl+PageDown |
| `when` clause | **none** | **none** |

Four properties the leaf asked about, all read off the registration rather
than guessed:

- **No `when` clause, weight 200.** The chord is live from anywhere in the
  workbench — which is exactly what makes the focus problem reachable.
- **They cross editor groups.** `navigate` takes the active group's
  *sequential* editor list (`getEditors(1)`); past either end it calls
  `findGroup({location: NEXT|PREVIOUS}, group, /*wrapAround*/ true)` and
  returns that group's first/last editor.
- **They wrap.** The wrap-around walk is bounded by a visited-id set, so it
  terminates on a single group and cycles the whole window otherwise.
- **They survive the terminal.** Both ids sit in the default
  `terminal.integrated.commandsToSkipShell` array, so the workbench handles
  the chord instead of the shell swallowing it. Without this the whole
  "cycle while the terminal has focus" case would be unreachable and the
  leaf would have no answer at all.

### The focus-first clause is REAL, and the source says why

This was the one claim worth trying to disprove, because the cycle command
ends in `group.openEditor(editor)` with no options — and an editor opened
with `preserveFocus` unset normally focuses itself. If it did, `[` and `]`
would need no focus half and the leaf would collapse to two bare chords.

It does not. The open path ends:

```js
!options?.preserveFocus && this.shouldRestoreFocus(previouslyActiveElement)
  ? pane.focus()
  : /* only reorders windows */
```

and `shouldRestoreFocus(el)` is true only when `el` is falsy, is the
document body, is the pane itself, is not an element, or **is contained
within `this.editorGroupParent`**. Focus sitting in the terminal or the
explorer fails every branch, so `pane.focus()` is never called and focus
stays where it was. `groupsView.activateGroup` does not rescue it either:
`doSetGroupActive` guards on `if (this._activeGroup !== e)`, and focus
moving to the terminal never changed which editor group is *active*.

So: the tab changes under you and you cannot type into it. The human's
report is the source's behaviour, and "focus, then cycle" is one op.

### What the library gained: two chord thunks and one constructor

**Taken.** `(modaliser apps vscode)` gains `previous-editor` /
`next-editor` (bare thunks, matching `toggle-terminal` /
`focus-explorer` / `focus-editor` in shape and in kind — VSCode's own
default chords, a fact about the app), plus `editor-cycler`, a
constructor taking keyword opts:

```scheme
(editor-cycler 'previous)                       ; focus-editor, then ⌥⌘←
(editor-cycler 'next 'focus my-strict-focus)    ; your chord, then ⌥⌘→
(editor-cycler 'next 'focus #f)                 ; no focus step
```

The keyword-opts shape is the one `project-provider` already established
in this file, and `'cycle` is the same kind of seam as its `'enumerate`:
it defaults to the direction's chord and is what the tests drive, while
doubling as the escape hatch for a user who has bound their own cycle
command in `keybindings.json`.

**Why the combinator rather than leaving the composition to config.** The
config *could* write `(λ () (my-focus) (code:next-editor))` — one line, and
that was the serious alternative. Two things decided against it:

1. **The focus half is a fact about VSCode, not a preference.** *Which*
   focus chord is the user's (their `ctrl+alt+i` is a strict-focus command
   the library cannot know about, and cmd-1 is the leftmost group rather
   than the active one — which is why the focus thunk is a parameter). But
   *that a focus step is needed at all* is the finding above, and it belongs
   next to the evidence for it, not restated in every config that binds the
   row.
2. **It is the seam for a behaviour we cannot fully pin offline.** The read
   above is static; if live use shows the focus step redundant or wrongly
   ordered, one definition changes rather than two config files (the human's
   and the shipped example).

The alternative of exporting a bare generic "do A then B" was rejected as a
shallow module: it would carry none of the above, and it is not VSCode's.

## Verification

**Offline, all green.**

- `swift build` clean; `swift test` — **1247 tests in 103 suites passed**.
- `./scripts/check-portable-surface.sh` OK; `./scripts/check-decision-free.sh` OK.
- Six new tests in `ModaliserAppsVscodeLibraryTests`, all driving the
  `'focus` / `'cycle` seams so nothing posts a real keystroke (ADR-0023).
- **The order test was watched failing before it was trusted.** Swapping the
  two lines in `editor-cycler` to cycle-then-focus turned
  `editorCyclerFocusesBeforeCycling` red on exactly the expectation that
  states the order; restoring it turned it green again. A control that has
  never been seen to fail is not a control.

**In the installed app.**

- `./scripts/install.sh` → `/Applications/Modaliser.app` (the bundled
  `Scheme/` tree verified against `Sources/` by the packaging guard,
  ADR-0019), relaunched, and `Modaliser Scheme runtime initialized
  (config: loaded)` in the log — so `code:editor-cycler` resolves out of the
  freshly mirrored `sys/` tree and the human's two new rows compose. Process
  healthy (96 MB RSS), no config errors.
- `keybindings.json` checked: `ctrl+alt+i` → `workbench.action.focusActiveEditorGroup`
  is present, and nothing in it rebinds alt-cmd-Left/Right away from the
  cycle commands. So the human's rows have the strict-focus half they claim.

**Live press: confirmed by the human.** `[` and `]` cycle the editor from the
F17 VSCode screen — *"that works"* — including from the terminal and the
explorer, which is the case the whole leaf exists for. The Done-when's first
clause is closed.

**No ADR.** Same ruling k2 recorded for the storage-state reader, and for the
same reason: the choice sits behind a seam small enough to reverse in one
definition, so the durable record is the library header and
`docs/reference/libraries.md`, not a decision record. Nothing here hardens a
term either, so `CONTEXT.md` is untouched.
