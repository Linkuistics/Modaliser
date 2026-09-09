# grove-leaf-reveal-k3

## Goal

Deliver requirement 5: from the F17 VSCode screen, open the live grove task file
belonging to *this window's* worktree, with the explorer landing on it.

The human runs several groves at once — one VSCode window per worktree — and
currently opens each grove's live leaf by hand. "This window's worktree" is the
whole point: the operation must resolve the worktree from the window it was invoked
from, not from a configured path and not from whichever grove ran last.

## Context

Read the root brief's "Contracts settled with the human" and "Test seams" first.
Both were agreed with the human in `plan-k1`; the seam in particular is not a
suggestion to re-derive.

**The chain this leaf builds**, each link already decided:

1. **Frontmost VSCode window → folder path.** Join the window's title to VSCode's
   own state file: `windowsState.openedWindows[].folder` carries an exact `file://`
   URI per open window, and the title's last em-dash segment is that folder's
   basename. The state file is authoritative for the path; the title only matches
   against it.
2. **Folder path → live leaf path.** `(modaliser tools grove)` asks `grove-llm`,
   through the portable shell seam. Grove's own CLI is the authority on which verb
   answers "the next live leaf" and what it prints — read its `--help` rather than
   trusting a transcription. It exits zero with an empty result when a tree has no
   live leaves, and the directory may not be a grove at all; both are ordinary
   outcomes to handle, not errors to surface.
3. **Leaf path → open and reveal.** Hand the path to the `code` CLI, then send one
   chord to focus the explorer. `explorer.autoReveal` is true, so the file is
   already selected in the tree by the time the explorer takes focus.

**Two things to establish empirically rather than assume**, both flagged during
requirements and neither settled:

- Whether the `code` CLI reliably opens the file in the window that owns its folder,
  or in the last-focused window. If it is the latter, focus the target window first
  — Modaliser can already focus a window by id.
- Whether the state file is fresh enough at press time. It is written on window
  state change rather than continuously, so a window opened seconds ago may not be
  in it yet. Decide what the operation does when the front window has no entry: say
  nothing, or say something.

**Pin the setting you depend on.** Set `explorer.autoReveal` explicitly to true in
the human's VSCode settings rather than resting on an inherited default. Their
settings file contains trailing commas and comments — it is JSON-with-comments, so
edit it as such.

## Done when

- `(modaliser tools grove)` exists, resolving a worktree to its live leaf path via
  `grove-llm` through the portable shell seam, and handling both "not a grove" and
  "no live leaves" as ordinary results.
- `(modaliser apps vscode)` gains the workspace resolver: a **pure** function over
  the state-file *text* returning the open workspaces (folder path and name), with
  the file read a single call no test exercises.
- The composition is bound on the F17 VSCode screen in the human's config, and
  appears in `examples/vscode.scm`.
- Pressing the key in a VSCode window whose folder is a grove worktree opens that
  grove's live leaf and leaves the explorer focused on it — verified against at
  least two concurrently-open worktrees, since resolving the *right* one is the
  requirement.
- Tests drive the parser from a fixture captured from a real state file, and drive
  anything that spawns through a canned runner on the shell seam. Nothing runs
  `grove-llm` or `code` for real under `swift test`.
- `swift build` and `swift test` green; `./scripts/check-portable-surface.sh` and
  `./scripts/check-decision-free.sh` both pass.
- The new library is documented alongside its peers in `docs/reference/libraries.md`.

## Notes

- **Neither library imports the other.** The composition lives in user config. A
  grove reference inside the VSCode library, or a VSCode reference inside the grove
  library, is the thing this factoring was chosen to prevent.
- **Capture the fixture from real data, then treat it as frozen.** Its value is
  that it is a real state file's shape; a hand-written approximation tests the
  approximation.
- **The state file's format is undocumented and can change across VSCode releases.**
  That risk was accepted with eyes open. Put the reasoning in the library header
  the way `dia.sld` and `nvim.sld` carry theirs. The `plan-k1` assessment is that
  this does *not* earn an ADR — it fails the hard-to-reverse limb, being one pure
  function behind a seam — but disagree explicitly if you find otherwise, rather
  than re-deriving it.
