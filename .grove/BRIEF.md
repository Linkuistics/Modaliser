# vscode-show-grove-task-file-should-close-deleted-editors — brief

## Goal

When “Grove Leaf” shows the current task in the focused VSCode window, clear
stale tabs left by Grove renaming, moving or deleting task files. The human's
scope is explicit: “Only deleted Grove task tabs.”

## Done when

- Invoking “Grove Leaf” closes eligible deleted task tabs across the initiating
  window's editor groups and retains the normal current-task reveal and explorer
  follow-up.
- Eligibility is limited to task files under that workspace's own `.grove/`
  tree, including nested task directories. A task uses Grove's current filename
  shape: `NN-[DONE-|ABANDONED-]<session-kind>--<slug>-k<key>.md`. A rename makes
  the tab's old path eligible only when that path is now missing. A terminal
  marker alone does not make an existing file eligible.
- Text tabs and custom Markdown preview tabs are covered. Clean pinned tabs are
  eligible too. A task open in several groups is cleaned up in every group.
- Existing files, dirty tabs, unrelated deleted files, `.grove/BRIEF.md`, other
  non-task files, tabs from another workspace's grove, untitled/virtual resources
  and diff editors stay open. Paths are compared by directory containment, not
  by an arbitrary `.grove` substring or a workspace-name prefix.
- A file is considered missing only on a definite not-found result for its
  actual backing resource. Permission errors, an unavailable provider, and
  other uncertain results leave the tab open. No contents are saved, discarded,
  recreated or deleted by cleanup.
- The peer and live tab identities remain bound to the initiating window.
  Focus, membership and dirty state are checked again after asynchronous work
  before closing. A closed/replaced tab or a window that has lost focus is a
  no-op; the action never redirects to the new focused window.
- Cleanup preserves focus, is best effort, and does not block the Scheme
  evaluation thread waiting for file checks or tab closure. A missing/older
  companion or an individual cleanup failure does not prevent the existing
  current-task reveal.
- Cleanup is attempted whenever the action can identify the workspace, even
  when it has no live leaf or its `.grove/` directory has been removed. The
  existing no-live-leaf message still applies when there is nothing to reveal.
- Focused behavioral tests pass, the shipped example shows the new composition,
  and the existing companion contract documentation describes the added
  capability consistently.

The human accepted this behavior and test coverage with “Yes, proceed” in
`plan-k1`, including cleanup when no live task remains and preservation of
unsaved edits.

## Implementation boundary

Keep editor mechanics in the VSCode facility and Grove task recognition in the
Grove facility/composition. The join remains the caller's choice; neither
library imports the other and ordinary `reveal-file!` acquires no implicit
cleanup policy.

Prefer one narrow companion notification that closes a supplied existing editor
target only if its backing resource is now missing and the tab is clean. Use the
existing peer-plus-token identity discipline. The composition selects Grove task
targets from the initiating window's parts snapshot. The companion validates
the live resource and eligibility before acting, through the existing injected
VSCode environment. This keeps Grove filename policy out of the extension and
adds no arbitrary command passthrough, path-addressed close, or force-discard
operation. Exact naming and whether targets are sent singly or in one bounded
batch are implementation choices.

The current companion contract enumerates only listing and focusing; revise it
in place to include conditional closure and metadata checks. Keep the existing
wire meanings compatible with the separately installed companion. Update its
version/install guidance as appropriate so the source change can reach a live
installation through the established install flow.

## Test seams

Agreed with the human in `plan-k1`, reusing existing seams:

- **Companion dispatch through `PeerEnv` fakes:** exercise the notification from
  wire input through tab classification, resource checks and recorded closes.
  Cover clean missing text/custom tabs, duplicate resource tabs in several
  groups, existing/dirty/unsupported resources, not-found versus other errors,
  stale/wrong-kind tokens, focus changes, and dirty/membership changes while a
  resource check is pending. A refused or failed notification stays silent on
  the wire and logs locally. Close requests preserve focus and use the actual
  live tab object.
- **Scheme library/composition through the existing runner seams:** use canned
  parts snapshots and recording notification/async-shell runners. Prove only
  this workspace's task-shaped paths are selected, including nested and
  renamed/retired paths; a sibling workspace prefix and ordinary `.grove`
  markdown are rejected. Prove peer binding, no synchronous wait for cleanup,
  retained reveal/follow-up behavior, and cleanup with no live leaf. Use a
  recording follow-up so tests emit no real keystrokes. Extend the existing
  example-config load test if the composition changes its dependencies.

These tests operate on synthetic tabs and temporary paths; they need no access
to the human's running VSCode or open documents.

## Decomposition

- `plan-k1` settles the behavior and test seams.
- `grove-task-tab-cleanup-k2` delivers the companion operation, scoped
  composition, tests and reconciled documentation together.

No separate design or planning leaf is needed. The new cross-process close
capability warrants a focused implementation session rather than extending the
requirements interview into the entire change.

## Pointers

- `docs/adr/0021-decision-free-libraries.md` — the facility/composition boundary.
- `docs/adr/0026-vscode-parts-come-from-a-companion-extension.md` — bounded method
  set, notifications, separately installed peers and exposure inventory.
- `docs/adr/0027-vscode-window-addressed-by-pointer-acted-on-by-peer.md` — peer
  binding, token identity and focus checks.
- `docs/specs/vscode-window-parts.md` — current wire contract and agreed existing
  test seams; revise its affected sections in place with the implementation.
- Glossary: Editor tab, VSCode companion extension, Last-focused pointer file,
  Facility, Decision, Shell seam and Example composition.
- Current action: `Sources/Modaliser/Scheme/examples/vscode.scm`, “Grove Leaf”.
- Facilities: `Sources/Modaliser/Scheme/lib/modaliser/apps/vscode.sld` and
  `Sources/Modaliser/Scheme/lib/modaliser/tools/grove.sld`.
- Companion: `vscode-extension/src/{dispatch,actions,peerEnv,extension,protocol}.ts`
  and the existing `vscode-extension/test/` fakes and tests.
- Scheme tests: `ModaliserAppsVscodeLibraryTests`,
  `ModaliserAppsVscodeTransportTests`, `ModaliserAppsVscodePartPanelsTests` and
  `ModaliserToolsGroveLibraryTests`.
- [VSCode TabGroups API](https://code.visualstudio.com/api/references/vscode-api#TabGroups)
  supports closing a specific tab with focus preservation. Its ordinary close
  may prompt if a tab becomes dirty; never bypass that protection or promise an
  atomic no-prompt guarantee across the editor-host boundary.
- [VSCode filesystem API](https://code.visualstudio.com/api/references/vscode-api#FileSystem)
  provides metadata checks; `FileSystemError.FileNotFound` distinguishes a
  missing resource from other failures.

## Evidence limits

The codebase-memory CLI could not start because a pre-coordination or unverified
generation was active. No project/generation or coverage result was available;
the bounded code and test pointers above were verified by direct source reads.
Re-establish graph freshness and coverage in the implementation session if the
service is available. No code or tests have been changed or run by the
requirements session.
