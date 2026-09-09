# vscode-screen-k2

## Goal

Deliver requirements 1–4: an F17 screen that appears when VSCode is frontmost and
lets the human choose among the open VSCode windows/projects, focus the terminal,
focus the explorer, and focus the editor.

Ship the machinery as `(modaliser apps vscode)` plus a shipped example config, and
bind the keys in the human's own config. Requirement 5 is leaf `grove-leaf-reveal-k3`
and is explicitly *not* this leaf's work — but this leaf's window surface is what it
builds on, so design that surface knowing a caller will need a window's **folder
path**, not just its title.

## Context

Read the root brief's "Contracts settled with the human" and "Test seams" first;
both were agreed with the human in `plan-k1` and are not reopened here.

**The two shapes to copy.** `lib/modaliser/apps/dia.sld` is the model for this
library: a utilities-only app library exporting a chooser *source* and a *focus
action*, with a header that states plainly that the screen — keys, labels, walks —
is the user's under ADR-0021. `~/.config/modaliser/app-trees/dev.zed.Zed.scm` is
the model for the screen itself: a handful of `(key …)` rows over `send-keystroke`,
included from `config.scm` and listed in its `(configuration …)` call.

**Everything the window surface needs already exists.** `(modaliser window)`
supplies window enumeration and focus-by-id; each window arrives as an alist whose
display text is the window title, whose owner name is the app, and which carries
the bundle id and a window id. Filtering to VSCode is a bundle-id test. The
project name is the last em-dash segment of the title — VSCode titles are
`[<active editor> — ]<folder name>`, verified against four live windows.

**Requirement 4 has no Zed precedent** — the Zed screen has no "focus the editor"
row — so establish the right VSCode command yourself rather than copying.

## Done when

- `(modaliser apps vscode)` exists, exporting at minimum a window source suitable
  for a chooser and a focus action, and importing nothing outside `(scheme …)`,
  `(srfi …)` and other `(modaliser …)` libraries.
- A shipped `examples/vscode.scm` composes the screen, and the existing
  example-loading test covers it.
- The human's `~/.config/modaliser/` carries the screen: an `app-trees/` file named
  for the VSCode bundle id, included from `config.scm` and listed in its
  `(configuration …)` call.
- Pressing the F17 leader inside VSCode shows the screen, and all four operations
  work against a real VSCode.
- `swift build` and `swift test` green; `./scripts/check-portable-surface.sh` and
  `./scripts/check-decision-free.sh` both pass.
- The new library is documented alongside its peers in `docs/reference/libraries.md`.

## Notes

- **The decision-free check is strict zero.** One authored key or label anywhere
  under `lib/modaliser` fails it. Keys and labels belong in the example config and
  the human's config; the library exports only ops and sources.
- **ctrl-` is a toggle, not a focus.** It hides the panel when the terminal already
  has focus. The human asked for ctrl-` by name, so implement that — and tell them
  about the strict-focus alternative rather than substituting it silently.
- **Ask the human, while editing their config, whether VSCode should displace Zed**
  as the global Applications-panel "Editor" and as the target of Settings → Edit.
  It is one line each and it is their call; the root brief has it on the horizon.
- The human runs the Vim extension, so treat any keystroke sent into the editor
  surface as arriving at a modal editor.
- Registration proves procedures resolve, not that they work (`CLAUDE.md` records
  a shipped library whose primitives all resolved and permanently returned null).
  Verify against a real VSCode, not against a successful import.

## Decisions (running log)

**The three panel chords, established against the shipped bundle rather than
memory.** Read out of `/Applications/Visual Studio Code.app/Contents/Resources/
app/out/vs/workbench/workbench.desktop.main.js` (VSCode 1.136.2), which is where
each command's `keybinding:` is registered:

- **Terminal — ctrl-`** (`workbench.action.terminal.toggleTerminal`), as the
  human asked. The strict-focus command `workbench.action.terminal.focus` has
  `keybinding:{when:…activePanel=="terminal"…, primary:2066}` — ⌘↓, and *only*
  while the terminal is already the active panel — so it is not reachable as a
  general "focus the terminal" chord. Confirms the brief: ctrl-` is a toggle and
  hides the panel when the terminal already has focus.
- **Explorer — ⇧⌘E** (`workbench.view.explorer`, registered
  `openCommandActionDescriptor.keybindings:{primary:3107}` = CtrlCmd|Shift|KeyE).
  It is **not** a sidebar toggle: the action body is
  `!isViewContainerVisible(id) || !hasFocus("workbench.parts.sidebar")
   ? openViewContainer(id,true) : editorGroupService.activeGroup.focus()`.
  So it focuses the explorer from anywhere, and jumps to the **editor** when the
  explorer already has focus. Good enough for requirement 3, and worth stating
  because "it closes the sidebar" is the widely-repeated and wrong version.
- **Editor — ⌘1** (`workbench.action.focusFirstEditorGroup`,
  `keybinding:{weight:200,primary:2070}` = CtrlCmd|Digit1).
  `workbench.action.focusActiveEditorGroup` is the exact command but registers
  `f1:!0` with **no** `keybinding:` — no default chord — so a keystroke cannot
  reach it without the human adding a binding. ⌘1 differs only when several
  editor groups are open, where it goes to the leftmost rather than the active
  one. Requirement 4 had no Zed precedent; this is the establishment the brief
  asked for.

