# vscode-terminal-listing-k14

**Integrates:** vscode-terminal-listing-k13

## Goal

Triage the findings from the adversarial review of the VSCode window-parts
design, applying the findings that stand and recording why any are rejected,
before either implementation leaf builds against the design.

## Context

Read `vscode-terminal-listing-k13` from its committed review task, then reconcile
the current `docs/specs/vscode-window-parts.md`, ADR set, and live Grove briefs it
cites. This is design integration: resolve the record and downstream contracts,
not the companion-extension or Scheme implementation itself.

## Done when

- Every finding in `vscode-terminal-listing-k13` is explicitly accepted,
  rejected, or reframed with evidence.
- Every accepted finding is integrated into the durable design and any affected
  live implementation brief; every rejected or reframed finding has its
  rationale recorded in this task.
- The resulting spec/ADR set is internally coherent, and no queued implementation
  leaf is left pointing at a superseded path, decision number, or contract.

## Notes

Preserve the repository's deliberate numbered-ADR convention. No production or
test implementation belongs in this leaf.
