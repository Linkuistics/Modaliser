# Task: Modaliser Phase 2 Features

Implement six features for Modaliser: app icon integration, overlay in-place update, async run-shell with timeout, quicklinks/snippets selectors, clipboard history with full UTI support, and a full Scheme-based state machine reimplementation. Design spec at `docs/superpowers/specs/2026-03-20-phase2-design.md`.

## Session Continuation Prompt

```
You MUST first read `LLM_CONTEXT/index.md` and `LLM_CONTEXT/coding-style.md`.

Please continue working on the task outlined in `LLM_STATE/plan-phase2-features.md`.
The design spec is at `docs/superpowers/specs/2026-03-20-phase2-design.md`.
Review both files to see current progress, then continue from the next
incomplete step. After completing each step, update the plan file with:
1. Mark the step as complete [x]
2. Add any learnings discovered

Use TDD: write tests first, then implement. Keep files small and focused.
```

## Progress

### Feature 1: App Icon

- [x] 1.1 Add `Resources/AppIcon.png` placeholder and extend `build-app.sh` to generate `.icns` via `sips`/`iconutil`, copy to `Contents/Resources/`, add `CFBundleIconFile` to `Info.plist`, update `.gitignore` for generated iconset

**— Review 1 —**
- [x] 1.R Review app icon integration: verified icon generation pipeline produces 268KB .icns from 988x1024 source PNG; sips handles non-square source gracefully

### Feature 2: Overlay In-Place Update

- [x] 2.1 Refactor `OverlayPanel.showOverlay` to detect existing panel and update in-place: persist `panel`/`containerView` across calls, clear and rebuild subviews within existing container using `CATransaction`, recalculate layout and resize/reposition panel if entry count changed
- [x] 2.2 Update tests: verify no dismiss/recreate cycle on subsequent calls, test panel resize across different entry counts

**— Review 2 —**
- [x] 2.R Review overlay changes: 6 new OverlayPanel tests + 9 existing OverlayCoordinator tests all pass. CATransaction batches subview changes to prevent flicker. Panel reuse verified via identity check.

### Feature 3: Async `run-shell`

- [x] 3.1 Write tests for `run-shell-async`: callback receives correct exit-code/stdout/stderr, timeout kills process and returns `-1`/`"timeout"`, sync `run-shell` regression test
- [x] 3.2 Implement `run-shell-async` in `ShellLibrary`: background dispatch, separate stdout/stderr pipes, main-thread callback invocation, optional `'timeout` parameter, process tracking for cleanup on quit

**— Review 3 —**
- [x] 3.R Review async shell: 11 shell tests pass (5 new async + 6 existing sync). LispKit VirtualMachine requires main-thread evaluation; callback dispatches via DispatchQueue.main.async. Tests use async/await Task.sleep to yield main actor for GCD block processing. Process tracking via Set<Process> with terminateAllProcesses() for app quit cleanup.

### Feature 4: Quicklinks & Snippets Selectors

- [x] 4.1 Write tests for `QuicklinksLibrary`: s-expr file parsing (valid, empty, malformed), tag filtering, alist-to-ChooserChoice transformation
- [x] 4.2 Implement `QuicklinksLibrary`: NativeLibrary with `get-quicklinks`, reads `~/.config/modaliser/quicklinks.scm`, transforms `name` to `text` key for chooser, supports `'tag` filter parameter
- [x] 4.3 Write tests for `SnippetsLibrary`: s-expr parsing, tag filtering, `expand-snippet` with each placeholder (`{{date}}`, `{{time}}`, `{{datetime}}`, `{{clipboard}}`)
- [x] 4.4 Implement `SnippetsLibrary`: NativeLibrary with `get-snippets` and `expand-snippet`, same file-reading pattern as quicklinks, string-replace pass for template placeholders

**— Review 4 —**
- [x] 4.R Review: 6 quicklinks + 8 snippets tests pass. Both libraries use Scheme-driven approach: Swift provides only config path + date formatting, Scheme handles file I/O via `read`/`call-with-input-file`, data transformation via `map`/`filter`. No reentrant evaluator issues. `name` -> `text` rename confirmed. Registered in SchemeEngine.

### Feature 5: Clipboard History

