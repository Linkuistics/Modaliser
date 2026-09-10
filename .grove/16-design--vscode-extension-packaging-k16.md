# vscode-extension-packaging-k16

## Goal

Decide how the VSCode companion extension gets to a user's machine once
Modaliser ships as a release, and record it as an ADR (plus whatever
`docs/specs/vscode-window-parts.md` has to change). The human's words: *"we
will need to work out how to package/install the vscode extension as part of
modaliser, and then do a release."*

This leaf **decides**; the build is a later leaf, and the release
(`modaliser-release-k17`) sequences after both.

## Context

**You are reversing, or softening, a decision that was made deliberately and
whose reasons are written down.** `scripts/install-vscode-extension.sh`'s header
is the counter-argument, and it is a real one — read it first and answer it
rather than around it:

- the extension targets a *different application*, which may not be installed;
- it has its own upgrade cadence;
- keeping it out of `install.sh` is what keeps a `.vsix` — a committed build
  artifact nothing verifies — out of the repo.

`CLAUDE.md` states the same separation ("deliberately separate from
`install.sh`"), so whatever this leaf decides, that paragraph and the script
header both move with it. Do not leave two files asserting the old rule.

**What already exists, and is the seam any answer builds on.** The skew problem
is *already solved as a detection problem*: the protocol version in the `parts`
reply means a stale or missing extension shows up as an **empty panel and a log
line**, never as wrong rows. That is why nothing in the Swift build fails when
the extension goes stale (ADR-0019's exact-mirror invariant covers `Scheme/`
only). So the open question is not *how do we notice* — it is *who installs,
when, and with whose consent*.

**The release path constrains the answer.** Modaliser ships as a **Homebrew
cask** (`docs/RELEASING.md`, `scripts/release-*.sh`), and a cask installs an
`.app`. It cannot write into `~/.vscode/extensions`. So "ship it in the release"
cannot mean "the installer installs it" — something at *runtime* would have to,
or it is a second distribution channel.

**The shapes worth pricing** — the leaf should reach one, not survey all four:

- **Bundle + install on launch.** Build the extension into
  `Contents/Resources/` at `build-app.sh` time and have Modaliser copy it into
  `~/.vscode/extensions` when it sees a version skew. Note what this drags in:
  it puts the extension under a mirror-style freshness invariant (the ADR-0019
  shape, now covering something outside `Scheme/`), it needs `npm` at *build*
  time rather than at *install* time, and **writing into another app's
  extensions directory without asking is a decision, not a facility** — consent
  and an opt-out are part of this option, not a refinement of it.
- **Bundle + offer.** Same bundling, but the app *offers* rather than acts —
  the existing skew log line becomes a menu-bar item or a dialog that runs the
  copy. Cheaper on consent, costs a manual step.
- **Marketplace.** Publish `antony.modaliser-companion` properly; VSCode's own
  update machinery does the rest, and Modaliser ships nothing. This is the only
  option where the extension's independent cadence survives intact — which is
  the thing the current separation exists to protect — and the only one with an
  ongoing publishing obligation attached.
- **Status quo, documented.** Keep the script; make the release notes and the
  first-run experience name it. Cheapest, and the honest baseline the other
  three have to beat.

**Do not treat `npm` as free.** `install-vscode-extension.sh` requires it and
says so. Bundling moves that requirement from the user's machine to the release
machine, which is a real improvement for a cask user and a real new coupling for
`build-app.sh` — which today has no Node dependency at all.

**Pointers**

- `scripts/install-vscode-extension.sh` — the header is the recorded rationale.
- `scripts/build-app.sh`, `docs/RELEASING.md`, `scripts/release-*.sh`.
- ADR-0026, ADR-0027, `docs/specs/vscode-window-parts.md` (its *Out of scope*
  section is where the current answer lives).
- ADR-0019 — the exact-mirror invariant, and why it stops at `Scheme/`.
- `vscode-extension/README.md` — install, on-disk layout, the three methods.

## Done when

- One option is chosen, with the rejected ones and *what would reopen them*
  recorded — as an ADR (new, or a rework of ADR-0026's scope) per
  `ADR-FORMAT.md`.
- The consent question is answered explicitly if the answer writes into
  `~/.vscode/extensions` on the user's behalf.
- `docs/specs/vscode-window-parts.md`'s *Out of scope* section, `CLAUDE.md`'s
  paragraph on the separate installer, and
  `scripts/install-vscode-extension.sh`'s header all agree with the decision —
  or are named as the build leaf's work if the design leaves them standing.
- The build work is cut as a leaf if it is more than the design session can
  land, and `modaliser-release-k17` is re-read to see whether the choice
  changes it.

## Notes

- The extension's own suite (`npm test`) is separate from `swift test` by
  design and nothing here should join them (ADR-0023, `CLAUDE.md`).
- A version bump is `vscode-extension/package.json`; the installed directory
  name carries the version, and the installer removes earlier copies of *this*
  extension only — two copies in one window would each bind a socket.

## Decisions (running log)
