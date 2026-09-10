# The companion extension ships inside the app and installs only when asked

## Context

The VSCode companion extension (ADR-0026) is installed by a script of its own,
`scripts/install-vscode-extension.sh`, deliberately outside `install.sh`. The
recorded reasons are good ones: the extension targets a *different application*
that may not be present, it has its own upgrade cadence, and keeping it out of
the install path is what keeps a committed `.vsix` — a build artifact nothing
verifies — out of the repository.

**Those reasons were written for a reader who has the repository, and one of
them stopped holding when Modaliser went public.** Modaliser ships as a Homebrew
cask (`docs/RELEASING.md`), and `release-build.sh` assembles a tarball
containing exactly `Modaliser.app`, `README.md` and `LICENSE`. There is no
`scripts/` directory in it and no `vscode-extension/`. The shipped `README.md`
nonetheless instructs the reader to run `./scripts/install-vscode-extension.sh`,
naming a path the shipped artifact does not contain — and the script it names
would need npm and a source checkout even if it were there.

So for every user who did not build from source, the two panels that list what
is open inside a VSCode window do not ship inconveniently. They ship
**unreachable**, and they do so silently, because a missing extension is by
design an empty panel and a log line rather than an error (ADR-0026). The
question is therefore not how a skew is noticed — that is solved — but **who
installs the extension, when, and with whose consent.**

Three facts constrain every answer, and each of them rules something out on its
own.

- **A cask installs an `.app`.** It can run arbitrary commands in `postflight`
  (the shipped template already strips `com.apple.quarantine` that way), so
  "brew cannot write into `~/.vscode/extensions`" is not true as stated. What is
  true is that brew would be writing into another application at
  *Modaliser*-install time, when VSCode may not be present and the user has not
  asked for it, and `brew uninstall` would not take it away again.

- **VSCode scans `~/.vscode/extensions` at startup only.** An install performed
  in response to a keypress cannot repair the press that provoked it. The user
  must restart VSCode, and therefore must be told.

- **Modaliser cannot tell "not installed" from "not reachable".** ADR-0026
  records that every miss — absent, not yet activated, disabled for the profile,
  a stale pointer, a crashed host — ends at `unix-socket-request` returning
  `#f`. Any trigger built on that signal fires on transient misses.

Together the last two mean a silent install is not merely impolite: it cannot be
both silent and useful, because the user has to act anyway.

**Writing into another application's configuration is not a new act here.**
`apps/kitty.sld`, `apps/iterm.sld` and `apps/alacritty.sld` each carry a
`configure!` op with the same five parts — a `dialog-confirm` that enumerates
exactly what will be written, the write performed through the portable shell
seam, idempotence when it is already done, a `configured?` predicate paired as a
`'hidden` gate so the row retires itself, and a closing instruction to relaunch
the target application. Three instances make it a house pattern rather than a
precedent to be argued for.

## Decision

**`build-app.sh` builds the companion extension into the app bundle, and
Modaliser copies it into `~/.vscode/extensions` only when the user asks it to —
through the same confirm-and-provision op the terminal libraries already use.
Modaliser never writes there on its own initiative, in any circumstance.**

- **The payload is compiled output, and its freshness is structural rather than
  checked.** `build-app.sh` runs the extension's own build and copies its result
  into `Contents/Resources/`: `package.json`, `README.md`, and `out/src` — the
  same three things `install-vscode-extension.sh` copies today, and nothing else
  (`out/test` has no business in an installed extension). Because the copy
  source is produced by the step immediately before it, there is no drift for a
  `diff -rq` to catch and none is added; this is *not* ADR-0019's exact-mirror
  invariant extended past `Scheme/`, and should not be described as one. The one
  thing that has to be explicit is that `out/` is **wiped before the build**:
  `tsc` overwrites but does not prune, so a source file deleted from
  `vscode-extension/src` would otherwise leave its compiled output behind
  forever. That is the same wipe-before-assemble rule, and the same bug class,
  that ADR-0019 exists to close.

- **`npm` becomes a release-machine requirement, checked where the others are.**
  `build-app.sh` today has no Node dependency; it gains one. The cost lands on
  the maintainer's machine, which already has npm because the extension is
  developed there, and it comes *off* every user's machine. `release-doctor.sh`
  gains an `npm` row so a misconfigured machine fails in the checks step rather
  than mid-toolchain, exactly as the existing rows do.

