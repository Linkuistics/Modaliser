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

**The counter-argument is answered on a fact that post-dates it.**
`install-vscode-extension.sh`'s four reasons are sound *for a developer with the
repo*. They were written before Modaliser was public behind a cask, and one of
them silently stopped holding: the release tarball is `Modaliser.app`,
`README.md`, `LICENSE` (`release-build.sh:assemble_bundle`) — no `scripts/`, no
`vscode-extension/`. The shipped `README.md:52` nonetheless tells the reader to
run `./scripts/install-vscode-extension.sh`. For every user who did not build
from source the feature is not inconvenient, it is **unreachable**, and the
shipped README names a path the shipped artifact does not contain. That is the
finding that decides the leaf: the status quo is not the honest baseline the
other options must beat, it is a defect.

**"The cask cannot write into `~/.vscode/extensions`" is false as stated, and
the true objection is a different one.** A cask `postflight` runs
`system_command` as the user — the shipped template already uses one to strip
`com.apple.quarantine` — so brew *could* copy an extension. Rejected on three
grounds that survive: it would install into another application at
Modaliser-install time, when VSCode may not be present and the user has not
asked; `brew uninstall` would not remove it without a matching `uninstall
delete:`; and it needs the payload bundled anyway, so it is the auto-install
option with brew as the actor and the same consent question unanswered.

**Auto-install is dominated by offer-and-install, structurally.** Three
independent facts each force a user-visible moment, so the silence buys nothing:

1. VSCode scans `~/.vscode/extensions` **at startup only** (the script's own
   closing note), so an install triggered by a keypress cannot repair the press
   that triggered it — the user must restart VSCode and must therefore be told.
2. Modaliser **cannot distinguish "not installed" from "not reachable"**:
   ADR-0026's consequences say every miss — absent, not yet activated, disabled
   for the profile, stale pointer, crashed host — ends at `unix-socket-request`
   returning `#f`. A trigger built on that signal fires on transient misses.
   This is the BRIEF's own k6 lesson: a property asserted rather than made
   structural.
3. A silent write leaves an orphan the uninstaller cannot reach — the cask's
   `zap` knows `~/.config/modaliser` and nothing under `~/.vscode`.

Since the user must act anyway, "install without asking" costs the consent and
keeps none of the convenience.

**The consent question is not new here — the repo answers it three times
already.** `apps/kitty.sld:423`, `apps/iterm.sld:525` and `apps/alacritty.sld:233`
each carry a `configure!` op with the same five parts: a `dialog-confirm` that
enumerates exactly what will be written, the write performed through the
portable shell seam, idempotence (re-probe and return when already configured),
a `configured?` predicate paired as a `'hidden` gate so the row retires itself,
and a closing "you'll need to relaunch <app>". Installing the companion is that
op pointed at VSCode. So this design applies a house pattern rather than setting
a new policy.

**The offer's surface is a screen row, not a menu-bar item.** The option as
posed in this leaf's Context named "a menu-bar item or a dialog". A row on the
user's own VSCode screen beats both: it is discoverable where it is relevant,
it costs a non-VSCode user nothing, it retires itself through the `'hidden`
gate, and its key and label live in the user's config, so ADR-0021 holds
without argument. `root.scm`'s `status-menu-items` is untouched.

**`configured?` is a file-existence check, which makes skew detection certain.**
The bundled payload carries its own version; the op checks whether
`~/.vscode/extensions/<publisher>.<name>-<version>` exists for the version this
build ships. An installed *older* version reads as not-configured, so the row
reappears after a Modaliser upgrade — the exact case the script header says is
"manual, and the protocol version is what catches you if you forget". That
replaces an ambiguous socket miss with an unambiguous path test.

**Bundling is cheap in the way that was feared and costly in a way that was
not.** The extension has **no runtime dependencies** (`package.json` declares
only `devDependencies`), so the payload is 136 KB of `tsc` output plus
`package.json` and `README.md` — no `node_modules` to vendor. `npm` moves from
the *user's* machine to the *release* machine, which already has it. What
bundling really costs is the extension's independent upgrade cadence: an
extension-only fix now needs a Modaliser release. That is the one reason of the
original four that this decision spends, and it is spent knowingly.

**The Marketplace is the right long-run answer and the wrong one now, and the
tie-break is reversibility.** It is the only option that keeps the independent
cadence intact, and the only one carrying an ongoing obligation on an external
platform: a registered publisher id (the manifest says `publisher: "antony"`
and `private: true` — neither is Marketplace-ready), a token that expires, a
publish step per protocol change in a repo with no CI, and a public listing for
an extension useless without Modaliser. It also **inverts skew causality**:
VSCode auto-updates extensions and the cask does not auto-update Modaliser, so
the extension can advance past Modaliser while the user does nothing, and an
operation that worked yesterday stops for no visible reason. Today skew is
always user-caused. Whether that ongoing obligation is worth paying is the
human's to price, and it is not blocking: bundle-and-offer is **reversible** —
the payload stops being bundled and the row's action becomes "open the
Marketplace page" — while a published extension with installs is not quietly
withdrawn. Under an unpriceable preference, take the reversible option and
record what would settle it.

**Split the record rather than reworking ADR-0026 alone.** ADR-0026's *decision*
is that the source is a companion extension; distribution appears there only as
a consequence, and it has its own rejected alternatives. Per `ADR-FORMAT.md`
that is one record covering two independent calls: a new ADR takes distribution,
and ADR-0026's consequence paragraph is reworked to hand it over rather than
continue to assert the old rule. Numbered filename, cited bare — `CLAUDE.md`
overrules grove's slug-naming here and says not to "fix" it.

**Which files this session reconciles, and which it names for the build leaf.**
A document describing machinery that does not exist yet is a lie in the tree, so
the split is by what the file asserts. Records of a decision are true the moment
it is made and land now; descriptions of the shipped mechanism change when the
mechanism does. The Done-when named three files; a grep of the claim rather than
a file list found eleven, of which eight are prose:

  now — ADR-0028 (new), ADR-0026 (consequence + See also),
        docs/specs/vscode-window-parts.md (Out of scope),
        CLAUDE.md (one sentence, so no agent reads the old rule as settled),
        scripts/install-vscode-extension.sh (header points at ADR-0028)

  build leaf — README.md:48-56, docs/how-to/index.md:67-71,
        docs/reference/libraries.md:864-871,
        Sources/Modaliser/Scheme/examples/vscode.scm:275-280,
        Sources/Modaliser/Scheme/lib/modaliser/apps/vscode.sld:205-212
