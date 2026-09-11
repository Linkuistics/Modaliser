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

## Decisions (running log)

- Add `close-editor-if-missing` as a token-only notification. Keep protocol 1
  meanings compatible and bump the independently installed companion to 1.1.0.
  Restrict closure to local `file` text/custom tabs; check metadata via
  `workspace.fs.stat`, accept only FileSystemError `FileNotFound`, and recheck
  focus, membership, input identity and dirty state before `tabGroups.close(tab,
  true)`. Ordinary host close protection remains in force across the RPC race.
- Keep task-path recognition pure in `(modaliser tools grove)` and expose the
  full backing path on Scheme editor targets. Compose selection and cleanup in
  the example before live-leaf lookup, using the one initiating parts snapshot;
  retain the workspace fallback and reveal when the companion is unavailable.
- Graph startup failed with the active unverified-generation error; source
  evidence uses the brief's bounded paths. API decisions were checked against
  VSCode 1.136.0's official `vscode.d.ts`, matching the manifest's minimum.
- Task recognition compares absolute directory components, rejects traversal,
  and parses the current nineteen kinds and terminal outcomes without touching
  the filesystem. The shipped example keeps the original no-live-leaf dialog
  and takes an optional reveal follow-up for user composition and inert tests.
- Dispatch tests first failed with unknown-method replies, and Scheme tests
  first failed on the missing public operation/predicate. The implemented
  operations pass those cases. Dialogs use their own recorder so the no-leaf
  branch cannot be mistaken for an asynchronous file reveal.
- One bounded fresh-context review found no concrete contract violations.
  No second reviewer or review leaf is needed; the behavioral questions have
  executable coverage through the existing seams.

## Verification

- `cd vscode-extension && npm test`: 80 tests passed (TypeScript compilation
  plus the Node suite).
- `swift test --filter 'ModaliserAppsVscode|ModaliserVscodeGroveCleanupTests|ModaliserToolsGroveLibraryTests|ConfigDslTests.exampleConfigsLoadWithoutErrors'`:
  116 tests across nine suites passed, including the actual example operation
  with four live-leaf/send-failure combinations and the example-config load test.
- `scripts/check-portable-surface.sh` and `scripts/check-decision-free.sh` passed.
  `swift format lint` with four-space/120-column configuration passed for the
  new composition test file.
- SHA-256 inventories compared equal per file before and after the final runs:
  Sources, Tests, companion src/test, scripts, docs, CONTEXT.md, Package.swift,
  Package.resolved, and companion package/lock/tsconfig manifests. No subject
  was edited while those checks ran.
- These are fake-backed call checks. No live VSCode cleanup smoke test or
  user-owned config/companion installation was performed. Adoption uses the
  updated mirrored example and the documented companion 1.1.0 install flow.
- Root brief checked against the delivered code, tests and reconciled spec/ADRs:
  no remaining implementation gap. There are no intermediate nodes to close;
  final grove teardown remains the driver's finish session.
