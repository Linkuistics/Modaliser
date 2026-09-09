# What is open inside a VSCode window comes from the accessibility tree, and terminals are not listed at all

## Status

accepted

## Context

`(modaliser apps vscode)` can already list VSCode's **windows** and say which
folder each is rooted at. Listing what is open *inside* one window — the editor
tabs, the terminals — needed a source, and VSCode offers no scripting dictionary
and no IPC socket, which is the constraint `apps/vscode.sld`'s header opens with.

Three candidate sources were investigated against VSCode **1.136.2** on the
developer's machine, by reading the shipped bundle
(`Contents/Resources/app/out/vs/workbench/workbench.desktop.main.js` and
`out/nls.metadata.json`) and by probing the live application. Every claim below
is from one of those two, not from documentation.

**The per-workspace state database was the obvious lead, and it half-works.**
`~/Library/Application Support/Code/User/workspaceStorage/<hash>/state.vscdb` is
a SQLite file whose `ItemTable` holds two promising keys, and the `<hash>`
directory joins to a folder through its sibling `workspace.json` — a join key
Modaliser already has.

- `memento/workbench.parts.editor` **does** carry a complete editor listing: a
  recursive branch/leaf grid of editor groups, each leaf holding an `editors`
  array of `{id, value}` where `id` is the editor-input factory id and `value`
  is *serialised inner JSON* whose shape depends on that id. Three factories
  appear across the 28 workspaces on this machine; only the webview one carries
  a `title`, the file and untitled ones carry a resource and no name. A reader
  therefore needs a per-factory name rule and degrades to "no name" on a factory
  it has not seen.

- `terminal.integrated.layoutInfo` **cannot** carry a terminal listing, and the
  reason is structural rather than a matter of format. Its `terminals` entries
  are `{relativeSize, terminal}` where `terminal` is a persistent-process id
  integer — the shape `TerminalGroup.getLayoutInfo` emits, and the shape every
  one of the 19 workspaces holding the key had. The names live in the **pty
  host**, which substitutes a full attach-target object for that integer over
  IPC at restore time. Disk carries the join key and nothing else.

**The editor memento's cadence is what rules it out.** `EditorPart.saveState()`
is a `Component` hook on `storageService.onWillSaveState`, and that event fires
from three places only: `AbstractStorageService`'s idle flush, whose
`DEFAULT_FLUSH_INTERVAL` is **60 000 ms**; the window *losing* focus
(`onDidChangeFocus(a => { a || flush() })`); and shutdown. A four-minute poll of
a live `state.vscdb` recorded zero writes while its window sat idle, consistent
with a flush that writes nothing when nothing changed. So the stored editor list
lags reality by up to a minute, and the blur flush cannot rescue the press that
needs it: the leader fires while VSCode is still frontmost, and the provider
reads at come-to-rest.

**One fact reframes the whole question.** `workbench.action.openEditorAtIndex1..9`
registers with `mac: { primary: WinCtrl | Digit }` and `when: void 0` — ctrl-1 …
ctrl-9, live from anywhere in the workbench. Jumping to the Nth editor needs no
enumeration at all. Enumeration is needed only to put a **name** beside the
number, which raises the bar rather than lowering it: a name that disagrees with
the index beside it is worse than no name, because the jump still happens, to the
wrong file. A source that is a minute stale fails exactly there.

**The accessibility tree turned out to be cheap, and to have a clean anchor.**
VSCode is Electron, so its tab strip is rendered DOM mirrored into AX. Measured
with a `swiftc -O` walker against the live app, a pruned, early-exiting descent
of the focused window's tree costs **31.6 ms on the first call and a 3.1 ms
median warm**, visiting 80 nodes — reproduced 15 minutes apart. That is cheaper
than the `list-windows` sweep the projects panel already runs at every
come-to-rest (8–29 ms warm, past 200 ms cold). Unpruned whole-window walks of
the same windows measured 12–80 ms, so the pruning is the entire difference.

## Decision

**The editor listing is read from the accessibility tree at come-to-rest, and
acted on through `AXPress` on the tab that was read. There is no terminal
listing.**

- **Editors.** The rows are the `AXTabButton`-subroled children of the focused
  window's editor tab strip: name from `AXDescription` else `AXTitle` (the split
  between those two is *not* stable and varied between two reads of the same tab
  group), path from the first child group's `AXDescription`, active tab from
  `AXSelected`. The strip is identified by an **absence**: every other tab group
  in the window — panel switcher, activity bar, secondary sidebar — carries the
  `activityBarAriaLabel` on its own `AXDescription`, and the editor strip alone
  has none.

- **The action is `AXPress` on the element the row was read from**, so the row
  and what it does come from one snapshot and cannot disagree — the discipline
  the projects panel already follows for its per-Visit assignment. Measured at
  0.06 ms and verified to move `AXSelected` between tabs in a scratch window.

