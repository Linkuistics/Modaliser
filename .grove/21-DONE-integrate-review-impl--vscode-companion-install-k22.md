# vscode-companion-install-k22

**Integrates:** vscode-companion-install-k21

## Goal

Triage the implementation-review findings in `vscode-companion-install-k21`
against the current source, apply the real ones, and leave the companion install
safe to release. The review is the finding authority; do not treat its list as
pre-accepted work.

## Context

The reviewed producer is `vscode-companion-install-k18`. ADR-0028 is the
contract, with ADR-0019 and ADR-0023 carrying the build and inert-seam
constraints. This step owns fixes and all post-fix verification; the review step
was inspection-only.

## Done when

- Every finding in `vscode-companion-install-k21` is classified against the
  current source as valid/actionable, visible trade-off, stale, or noise, with
  the decision recorded as it settles.
- Every accepted defect is fixed without broadening the install-time deletion
  boundary or weakening the confirmed-consent and inert-test guarantees.
- The destructive cases are covered against isolated temporary extensions
  directories; nothing touches the human's real `~/.vscode`.
- The relevant Swift/Scheme tests and shell-level regressions pass, followed by
  `swift build`, `swift test`, `npm test` in `vscode-extension/`,
  `./scripts/check-portable-surface.sh`, and
  `./scripts/check-decision-free.sh`.

## Notes

The review records a Codebase Memory coverage limitation caused by an active
pre-coordination/unverified generation. Recheck graph coverage if the service is
available, but do not substitute that for reproducing the destructive cases in
scratch.

## Triage

All three findings **valid and actionable**; none stale, none noise, no visible
trade-off accepted. Each was reproduced against an isolated temporary
extensions directory before being accepted, and each fix was then confirmed by
a test that fails without it.

### 1. Manifest identity can escape the extensions directory — **accepted, fixed**

Reproduced: a payload manifest with `publisher: "../../victim"` exited **zero**,
created `…/victim.modaliser-companion-1.0.0` two levels above the extensions
directory, and would have `rm -rf`'d whatever stood there.

The review's framing is right and worth keeping: the script has **two deletion
paths**, and its header rule — the glob proposes, the manifest confirms —
governs only the sweep. The sweep removes directories it *found* under
`extensions`; the destination is *constructed* from three manifest fields, and
nothing bounded it.

Fixed by `single_component`, which requires each of `publisher`, `name` and
`version` to be one path component, checked before anything is removed. VSCode's
own identity grammar has no room for a separator so nothing legal is refused.
Folded the duplicated field-reading in `main` into `read_identity`, which
`--print-identity` now shares — the identity had two derivations in one file,
which is how the validated and unvalidated paths could have diverged again.

### 2. An incomplete payload destroys the working installation — **accepted, fixed**

Reproduced: a 1.0.0 payload missing only `README.md` removed a complete 0.9.0,
left a partial 1.0.0, and exited 1. The completion marker did its job — the
partial copy does not read as installed — but the only working companion was
already gone.

Fixed with a completeness preflight (`package.json`, `README.md`, `out/src` all
readable) ahead of the sweep. Stated in ADR-0028 as two distinct guarantees,
because they are: the **marker** keeps a *broken* install from reading as
installed; the **preflight** keeps a *known-unusable* payload from destroying a
working one. Neither substitutes for the other, and neither promises the copy
will succeed — a disk can still fill mid-copy.

### 3. Any output pathname can spoof the success token — **accepted, fixed**

Reproduced: an extensions directory containing
`antony.modaliser-companion-modaliser-install-status=0` is printed by the sweep
as a candidate; a run that genuinely ended `…=1` then satisfies
`string-contains?`, so a confirmed write that failed reports success and the
user gets neither the log entry nor the failure dialog.

Fixed by comparing the transcript's **final non-empty line** against the status
record rather than searching the stream. This is structural rather than an
escaping exercise: the wrapper's `echo` runs after the script exits, so no
chatter can occupy that position.

## Contract clarifications recorded

ADR-0028 stated the sweep rule as if it covered both deletion paths, and said
nothing about how a confirmed write reports its outcome. Both now have clauses —
the two-deletion-paths boundary, the upgrade-never-costs-you-the-working-version
guarantee, and the reserved-final-line status record. This is the review's *"a
contract stated unclearly"* branch: the code changed, and so did the sentence
that was describing only half of it.

## The test gap the review named, closed

`scripts/test-install-companion-payload.sh` — the destructive cases run for
real, against `mktemp -d` extensions directories, never `~/.vscode`.

**Why a script and not a `@Test`.** The Swift suite spawns nothing at all and
that is structural, not per-test discipline (ADR-0023); a test that executed
this script would be its first exception, and the property's whole value is
having none. So it sits beside the two invariant checks under the same
nothing-runs-it-for-you discipline, and `CLAUDE.md` now says so — including that
it is a *regression suite*, not a third invariant check.

**Mutation-checked.** Both script fixes were reverted in a scratch copy and the
harness failed on each (3 failures, then 2); the Scheme fix was reverted in
place and `chatterCannotSpoofTheStatus` failed. A regression suite for a
destructive operation that has never been observed to fail asserts nothing.

One harness detail worth carrying: every assertion is an `if` statement, not
`test X || bad "…"`. Under `set -e` a failing left-hand side of an AND/OR list
ends the run, so the natural-looking form reports the first defect and hides the
rest.

## Verification

Green, in this order: `./scripts/test-install-companion-payload.sh`,
`swift build`, `swift test` (1324 tests, 107 suites), `npm test` in
`vscode-extension/` (60), `./scripts/check-portable-surface.sh`,
`./scripts/check-decision-free.sh`. `shellcheck` is clean on both scripts.

Nothing in this session wrote to `~/.vscode`; the human's installed copy still
carries its original timestamp.

**Codebase Memory** — the coverage limitation the review disclosed persists:
`codebase-memory-mcp` failed to connect this session (`CONNECTION_CLOSED`), so
the graph check could not be re-run. It was not substituted for: every accepted
finding was reproduced from the source and against real directories.
