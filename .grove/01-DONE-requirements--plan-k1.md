# plan-k1

## Goal

Define how “Grove Leaf” closes deleted Grove task tabs while showing the current
task file in the focused VSCode window.

## Context

The driver created an empty task and root brief. The workspace name supplied
the initial request; the human then narrowed cleanup to Grove task tabs.
The existing “Grove Leaf” composition reveals the current task but does not
close stale tabs. The root brief contains the agreed behavior,
implementation boundary and test seams.

## Done when

- Cleanup scope and acceptance cases are recorded in the root brief.
- The human has checked the proposed test seams before the design is committed.
- One complete implementation increment is ready for a fresh session.

## Notes

Implementation is prepared as `grove-task-tab-cleanup-k2`. The requirements and
test seams are settled; implementation and its validation belong to that leaf.

## Decisions (running log)

- The human scoped cleanup to “Only deleted Grove task tabs.” Other deleted-file
  tabs are outside this change.
- There were fewer than three interdependent open questions, so a full grilling
  was unnecessary. The concrete behavior and test seams are recorded in the
  root brief.
- The existing companion environment and Scheme runner seams are sufficient to
  test this increment without driving the human's editor. A new independent
  test harness or a standalone design spec is unnecessary.
- The human accepted the concrete behavior and test coverage with “Yes,
  proceed”: clean missing Grove task tabs only, including Markdown previews;
  cleanup even without a live task; and the existing companion fakes and
  Scheme runners covering scope, unsaved edits, window identity, failures and
  normal reveal behavior. No further requirements questions remain.
