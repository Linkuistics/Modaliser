# vscode-companion-install-k18

## Goal

Build what ADR-0028 decided: `build-app.sh` compiles the VSCode companion
extension into the app bundle, and Modaliser installs it into
`~/.vscode/extensions` on the user's confirmed request — through the
`configure!` op shape `apps/kitty.sld` already uses. Then reconcile the five
files still describing the old install path.

**Read `docs/adr/0028-…` first; it is the contract, not a summary of one.**
`review-design--vscode-extension-packaging-k19` raised six findings and
`integrate-review-design--vscode-extension-packaging-k20` applied all six, so
**the ADR has moved** and four of them changed this leaf's work. Those changes
are folded into the sections below; k19's task file carries the reasoning if an
instruction here reads as arbitrary.

## Context

**The shape, end to end.** Six pieces, and the ordering below is dependency
order rather than importance.

1. **`scripts/build-app.sh` gains the payload.** Wipe `vscode-extension/out`
   first — `tsc` overwrites but does not prune, so a deleted source otherwise
   leaves its compiled output behind forever, which is the ADR-0019 bug class
   this build is otherwise structurally free of. Then `npm install`,
   `npm run build`, and copy `package.json`, `README.md` and `out/src` into
   the bundle. **Not `out/test`** — the existing installer is explicit about
   why. Place this after the `Scheme/` `diff -rq`, which must keep passing
   untouched: this payload is deliberately *not* under that invariant, and
   nothing should be written that implies it is.

2. **The payload has to be identifiable from a file at a fixed path.** The
   portable tree has **no directory listing** — ADR-0027 records that as the
   reason a socket cannot be found by scanning — so Scheme cannot discover a
   versioned directory name inside the bundle. `build-app.sh` therefore writes
   the identity (`<publisher>.<name>-<version>`, or the version alone) into a
   fixed-name file beside the payload, and the op reads it with the
   `read-file-text` that already exists.

   **The payload's *location* needs a host input that does not exist yet, and
   supplying it is part of this leaf (k19 F1).** `root.scm` can default the
   socket pointer because `$HOME` is visible to Scheme; a bundle resource root is
   not. The only path Swift defines is `*scheme-directory*`, and it is the
   **wrong** one — in production `SysSync` redirects it to
   `~/.config/modaliser/sys/scheme`, while the payload sits directly under
   `Contents/Resources`. Do **not** derive the payload path from it. Add a second
   definition beside it in `SchemeEngine`, a bundle-resources path, set **only**
   on the `isProductionBundlePath` branch that already governs the mirror;
   ADR-0028 tabulates the three values it must take (installed `.app`,
   `swift run`, bare `SchemeEngine()`) and what each makes `companion-installed?`
   answer. A `swift run` has never assembled a payload, so *undefined* there is
   correct rather than a gap.

3. **`(modaliser apps vscode)` gains `install-companion!` and
   `companion-installed?`.** Follow `apps/kitty.sld:423` closely — the
   `dialog-confirm` enumerating exactly what will be written, the write through
   `(modaliser shell)`, idempotence, the re-probe, the closing "restart VSCode".
   **The dialog says two things kitty's does not (k19 F4):** that this installs
   extension code which activates in every VSCode window, and that a plain
   `brew uninstall` leaves it behind — only `--zap` or a manual delete removes
   it. kitty's analogy covers the op's mechanics, not this act's consent, and
   those two lines are what closes the gap.
   The library authors **no key and no label** (ADR-0021); kitty proves a dialog
   *message* is not a label for `check-decision-free.sh`, but run it and see.
   Two seams the ADR requires, both defaulting to *not configured* and both
   installed by `root.scm` at boot, exactly as the socket path is (ADR-0023):
   the **payload directory**, which is host knowledge, and — consider —
   the **existence probe** itself, which is what lets a test install a canned
   answer rather than reach a real `~/.vscode`. An un-configured payload
   parameter must make `companion-installed?` answer *not installed* and the op
   a no-op that logs why.

4. **The sweep-and-copy logic ships once.** One script inside the bundle does
   sweep-then-copy over an already-built payload;
   `scripts/install-vscode-extension.sh` keeps its build step and delegates the
   rest to it. The deletion is an `rm -rf` in another application's directory —
   the sharpest line in this leaf, and it must exist in exactly one place.

   **`<publisher>.<name>-*` alone is not a safe predicate, and the existing
   installer's `find … -name` is the bug (k19 F2).** Extension names may contain
   hyphens and this one's is `modaliser-companion`, so the pattern marks no
   name/version boundary and matches a distinct sibling such as
   `antony.modaliser-companion-beta-1.0.0`. Treat the glob as a *candidate
   filter* and confirm each candidate by reading its own `package.json`,
   requiring `publisher` and `name` to equal this extension's exactly before
   removing it; leave alone anything that does not parse or that names something
   else. `install-vscode-extension.sh`'s current sweep is fixed by the act of
   delegating — it inherits the check rather than keeping its own.

