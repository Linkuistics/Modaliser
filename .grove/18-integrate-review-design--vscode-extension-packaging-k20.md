# vscode-extension-packaging-k20

**Integrates:** vscode-extension-packaging-k19

## Goal

Triage the adversarial review of the companion-extension packaging design,
applying every finding that stands before implementation builds against the
decision.

## Context

Read `vscode-extension-packaging-k19` from its committed review task, then
reconcile ADR-0028, any affected current-state documentation, and the live
implementation handoffs it cites. This is design integration: settle the
distribution, consent, cleanup, and host-boundary contracts rather than
implementing the companion-extension installer.

## Done when

- Every finding in `vscode-extension-packaging-k19` is explicitly accepted,
  rejected, or reframed with evidence.
- Every accepted finding is integrated into the durable design and affected
  live implementation briefs; every rejection or reframing records why.
- The resulting ADR set and documentation are internally coherent, and no live
  implementation leaf points at a superseded or under-specified contract.

## Notes

Preserve this repository's numbered-ADR convention. Production and test
implementation remain the responsibility of the downstream implementation
leaves.