- **The offer is a row on the user's VSCode screen, not a menu-bar item.**
  `(modaliser apps vscode)` exports the op and its predicate; the user's
  `config.scm` binds a key and a label to them, and `examples/vscode.scm` carries
  the row it ships. That keeps ADR-0021 intact without argument — the library
  authors neither — puts the offer where it is relevant, costs a user who does
  not run VSCode nothing, and leaves `root.scm`'s status menu untouched. A
  menu-bar item was the obvious surface and is the worse one: it is present for
  every user in a six-item menu, it cannot retire itself, and it would put a
  VSCode-specific decision into the host bootstrap.

- **The row retires itself on a path test, not a socket probe.** The bundled
  payload carries the version this build ships, and `companion-installed?` asks
  whether `~/.vscode/extensions/<publisher>.<name>-<version>` exists for exactly
  that version. An *older* installed copy reads as not-installed, so the row
  comes back after a Modaliser upgrade — which is precisely the case the script's
  header calls out as manual and easy to forget. This is deliberately not built
  on the `parts` reply: that signal cannot distinguish absent from unreachable,
  and a property that must hold is made structural here rather than asserted.

- **The library never knows where the payload is; the host installs the path.**
  `(modaliser apps vscode)` is portable-tree code and cannot name
  `Contents/Resources/`, which is host knowledge and differs between a dev run
  and an installed `.app` — the same divergence `SchemeEngine.resolveSchemeDirectory`
  already branches on. So the payload directory is a parameter defaulting to *not
  configured*, installed by `root.scm` at boot, exactly as the socket path and
  the shell runner are (ADR-0023). Both halves follow from that and neither is
  optional: an un-configured parameter makes `companion-installed?` answer *not
  installed* and the op a no-op that says why, and `swift test` reaches no bundle
  and no extensions directory for the same structural reason the rest of the
  outward surface is inert.

- **The sweep rule lives in exactly one place.** Removing earlier copies of this
  extension — and only this extension, because two copies in one window would
  each bind a socket — is an `rm -rf` over a glob, and two transcriptions of it
  is one too many. One script inside the bundle performs sweep-and-copy over an
  already-built payload; `install-vscode-extension.sh` keeps its build step and
  then delegates to the same logic. Two entry points, one deletion rule.

- **Consent is the act, and it is enumerated before it happens.** The confirm
  dialog names the source directory, the destination, the earlier versions that
  will be removed, and the fact that VSCode must be restarted — the kitty
  dialog's shape. There is no opt-out to design, because there is nothing to opt
  out of: absent the user pressing the key and confirming, nothing is written.
  The cask additionally learns to `zap` the installed extension, so the tool
  that installed Modaliser can take the extension away again; a plain
  `brew uninstall` leaves it, on the same terms as the user's `config.scm`.

- **What does not change.** The protocol version in the `parts` reply remains
  the skew detector and keeps its empty-panel-and-log-line answer — the install
  path is a convenience, not a guarantee, and a user may still be running a
  hand-installed or disabled copy. `npm test` stays separate from `swift test`
  (ADR-0023). The write is performed through `(modaliser shell)`, so no new
  native surface appears and the seam stays inert under test.

## Considered options

- **Keep the separate script and document it better.** The baseline, and the
  option this record set out expecting to confirm. Rejected because it is not a
  baseline: it leaves the feature unreachable for every user who installs the
  cask, while the shipped `README.md` tells them to run a script the artifact
  does not carry. Documenting it more clearly would at best replace an
  unreachable instruction with "clone the repository and install npm", which is
  a different product's answer. **Reopen if** the release ever ships the
  repository alongside the app, which nothing plans.

- **Install silently on detecting a skew.** Rejected on two structural grounds
  rather than on taste. The trigger would be the `parts` miss, which ADR-0026
  records as indistinguishable from five other conditions; and the install has
  no effect until VSCode restarts, so it must tell the user anyway. Once a
  user-visible moment is forced, silence has bought nothing and has cost the
  consent — the offer strictly dominates. It would also leave an extension in
  another application that the user never agreed to and that a plain uninstall
  does not remove. **Reopen if** VSCode ever gains a live extension-directory
  scan *and* a reliable "is it installed" signal reaches Modaliser; both are
  needed, since either alone leaves one of the two grounds standing.

