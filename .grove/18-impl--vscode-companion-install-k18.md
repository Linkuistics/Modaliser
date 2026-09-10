# vscode-companion-install-k18

## Goal

Build what ADR-0028 decided: `build-app.sh` compiles the VSCode companion
extension into the app bundle, and Modaliser installs it into
`~/.vscode/extensions` on the user's confirmed request — through the
`configure!` op shape `apps/kitty.sld` already uses. Then reconcile the five
files still describing the old install path.

**Read `docs/adr/0028-…` first; it is the contract, not a summary of one.** If
`review-design--vscode-extension-packaging-k19` produced findings and an
integration ran, read that too — the ADR may have moved.

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

3. **`(modaliser apps vscode)` gains `install-companion!` and
   `companion-installed?`.** Follow `apps/kitty.sld:423` closely — the
   `dialog-confirm` enumerating exactly what will be written, the write through
   `(modaliser shell)`, idempotence, the re-probe, the closing "restart VSCode".
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
   rest to it. The deletion is `rm -rf` over `<publisher>.<name>-*` in another
   application's directory — it is the sharpest line in this leaf, it must exist
   in exactly one place, and its glob must be incapable of matching anything but
   this extension.

5. **The release path learns about npm.** `scripts/release-doctor.sh` gains an
   `npm` row naming its remediation, as its existing rows do, and
   `docs/RELEASING.md`'s prerequisites table gains the matching line. A machine
   without npm must fail in the checks step, never produce an app with a missing
   payload.

6. **The cask learns to remove it.** `scripts/templates/modaliser.rb.tmpl` gains
   a `zap trash:` entry for `~/.vscode/extensions/<publisher>.<name>-*`, on the
   same terms as `~/.config/modaliser`: `--zap` removes it, a plain uninstall
   leaves it. **Confirm a cask `zap trash:` actually accepts a glob** before
   resting on it; ADR-0028 asserts it without evidence in the tree.

**The offer's surface is a row in the user's config, not a menu item.**
`examples/vscode.scm` carries it — key, label and the `'hidden` gate paired with
`companion-installed?` so the row retires itself once the shipped version is
installed, and returns after a Modaliser upgrade outruns it. That gate is the
whole reason the predicate is a path test rather than a `parts` probe: a socket
miss cannot tell *absent* from *unreachable* (ADR-0026), and a path test can.

**The five files still describing the old install path** — k16 left these
standing deliberately, because a document describing machinery that does not
exist yet is a lie in the tree. They become true when this leaf lands, and they
are the leaf's work:

    README.md:48-56                                        (shipped in the tarball)
    docs/how-to/index.md:67-71
    docs/reference/libraries.md:864-871
    Sources/Modaliser/Scheme/examples/vscode.scm:275-280
    Sources/Modaliser/Scheme/lib/modaliser/apps/vscode.sld:205-212

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
  extensions directory.
- `swift build`, `swift test`, `./scripts/check-portable-surface.sh`,
  `./scripts/check-decision-free.sh`, and `npm test` in `vscode-extension/` are
  all green.
- `./scripts/release-doctor.sh` reports the npm requirement, and
  `docs/RELEASING.md` lists it.
- All five files above describe the new path, and the "not built yet" qualifiers
  in `CLAUDE.md`, the spec's *Out of scope* and the installer header are gone.

## Notes

- The extension declares **no runtime dependencies**, so there is no
  `node_modules` to vendor: the payload is ~136 KB of `tsc` output plus two
  files.
- VSCode scans `~/.vscode/extensions` at startup only, so the dialog must say to
  restart VSCode and the install can never repair the press that asked for it.
- `~/.vscode/extensions` is the only destination; Insiders and other variants are
  out of scope, matching what the script does today (ADR-0028, Consequences).
- A signed `.app` is the thing being shipped — check that a shell script inside
  `Contents/Resources/`, invoked through the shell seam, runs without signature
  or quarantine trouble. ADR-0028 assumes it does.
