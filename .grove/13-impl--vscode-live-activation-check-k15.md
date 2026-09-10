# vscode-live-activation-check-k15

## Goal

Drive the companion extension against a **focused** VSCode window and settle the
four things `vscode-companion-extension-k12` built, tested and measured but could
not verify, because no window on the machine had focus for the whole of that
session and VSCode would not open a new one.

Every one of these is a case a fake passes and a real window can fail. Two of
them are named in the spec's own *Test seams* section as "neither is a suite's to
hold", and the other two are the focus-gated half of the design — the half whose
whole point is that it can only be checked where focus is real.

- **The pointer file appears** at `~/.config/modaliser/vscode/focused`, naming
  the socket of the window with focus, and follows focus as the human moves
  between windows.
- **`focused` is `true`** in a `parts` reply from the focused window, and
  `false` in every other window's at the same moment.
- **The same file open in two editor groups**, with the groups then reordered:
  each row's `focus-editor` must activate **its own** tab. This is the case a
  recorded `viewColumn` fails invisibly and the whole `LIVE` discipline exists
  for.
- **A preview tab that is already active**: pressing its label must change
  nothing — in particular it must **stay a preview tab**, not become pinned.

## Context

**Everything else in k12 is done and green** — `swift build`, `swift test`
(1265), the extension's own 60, and both invariant checks. The pieces below are
already verified against real VSCode windows and do not need redoing: `parts`
answering with real terminals and editors from four live windows, the terminal
panel **hidden** and a **single terminal** open (the two cases that killed the
accessibility design), the sweep removing a genuine crashed-host leftover on an
`ECONNREFUSED` while leaving four live peers alone, and the wire measured at a
**0.041 ms median** (`vscode-extension/scripts/measure-parts.js`).

**Why the session before could not do this.** No VSCode window reported
`focused: true` at any point — all four of the human's windows and a fifth,
scratch instance all read false — and neither `code -n`, `open -a`, nor an
AppleScript `set frontmost` produced a new or focused window. That is consistent
with the GUI session being locked or inactive rather than with any defect: a
window that has never had focus is exactly what the pointer file is defined not
to name. **Expect this leaf to be trivial with a human at the keyboard and
impossible without one** — if it is picked and the machine is again unattended,
say so and retire nothing.

**How to drive it, so this is fifteen minutes and not a rediscovery.**

- `./scripts/install-vscode-extension.sh`, then **restart VSCode** — an
  already-running host does not pick up a reinstall of the same version. Confirm
  with `listening on …` in the *Modaliser Companion* output channel, or by a new
  socket appearing in `~/.config/modaliser/vscode/`.
- Probe a peer without Modaliser: one line of newline-delimited JSON per
  connection, `{"id":1,"method":"parts","params":{}}`. There is a worked probe in
  k12's session and `vscode-extension/scripts/measure-parts.js` is the committed
  shape of it.
- For the two-group case: open one file, split the editor (`cmd-\`), read
  `parts` — two editor rows, same `path`, different `group`. Then move a group
  (`workbench.action.moveEditorGroupLeft`) and send `focus-editor` for **each**
  token in turn, checking after each that the intended tab is the active one.
  The failure this is looking for is the *other* row's tab activating.
- For the preview case: open a file from Quick Open (`cmd-p`, Enter) so it is a
  preview tab, confirm `isPreview` by reading it back through a second `parts`
  after pressing, and check the tab title is still italic.

**If something is wrong, the fix is here and it is small.** The activation code
is `vscode-extension/src/actions.ts`, and the property under test is that
`viewColumn` and `isPreview` are read off the live `Tab` at act time rather than
off the snapshot — `test/actions.test.ts` already pins that against a fake whose
group is mutated between the read and the press, so a real-window failure means
the fake models the wrong thing, and the fake is what has to change first.

**One thing to watch that nothing else will catch.** `focus-editor` on a
**custom editor** goes through `vscode.openWith`, which k12 added against the
spec's original table — the human's own settings map `*.md` to
`vscode.markdown.preview.editor`, so every markdown file is a custom-editor tab
and this is the *common* path here, not an exotic one. The argument that it is
identity-preserving is recorded in `actions.ts`'s header and in the spec's
decision 1; it is read out of the shipped command registration and has never been
run against a real window. Include a `.md` tab in the two-group case.

**Pointers**

- `docs/specs/vscode-window-parts.md` — decisions 1 (the activation table), 3
  (the pointer file and the focus gate) and 4 (identity across the read→act gap);
  and its *Test seams* section, which names these cases and says why no suite
  holds them.
- ADR-0027 — why the check is the peer's and what race it does and does not
  close.
- `vscode-extension/README.md` — install, the on-disk layout, and the three
  methods.

## Done when

- The pointer file exists, names the focused window's socket, and changes when
  the human switches VSCode windows.
- A `parts` reply from the focused window carries `focused: true`, and one from
  another window carries `false` at the same moment.
- With one file open in two groups and the groups reordered, each row's
  `focus-editor` activates its own tab — checked for a text tab **and** a
  markdown (custom-editor) tab.
- Pressing the label of an already-active preview tab leaves it a preview tab.
- Anything that failed is fixed, with the fake in
  `vscode-extension/test/actions.test.ts` changed first so the suite would have
  caught it; `swift test`, `npm test` and both invariant checks green again.
- If the machine is again unattended and none of this can be driven, the leaf
  says so plainly and stays live.

## Notes

- Nothing in the Swift suite reaches the extension, and nothing here should
  change that (ADR-0023).
- A wedged first launch of Modaliser is a known hazard and not a bug in this
  work: ~32 KB RSS at 0% CPU means Gatekeeper;
  `pkill -f "/Applications/Modaliser.app/Contents/MacOS"` and relaunch.
- Killing a VSCode host with `pkill` leaves its socket behind. That is correct —
  names are never reused — and the next activation sweeps it. Useful for
  producing the leftover on purpose; not a leak.
