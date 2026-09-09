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
