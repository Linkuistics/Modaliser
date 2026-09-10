# modaliser-release-k17

## Goal

Cut a Modaliser release carrying this grove's work — the VSCode screen, the
three jump-label panels, the companion extension, and whatever
`vscode-extension-packaging-k16` decided about shipping that extension.

The human's words: *"we will need to work out how to package/install the
vscode extension as part of modaliser, and then do a release."* This is the
"and then".

## Context

**Read `docs/RELEASING.md` first and follow it — it is the runbook, and this
leaf does not re-derive it.** Three scripts in order, cut by hand from this
machine because there is no CI in this repository:

    ./scripts/release-doctor.sh     # pure checks, installs nothing
    ./scripts/release-build.sh      # → dist/  (runs the doctor itself first)
    #  ... inspect dist/ ...
    ./scripts/release-publish.sh    # → GitHub Release + Homebrew tap

The scripts carry the *reasoning* for individual guards in their comments; the
page carries the *procedure*. When the two seem to disagree, the page wins on
what to do and the comment wins on why.

**This leaf is sequenced after `vscode-extension-packaging-k16` for a reason.**
That leaf decides whether the extension ships inside the `.app`, through the
Marketplace, or not at all. All three change what a release *is* here — the
first adds a Node dependency to `build-app.sh` and a new artifact to the
bundle, the second adds a publishing step outside this repo, the third makes
the release notes carry an install instruction. **Re-read k16's ADR before
starting**; if it was abandoned or deferred, this leaf ships the status quo and
says so in the notes.

**k16 has since settled it, so both conditionals in this leaf now resolve to
yes.** ADR-0028 chose the first shape: `build-app.sh` builds the extension into
the bundle, and Modaliser installs it into `~/.vscode/extensions` on a confirmed
user request. Three consequences, all of which the Done-when below already
anticipates in conditional form — `npm test` is in scope; the release notes must
say how a user gets the extension and that VSCode has to be restarted; and
`release-doctor.sh` now checks for `npm`, so a machine without it fails the
checks step rather than producing an app with a missing payload. The work is
`vscode-companion-install-k18`, which sequences immediately before this leaf. If
it has not landed, there is nothing to release on this front and the notes say
so.

**What is new since the last release, and belongs in the notes** — read the
`DONE` leaves in `.grove/` for the full list, but the user-visible shape is:

- an F17 VSCode screen with five operations, including opening the live grove
  task file for that window's worktree;
- three jump-label panels on it — Terminals, Editors, Projects — each with its
  own alphabet;
- a companion VSCode extension that answers what is open inside a window over
  a Unix socket (ADR-0026, ADR-0027).

**The prerequisites that are not code** and will stall a first attempt:
`gh` authenticated, and a real git checkout of
[`linkuistics/homebrew-taps`](https://github.com/Linkuistics/homebrew-taps) at
`~/Development/homebrew-taps` (override with `MODALISER_TAP_DIR`) —
`release-publish.sh` commits and pushes into it. Run the doctor standalone
first; it names the remediation command for anything missing.

**Publishing is outward-facing and irreversible in the way that matters** — a
pushed tag, a GitHub Release and a commit into a public tap. Confirm the version
and the notes with the human before `release-publish.sh`, and inspect `dist/`
between build and publish as the pipeline diagram says to. That inspection step
is in the runbook because it is the last point where a bad bundle is cheap.

**Pointers**

- `docs/RELEASING.md` — the procedure. Canonical.
- `scripts/release-doctor.sh`, `release-build.sh`, `release-publish.sh`.
- `scripts/build-app.sh` — signs with the "Modaliser Dev" certificate when
  present, and **fails the build** unless the bundled `Scheme/` tree matches
  `Sources/Modaliser/Scheme/` exactly (ADR-0019).
- `.grove/BRIEF.md` and the `DONE` leaves — what this release contains.

## Done when

- `./scripts/release-doctor.sh` passes on this machine.
- `swift build`, `swift test`, `./scripts/check-portable-surface.sh` and
  `./scripts/check-decision-free.sh` are all green at the released commit, and
  `npm test` in `vscode-extension/` too if k16 put the extension in the release.
- `dist/` is built and inspected before anything is published.
- The version and the release notes are confirmed **with the human** before
  publishing.
- The GitHub Release and the tap commit exist, and a `brew upgrade` from the
  tap installs the new version on this machine.
- If k16 chose to ship the extension, the release notes say how a user gets it
  and that VSCode must be restarted before Modaliser can reach it.

## Notes

- A wedged first launch of a freshly signed bundle is a known hazard, not a
  release defect: ~32 KB RSS at 0% CPU means Gatekeeper is still scanning.
  `pkill -f "/Applications/Modaliser.app/Contents/MacOS"` and relaunch.
- A shell alias shadows `log` — use `/usr/bin/log show --predicate 'subsystem
  == "dev.antony.Modaliser"'` to confirm `config: loaded` after installing.

## Decisions (running log)

- **All five gates are green at this stack's tip** (`e4a69b35`, k22):
  `release-doctor.sh` passes all seven prerequisites; `swift build` clean;
  `swift test` 1324 tests / 107 suites passed; `check-portable-surface.sh` and
  `check-decision-free.sh` both OK; `vscode-extension` `npm test` 60/60; and
  `test-install-companion-payload.sh` all cases pass. The last is not in the
  Done-when but is this release's one `rm -rf` inside another application's
  directory, so it runs.

- **The version is v4.3.0.** `v4.2.1` is `b3844f78`, which is exactly `main`
  and exactly the base of this grove's stack — `git log v4.2.1..main` is empty.
  So the release contains this grove's 22 commits and nothing else, and the
  content (a new screen, three panels, a shipped companion extension) is a
  minor bump rather than a patch.

- **`release-publish.sh` could not meet this leaf's Done-when, so it changed.**
  It passed a hardcoded `--notes "Release $tag"` to `gh release create`, so
  every Release body so far has merely restated its own title. The Done-when
  requires notes that say how a user gets the companion extension and that
  VSCode must be restarted, and the pipeline had no seam for prose. Added:
  `docs/release-notes/v<ver>.md`, **required** by a `require_release_notes`
  preflight in `release-publish.sh` that runs before the first push, and read
  with `--notes-file`. Requiring rather than falling back follows the doctor's
  own `npm` reasoning — a missing thing that would otherwise ship silently.
  Guard verified to fire: resolves with the file present, exits 1 with the
  version missing and with the directory missing. `docs/RELEASING.md` gained
  step 1, a diagram node, a troubleshooting row, and lost a stale test count
  (it claimed 1157/95 against an actual 1324/107 — replaced with "the whole
  suite" rather than a fresher number that would rot the same way).

- **The release is cut from the default jj workspace** (`~/Development/Modaliser`),
  not from this one. This workspace has no `.git`, and all three release scripts
  drive git through `git -C "$REPO_ROOT"`; `release-publish.sh` additionally
  needs a root that is *both* jj and git to push the bookmark. The default
  workspace is the only tree that is both.
