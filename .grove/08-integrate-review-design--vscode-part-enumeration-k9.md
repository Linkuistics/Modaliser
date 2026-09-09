# vscode-part-enumeration-k9

**Integrates:** `vscode-part-enumeration-k8`

## Goal

Triage the paired design review and apply every finding that survives scrutiny
to the VSCode part-enumeration design, leaving k7 an implementable and coherent
contract.

## Context

- The reviewed artifacts are `docs/specs/vscode-editor-listing.md` and
  `docs/adr/0026-vscode-parts-come-from-the-accessibility-tree.md`.
- The producer is `vscode-part-enumeration-k6`; the review handle above is the
  source of findings and evidence.
- `vscode-part-panels-k7` is the consumer. Reconcile its charter with the
  resulting current-state design rather than leaving it to rediscover a design
  choice during implementation.

## Done when

- Every review finding is classified and every accepted one is integrated into
  the design artifacts; rejected findings retain the evidence for rejection.
- The spec's requirements, seams, accessibility anchors, collision policy, and
  handle invariants agree with one another and with ADR-0026.
- ADR-0026 remains a minimum coherent current-state record, reworked in place if
  its terminal or editor-source decision changes.
- k7 can implement the result without reopening a source-selection or sequencing
  question.

## Notes

Findings live in the review leaf and are deliberately not copied here.