- **Install from the cask's `postflight`.** Technically available. Rejected
  because it acts at Modaliser-install time, when VSCode may be absent and the
  user has not asked; because `brew uninstall` would not reverse it without a
  matching `uninstall delete:`; and because it needs the payload bundled anyway,
  so it is the silent-install option with brew as the actor and the same consent
  question unanswered. **Reopen if** Homebrew grows a first-class notion of an
  optional, user-confirmed component, which would answer the objection that
  actually carries.

- **Publish to the Visual Studio Marketplace.** The strongest rejected option,
  and the only one that keeps the extension's independent upgrade cadence
  intact — which is the reason the current separation exists, and the one this
  decision spends. Rejected on ongoing cost and on reversibility, not on merit.
  It needs a registered publisher identity (the manifest declares
  `publisher: "antony"` and `private: true`; neither is ready, and changing the
  publisher id changes the installed directory name and therefore the sweep glob
  that stops two copies binding two sockets), a credential that expires, and a
  publish step per protocol change in a repository with no CI. It also **inverts
  skew causality**: VSCode auto-updates extensions while the cask does not
  auto-update Modaliser, so the extension can move past Modaliser while the user
  does nothing, and an operation that worked yesterday goes quiet for a reason
  the user did not cause. Today every skew is user-caused. Against that,
  bundling is reversible — the payload stops being bundled and the row's action
  becomes "open the Marketplace page" — while a published extension with
  installs is not quietly withdrawn. **Reopen if** Modaliser gains VSCode users
  who are not the maintainer, or if the extension starts needing releases of its
  own between Modaliser releases. Either is the signal that the cadence this
  decision spent has become worth paying for.

- **Commit a `.vsix` and install it with `code --install-extension`.** Rejected
  when the installer was written, and still rejected for the same reason: a
  committed build artifact that nothing verifies. Worth stating explicitly that
  bundling does **not** reintroduce it — the payload is produced during
  `build-app.sh` and never enters the repository — so the fourth of the original
  four reasons survives this decision untouched.

## Consequences

- **The extension's upgrade cadence is now Modaliser's.** An extension-only fix
  needs a Modaliser release. That is the single reason from the original
  separation that this decision spends, it is spent knowingly, and the
  Marketplace option above records what buys it back.

- **`build-app.sh` acquires a third language's toolchain.** A Swift-and-Scheme
  build now shells out to npm. It is a release-machine dependency, named in
  `release-doctor.sh` and in `docs/RELEASING.md`, and a machine without it fails
  the checks step rather than producing an app with a missing payload.

- **Modaliser writes outside `~/.config/modaliser` for the first time in this
  area, and the enumeration is the whole of it**: it creates
  `~/.vscode/extensions/<publisher>.<name>-<version>/`, and it removes earlier
  directories matching `<publisher>.<name>-*`. Nothing else under `~/.vscode` is
  read, written or removed, and none of it happens without a confirmed dialog.

- **`~/.vscode/extensions` is the only destination.** VSCode Insiders and other
  variants keep their extensions elsewhere and are not served; that matches what
  the script does today, and it is a gap rather than a decision — a variant-aware
  destination is a later question if anyone hits it.

- **A fresh cask user's path to the panels is several steps and stays that way.**
  Copy `examples/vscode.scm` into `config.scm` (the screen is preference and is
  not seeded — ADR-0019, ADR-0021), relaunch Modaliser, press the row, confirm,
  restart VSCode. Every step but the last two was already required to have the
  screen at all, and the release notes carry the sequence.

- **The `.app` grows by the compiled extension**, roughly 136 KB. The extension
  declares no runtime dependencies, so there is no `node_modules` to vendor and
  the payload is `tsc` output plus two files.

## See also

- ADR-0026 — why the source is a companion extension at all, and why a missing
  one is an empty panel rather than an error.
- ADR-0027 — how one window is addressed among several.
- ADR-0019 — the seed-once/mirror-always contract, the wipe-before-assemble rule
  this reuses, and why its exact-mirror invariant stops at `Scheme/`.
- ADR-0021 — no library authors a key or a label, which is why the offer is a
  row in the user's config rather than a menu item.
- ADR-0023 — the inert-by-default outward seams the install write goes through.
- `docs/RELEASING.md` — the release runbook the npm requirement lands in.
- `docs/specs/vscode-window-parts.md` — how the area works.
