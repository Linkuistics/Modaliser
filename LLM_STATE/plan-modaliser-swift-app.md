# Task: Build Modaliser — A Scheme-Scriptable Modal Keyboard System for macOS

Replace the Hammerspoon-based modal keyboard system with a standalone native Swift app. Configuration and actions are defined in Scheme (via LispKit). The Swift layer handles keyboard capture, native UI rendering, and macOS system integration. The Scheme layer handles all user-facing logic: command tree definition, action execution, and extensibility.

## Session Continuation Prompt

```
You MUST first read `LLM_CONTEXT/index.md` and `LLM_CONTEXT/coding-style.md`.

Please continue working on the task outlined in `LLM_STATE/plan-modaliser-swift-app.md`.
Review the file to see current progress, then continue from the next
incomplete step. After completing each step, update the plan file with:
1. Mark the step as complete [x]
2. Add any learnings discovered

Key context:
- This is a standalone macOS Swift app (SPM executable) with LispKit (Scheme) for config/scripting
- Port UI code from ~/.config/hammerspoon/modal-chooser/ (ChooserWindow, OverlayWindow, etc.)
- CGEvent tap for global keyboard capture (requires Accessibility permissions)
- Config is Scheme with a DSL using macros: (define-key), (define-group), (define-selector)
- Actions are Scheme lambdas in the config
- Fuzzy matcher is a Swift native LispKit library for performance
- The app is an accessory app (no dock icon), lives in the menu bar
- Apply TDD, small focused files, descriptive naming per coding-style.md
```

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    Modaliser.app                         │
│                                                         │
│  Swift Host Layer (thin, mechanical)                    │
│  ├── main.swift          App entry, LispKit bootstrap   │
│  ├── KeyboardCapture     CGEvent tap, global hotkeys    │
│  ├── OverlayWindow       Which-key overlay (NSPanel)    │
│  ├── ChooserWindow       Search/select UI (NSPanel)     │
│  ├── FuzzyMatcher        DP fuzzy match (native lib)    │
│  ├── Theme               Colors/fonts from config       │
│  └── Native Libraries    macOS API wrappers for Scheme  │
│      ├── ModalAppLib         launch/focus apps          │
│      ├── ModalWindowLib      window list/focus/position │
│      ├── ModalShellLib       shell command execution    │
│      └── ModalPasteboardLib  clipboard read/write       │
│                                                         │
│  LispKit Scheme Layer (all user-facing logic)           │
│  ├── init.scm            Entry point, loads config      │
│  ├── config.scm          User config (keys, actions)    │
│  ├── modal.scm           State machine, key dispatch    │
│  ├── dsl.scm             Macros: define-key, etc.       │
│  └── ui.scm              Overlay/chooser coordination   │
└─────────────────────────────────────────────────────────┘
```

## Key Design Decisions

- **Config format**: Scheme (not YAML/JSON). The config IS code — actions are lambdas, the DSL uses macros, and users can define helper functions inline.
- **Incremental migration**: Phase 1 keeps modal state machine and UI coordination in Swift, with Scheme for config + actions. Phase 2 (future) moves state machine to Scheme.
- **Fuzzy matcher**: Stays in Swift as a native LispKit library — the DP algorithm runs 50K+ times per keystroke and needs native performance.
- **UI code**: Ported from the existing `~/.config/hammerspoon/modal-chooser/` Swift code (ChooserWindow, OverlayWindow, ActionPanel, Theme, IconLoader).
- **No Hammerspoon dependency**: CGEvent tap replaces hs.eventtap, NSWorkspace replaces hs.application, etc.

## Example Config (config.scm)

```scheme
;; DSL functions are auto-imported by SchemeEngine at startup.
;; No explicit (import ...) needed.

