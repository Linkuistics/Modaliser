# Modaliser.local-tree-for-vscode — brief

## Goal

Give VSCode a first-class place in Modaliser: an F17 screen that appears when
VSCode is frontmost, carrying five operations — choose among the open
windows/projects, focus the terminal, focus the explorer, focus the editor, and
open the live grove task file for that window's worktree with the explorer landing
on it.

The fifth is the one with weight behind it. The human runs several groves
concurrently, one VSCode window per worktree, and reaches the active leaf file by
hand in each. This automates a thing already being done four times over.

## Done when

- The five operations work from the F17 VSCode screen on the human's machine.
- The machinery ships in the repo as two libraries and a shipped example config;
  the keys and labels live in the human's own config (ADR-0021).
- `swift build` and `swift test` are green, and both invariant checks pass:
  `./scripts/check-portable-surface.sh` and `./scripts/check-decision-free.sh`.
- The libraries' surface is documented where `docs/reference/libraries.md`
  documents its peers.

## Decomposition

Two vertical slices, in dependency order. Each is demoable alone.

- **02 — the VSCode screen (requirements 1–4).** The app library's window surface
  plus the screen. Delivers four of the five operations by itself, and is what
  requirement 5 hangs its row on.
- **03 — the grove leaf reveal (requirement 5).** The grove library, the
  window→worktree resolver, and the open-and-reveal composition.

Neither carries a `review-impl` step yet. A review chain is lazy and earned: the
producing session cuts one as its last act only if it judges an adversarial read
necessary (`references/decompose.md`).

## Contracts settled with the human

These are decided. A build session implements them; it does not reopen them
without saying why. The reasoning behind each is in the `requirements` leaf's
running decision log.

- **Two libraries, separate concerns.** `(modaliser apps vscode)` knows only
  VSCode: what windows are open, which folder each belongs to, how to open a file
  and focus a panel. `(modaliser tools grove)` knows only grove: given a worktree,
  what its live leaf file is. Neither imports the other; user config composes
  them. `tools/nvim.sld` is the shape to follow, `apps/dia.sld` the shape for a
  window/tab source.
- **A window resolves to its worktree through VSCode's own state file** —
  `windowsState.openedWindows[].folder` in the user-level `globalStorage`
  `storage.json` — which carries an exact `file://` URI per open window. The
  window title supplies only the *join key* (its last em-dash segment is the
  folder basename); it never constructs a path, so no directory-naming convention
  is load-bearing. Accepted risk: the format is undocumented and written on state
  change rather than live.
- **Requirement 5 opens with the `code` CLI and focuses the explorer with one
  chord.** `explorer.autoReveal` defaults to true, so whatever opens the file has
  already selected it in the tree; the remaining work is opening it. Pin
  `explorer.autoReveal` to an explicit `true` rather than resting on an inherited
  default.
- **Both operations reach outside the process through the existing portable
  seams** — `(modaliser shell)` for `grove-llm` and for `code`, never a
  `…-native` library. That is the portability contract, and it is what keeps
  `swift test` inert (ADR-0023).

## Test seams (agreed with the human)

One seam, placed as high as it goes.

- **The storage-state parser is pure and takes text.** A function over the JSON
  *text* returning the open workspaces — folder path and folder name — is where
  every test lands, driven from a fixture string captured from a real state file.
  The file read stays a single `read-file-text` call that no test exercises, so
  ADR-0023's "reaches nothing outside the process" holds *structurally*: there is
  no file-reading path under test that could reach `~/Library`. When VSCode
  changes the format, the fixture is updated and the test says what broke.
- **Everything that spawns is tested through the shell seam's runner**, installed
  canned in the test, exactly as the existing suites do it. Nothing runs
  `grove-llm` or `code` for real under `swift test`.
- **The example config is load-tested** by the existing example-loading test, so a
  shipped example that stops composing is a red suite rather than silent rot.

## Pointers

- **ADRs a session here must read:** ADR-0021 (decision-free libraries — no file
  under `lib/modaliser` authors a key or a label), ADR-0023 (the inert-by-default
  outward seams and why `swift test` reaches nothing), ADR-0019 (the `sys/` mirror
  and why machinery belongs in the library tree rather than in the seeded config).
- **ADR filenames in this repo stay numbered** (`docs/adr/00NN-slug.md`, cited
  bare as `ADR-00NN`). `CLAUDE.md` overrules grove's own slug-naming rule here and
  says explicitly not to "fix" it; several hundred citations depend on it.
- **Prior art in the tree:** `lib/modaliser/apps/dia.sld` (an app utilities
  library with a chooser source and a focus action), `lib/modaliser/tools/nvim.sld`
  (an external tool wrapped as a facility), `Scheme/examples/chrome.scm` (a shipped
  never-loaded example config).
- **The human's config** is a separate repo-less tree at `~/.config/modaliser/`
  with its own `CLAUDE.md`. `app-trees/dev.zed.Zed.scm` is the working model for
  the screen this grove adds.
- **Glossary:** `CONTEXT.md` is the ubiquitous-language glossary and is
  load-bearing against terminology drift. If this work hardens a term — what a
  *workspace*, a *project* or a *worktree* means in Modaliser's vocabulary — append
  it there.

## On the horizon

- **Should VSCode displace Zed as "the editor"?** The global F18 screen's
  Applications panel binds `e` to Zed, and Settings → Edit opens the config
  directory in Zed. Precisely stateable, one line each, and the human's call —
  leaf 02 will be editing that file anyway, so put it to them there rather than
  guessing.
- **ctrl-` hides the terminal when the terminal already has focus**, because it is
  a toggle. If that grates in use, the fix is a bound strict-focus command; left
  alone for now because the human asked for ctrl-` by name.
- **The window selector is reachable only while VSCode is frontmost**, since F17
  dispatches on the frontmost app. Crossing in from another app is therefore two
  steps. A row on the global F18 screen was considered and set aside; it returns if
  the two-step cost annoys.

## Notes

The repo has no CI. `check-portable-surface.sh` and `check-decision-free.sh` are
local discipline — nothing runs them for you, and both are strict-zero checks that
a single authored key, label, or `(lispkit …)` import will fail. Note the prose
convention they force: because both are textual greps, files under `lib/modaliser`
must avoid writing those literals even in comments.
