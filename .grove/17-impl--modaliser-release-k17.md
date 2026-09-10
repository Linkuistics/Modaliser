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