- **Terminals get no panel.** Three independent blockers, any one fatal: no name
  on disk (above); nothing in the AX tree in the state that matters, because AX
  mirrors *rendered* DOM and the panel is hidden in every one of the developer's
  windows, with `terminal.integrated.tabs.hideCondition` defaulting to
  `singleTerminal` so the tab list is absent even when shown; and
  `workbench.action.terminal.focusAtIndex1..9` registering with `primary: 0`,
  no keybinding on any platform, so a synthetic keystroke cannot reach it. The
  replacement is the shape editor cycling already uses: a strict-focus chord,
  then `focusNext`/`focusPrevious`.

- **`editor.accessibilitySupport` is pinned to `"off"`** by any configuration
  that uses the editor listing. Reading the tree is what makes Chromium build
  one, and under the `"auto"` default VSCode would then flip the editor into
  screen-reader-optimised rendering. The tab strip does not depend on the editor
  being accessible — with the pin in place the editor's own text area reports
  itself unavailable while the tab strip is fully populated — so the pin costs
  nothing and is the same kind of explicit pin `explorer.autoReveal` already
  gets.

## Considered options

- **Read `memento/workbench.parts.editor` from the SQLite state database.** The
  option this leaf expected to take, and it is a complete listing with group
  structure and MRU order that AX does not expose. Rejected on the 60-second
  cadence, above: the failure mode is a row whose name and whose index disagree,
  which is a silent wrong jump. Reading it is genuinely in reach — LispKit ships
  a SQLite library, so this needs no subprocess, only a host-installed seam of
  the kind ADR-0023 already establishes — so the cost was never the obstacle.
  **Reopen if** VSCode gains a flush on editor open/close, or if a listing is
  ever wanted for a window that is *not* frontmost, where AX gives nothing and
  stored state is the only source there is.

- **Pair the stored listing with `code <path>` instead of an index.** This
  repairs the failure mode rather than the staleness: a stale row reopens the
  file it names instead of jumping to the wrong one, and a file opened since the
  last flush is simply missing. Rejected because `code` against a running
  instance was measured at ~1.1 s to return — acceptable for opening a grove
  leaf, absurd for switching tabs — and because a listing that is quietly a
  minute behind is a worse thing to look at than one that is right.

- **Numbered slots, no enumeration.** Priced rather than dismissed, and it is
  what terminals get. For editors it collapses to *do not build the panel*,
  since ctrl-1 … ctrl-9 already are the numbered slots and a panel of nine
  unnamed rows adds nothing over pressing them. Two caveats found while pricing
  it, both from the registration: the index is active-group relative, and the
  ids are **not** in the default `terminal.integrated.commandsToSkipShell`
  array — unlike the editor-cycling commands, which are — so ctrl-3 pressed with
  the integrated terminal focused reaches the shell.

- **`ax-click-handle`, the primitive that already exists.** Rejected: it
  synthesises a mouse click at the element's centre, so it needs the tab to be
  on screen and it moves the cursor. `AXUIElementPerformAction` needs neither.
  The existing primitive stays for the cases it was written for.

## Consequences

- `AccessibilityLibrary` gains two procedures: a tab-strip reader and an
  `AXPress` over a handle. The bridge grows by the smallest amount that keeps
  the domain knowledge in Scheme, which is what that file's header already
  promises — nothing VSCode-specific goes into Swift.

- **The listing is frontmost-window-only, by construction.** AX gives a live
  window's rendered tree, so there is no cross-window editor listing and no
  cheap way to get one. That matches what the screen asks for and closes off a
  feature nobody has asked for.

- **The anchor is an absence, and absences are the fragile kind of anchor.** If
  a future VSCode gives the editor tab strip its own aria-label, the rule stops
  matching and the listing goes *empty* rather than wrong — which is the right
  direction to fail, and which a test over a captured fixture will not catch.
  The mitigation is placement: the join is one pure function over rows, so a
  changed shape is a one-function fix, and an empty listing is what the screen
  shows on a miss.

- **Matching the aria-label's text would not have worked.** Both strings a
  reader might reach for — `activityBarAriaLabel` and the terminal tab list's —
  are localised, resolved out of `out/nls.metadata.json` rather than compiled
  in. Discriminating on the *presence* of a localised label is locale-safe;
  discriminating on its text is not. Any future AX anchor in this app is subject
  to the same rule.

- **A newly opened window can answer nothing, and it is not the tree's fault.**
  A window sitting behind a modal — the workspace-trust prompt is the one met
  here — renders only the modal, so AX shows only the modal. Same class as the
  stale-read miss: the screen shows an empty listing, which is honest.

- ADR-0023 is untouched: nothing here reaches outside the process. AX is an
  in-session read like window enumeration and keystroke emission, which that
  ADR's closing paragraph already places outside its scope and names as the next
  place this class would surface.
