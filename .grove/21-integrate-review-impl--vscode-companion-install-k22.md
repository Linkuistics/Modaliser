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