- The human's config is a separate tree at `~/.config/modaliser/` with its own
  `CLAUDE.md` scoped to editing configuration. Changes there are not carried by
  this repo's commit.

## Decisions (running log)

**The two empirical questions the brief flagged, both answered from the
shipped source rather than from a guess.**

- **`code <file>` routes to the window that owns the folder** — not to the
  last-focused one. Read out of the shipped main process (VSCode 1.136.2,
  `/Applications/Visual Studio Code.app/Contents/Resources/app/out/main.js`):
  the CLI open path, with files and no folder argument, calls a
  `findWindowOnFilePath` helper that returns the window whose opened folder
  `isEqualOrParent` the file URI — preferring the **longest** such folder when
  several nest — and falls back to the last active window only when no window
  owns the file. The chosen window is focused by the same call that sends it
  the file (`doOpenFilesInExistingWindow` → `focusMainOrChildWindow`). So the
  "focus the target window first" contingency the brief allowed for is not
  needed. Two flags would break it and are therefore absent: `-r` forces the
  last active window, `-n` a new one; so does `window.openFilesInNewWindow` if
  a user sets it, which the human has not.

- **State-file freshness: the miss is reported, not papered over.** The file
  is written on window state change, so a window opened seconds ago can be
  absent. Rather than choose "say nothing" or "say something" in the library,
  every step of the chain answers `#f` and the SCREEN decides — which is
  ADR-0021 applied to a degradation rather than to a key. The shipped example
  and the human's config both put a `dialog-info` there, on the reasoning that
  a silent no-op on a key you meant to press is worse than an interruption;
  deleting that line is a one-line change and needs no library edit.

**Two measurements redirected the design, and both are recorded at their
decision sites rather than only here.**

- **Parsing the whole state file costs 899 ms.** The file is ~100 KB and
  `windowsState` is its last 5%; handing all of it to `(modaliser json)` was
  timed at 899 ms on a debug build — squarely inside ADR-0014's stalled-tap
  territory for something on a key press. So the reader **slices** the
  `openedWindows` array out with a bracket scan (string-aware, so a `]` inside
  a string is text) and parses only that. The scan reads a char vector bridged
  once, for the reason `(modaliser json)`'s own header sets out at length.
  Without the measurement the obvious implementation — parse, then `json-ref`
  twice — would have shipped.

- **`code <file>` against a running instance takes ~1.1 s to return.** Timed
  directly. That rules out a synchronous `run-shell`, so `reveal-file!` goes
  through `run-shell-async` and runs its follow-up from the callback. The
  ordering falls out for free: the explorer is focused *after* the open rather
  than racing it, which is also why "call `focus-explorer` yourself
  afterwards" is not an equivalent a caller could write.

**`reveal-file!` takes an OPTIONAL follow-up, and that is ADR-0021, not
flexibility for its own sake.** It first sent the library's `focus-explorer`
unconditionally. But the human's screen deliberately does *not* use the
library's three chord ops: `vscode-screen-k2` established that VSCode's
defaults are not strict focus, and bound `ctrl+alt+t/e/i` in their own
`keybindings.json` instead. Sending shift-cmd-e after the open would have
bounced to the **editor** whenever the explorer already had focus — the exact
miss those bindings exist to avoid. Which chord reaches the explorer is a fact
about a machine, not about VSCode, so it is a parameter; the default stays
VSCode's own, which is what `examples/vscode.scm` ships.

**The command clears `GROVE_SIGNAL_FILE`.** `grove-llm pick` refuses when the
tree it resolves is not the one the *calling session* belongs to, identifying
that session by that variable. Found by observation, not by reading: the
first end-to-end smoke run returned a leaf for this worktree and `#f` for two
others that demonstrably have live leaves, because the test process had
inherited the variable from the grove session running it. A GUI-launched
Modaliser has none and would never trip it, but one started from an agent's
own shell would, and it would read as a broken lookup rather than as a guard.
Clearing it answers the guard truthfully — this invocation is not part of any
grove session — and makes the answer independent of how Modaliser was
started. `pick` is a read; every writing verb stays with the session that
owns the tree.

