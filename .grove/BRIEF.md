# Modaliser.vscode-show-grove-task-file-should-close-deleted-editors — brief

## Goal

Resolve the reported loss of VSCode and its Grove sessions before inferring any
change to the Grove Leaf deleted-editor cleanup workflow.

## Done when

- The application exit and matching crash dump have been checked.
- The user's question about increasing the heap limit has been answered against
  the installed executable.
- The durable troubleshooting guidance distinguishes verified observations from
  the remaining memory-retention hypothesis.

## Decomposition

`plan-k1` owns the incident triage and resulting requirements. The confirmed
failure is VSCode main-process heap exhaustion; no Modaliser implementation
change follows from the evidence. The remaining retainer-chain investigation
has an existing upstream lead, microsoft/vscode#329843.

## Pointers

- `vscode-extension/README.md`, “Diagnosing a whole-application crash”.
- https://github.com/microsoft/vscode/issues/329843

## Notes

The user was letting Grove sessions run when VSCode disappeared. Raising the
heap flag to 8192 MiB leaves the installed Electron 42.10.0 build's effective
heap limit at 4 GiB. The proposed operational workaround is an external terminal
for long-lived Grove sessions; it has not been tested as a fix for this incident.
No application settings, running sessions or companion behavior were changed.
Extension and release-documentation edits already present at launch are in the
parent change; this incident triage does not verify those edits or establish
their readiness for integration.