5. **The release path learns about npm.** `scripts/release-doctor.sh` gains an
   `npm` row naming its remediation, as its existing rows do, and
   `docs/RELEASING.md`'s prerequisites table gains the matching line. A machine
   without npm must fail in the checks step, never produce an app with a missing
   payload.

6. **The cask learns to remove it.** `scripts/templates/modaliser.rb.tmpl` gains
   a `zap trash:` entry for `~/.vscode/extensions/<publisher>.<name>-*`, on the
   same terms as `~/.config/modaliser`: `--zap` removes it, a plain uninstall
   leaves it. k19 cleared the glob against Homebrew's Cask Cookbook (`trash:`
   follows `delete:` path rules, and those glob-expand); confirm it on the real
   cask anyway. Note that this one path **cannot** run the manifest check above —
   it is a path list, not a program — so it reserves the whole
   `antony.modaliser-companion-*` prefix, and ADR-0028 now states that weaker
   claim for the cask deliberately. Do not "tidy" it back to the stronger one.

**The offer's surface is a row in the user's config, not a menu item.**
`examples/vscode.scm` carries it — key, label and the `'hidden` gate paired with
`companion-installed?` so the row retires itself once the shipped version is
installed, and returns after a Modaliser upgrade outruns it. That gate is the
whole reason the predicate is a path test rather than a `parts` probe: a socket
miss cannot tell *absent* from *unreachable* (ADR-0026), and a path test can.

**The six files still describing the old install path** — k16 left five
standing deliberately, because a document describing machinery that does not
exist yet is a lie in the tree. They become true when this leaf lands, and they
are the leaf's work:

    README.md                                              (shipped in the tarball)
    docs/how-to/index.md:67-71
    docs/reference/libraries.md
    Sources/Modaliser/Scheme/examples/vscode.scm:275-280
    Sources/Modaliser/Scheme/lib/modaliser/apps/vscode.sld
    vscode-extension/README.md                             (shipped IN the payload)

**The sixth is k19's F3 and it is not optional.** ADR-0028 requires
`vscode-extension/README.md` to be copied into the bundled payload, and it
currently tells the reader to run the repository-only installer and states the
separation being reversed as current. Satisfying every other row here exactly
while leaving it alone would ship a new app whose bundled README asserts the
decision ADR-0028 reversed and names a script no cask user has — the very defect
this leaf exists to remove.

Three of the six — `README.md`, `docs/reference/libraries.md` and
`apps/vscode.sld` — were additionally **qualified** by k20 rather than left
asserting the reversed rationale, because "upgrades on its own cadence" is a
claim about the present rather than a description of unbuilt machinery. Each now
names ADR-0028 and marks the script as what runs *until this leaf lands*. Remove
those qualifiers as well as the commands: the sentence to end up with states the
new path plainly, with no "until that lands" left anywhere.

`README.md` is the urgent one: it ships *inside the release tarball* and today
instructs the reader to run a script that tarball does not contain. That defect
is the reason ADR-0028 exists, so do not leave this leaf with it still standing.
`CLAUDE.md`, `docs/specs/vscode-window-parts.md` and the installer's header
already point at ADR-0028 and describe the change as unbuilt — **each says so in
those words, so each needs its qualifier removed** once it is built.

**Pointers**

- `docs/adr/0028-…` — the contract. `ADR-0026`, `ADR-0019`, `ADR-0021`,
  `ADR-0023` — what it leans on.
- `Sources/Modaliser/Scheme/lib/modaliser/apps/kitty.sld:395-433` — the
  `configure!` op, dialog and all. `apps/iterm.sld:525`, `apps/alacritty.sld:233`
  are the other two instances.
- `scripts/install-vscode-extension.sh` — the sweep and copy this reuses, and a
  header that already says what it becomes.
- `scripts/build-app.sh`, `scripts/release-build.sh`, `scripts/release-doctor.sh`,
  `docs/RELEASING.md`, `scripts/templates/modaliser.rb.tmpl`.
- `Sources/Modaliser/Scheme/root.scm` — where the two parameters get installed at
  boot, beside the socket path and the shell runner.

## Done when

- `./scripts/build-app.sh` produces a bundle carrying the built extension, and
  the `Scheme/` exact-mirror check still passes unchanged.
- Pressing the row on the VSCode screen shows the dialog, and confirming it puts
  a working extension in `~/.vscode/extensions` — verified on this machine by
  restarting VSCode and seeing the Terminals and Editors panels fill.
