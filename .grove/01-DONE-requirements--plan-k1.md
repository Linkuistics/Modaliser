# plan-k1

## Goal

Establish what a VSCode integration for Modaliser should be, in the human's own
words, and leave the tree shaped so the work can proceed.

## Context

The human's requirement, verbatim, across two messages:

> I want the following in the top level for vscode: 1. select from the open
> VSCode windows/projects, 2. focus on the terminal (ctrl-~) 3. focus on the
> explorer 4. focus on the editor.

> and 5. select the currently active grove task file in the explorer

Facts established by reading, not by asking:

- **No VSCode support exists** anywhere in the Scheme tree. `lib/modaliser/apps/`
  holds five terminal emulators plus `dia.sld`; nothing matches vscode / Code.app /
  `com.microsoft.VSCode`.
- **VSCode is installed** as `com.microsoft.VSCode`, with the `code` CLI symlinked
  at `/usr/local/bin/code`.
- **`~/.config/modaliser/app-trees/dev.zed.Zed.scm` is the working template** for
  items 2–4: a six-row `(screen 'dev.zed.Zed …)` whose rows are already
  `(key "t" "Terminal" (λ () (send-keystroke '(ctrl) "`")))` and
  `(key "e" "Project Panel" (λ () (send-keystroke '(cmd shift) "e")))`. VSCode's
  default macOS chords are the same.
- **Two leaders.** F18 → `global-screen` (spaces, Settings, `w` windows,
  Applications panel, Search panel). F17 → the per-app screen selected by the
  frontmost app's bundle id. Adding an app = drop `app-trees/<bundle-id>.scm`,
  `(include …)` it in `config.scm`, list the screen in the `(configuration …)` call.
- **Window selection has all its primitives.** `(modaliser window)` exports
  `list-windows` / `list-current-space-windows` / `focus-window`; each window is an
  alist of `text` (title), `subText` (owner name), `icon` (bundle id),
  `iconType`, `windowId`, `ownerPid`. `TODO.md` records that a window switcher
  already composes `list-windows` with `focus-window` in user config.
- **`apps/dia.sld` is the template for a library facility** — utilities only, with
  the per-app screen's keys and labels left to user config (ADR-0021).
- **`examples/chrome.scm` is the precedent for a shipped example config**, and
  `ConfigDslTests.exampleConfigsLoadWithoutErrors` load-tests every example, so a
  shipped example cannot rot silently.
- **Item 5 is the only requirement with no existing primitive.** It needs the front
  VSCode window's *workspace path* (`list-windows` yields the title, not the path),
  then the grove lookup, then a reveal-in-explorer mechanism.

## Done when

- Every open question with an interdependent answer is settled with the human and
  recorded below. **Met** — six decisions.
- The root `BRIEF.md` charter carries the goal, the agreed test seams, the
  contracts a build session must honour, and the horizon. **Met.**
- The build leaves are cut, each a vertical slice that can be demoed on its own.
  **Met** — two `impl` leaves.

## Notes

**Requirements restated as behaviour, for the leaves downstream.** On the F17
screen that activates when VSCode (`com.microsoft.VSCode`) is frontmost:

1. Select from the open VSCode windows/projects, and focus the chosen one.
2. Focus the terminal — the human specified ctrl-` explicitly.
3. Focus the explorer.
4. Focus the editor.
5. Open the live grove task file for *this window's* worktree and land the
   explorer on it.

**Three details a build session must not rediscover the hard way.**

- **ctrl-` is a toggle, not a focus.** It is bound to
  `workbench.action.terminal.toggleTerminal`, so pressing it while the terminal
  already has focus *hides* the panel. `workbench.action.terminal.focus` is the
  strict-focus command and has no default macOS binding. Honour the human's
  literal request (ctrl-`) and surface the difference rather than silently
  substituting.
- **The Vim extension is installed** (`extension.vim_tab` in the human's
  `keybindings.json`), so anything synthesising keystrokes into the *editor*
  meets a modal editor. This is why item 5 was designed down to one chord.
- **ADR filenames in this repo stay numbered.** `CLAUDE.md` requires
  `docs/adr/00NN-slug.md` with bare `ADR-00NN` citations and says not to "fix" it
  to slugs; grove's own `ADR-FORMAT.md` asks for slug names. Project instructions
  win. Several hundred bare citations depend on it.

**On whether the storage.json dependency earns an ADR.** It fails the AND test on
reversibility — swapping the resolver is a contained change behind one pure
function — so the assessment here is *no ADR*, and the reasoning belongs in the
library header the way `dia.sld` and `nvim.sld` carry theirs. A build session that
disagrees should say why rather than re-deriving this from scratch.

## Decisions (running log)

**Where the work lands: both the repo and the personal config.** The machinery
goes into the Modaliser repo as a `(modaliser apps vscode)` facility shaped like
`apps/dia.sld`, plus a shipped `examples/vscode.scm` alongside `examples/chrome.scm`;
`~/.config/modaliser/` then binds keys to it. Chosen over config-only because
`.grove/` lives in this repo — a config-only deliverable would leave this grove's
commits empty of the work they claim to carry — and over repo-only because that
would finish the grove with nothing actually bound to a key. ADR-0021 still splits
them the same way: the facility is machinery, the keys and labels are decisions and
stay in user config.

**"Top level" means the F17 VSCode screen, five flat rows.** A new
`app-trees/com.microsoft.VSCode.scm` defines `(screen 'com.microsoft.VSCode …)`
with all five requirements as top-level rows — `zed-screen`'s shape exactly.
Chosen over putting the window selector on the F18 global screen as well: the
cost accepted is that crossing into a VSCode project from another app takes two
steps (launch VSCode, then F17), because F17 dispatches on the frontmost app's
bundle id.

**A VSCode window resolves to its worktree via VSCode's own storage JSON.**
`~/Library/Application Support/Code/User/globalStorage/storage.json` →
`windowsState.openedWindows[].folder` carries an exact `file://` URI per open
window (verified: all four of the human's current worktrees, plus `uiState`
geometry). Chosen over parsing the window title against configured search roots,
which was the recommendation; the human took exactness over convention. The
trade-off accepted and to be designed around: the format is undocumented (VSCode
1.136.1), can change across releases, and is written on state change rather than
live. The window title still supplies the *join key* (its last em-dash segment is
the folder basename) — but it no longer constructs a path, so a naming
convention is not load-bearing.

**Item 5 opens the leaf with `code -g` and focuses the explorer with ⇧⌘E.**
`explorer.autoReveal` is unset in the human's settings and so sits at its default
`true`, which means whatever opens the file *already* selects it in the explorer;
the remaining work is opening it. One chord rather than a typed path keeps the
synthetic-keystroke surface minimal, which matters because the human runs the Vim
extension. Two things a build session must establish rather than assume: whether
`code -g` reliably routes to the window owning that folder rather than the
last-focused one, and pinning `explorer.autoReveal` to an explicit `true` so the
behaviour rests on a stated value rather than an inherited default.

**Two libraries, not one: `(modaliser apps vscode)` and `(modaliser tools grove)`.**
The VSCode library holds only VSCode knowledge (enumerate open windows, resolve a
window to its folder, open a file, focus panels); the grove library holds only
grove knowledge (given a worktree, return its live leaf path via `grove-llm`).
Item 5 becomes composition in user config. `lib/modaliser/tools/nvim.sld` is the
exact precedent — it wraps an external tool and leaves the screen to the user,
stating the ADR-0021 split in its own header. Rejected: a single `apps/vscode`
carrying a `grove-llm` reference, which would ship a dependency on a tool almost
no Modaliser user has, and would weld two concerns that should move and be tested
apart.

**The storage.json resolver is tested through a pure parser.** A pure function
takes the storage JSON *text* and returns the open workspaces (folder path +
name); tests drive it from a fixture string captured from a real `storage.json`.
The file read stays one `read-file-text` call (`(modaliser util)`, already
portable over `(scheme file)`) that no test exercises. This satisfies ADR-0023
structurally rather than by discipline — there is no file-reading code path under
test that *could* leak to `~/Library` — and it puts the one seam at the highest
point, over the parse and the join, which is where all the risk is. It also makes
the undocumented-format risk a testable thing: when VSCode changes shape, the
fixture is updated and the test names what broke. Rejected: a path parameter with
a fixture file (real I/O under test, downgrading the invariant to a discipline),
and a full quarantined `(modaliser file)` seam mirroring shell/http (a new seam,
with check-script consequences, for one call site).
