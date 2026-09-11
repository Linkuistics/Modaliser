# plan-k1


## Goal

Establish the failure and any resulting requirements after the user reported:
“I think some grove workflow somehow killed VSCode, and all of the grove sessions.”

## Context

This workstream is named for the Grove Leaf deleted-editor cleanup. Its bootstrap
brief and task body were empty when this session began; the workspace already
contained extension and release-documentation edits.

## Done when

- The reported application/session loss has a concrete evidence-based explanation,
  with the observed failure separated from any unproven initiating cause.
- Any resulting work is scoped to its actual owner without assuming that deleted
  editor cleanup or Grove's completion signal caused the failure.

## Notes

The user placed the event about two minutes before answering the timing question.

## Decisions (running log)

2026-09-11: Diagnose the reported shutdown before proposing behavior changes.
Graph startup refused an incompatible active generation, so code evidence comes
from direct source reads; no graph freshness or coverage claim is made.

2026-09-11: macOS launchd records VS Code PID 67437 exiting at 16:53:40.808 AEST
“due to SIGTRAP | sent by exc handler[67437]”. VS Code's next main log begins at
16:53:48.676. The matching Crashpad dump is
`~/Library/Application Support/Code/Crashpad/completed/2f29dee4-6d1e-4e9a-b2a4-9ca9e87b5a3b.dmp`.
Its annotations identify VS Code 1.137.0, Electron 42.10.0, process type `browser`,
PID 67437, `electron.v8-oom.location=Reached heap limit`, heap used 4,164,542,836
bytes and heap limit 4,294,967,296 bytes. This establishes a main-process heap
exhaustion crash. It does not identify what retained the memory or prove that
Grove or Modaliser activity triggered it. Do not change editor cleanup or process
signalling on that unsupported premise.

2026-09-11: The user was “Letting Grove sessions run” immediately before the
failure. No deliberate Grove Leaf invocation was reported. Sustained session
activity is context for investigating memory growth, not proof of its cause.

2026-09-11: The user asked whether the heap limit can be increased. Two isolated
headless runs of the installed Code executable (`ELECTRON_RUN_AS_NODE=1`) queried
`require("v8").getHeapStatistics().heap_size_limit`: both the default and
`--max-old-space-size=8192` returned 4,294,967,296. Both reported Electron 42.10.0
and Node 24.18.1. A heap-size setting does not lift this build's 4 GiB cap.
No live application restart or settings change was needed for that check.

2026-09-11: The previous Crashpad dump, `fd0a0eaf-4ee3-4253-b10a-738e98f54339.dmp`
(file timestamp 2026-09-10 21:20), has the same VS Code version, browser process,
`Reached heap limit` annotation and 4 GiB cap (4,174,177,428 bytes used).
Upstream microsoft/vscode#329843 reports main-process retention of integrated
terminal output under concurrent CLI sessions. This is a plausible lead, not a
locally verified retainer chain. Prefer trying an external terminal for long-lived
Grove sessions over changing Modaliser cleanup or proposing an ineffective heap
flag. Further attribution requires a heap profile or an isolated reproduction.

2026-09-11: The requirements outcome is diagnostic guidance, with no new
Modaliser behavior or test seam to design. Record the durable guidance in the
companion README. The existing upstream report carries the remaining terminal
retention lead; no duplicate issue or speculative implementation leaf is needed.