**`&&`, not `;`, between the `cd` and the CLI — and it has a test of its
own.** `pick` takes no directory argument; it walks up from the current
directory, so the `cd` *is* how the worktree is named. With `;` a failed `cd`
— a worktree moved or deleted since VSCode last recorded it, which is
ordinary — would leave the CLI running wherever Modaliser was launched and
answer about **that** grove. A wrong leaf opening silently is much worse than
no leaf opening.

**Both quoting tests assert the escape, not the absence of the payload.**
First written as "the command does not contain `; touch /tmp/pwned; `" — which
fails, correctly: the payload text *is* in the command, harmlessly, inside a
single-quoted word. A test phrased that way would have passed for the wrong
reason on any escaper that merely deleted the text. They now assert that every
`'` arrives as the `'\''` idiom.

**The fixture is a verbatim capture, and two decoys in it are the reason.**
`windowsState` was taken byte-for-byte out of a real `storage.json` and
wrapped as a document of its own (trimmed of ~96 KB of unrelated keys, nothing
else touched). It happens to carry `lastActiveWindow` **and**
`lastPluginDevelopmentHostWindow`, both with a `folder` key, both **before**
`openedWindows` — so a reader that hunted for folders rather than for the
array answers with the wrong window, and `prince-live-test` (not open at all)
is the tell. A tidy hand-written fixture would have had neither. The three
cases the real capture lacked — an empty window, a multi-root window, a remote
window — are hand-written and labelled as such.

**No ADR.** The brief's `plan-k1` assessment was that depending on an
undocumented state file does not earn one, failing the hard-to-reverse limb:
it is one pure function over text, behind a seam, pinned by a fixture test.
Nothing found here disagrees. The reasoning lives in the library header, as
`dia.sld` and `nvim.sld` carry theirs.

**`CONTEXT.md` gained two terms.** **Workspace** (VSCode) — the folder a
window is rooted at, as a real *path* — because the existing **Project** entry
is the same folder's *name*, and the distinction is exactly what this leaf
turns on: a name is not a location. And **Live leaf** (grove), because the
operation's whole subject had no word in the glossary.

**Verified against real data before the app build.** A throwaway smoke run
(deleted, not committed) drove the real chain with the live shell runner
installed: three concurrently-open worktrees each resolved to their own
distinct live leaf — `Modaliser.local-tree-for-vscode` →
`03-impl--grove-leaf-reveal-k3.md`, `InTheLoop` →
`01-requirements--product-direction-k1.md`, and the grove worktree → a leaf
five levels deep — and `/tmp`, which is not a working tree, to `#f`. That is
the "at least two concurrently-open worktrees" requirement demonstrated at the
library level; the live press is below.

### What the live press found (and it was not this leaf's code)

The first press said "No live grove leaf" in every window. The diagnostics —
a temporary row logging each link of the chain through `(modaliser log)`, since
`run-shell` discards stderr — showed the whole resolution working and only the
spawn empty:

    DIAG bundle=com.microsoft.VSCode
    DIAG focused-window=id=16492 pid=12040
    DIAG vscode-win id=16492 title=Modaliser.local-tree-for-vscode   (+3 more)
    DIAG statefile=…/globalStorage/storage.json chars=99571
    DIAG slice-chars=1961
    DIAG ws=…/Modaliser.local-tree-for-vscode                        (+3 more)
    DIAG focused-workspace-path=…/Modaliser.local-tree-for-vscode
    DIAG live-leaf=#f

A second pass logged the command and ran a hand-built variant beside it. The
hand-built one worked; the library's did not. The difference was the PATH.

