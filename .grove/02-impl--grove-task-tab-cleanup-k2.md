# grove-task-tab-cleanup-k2

## Goal

Make “Grove Leaf” close clean, deleted Grove task tabs in the initiating VSCode
window while preserving the existing current-task reveal. Deliver the complete
path through the companion, Scheme facilities and example composition, using
the root brief's scoped behavior and test seams.

## Context

Read the root brief's curated ADRs and existing VSCode-window-parts spec before
changing the companion's bounded method set. Its current contract admits only
listing and focus; this increment adds conditional closure and metadata checks,
so update that contract in place with the code.

Start with the existing companion `dispatch`/`PeerEnv` seam and Scheme query,
notification and asynchronous-shell runners. Preserve peer-plus-token identity,
live dirty/focus/membership checks, and the no-command-passthrough boundary.
Keep Grove task recognition separate from editor mechanics; compose the two at
the “Grove Leaf” row.

## Done when

- The root brief's behavioral cases are implemented and verified together.
- Focused companion and Scheme tests exercise actual public operations through
  the agreed existing seams; the affected example config still loads.
- The current method inventory, capability descriptions, glossary, spec and
  install/version guidance agree with the resulting implementation. Keep
  unrelated documentation and existing public behavior unchanged.
- Record the tests actually run and distinguish fake-backed call verification
  from any live-editor effect verification. If a VSCode smoke check is needed,
  follow the existing spec's isolated-VM workflow, using disposable task files.

## Notes

- A missing task path after a DONE rename is an ordinary case; a DONE task file
  that still exists must remain open. Cleaning a finished or removed grove must
  not require its `.grove/` directory to still exist.
- Check definite absence through the backing resource's filesystem API, not a
  displayed “Deleted” label or a general catch-all error. Cleanup must not save
  or discard edits, and it must not turn an ordinary reveal into a synchronous
  wait for the editor host.
- The human's user-owned composition is distinct from the shipped example.
  Document adoption through the existing example/mirror and companion install
  flow; shipping new facilities alone does not rewrite an existing config.