**The window item's display text is the project name; the raw title is kept
beside it.** `list-windows` yields `'text` = the window title, and VSCode's
default macOS title template is `${activeEditorShort}${separator}${rootName}
${separator}${profileName}` with `${separator}` = `" — "` — both read out of
the same bundle. The chooser fuzzy-matches and displays `'text`, so `'text`
becomes the last em-dash segment (the folder name) and the untouched title moves
to `'title`. `focus-window!` rebuilds the choice alist with the **real** title,
because `WindowManipulator.focusWindow` uses the title as its fallback match when
the window id misses — the same reason `wms/paneru.sld` has a `strip-focus-choice`
rather than passing its rows straight through.

**Caveat recorded rather than engineered around:** the last segment is the folder
name only under the *default* profile, since a named profile appends
`${profileName}` after `${rootName}`. The human is on the default profile (their
four open windows carry no profile in `storage.json`). Leaf 03 must not join on
the last segment alone — which is why the item keeps `'title`: a robust join
tests *every* em-dash segment against the folder basenames `storage.json` knows.

**The pure seam is `windows-of`, over an enumeration passed as an argument.**
Filtering to the VSCode bundle id, extracting the project name and shaping the
chooser item are all pure and take the window list as a parameter; `window-source`
is the one-line impure wrapper that calls `list-windows`. Exactly the shape
`wms/paneru.sld` uses for its join, and it keeps every assertion in the test suite
off the live accessibility sweep.

**Strict focus, at the human's direction — and it lands in their config, not
the library.** Asked about the three non-strict defaults, the human replied that
ctrl-` was them describing how VSCode can be driven rather than naming the chord
they wanted, and asked for the strict-focus bindings. So
`~/Library/Application Support/Code/User/keybindings.json` gains
`ctrl+alt+t` → `workbench.action.terminal.focus`, `ctrl+alt+e` →
`workbench.files.action.focusFilesExplorer` and `ctrl+alt+i` →
`workbench.action.focusActiveEditorGroup` (backup at
`keybindings.json.pre-modaliser.bak`), and the three screen rows send those
chords as plain `send-keystroke` lambdas.

The explorer got the same treatment as the other two even though the question
only named terminal and editor: `workbench.view.explorer` bounces to the editor
when the explorer already has focus, which is the same class of miss, and
leaving one of three on a non-strict chord would have been an inconsistency
nobody chose.

**The library keeps the DEFAULT chords, and the human's rows do not use its
three ops.** A chord that exists only because of an entry in one person's
`keybindings.json` is a decision, and ADR-0021 puts it in user config; the
library's `toggle-terminal` / `focus-explorer` / `focus-editor` stay on VSCode's
own defaults, which is the facility that is correct for every user and is what
`examples/vscode.scm` ships. The human's screen therefore imports the library
for the window surface alone — which is exactly the split the example's header
argues for, arrived at from the other direction.

**Chord choice was verified free, not assumed.** `ctrl+alt+t/e/i` encode as mac
primaries 818/803/807; a search of the shipped 1.136.2 bundle found zero
`primary:` registrations for any of the three, and the human's 31 existing
bindings use none of them. `cmd+0` was the first candidate for the editor and
was rejected on the same evidence: it is already
`workbench.action.focusSideBar`.

**Applications panel: a new row rather than a displacement.** The human chose
`v` → VSCode alongside the existing `e` → Zed, and left Settings → Edit on Zed.
The horizon item in the root brief is settled that way and needs no follow-up.

**Screen shape: five flat rows, per plan-k1.** The three focus operations sit
beside the project selector at top level rather than under a Focus group — the
decision `plan-k1` already recorded ("'Top level' means the F17 VSCode screen,
five flat rows"), with the fifth row reserved for `grove-leaf-reveal-k3`. The
editor chords `p` / `P` / `/` / `f` carry over from
`app-trees/dev.zed.Zed.scm` unchanged so the muscle memory crosses.

**Verified live, by the human, against real VSCode.** After `./scripts/install.sh`
(release build ~23 min) and a relaunch, `/usr/bin/log show --predicate
'subsystem == "dev.antony.Modaliser"'` reported `config: loaded`, and the `sys/`
mirror had picked up both `lib/modaliser/apps/vscode.sld` and
`examples/vscode.scm`. The human then pressed F17 in VSCode and confirmed all
four operations: the project list, and the three focus rows — each idempotent,
which is what the strict-focus bindings bought.

Two follow-ups came back with that confirmation, and neither is a defect:

- **"I don't see the option to select the current grove step in the explorer."**
  That is requirement 5, which is `grove-leaf-reveal-k3` by the root brief's
  own decomposition and explicitly not this leaf. No action.
- **"I would rather that project list at the top level with the standard
  'asdfg' extensible shortcut assignment."** A new concern, so it goes to the
  tree rather than inline (`references/decompose.md`): cut as
  `vscode-project-panel-k4`. It is not a tweak — a jump-labelled panel needs an
  Edge provider minting states and edges, and paneru's is ~120 lines of the
  subtlest machinery in the tree, so *whether to duplicate it, extract a shared
  one, or share only the block* is a decision worth a session with its own
  context. The leaf body carries all three routes and the evidence for each.
  It lands after `grove-leaf-reveal-k3`, which keeps the requirement with the
  weight behind it next.

**No `review-impl` leaf cut.** The surface is small and every claim in it is
either pinned by an executable test (the pure trio, with the separator mutation
watched to fail), read directly out of the shipped VSCode bundle rather than
recalled (all three chord registrations, the title template), or confirmed by
the human against the running app (all four operations). What an adversarial
read would add over that is not nothing, but it is not the second-review
boundary `references/execute.md` describes either, and the in-session reviewer
allowance was never spent.
