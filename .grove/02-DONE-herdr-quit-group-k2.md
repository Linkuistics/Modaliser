# herdr-quit-group-k2

**Kind:** work

## Goal

Add a top-level `q` "Quit" group to `build-herdr-tree` in
`Sources/Modaliser/Scheme/lib/modaliser/muxes/herdr.sld`:

- `d` **Detach** — emit herdr's default detach binding into the focused
  client: `(send-keystroke '(ctrl) "b")` then `(send-keystroke "q")` (mirror
  the config's copy-mode key shape, `app-trees/com.googlecode.iterm2.scm`).
  Import `(modaliser input)` (portable — apps/*.sld precedent). Document the
  v1 default-prefix assumption at the op, as the copy-mode key does.
- `s` **Stop Server** — `dialog-confirm` (message naming the consequence:
  every pane and agent terminates; ok-label "Stop"), on OK
  `(herdr-cmd-async "server stop")`. CPS per ADR-0014; a Dialog command,
  necessarily Terminal.

Both variant trees pick the group up automatically (they splice
build-herdr-tree).

## Context

- Root BRIEF Notes hold the grilled decisions (key shape, placement, seams).
- Existing group precedent in the same file: `(group "x" "Split" …)`.
- Update the tree-shape doc comment above build-herdr-tree (the top-level key
  roster) and the stale "`c` is free in build-herdr-tree (top-level keys:
  x m z d t w g b a)" comment in `app-trees/com.googlecode.iterm2.scm`.
- Tests: `Tests/ModaliserTests/ModaliserMuxesHerdrLibraryTests.swift` — shape
  assertions and the `parameterize` pattern around
  `current-herdr-async-runner` (~line 770+) to copy for the dialog-gated stop.

## Done when

- `q` group present with `d`/`s` in build-herdr-tree (shape test).
- Stop Server behaviour tests through existing seams only: cancel → no async
  verb fired; OK → exactly `"server stop"` fired (`current-dialog-runner` +
  `current-herdr-async-runner`).
- `./scripts/check-portable-surface.sh` passes; `swift test` herdr classes
  green (note memory: ModaliserAppsItermLibraryTests crashes pre-existing —
  skip it and HttpLibraryTests for a green local run).
- Export list updated if the ops are exported; docs touched where the herdr
  tree surface is described.

## Notes

No new test seam (grilled decision). Detach's emission body stays untested by
design — same trust level as the copy-mode key.