- The row is hidden once installed and returns when the bundled version outruns
  the installed one.
- Nothing is written to `~/.vscode` without a confirmed dialog, and the seams
  default to *not configured* so `swift test` reaches neither the bundle nor the
  extensions directory. The dialog carries the two disclosures ADR-0028 requires
  (activating code; a plain `brew uninstall` leaves it).
- The sweep deletes only directories whose own `package.json` names this
  publisher and name — demonstrated by a decoy directory
  (`antony.modaliser-companion-beta-1.0.0`, or another manifest under a matching
  prefix) surviving an install.
- `SchemeEngine` defines the bundle-resources path only inside an `.app`, and a
  `swift run` therefore reports *not installed* with a log line saying why —
  never an error and never a guess at a path.
- `swift build`, `swift test`, `./scripts/check-portable-surface.sh`,
  `./scripts/check-decision-free.sh`, and `npm test` in `vscode-extension/` are
  all green.
- `./scripts/release-doctor.sh` reports the npm requirement, and
  `docs/RELEASING.md` lists it.
- All **six** files above describe the new path — including the payload's own
  `vscode-extension/README.md` — and every "not built yet" qualifier is gone:
  `CLAUDE.md`, the spec's *Out of scope*, the installer header, and the three
  k20 added to `README.md`, `docs/reference/libraries.md` and `apps/vscode.sld`.

## Notes

- The extension declares **no runtime dependencies**, so there is no
  `node_modules` to vendor: the payload is ~136 KB of `tsc` output plus two
  files.
- VSCode scans `~/.vscode/extensions` at startup only, so the dialog must say to
  restart VSCode and the install can never repair the press that asked for it.
- `~/.vscode/extensions` is the only destination; Insiders and other variants are
  out of scope, matching what the script does today (ADR-0028, Consequences).
- A signed `.app` is the thing being shipped. k19 cleared the *placement*
  against Apple's Code Signing Guide (non-Mach-O executables belong in
  `Contents/Resources`, where the outer signature seals them in `CodeResources`)
  and against the cask's recursive quarantine strip — so the shape is supported.
  Still drive it end-to-end on a real installed app rather than resting on that:
  the clearance is about placement, not about this script.

## Decisions (running log)