**The tree-wide bug: the shell preamble was never quoted.** Every CLI-driven
module builds `export PATH=<derived>:$PATH; `, and the derived path comes from
the user's login shell. This machine's contains
`/Users/antony/Library/Application Support/Code/User/globalStorage/github.copilot-chat/debugCommand`
— VSCode's Copilot extension puts it there, and it has a **space**. Unquoted,
the shell word-splits it, and `export` is a POSIX **special** builtin, so its
error does not merely fail:

    zsh:export:1: not valid in this context: Support/Code/…
    exit=1

It **aborts the entire command line**. Nothing after the `;` ever runs, the
caller reads the empty result as ADR-0017's "the tool told us nothing", and
every op in every CLI-driven module silently no-ops while looking exactly like
a missing binary. On this machine that was paneru, tmux, zellij, wezterm,
kitty, iTerm and the nvim helpers, all quietly dead, and nobody had noticed —
ADR-0017's degradation path is what hid it.

Fixed centrally rather than at the two new call sites: `(modaliser terminal)`
now exports `tool-path-prefix`, single-quoted through the canonical
`sq-escape`, and the ten modules that each rebuilt the string now import it.
Fixing two sites and leaving eight known-broken siblings was not a defensible
option. Each module keeps its own one-line note on *why* it needs a preamble
(which tool lives where) — that was local knowledge, and consolidating the
string should not have cost it.

**The regression test carries a negative control.** It runs both forms in a
real `/bin/zsh` and asserts the quoted one reaches its command **and that the
unquoted one still does not**. Without the second half the test would pass on
any machine whose PATH has no space — that is, it would prove nothing, which
is precisely how this survived to be found by hand.

### Two things measured after the diagnostics, before shipping

- **The anchor scan now runs backwards.** The DIAG timings showed ~490 ms in
  `opened-windows-json` alone on the release build — the slice was 20× cheaper
  than the whole-file parse it replaced, and still a fifth of a second of the
  thread that owns the CGEvent tap. `windowsState` sits in the last 5% of the
  file and the key is unique, so direction cannot change the answer, only how
  much gets walked: backwards took it to ~40 ms. If VSCode ever moves the key
  to the front this becomes the slow direction — which is exactly where the
  forward scan already was, so the bet is one-sided.

- **The window list is sorted alphabetically**, at the human's request during
  the session. The enumeration's order is front-to-back stacking order, so it
  changes every time a window is focused, and a chooser whose rows move
  between presses cannot be learned. Case-insensitive (a human reading folder
  names is not thinking in ASCII; a plain `string<?` would sort every
  capitalised name ahead of every lowercase one) with the case-sensitive
  comparison as tie-break, so the order is **total** — two folders differing
  only in case cannot swap places either. The sort is a local stable insertion
  sort: LispKit ships no `list-sort` and no `set-cdr!` (an absence
  `blocks/herdr-list.sld` and `muxes/herdr.sld` each note), and the list is one
  entry per open editor window.

### Verified live, by the human, against real VSCode

After `./scripts/install.sh` and a relaunch (`config: loaded`, and the `sys/`
mirror carrying `tools/grove.sld` and the updated `apps/vscode.sld`), the
human pressed F17 `g` across several VSCode windows and confirmed: each opens
its **own** worktree's live leaf with the explorer landing on it, and the
project list under `w` is alphabetical.

### No `review-impl` leaf cut

The surface is larger than `vscode-screen-k2`'s and it includes a tree-wide
edit, so the question was live rather than reflexive. Against it: every claim
in the new code is pinned by an executable test (the parser off a real
capture, the join, the command shapes, the sort's totality), the two version-
sensitive facts were read out of the shipped VSCode bundle rather than
recalled, the PATH fix has a test with a negative control, and the human
confirmed the whole chain against the running app. The one part a fresh
context would genuinely add value on — did the mechanical ten-file edit break
a call site no test asserts? — was answered directly instead, by reading the
diff of all ten (the five backends with no command assertions in their suites
are the ones this was for). The in-session reviewer allowance went unspent.