;; Leader keys (named constants: F17, F18, F19, F20)
(set-leader! 'global F18)
(set-leader! 'local F17)

;; Global command tree
(define-tree 'global
  (key "s" "Safari"
    (lambda () (launch-app "Safari")))
  (group "f" "Find"
    (selector "a" "Find Apps"
      'prompt "Find app…"
      'source find-installed-apps
      'on-select activate-app
      'remember "apps"
      'id-field "bundleId"
      'actions
        (list
          (action "Open" 'key 'primary 'run activate-app)
          (action "Show in Finder" 'key 'secondary 'run reveal-in-finder)
          (action "Copy Path" 'run (lambda (c) (set-clipboard! (cdr (assoc 'path c)))))
          (action "Copy Bundle ID" 'run (lambda (c) (set-clipboard! (cdr (assoc 'bundleId c)))))))
    (selector "f" "Find File"
      'prompt "Find file…"
      'file-roots '("~")
      'on-select open-file
      'actions
        (list
          (action "Open" 'key 'primary 'run open-file)
          (action "Show in Finder" 'key 'secondary 'run reveal-in-finder)
          (action "Copy Path" 'run (lambda (c) (set-clipboard! (cdr (assoc 'path c)))))
          (action "Open in Zed" 'run (lambda (c) (open-with "Zed" (cdr (assoc 'path c))))))))
  (group "w" "Windows"
    (key "c" "Center" (lambda () (center-window)))
    (key "m" "Maximize" (lambda () (maximize-window)))
    (selector "s" "Switch Window"
      'prompt "Select window…"
      'source list-windows
      'on-select focus-window)))
```

## Progress

### Phase 1: Swift host + Scheme config/actions

- [x] **Session 1: Project scaffold + keyboard capture**
  - [x] Create SPM executable project with LispKit dependency
  - [x] NSApplication setup (accessory app, no dock icon)
  - [x] CGEvent tap for global hotkey capture (F17/F18)
  - [x] Verify Accessibility permission flow
  - [x] Test: pressing F18 prints to console
  - [x] Commit and stop

- [x] **Code Review 1**
  - [x] Review project structure, CGEvent tap implementation
  - [x] Verify clean separation of concerns
  - [x] Check error handling for permission denial
  - [x] Update plan with findings

- [x] **Session 2: LispKit integration + Scheme DSL**
  - [x] Set up LispKit context with custom environment
  - [x] Design DSL functions: `key`, `group`, `selector`, `action`, `define-tree`, `set-leader!`
  - [x] Implement `(modaliser dsl)` Scheme library
  - [ ] Implement `(modaliser app)` native library (launch-app, open-file, set-clipboard!, shell basics) — deferred to Session 7
  - [x] Load and evaluate config.scm, build internal command tree representation
  - [x] Write sample config.scm with a few commands
  - [x] Test: config loads, command tree is traversable from Swift
  - [x] `set-theme!` — implemented in Session 4
  - [ ] Commit and stop

- [x] **Code Review 2**
  - [x] Review LispKit integration pattern
  - [x] Review DSL ergonomics — is the config pleasant to write?
  - [x] Check Scheme↔Swift data marshalling
  - [x] Update plan with findings

- [x] **Session 3: Modal state machine**
  - [x] Implement modal state: enter/exit leader, current node tracking, path breadcrumb
  - [x] Key dispatch: look up child in current group, descend or execute
  - [x] Command execution: call Scheme lambdas from Swift
  - [x] Group navigation: descend into subgroups, step back on delete
  - [x] Exit on escape, leader key re-press, or command execution
  - [ ] Guard: block leader key when chooser is open — deferred to Session 5 (when chooser exists)
  - [x] Test: F18 → key sequences execute Scheme actions
  - [x] Event suppression: modal keys suppressed when active, pass through when idle
  - [x] KeyCodeMapping: CGKeyCode → character for all letters, digits, punctuation
  - [x] Wired KeyEventDispatcher → ModalStateMachine → CommandExecutor in AppDelegate
  - [ ] Commit and stop

- [x] **Code Review 3**
  - [x] Review state machine correctness
  - [x] Check edge cases (rapid key presses, re-entry, focus loss)
  - [x] Verify Scheme lambda execution is robust (error handling)
  - [x] Update plan with findings

- [x] **Session 4: Which-key overlay**
  - [x] Port OverlayWindow.swift from modal-chooser (passive floating NSPanel)
  - [x] Port ChooserTheme.swift (read theme from Scheme config)
  - [x] Wire overlay show/hide to modal state machine (with configurable delay)
  - [x] Render: header breadcrumb (with app icon for local mode), sorted entries, footer
  - [x] Styling: blue keys, orange groups with "…", grey arrows, esc/del footer
  - [x] Ensure overlay never steals keyboard focus
  - [x] Test: F18 → overlay appears after delay, updates on navigation, hides on exit
  - [x] Commit and stop

- [ ] **Code Review 4**
  - [ ] Review overlay rendering, positioning, focus behavior
  - [ ] Compare visual output with existing Hammerspoon version
  - [ ] Update plan with findings

- [ ] **Session 5: Chooser window + selectors**
  - [ ] Port ChooserWindow.swift (search field, table view, keyboard handling)
  - [ ] Port ActionPanel.swift (⌘K, digit shortcuts, del back, esc cancel)
  - [ ] Port IconLoader.swift (app icon loading + caching)
  - [ ] Wire selectors from Scheme config to chooser presentation
  - [ ] Selector source functions called in Scheme, results marshalled to Swift Choice objects
  - [ ] Choice round-tripping: retain Scheme objects, resolve on selection
  - [ ] Action callbacks: dispatch to Scheme lambdas
  - [ ] ⌘1-⌘9 item selection, ⌘↵ secondary action
  - [ ] Focus management: cancel on focus loss, deactivate on dismiss
  - [ ] Test: F18→f→a opens app chooser, selection launches app, actions work
  - [ ] Commit and stop

- [ ] **Code Review 5**
  - [ ] Review chooser completeness against existing implementation
  - [ ] Check Scheme↔Swift marshalling for choices and actions
  - [ ] Verify keyboard handling (arrows, return, escape, cmd+digit, cmd+K)
  - [ ] Update plan with findings

- [ ] **Session 6: Fuzzy matching + file search**
  - [ ] Implement fuzzy matcher as native LispKit library `(modaliser fuzzy-match)`
  - [ ] Port DP algorithm from ChooserWindow.swift (match score, gap penalty, position bonus, camelCase)
  - [ ] Match highlighting: return matched indices for bold+blue rendering
  - [ ] Background search with debounce (30ms, generation counter, serial queue)
  - [ ] File indexing via fd (--hidden --follow, exclusions for Library/.Trash/.cache/.build/.git)
  - [ ] Path-aware search: "/" in query enables subText matching, tail proximity bonus
  - [ ] Search mode: showAll (apps) vs requireQuery (files)
  - [ ] Test: fuzzy search with highlighting works for both apps and files
  - [ ] Commit and stop

- [ ] **Code Review 6**
  - [ ] Review fuzzy matcher correctness (compare with existing implementation)
  - [ ] Profile performance with large file lists (50K+ entries)
  - [ ] Check debounce/threading for race conditions
  - [ ] Update plan with findings

- [ ] **Session 7: System integration native libraries**
  - [ ] `(modaliser app)` — find-installed-apps, activate-app, reveal-in-finder, open-with
  - [ ] `(modaliser window)` — list-windows, focus-window, center-window, maximize-window, window positioning (thirds)
  - [ ] `(modaliser shell)` — run shell commands, capture output
  - [ ] `(modaliser pasteboard)` — get-clipboard, set-clipboard!
  - [ ] Search memory: persist query→selection mappings to JSON files
  - [ ] Port all actions from current global.lua config to config.scm
  - [ ] Test: all existing keybindings work end-to-end
  - [ ] Commit and stop

- [ ] **Code Review 7**
  - [ ] Review native library API design (Scheme-idiomatic? consistent?)
  - [ ] Check error handling in native libraries
  - [ ] Verify feature parity with Hammerspoon version
  - [ ] Update plan with findings

- [ ] **Session 8: App-local commands + polish**
  - [ ] Implement app-local command trees (detect focused app via NSWorkspace)
  - [ ] Port Zed, Safari, iTerm local commands to config.scm
  - [ ] Menu bar icon / status item (optional, for quit/reload)
  - [ ] Config reload (re-evaluate config.scm without restarting)
  - [ ] Error reporting: Scheme evaluation errors shown as alerts
  - [ ] Launch at login support (LSUIElement + LaunchAgent or LoginItem)
  - [ ] Clipboard history watcher (port from current implementation)
  - [ ] Test: complete feature parity with Hammerspoon version
  - [ ] Commit and stop

- [ ] **Code Review 8 (Final)**
  - [ ] Full review of architecture, code quality, test coverage
  - [ ] Review config.scm ergonomics — is it pleasant for users?
  - [ ] Performance review (startup time, memory, responsiveness)
  - [ ] Document any remaining issues or Phase 2 items
  - [ ] Update plan with findings

## Reference: Files to Port from modal-chooser

Source directory: `~/.config/hammerspoon/modal-chooser/Sources/`

| File | Port strategy |
|------|--------------|
| `ChooserWindow.swift` | Port directly, remove socket protocol wiring, call Scheme callbacks |
| `OverlayWindow.swift` | Port directly, remove socket protocol, read from Swift command tree |
| `ChooserTheme.swift` | Port, read values from Scheme config instead of JSON |
| `ActionPanel.swift` | Port as-is |
| `IconLoader.swift` | Port as-is |
| `FuzzySearch.swift` | Port fd indexing; fuzzy matcher becomes native LispKit library |
| `Protocol.swift` | Not needed (no socket protocol) |
| `main.swift` | Replace with new app entry point + LispKit bootstrap |

## Learnings

### Session 1
- **LispKit dependency resolution**: LispKit 2.6.0 depends on `swift-dynamicjson` via `branch: "main"` (an unstable reference). SPM won't allow a version-pinned package to depend on unstable packages. Fix: use `branch: "master"` for swift-lispkit itself.
- **SPM entry point**: Only `main.swift` can contain top-level statements in an SPM executable target. Other filenames cause "expressions are not allowed at the top level" errors.
- **Test target linking**: SPM test targets can `@testable import` an executable target — the `main.swift` entry point doesn't interfere with test compilation, which was a concern. Works fine with Swift 6.2.
- **CGEvent tap callback**: Must be a free function (not a closure or method) due to C interop. We bridge to the Swift instance via `Unmanaged<KeyboardCapture>` passed through the `userInfo` pointer.
- **Tap auto-disable**: macOS will disable an event tap if the callback takes too long. We handle `.tapDisabledByTimeout` by re-enabling. This is important for later when Scheme lambdas are called from the callback.
- **File layout**: 5 source files, 3 test files. Each file < 100 lines, single concern. `main.swift` (4 lines), `ModaliserAppDelegate` (lifecycle+wiring), `KeyboardCapture` (event tap), `AccessibilityPermission` (permission check), `KeyCode` (constants).

### Code Review 1
- **Extracted nested types**: `CapturedKeyEvent` and `CaptureError` were nested inside `KeyboardCapture`, making it 129 lines (over the 100-line guideline). Extracted to `CapturedKeyEvent.swift` and `KeyboardCaptureError.swift` as top-level types. `KeyboardCapture.swift` is now 97 lines.
- **Renamed `CaptureError` → `KeyboardCaptureError`**: As a top-level type, the original name was too generic. The new name is self-documenting without needing the namespace prefix.
- **Added missing tests**: `KeyCode.tab`, `KeyCode.f19`, `KeyCode.f20` were defined but untested. Now all key codes have tests (16 total, up from 13).
- **`AccessibilityPermission.requestIfNeeded()` is unused**: The delegate uses a custom alert instead of the system prompt. Kept for now — may be useful for a streamlined permission flow in Session 8.
- **File count**: Now 7 source files, 3 test files. All source files under 100 lines.

### Session 2
- **LispKit `bootstrap()` vs `import(BaseLibrary.name)`**: `bootstrap()` sets up error handlers and imports `(lispkit dynamic)`, but the bindings for `define`, `+`, `lambda` etc. come from `(lispkit base)`. Using `environment.import(BaseLibrary.name)` directly is sufficient and matches LispKit's own test patterns. Can add `bootstrap()` later if dynamic features are needed.
- **No `#:keyword` syntax in LispKit**: LispKit is R7RS-based, not Racket. There is no `Expr.keyword` type. DSL uses alternating `'symbol value` pairs instead: `(selector "a" "Apps" 'prompt "Find app…" 'remember "apps")`. Works well and is standard Scheme.
- **NativeLibrary injection**: LispKit's `required init(in:)` prevents constructor injection. Solution: register library, then `lookup()` the instance and set properties. A static injection pattern causes race conditions in concurrent tests.
- **Hybrid alist approach works**: DSL functions (`key`, `group`, `selector`, `action`) return pure Scheme alists. `define-tree` walks the alists and converts to Swift `CommandNode` objects. This keeps the DSL debuggable in Scheme while giving Swift typed access.
- **Procedure init overloads**: LispKit selects the implementation style via Swift overload resolution: `native3` (3 fixed args), `native2R` (2 fixed + rest), `native1R` (1 fixed + rest), etc. `Arguments` is `ArraySlice<Expr>`.
- **File layout**: 12 source files, 8 test files. New: `CommandNode.swift` (95 lines), `CommandTreeRegistry.swift` (38 lines), `SchemeEngine.swift` (67 lines), `ModaliserDSLLibrary.swift` (158 lines), `CommandNodeBuilder.swift` (79 lines).
- **51 tests total**, 8 test suites. All pass in ~2s.
- **Deferred items**: `set-theme!` deferred to Session 4 (overlay UI), `(modaliser app)` native library deferred to Session 7 (system integration). These are the right sessions for those features.

### Code Review 2
- **Extracted `CommandNodeBuilder`**: Alist-to-CommandNode conversion logic extracted from `ModaliserDSLLibrary` into `CommandNodeBuilder.swift` (79 lines). DSL library dropped from 220 to 158 lines.
- **Registry guard**: Changed `registry` from force-unwrapped `!` to optional `?` with `guard let` in `defineTreeFunction` and `setLeaderFunction`. Crash on misconfiguration → descriptive error.
- **Descriptive alist errors**: `alistLookup` now throws `RuntimeError.custom("eval", "required key 'X' not found in DSL alist", ...)` instead of a misleading type error. Added `lookupOptional` for optional fields in selectors.
- **Key code constants**: DSL library now exports `F17`, `F18`, `F19`, `F20` as Scheme variables. Config uses `(set-leader! 'global F18)` instead of magic number `79`.
- **Plan example config updated**: Replaced `#:keyword` syntax with actual `'symbol value` syntax. Corrected `selector`-inside-`key` nesting to show selectors as direct children of groups.
- **TODO for Session 5**: `actions` and `fileRoots` parsing in `convertAlistToCommandNode` is marked with TODO, deferred to Session 5 when chooser UI is built.
- **Thread safety note**: `CommandTreeRegistry` is not thread-safe. Fine for now (single-threaded access), but needs attention in Session 8 (config reload) when concurrent reads/writes may occur.

### Session 3
- **Architecture: result-returning state machine**: `ModalStateMachine` returns `KeyDispatchResult` (navigated/executed/openSelector/noBinding) rather than performing side effects. This keeps it pure and testable. The `CommandExecutor` handles actual Scheme lambda invocation separately.
- **Three-layer dispatch**: `KeyboardCapture` → `KeyEventDispatcher` → `ModalStateMachine`. Each has a single concern: raw events, key code translation + special keys, and tree navigation logic respectively.
- **Event suppression**: Changed `KeyboardCapture` callback from `(CapturedKeyEvent) -> Void` to `(CapturedKeyEvent) -> KeyEventHandlingResult`. Returns `nil` from CGEvent callback to suppress events during modal navigation. This prevents modal keys from reaching the focused app.
- **KeyCodeMapping**: Static lookup table mapping CGKeyCode → character string. Covers all 26 letters, 10 digits, 11 punctuation keys, and space. Based on US ANSI HID key codes. F-keys, escape, delete, return do not map (handled as special keys by the dispatcher).
- **LispKit `machine.apply`**: To call a Scheme lambda from Swift, use `machine.apply(proc, to: .null)` (two args, no `in:` parameter). The `.null` argument is the empty argument list for zero-arg procedures.
- **Modifier key passthrough**: Keys pressed with Cmd modifier pass through even during modal (lets system shortcuts like Cmd+Tab work). This matches the Hammerspoon behavior where only unmodified keys are modal.
- **Chooser guard deferred**: The "block leader when chooser is open" guard requires the chooser to exist (Session 5). Added as a note in the dispatcher where the check will go.
- **File layout**: 17 source files, 13 test files. New: `ModalStateMachine.swift` (106 lines), `KeyEventDispatcher.swift` (104 lines), `KeyDispatchResult.swift` (28 lines), `CommandExecutor.swift` (39 lines), `KeyCodeMapping.swift` (34 lines).
- **103 tests total**, 13 test suites. All pass in ~3.8s. Up from 51 tests in Session 2.

### Code Review 3
- **Encapsulated state machine access**: Made `KeyEventDispatcher.stateMachine` private, exposed `isModalActive` and `currentNodeLabel` as read-only forwarding properties. Tests now use these instead of reaching through to the state machine directly. Prevents external code from calling `enterLeader`/`exitLeader`/`handleKey` on the state machine, bypassing the dispatcher's orchestration.
- **Local mode TODO**: `ModalStateMachine.enterLeader(mode:)` uses `appLocal("")` for local mode — will never match a real app-local tree. Added TODO comment for Session 8, which will inject the focused app's bundle ID via NSWorkspace observation.
- **Extracted `ConfigPathResolver`**: Config path finding logic extracted from `ModaliserAppDelegate` (which was 118 lines, over the 100-line guideline) into a small injectable struct. AppDelegate now 97 lines. `ConfigPathResolver` takes `FileManager` and `homeDirectory` for testability.
- **`CommandExecutorError` → `LocalizedError`**: Changed from `CustomStringConvertible` to `LocalizedError` with `errorDescription` so that `error.localizedDescription` shows the actual error message. Required adding `import Foundation`.
- **Explicit `Equatable` on `KeyEventHandlingResult`**: Swift auto-synthesizes it for enums without associated values, but explicit conformance documents intent and protects against silent breakage if associated values are added later.
- **Added missing test**: `handleKeyWhenIdleReturnsNoBinding` directly tests the idle guard clause in `ModalStateMachine.handleKey`. Previously only tested indirectly through the dispatcher.
- **Test precision**: Added log length assertions to end-to-end tests that were checking execution results without verifying exactly-once execution. Catches hypothetical double-execution bugs.
- **KeyCodeMapping documentation**: Added note about international keyboard support — HID key codes are physical positions, not characters, so AZERTY/Dvorak users press the same physical key for the same shortcut. This is intentional for a modal shortcut system.
- **Fixed compiler warnings**: Removed unused `let log` variables in `KeyEventDispatcherTests` and `CommandExecutorTests`.
- **File layout**: 18 source files (+1 `ConfigPathResolver`), 13 test files. **104 tests total**, all passing, zero warnings.

### Session 4
- **Architecture: layered overlay system**: Five-layer separation: `OverlayContentBuilder` (pure data transform), `OverlayCoordinator` (timing/lifecycle), `OverlayNotifier` (state machine → coordinator bridge), `OverlayPanel` (NSPanel rendering), and three renderers (header/entry/footer). Each is independently testable.
- **Protocol-based panel testing**: `OverlayPresenting` protocol abstracts the NSPanel. Tests inject `MockOverlayPresenter` to verify coordinator timing behavior without creating real windows. This is the only mock in the test suite — everything else uses real objects.
- **Timer testing challenge**: `Timer.scheduledTimer` fires on the creating thread's RunLoop. Swift Testing runs on a cooperative thread pool, not the main thread. Solution: coordinator accepts `showDelay: 0` for synchronous behavior in tests. Tests verify state transition logic; Timer is trusted as framework infrastructure.
- **NSFont fontName vs familyName**: `NSFont(name: "Menlo", size: 15)` resolves to fontName `"Menlo-Regular"`, not `"Menlo"`. Tests should assert on `familyName` for user-specified fonts.
- **set-theme! DSL function**: Accepts alternating `'symbol value` pairs: `(set-theme! 'font "Monaco" 'font-size 14 'bg '(0.1 0.1 0.1))`. Colors are Scheme lists of 3 flonums. All properties are optional, defaulting to the warm beige theme from the Hammerspoon version.
- **ThemeConfigParser extraction**: Parsing Scheme `'symbol value` pairs into an `OverlayTheme` was extracted from `ModaliserDSLLibrary` into `ThemeConfigParser` (57 lines). DSL library dropped from 238 to 181 lines.
- **OverlayNotifier extraction**: Overlay notification logic extracted from `KeyEventDispatcher` into `OverlayNotifier` (44 lines). Dispatcher dropped from 159 to 115 lines.
- **Breadcrumb header**: Uses `treeLabel + " › " + currentGroupLabel`. The path stores keys (["f"]) not labels (["Find"]), so full breadcrumb reconstruction for deep nesting would need `pathLabels` on the state machine. Current approach works for typical 2-3 level trees.
- **OverlayPanel focus behavior**: `styleMask: [.borderless, .nonactivatingPanel]` prevents the overlay from stealing keyboard focus. `hidesOnDeactivate = false` keeps it visible even when the app deactivates. `orderFront(nil)` shows without activating.
- **File layout**: 31 source files (+13), 16 test files (+3). **145 tests total** (up from 104), 16 suites (up from 13). All passing, zero warnings.
- **Deferred**: `set-theme!` from Session 2 is now implemented. Session 2's deferred item can be marked done.