- [x] 5.1 Write tests for `ClipboardHistoryStore`: add entry with multiple UTI types, directory structure creation, index.scm round-trip, history limit enforcement (oldest deleted), deduplication
- [x] 5.2 Implement `ClipboardHistoryStore`: directory-based storage under `~/.config/modaliser/clipboard-history/`, s-expr index with R7RS alists, per-entry UTI directories, limit enforcement
- [x] 5.3 Write tests for `ClipboardMonitor`: change count detection, app-based exclusion filtering, dedup logic (mock NSPasteboard and FocusedAppObserver)
- [x] 5.4 Implement `ClipboardMonitor`: PasteboardReading protocol for testability, enumerate all UTI types, write to store, check exclusion list
- [x] 5.5 Implement `ClipboardHistoryLibrary`: NativeLibrary with `get-clipboard-history`, `clear-clipboard-history!`, `restore-clipboard-entry!`, `set-clipboard-exclude!`, `set-clipboard-history-limit!`. Registered in SchemeEngine. Wiring `ClipboardMonitor` startup in `ModaliserAppDelegate` deferred to integration.

**— Review 5 —**
- [x] 5.R Review: 18 clipboard tests pass (9 store + 4 monitor + 5 library). PasteboardReading protocol enables mock testing. Index persistence verified via reload test. Binary data round-trip verified with PNG bytes. Timer-based polling (500ms) not yet wired in AppDelegate — that's an integration concern.

### Feature 6: State Machine in Scheme

- [ ] 6.1 Write Scheme state machine module: `modal-enter`, `modal-handle-key`, `modal-exit`, `modal-step-back`, tree storage via `define-tree`, helper predicates (`command?`, `group?`, `selector?`). Load as a LispKit library.
- [ ] 6.2 Write tests for `SchemeModalBridge`: translation of each Scheme result type (`activated`, `navigated`, `executed`, `open-selector`, `no-binding`, `deactivated`) to `KeyDispatchResult` enum, error recovery (Scheme throws -> fallback to exit)
- [ ] 6.3 Implement `SchemeModalBridge`: Swift class that calls Scheme state machine functions via `SchemeEngine`, parses s-expr results to `KeyDispatchResult`, wraps all calls in try/catch
- [ ] 6.4 Modify `define-tree` to store trees in Scheme-side data structures instead of building Swift `CommandNode` enums. Keep Swift `CommandNode`/`CommandTreeRegistry` for the existing code path.
- [ ] 6.5 Add `(set-state-machine! 'scheme)` config flag. Wire `SchemeModalBridge` into `KeyEventDispatcher` as alternative to `ModalStateMachine` based on flag. Port overlay content building to work with Scheme-side tree data.
- [ ] 6.6 Port all `ModalStateMachineTests` to run against both Swift and Scheme implementations. Add integration test: full key event -> Scheme -> result -> Swift action cycle. Benchmark Scheme vs Swift per-keypress latency.

**— Review 6 —**
- [ ] 6.R Review state machine: manual testing with `(set-state-machine! 'scheme)` in config, verify all key bindings work, test edge cases (escape at root, step-back at root, unknown keys, rapid key presses), compare behavior with Swift implementation

**— Final Review —**
- [ ] F.R Final review: run full test suite, verify all features work together, update `LLM_README.md` Phase 2 section to reflect completed work, clean up any dead code from migration

## Learnings

- **Scheme should drive file I/O, not Swift.** NativeLibrary functions run inside an `evaluator.execute` block, so calling `evaluator.execute` again is reentrant and crashes. Instead, use `self.define(name, via:)` to define Scheme functions that use `read`/`call-with-input-file` — Scheme handles its own data natively.
- **Import the full `(lispkit base)` library** rather than cherry-picking symbols — `self.import(from: ["lispkit", "base"])` with no trailing args imports everything. This avoids issues with syntax forms like `let*` which can't be imported by name, and keeps dependencies clean.
- **LispKit's `VirtualMachine` requires main-thread evaluation.** Async callbacks must dispatch to `DispatchQueue.main.async`. Tests use `async/await` with `Task.sleep` to yield the main actor.
- **`Expr.asInt()` defaults to `above: 0`** — use `asInt64()` for values that may be negative.