- **The bundle-resources path is `#f` outside an `.app`, not unbound.**
  ADR-0028's table said "not defined" for a `swift run`. `root.scm` reads the
  name, and an unbound name unwinds the LispKit VM past every handler
  (ADR-0022's reason the host sequences two evaluations) — so a literally
  undefined variable would take the boot down rather than degrade. `#f` is the
  same fact in a form Scheme can read. ADR-0028's table and the paragraph above
  it now say `#f` and say why.

- **The existence probe gets no seam of its own.** The task said "consider" one.
  It buys nothing: the probe runs through `run-shell`, which is already the
  inert-by-default seam (ADR-0023) and which a test already installs a canned
  answer on. A second parameter would be a second thing to keep inert for the
  same guarantee. Recorded in the library header beside the payload parameter.

- **Three siblings in `Contents/Resources`, all derived from one parameter by
  suffix**: `ModaliserCompanion/`, `ModaliserCompanion.id`,
  `ModaliserCompanion.install.sh`. The suffix derivation is why one host-installed
  parameter suffices and why nothing in the portable tree has to take a path
  apart — it has no directory listing (ADR-0027) and does not index strings
  (ADR-0025).

- **The identity is a stamped file rather than the payload's own manifest**, even
  though the manifest sits at a fixed path too and `(modaliser json)` could parse
  it. `companion-installed?` gates a row, so the overlay reads it on every render
  and it must be cheap: one `read-file-text` of a pre-computed line, not a JSON
  parse. `build-app.sh` stamps it from that same manifest — one source of truth,
  two readers — via `install-companion-payload.sh --print-identity`, so the
  identity has one derivation rather than two.

- **`plutil`, not `node` and not `python3`, reads the manifests in the sweep.**
  It is part of the base system, so the check works on a cask user's machine that
  has never seen a toolchain; `/usr/bin/python3` is a stub that fails without
  Command Line Tools. A malformed manifest exits non-zero, which reads as "not
  ours" and leaves the directory alone.

- **`install-companion!`'s idempotent branch notes the answer it already has
  rather than re-probing.** kitty's `configure!` probes, then calls a refresh
  that probes again — two subprocesses per press to learn what the first said.
  Caught by a test asserting one command, not two; `companion-note-installed!`
  is the split.

- **The dialog is raised only after the probe says absent, and the copy only
  after the dialog returns true.** Pinned by
  `installWhenAbsentWritesNothingBeforeConfirmation`: one command reaches the
  shell runner from the press alone, and it is the probe.

### After the in-session adversarial read

The leaf's one review allowance was spent on the sweep script and the consent
path. It found six real defects, all reproduced, and every one of them lived in
what happens *around* the confirmed decision rather than in the decision itself
— the manifest-confirmation logic it was pointed at came back clean. Classified
and applied:

- **VALID, severe — the copy was a merge.** No `rm -rf "$target"` before
  `cp -R`, so a destination the sweep deliberately *leaves* (its `package.json`
  does not parse — exactly the state a Ctrl-C mid-sweep produces) got copied
  *into*: stale `out/src/*.js` survived and the new payload landed one level
  down at `out/src/src/`, which `main` does not point at. VSCode would load the
  old code, the script would exit 0, and the next run's sweep would then see a
  matching manifest and call it current. Fixed by wiping the destination; the
  sweep cannot stand in for that wipe, precisely because it is designed to leave
  what it cannot identify.

- **VALID — installing a payload onto itself destroyed it.** The destination
  wipe runs before the sweep's payload-exclusion can help, so pointing the
  script at an installed copy to refresh it deleted the source and then failed
  the copy, leaving no extension at all. Now refused up front, before anything
  is removed. Both guards are kept: the early refusal for payload==destination,
  the in-loop exclusion for a payload that is some *other* matching directory.

- **VALID — a confirmed write could fail in total silence.** `run-shell` returns
  stdout and nothing else: no exit code, no stderr. So an unremovable candidate,
  a full disk, or a tampered bundle produced `""`, the row reappeared, and
  Modaliser said nothing to a user who had just consented to a write. The
  command now folds stderr in and echoes its status; `companion-install-succeeded?`
  reads it, and a failure gets a `log-line` and a `dialog-info` carrying the
  transcript. **A user who consents to an act is owed the outcome of it** — that
  is the principle, and it was missing.

- **VALID — a half-finished install read as installed** and permanently hid the
  only row that could repair it, because the probe was `[ -d target ]`. The
  sweep script now writes `.modaliser-installed` **last**, and the probe tests
  for that: "installed" means "the copy completed". A copy put there by hand or
  by an older Modaliser carries no marker and so reads as not-installed — the
  row offers a reinstall, which is harmless and is the right offer.

- **VALID — `find -type d` skipped symlinked candidates**, so a symlinked older
  copy survived and VSCode loaded two, each binding a socket in the same window:
  the exact outcome sweeping exists to prevent, and reachable through VSCode's
  own local-development idiom. Now `\( -type d -o -type l \)`; `rm -rf` on a
  symlink takes the link and not its target, demonstrated.

- **VALID — the npm precondition sat after the bundle wipe**, so a machine
  without npm aborted partway and left a half-assembled, unsigned, iconless
  `.app` that looks like a build product. Hoisted above the wipe. `npm ci`
  rather than `npm install` in the release build, so it resolves from the
  committed lockfile and cannot rewrite it as a side effect of a release.

- **VALID, adjacent — host paths were interpolated into Scheme source
  unescaped.** macOS permits `"` and `\` in file names, so an app under a path
  containing one produced source the reader rejects, unwinding the whole boot
  rather than only the feature. Fixed for `*bundle-resources-directory*` **and**
  for the pre-existing `*scheme-directory*` beside it: leaving the identical
  defect standing next to its own fix is not a scope boundary worth keeping.

- **VALID but unreachable, fixed anyway** — the new `define` sat inside
  `if let bundlePath`, so the name would be unbound if `resolveSchemeDirectory`
  returned nil. `root.scm` never loads in that case, so nothing could observe
  it; but the comment claimed an unconditional guarantee, so the `define` is
  hoisted out and the claim is now true as stated rather than true by accident.

- **VISIBLE TRADE-OFF, prose fixed** — the dialog promised to "change nothing
  else under ~/.vscode" while `mkdir -p` creates `~/.vscode/extensions` when
  VSCode never has. Creating the destination is necessary; over-claiming was
  not. The line now says what it does.

- **NOISE / already covered** — divergent `HOME`-unset handling between the
  script (aborts) and the predicate (probes an impossible path). Both are safe;
  only the silence hurt, and the silence is fixed above.

- **UNCERTAIN, accepted and recorded** — `~/.vscode/extensions/extensions.json`
  is not touched, as the repository installer has never touched it and that is
  what has been in service against this engine. Noted in the script's header as
  the first place to look if a swept directory ever leaves a stale entry.

Applying five substantive fixes to code a reviewer had already read is the
signal `references/execute.md` names: review here has become tree-sized work, so
a `review-impl` leaf is cut beside this one rather than a second in-session pass.
