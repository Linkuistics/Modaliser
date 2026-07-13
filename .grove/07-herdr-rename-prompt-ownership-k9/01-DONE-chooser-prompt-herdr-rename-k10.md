# chooser-prompt-herdr-rename-k10

**Kind:** work

## Goal

Add a `chooser-prompt` primitive (text input + closure continuation,
reusing the chooser's activating-WebView-panel machinery) and wire it into
`rename-focused-tab!` / `rename-focused-workspace!`, pre-filled with the
focused id's current label, so herdr's rename ops actually collect a label
instead of hitting herdr's own missing-arg usage error.

## Context

- Parent `BRIEF.md` has the full architectural decision — read it first.
- `ui/chooser.scm` structure to extend: `chooser-open-impl`,
  `render-chooser-html`, `chooser-message-handler` (dispatches on
  `'ready`/`'search`/`'select`/`'secondary-action`/`'cancel`/
  `'toggle-actions`), `chooser-webview-id`. A prompt mode needs its own
  render path (no result list, no actions panel) and its own message type
  for "submit typed value" — `chooser.js`'s `sendSelect` currently bails
  when `chooserItems.length === 0`, so Enter needs a new branch that always
  posts the current input value in prompt mode.
- `(modaliser state-machine)` hook pattern to mirror:
  `open-chooser-impl`/`set-open-chooser!`/`open-chooser` (state-machine.sld
  ~L404-420). `herdr.sld` is portable-tree and cannot import a host-specific
  `ui/*.scm` file directly — it must call through a deferred hook the same
  shape as `open-chooser`.
- Label pre-fill: `herdr tab list` / `herdr workspace list` (via the
  existing `herdr-json`/`current-herdr-query-runner` seam) return a `label`
  field per entry — filter to the focused `tab_id`/`workspace_id`
  (`focused-tab-id`/`focused-workspace-id` likely already exist in
  herdr.sld; confirm before adding new lookups).
- Rewire target: `herdr.sld` ~L377-390. Keep firing through
  `herdr-cmd-async`/`current-herdr-async-runner` once the label is in hand
  — only the missing argument changes, not the async-firing shape
  (`herdr-dialogs-async-k2` already proved that part out).
- `(modaliser dialogs)`'s `dialog-confirm` is the CPS shape to match:
  continuation is a closure, cancel means the continuation never fires
  (Escape → no herdr call at all), no capture handling in the primitive
  itself (ADR-0015 already released capture before this terminal leaf's
  action runs).
- Test pattern: `Tests/ModaliserTests/ChooserRenderTests.swift` stubs the
  four `webview-*` primitives at the Scheme level — mirror this so no test
  opens a real WebView. Extend
  `Tests/ModaliserTests/ModaliserMuxesHerdrLibraryTests.swift`'s
  `fourHerdrOpsFireExactAsyncVerbsWithFocusedId`-style pattern to verify
  the rename ops now pass a real typed label through to
  `current-herdr-async-runner`.

## Done when

- `chooser-prompt` (or equivalent name settled during implementation) is
  wired through a `(modaliser state-machine)` deferred hook so `herdr.sld`
  can call it without importing `ui/chooser.scm` directly.
- `rename-focused-tab!` / `rename-focused-workspace!` open the prompt
  pre-filled with the current label; submitting fires
  `herdr tab rename <id> <label>` / `herdr workspace rename <id> <label>`
  through the existing async seam; cancelling fires nothing.
- Pure render + message-handling tests for the new prompt mode (mirroring
  `ChooserRenderTests.swift`); herdr.sld tests confirming the label reaches
  `current-herdr-async-runner` unescaped-correctly (reuse `sq-escape` where
  the label is shell-interpolated, matching `worktree-switch-command`'s
  existing branch-name handling).
- `swift test` green (usual skips: `ModaliserAppsItermLibraryTests`,
  `HttpLibraryTests`); `scripts/check-portable-surface.sh` passes.
- Live spot-check: leader → herdr tree → rename tab (and workspace), the
  prompt appears pre-filled with the current label, Enter applies the
  edited label, Escape cancels with no herdr call fired.

## Notes

- If implementation reveals the parent brief's sketch needs adjusting
  (naming, message-protocol shape), that's expected — the brief recorded
  direction, not a locked API. Amend ADR-0014 / the root `BRIEF.md` again
  in place if the actual shape diverges from what they now state.
