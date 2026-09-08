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
