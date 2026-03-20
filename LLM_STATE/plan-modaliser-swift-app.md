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
  - [x] Guard: block leader key when chooser is open — implemented in Session 5
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

- [x] **Code Review 4**
  - [x] Review overlay rendering, positioning, focus behavior
  - [x] Compare visual output with existing Hammerspoon version
  - [x] Update plan with findings

- [x] **Session 5: Chooser window + selectors**
  - [x] Port ChooserWindow.swift (search field, table view, keyboard handling)
  - [x] Port ActionPanel.swift (⌘K, digit shortcuts, del back, esc cancel)
  - [x] Port IconLoader.swift (app icon loading + caching)
  - [x] Wire selectors from Scheme config to chooser presentation
  - [x] Selector source functions called in Scheme, results marshalled to Swift Choice objects
  - [x] Choice round-tripping: retain Scheme objects, resolve on selection
  - [x] Action callbacks: dispatch to Scheme lambdas
  - [x] ⌘1-⌘9 item selection, ⌘↵ secondary action
  - [x] Focus management: cancel on focus loss, deactivate on dismiss
  - [x] Test: F18→f→a opens app chooser, selection launches app, actions work
  - [ ] Commit and stop

- [x] **Code Review 5**
  - [x] Review chooser completeness against existing implementation
  - [x] Check Scheme↔Swift marshalling for choices and actions
  - [x] Verify keyboard handling (arrows, return, escape, cmd+digit, cmd+K)
  - [x] Update plan with findings

- [x] **Session 6: Fuzzy matching + file search**
  - [x] Implement fuzzy matcher as pure Swift type (`FuzzyMatcher.swift`) — not a LispKit library since matching is Swift-side only
  - [x] Port DP algorithm from ChooserWindow.swift (match score, gap penalty, position bonus, camelCase)
  - [x] Match highlighting: returns matched indices, wired to `ChooserRowRenderer.highlightedString` from Session 5
  - [x] Background search with debounce (30ms, generation counter, serial queue) — implemented in Session 5, now uses FuzzyMatcher
  - [x] File indexing via fd (--hidden --follow, exclusions for Library/.Trash/.cache/.build/.git)
  - [x] Path-aware search: "/" in query enables subText matching, tail proximity bonus
  - [x] Search mode: showAll (apps) vs requireQuery (files) — implemented in Code Review 5
  - [x] Test: fuzzy search with highlighting works for both apps and files
  - [ ] Commit and stop

- [x] **Code Review 6**
  - [x] Review fuzzy matcher correctness (compare with existing implementation)
  - [x] Profile performance with large file lists (50K+ entries)
  - [x] Check debounce/threading for race conditions
  - [x] Update plan with findings

- [x] **Session 7: System integration native libraries**
  - [x] `(modaliser app)` — find-installed-apps, activate-app, reveal-in-finder, open-with, launch-app, open-url
  - [x] `(modaliser window)` — list-windows, focus-window, center-window, move-window (unit rect), toggle-fullscreen, restore-window
  - [x] `(modaliser shell)` — run-shell (Process + Pipe, /bin/zsh -c)
  - [x] `(modaliser pasteboard)` — get-clipboard, set-clipboard!
  - [x] Search memory: SearchMemory with JSON persistence, wired into ChooserCoordinator
  - [x] Port all actions from current global.lua config to config.scm
  - [x] Test: 265 tests, 30 suites, all passing (up from 211/23)
  - [ ] Commit and stop

- [x] **Code Review 7**
  - [x] Review native library API design (Scheme-idiomatic? consistent?)
  - [x] Check error handling in native libraries
  - [x] Verify feature parity with Hammerspoon version
  - [x] Update plan with findings

- [x] **Session 8: App-local commands + polish**
  - [x] Implement app-local command trees (detect focused app via NSWorkspace)
  - [x] Port Zed, Safari, iTerm local commands to config.scm
  - [x] Menu bar icon / status item (Reload Config, Launch at Login, Quit)
  - [x] Config reload (re-evaluate config.scm without restarting)
  - [x] Error reporting: Scheme evaluation errors shown as alerts
  - [x] Launch at login support (SMAppService macOS 13+)
  - [ ] Clipboard history watcher — deferred to Phase 2
  - [x] Test: 297 tests, 34 suites, all passing
  - [ ] Commit and stop

- [x] **Code Review 8 (Final)**
  - [x] Full review of architecture, code quality, test coverage
  - [x] Review config.scm ergonomics — is it pleasant for users?
  - [x] Performance review (startup time, memory, responsiveness)
  - [x] Document any remaining issues or Phase 2 items
  - [x] Update plan with findings

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

### Code Review 4
- **Overlay port is faithful**: Every NSPanel flag, layout constant, rendering detail, and coordinate calculation matches the Hammerspoon reference exactly. Panel creation (`borderless`, `nonactivatingPanel`, `floating`, `hasShadow`, `hidesOnDeactivate`), container styling (`cornerRadius: 10`, `borderWidth: 2`, `masksToBounds`), positioning (`midX - width/2`, `maxY - height*0.2 - totalH`), entry rendering (space→␣, padded keys, blue accent, grey arrows, orange groups with "…"), header (grey 0.50 white, optional app icon), and footer (tab-stop right-alignment, accent keys, grey descriptions) — all identical.
- **Extracted `MockOverlayPresenter`**: Was defined inline in `OverlayCoordinatorTests.swift` but used by `KeyEventDispatcherTests.swift` — implicit cross-file dependency. Now in its own `MockOverlayPresenter.swift` test file (19 lines).
- **Extracted `AccessibilityPermissionAlert`**: 15-line permission alert method extracted from `ModaliserAppDelegate` (110→93 lines) into `AccessibilityPermissionAlert.swift` (23 lines). Enum with static `showAndTerminate()` method.
- **Added `OverlayNotifierTests`**: 6 new tests directly covering `OverlayNotifier` — activated/idle/navigated/deactivated/afterStepBack paths. Previously tested only indirectly through `KeyEventDispatcherTests`.
- **`OverlayFooterRenderer` vs reference `styledFooter`**: The reference's `styledFooter` has `cmdFont` support for ⌘/⏎ symbols (shared with chooser footer). The Modaliser overlay footer only uses "del"/"esc" text, so cmdFont is unnecessary now. Session 5 will need to add symbol font switching when implementing the chooser footer.
- **Files over 100 lines**: `ModaliserDSLLibrary` (181, addressed in CR2), `KeyEventDispatcher` (115, overlay one-liners), `ModalStateMachine` (108), `KeyboardCapture` (106), `OverlayPanel` (105). All are cohesive single-concern files with no clean extraction opportunities.
- **`showOverlay` recreates the panel each call**: Both the reference and Modaliser dismiss+recreate the NSPanel on every show/update. This works but could cause subtle flicker during rapid navigation. Future optimization: update content in-place via `setContentView` or subview replacement.
- **File layout**: 32 source files (+1 `AccessibilityPermissionAlert`), 18 test files (+2 `MockOverlayPresenter`, `OverlayNotifierTests`). **151 tests total** (up from 145), 17 suites (up from 16). All passing, zero warnings.

### Session 5
- **Architecture: layered chooser system**: Six-layer separation following the overlay pattern: `ChooserWindowController` (core state + selection), `ChooserWindowBuilder` (window construction + layout), `ChooserKeyboardHandler` (key dispatch), `ChooserRowRenderer` (table data source + row rendering), `ChooserFooterRenderer` (footer text), `ChooserSearchHandler` (search + filtering), `ChooserActionPanelHandler` (action panel management). Plus independent: `ChooserCoordinator` (lifecycle), `ChooserActionPanel` (action state), `SelectorSourceInvoker` (Scheme bridge), `IconLoader` (icon caching).
- **Scheme round-tripping via `schemeValue`**: `ChooserChoice` retains the original Scheme alist (`schemeValue: Expr`) alongside extracted Swift display fields. When the user selects a choice, the original Scheme value is passed to `onSelect`/action `run` lambdas. This avoids lossy Swift→Scheme conversion and means source functions can include arbitrary fields the UI doesn't know about.
- **`CommandExecutor` extended with argument support**: Added `execute(action:argument:)` for one-arg Scheme lambdas. Both zero-arg and one-arg variants delegate to a private `execute(action:arguments:)` that takes a proper Scheme argument list (`.pair(arg, .null)` for one arg, `.null` for zero args).
- **Action parsing in CommandNodeBuilder**: The `actions` field in selector DSL alists is a Scheme list of action alists. Each action alist has `name`, optional `key` (primary/secondary symbol), and `run` (procedure). `file-roots` is a simple list of strings. Both use tolerant parsing — missing or malformed entries are silently skipped rather than throwing.
- **Leader key guard**: When the chooser is open (`chooserCoordinator.isChooserOpen`), leader key presses are suppressed. This prevents the user from accidentally re-entering modal mode while the search field is active. The guard is in `KeyEventDispatcher.handleKeyEvent` before the leader key handler.
- **Chooser steals focus (intentionally)**: Unlike the overlay (which uses `.nonactivatingPanel` and `orderFront`), the chooser uses `NSApp.activate(ignoringOtherApps:)` + `makeKeyAndOrderFront` + `makeFirstResponder(searchField)` so the search field receives keystrokes. On dismiss, `NSApp.deactivate()` returns focus to the previous app.
- **Deactivation observer for focus loss**: The chooser registers for `NSApplication.didResignActiveNotification` and cancels on focus loss (user clicked elsewhere). The observer is removed on dismiss to prevent stale callbacks.
- **Debounced search with generation counter**: Search uses a serial `DispatchQueue` with 30ms debounce. A `searchGeneration` counter invalidates stale results — if the user types faster than search completes, only the latest generation's results are applied. This is the same pattern as the reference.
- **Simple substring matching (Session 6 placeholder)**: For now, search uses case-insensitive substring matching with position-based scoring. Session 6 will replace this with the DP-based fuzzy matcher from the reference, which handles camelCase boundaries, gap penalties, and consecutive bonuses.
- **ChooserPresenting protocol**: Mirrors `OverlayPresenting` but adds `onResult` callback. The coordinator passes a closure to the presenter; the presenter calls it when the user interacts. This avoids the presenter needing to know about Scheme or the coordinator.
- **cmdFont for ⌘/⏎ symbols in footer**: The chooser footer uses the same `styledFooter` pattern as the reference — segments containing only `⌘` or `↩` get `NSFont.systemFont` (which renders the symbols correctly), while other keys use the monospace theme font.
- **Files over 100 lines**: `ChooserRowRenderer` (194), `ModaliserDSLLibrary` (181), `ChooserWindowBuilder` (168), `ChooserWindowController` (164), `KeyEventDispatcher` (125), `ChooserKeyboardHandler` (124), `CommandNodeBuilder` (123). The chooser UI files are inherently larger due to AppKit view construction verbosity — each `NSTextField` requires 5-7 lines of configuration. All remain single-concern despite size.
- **File layout**: 48 source files (+16), 23 test files (+5). **187 tests total** (up from 151), 21 suites (up from 17). All passing, zero warnings.

### Code Review 5
- **Added `ActionConfig.description`**: The reference `ActionDef` has `description: String?` for subtext beneath action names. Added to `ActionConfig`, parsed from the `"description"` key in the action alist by `CommandNodeBuilder`, and rendered as subtext in `ChooserRowRenderer.makeActionRow` (matching the reference's layout exactly). Scheme DSL `(action "Open" 'description "Launch the app" ...)` now works.
- **Added `ChooserSearchMode`**: New enum (`showAll` / `requireQuery`) replacing the reference's nested `SearchMode`. Wired through `ChooserPresenting` protocol, `ChooserCoordinator` (derives mode from `fileRoots != nil`), `ChooserWindowController.showChooser`, and `ChooserSearchHandler.filterChoices`. File-based selectors will show empty results until the user types, preventing 50K+ results on open.
- **Removed redundant `theme` from `ChooserPresenting`**: The `showChooser` method accepted a `theme` parameter that was ignored (controller uses its own `chooserTheme` from init). Replaced with the `searchMode` parameter that is actually used.
- **Documented access control trade-off**: Added header comment to `ChooserWindowController` explaining that properties are `internal` (not `private`) because they are shared across extension files, not because they should be freely accessed externally.
- **No critical or blocking issues found**: Chooser port is faithful to the reference. All keyboard handling (arrows, return, escape, cmd+digit, cmd+K, cmd+return, cmd+shift+/, delete in action panel) matches. Scheme↔Swift marshalling preserves original alist values through the full round-trip.
- **File layout**: 49 source files (+1 `ChooserSearchMode`), 23 test files. **190 tests total** (up from 187), 21 suites. All passing, zero warnings.

### Session 6
- **FuzzyMatcher as pure Swift, not LispKit library**: The plan called for a native LispKit library `(modaliser fuzzy-match)`, but fuzzy matching is purely a Swift-side concern — it's used by `ChooserSearchHandler` to filter choices, never called from Scheme. Implementing as a pure Swift `enum FuzzyMatcher` with a static `match(query:target:)` method is simpler, faster (no Scheme bridge overhead), and more testable. If Scheme-level matching is ever needed, it can be added as a thin wrapper.
- **DP algorithm faithful to reference**: All scoring constants match the reference (`MATCH=16`, `GAP=-3`, `CONSECUTIVE=4`, position bonuses for `/`, space, `-_`, `.`, camelCase). The flat-array DP approach (`M[i*m+j]`, `D[i*m+j]`) avoids 2D array overhead. Traceback recovers exact matched positions for highlighting.
- **Named DP arrays for clarity**: Reference uses terse names (`M`, `D`, `from`). Renamed to `bestScores`, `consecutiveScores`, `tracebackPositions` for readability per coding style guidelines.
- **Path-aware search with tail proximity**: When query contains "/", the search also matches against `subText` (full path). A tail proximity bonus (`30 - charsAfterMatch`) rewards matches near the end of the path, so "src/main" prefers `project/src/main.swift` over `src/main/deeply/nested/file.txt`.
- **FileIndexer async flow**: File selectors use a different flow from app selectors. The coordinator shows an empty chooser immediately (requireQuery mode), starts `fd` indexing in background, and calls `updateChoices()` on the presenter when indexing completes. This avoids blocking the UI while scanning potentially 50K+ files.
- **FileIndexer inherits extended PATH**: GUI apps get a minimal PATH that excludes `/opt/homebrew/bin`. `FileIndexer` extends PATH to find Homebrew-installed `fd`, matching the reference's approach.
- **Test for scoring invariants, not exact scores**: FuzzyMatcher tests verify *relative ordering* (consecutive > scattered, word boundary > mid-word) rather than exact score values. This makes tests robust against scoring constant tuning while ensuring the ranking behavior is correct.
- **File layout**: 51 source files (+2 `FuzzyMatcher`, `FileIndexer`, `ChooserSearchMode`), 25 test files (+2 `FuzzyMatcherTests`, `FileIndexerTests`). **211 tests total** (up from 190), 23 suites (up from 21). All passing, zero warnings.

### Code Review 6
- **DP algorithm verified line-by-line**: All scoring constants, position bonuses, DP recurrence, gap/consecutive paths, and traceback logic match the reference exactly. The structural improvement (descriptive names) does not affect behavior.
- **Threading model is correct**: `choices` captured by value in search closure prevents data races. Generation counter invalidates stale results. Serial queue ensures only one search runs at a time. No race conditions found.
- **Added FileIndexer error logging**: The `catch` block now logs when `fd` fails (e.g., not installed), preventing silent failures. Previously `completion(false)` was called with no diagnostic output.
- **Added FileIndexer result cap**: `maxResults = 100_000` prevents runaway memory usage when file-roots cover a very large directory tree. Logs a warning when truncated.
- **Known tech debt: NSRange/character index mismatch**: `highlightedString` applies `FuzzyMatcher`'s character-based indices as `NSRange(location:length:)` on `NSAttributedString` (UTF-16). This is correct for ASCII but will diverge for multi-byte characters (emoji, CJK). The reference has the same bug. Tracked for future fix when non-ASCII file names are tested.
- **Performance analysis**: For 50K files with average path length 60 and query length 5, the DP allocates ~900 Ints per file per search cycle. The 30ms debounce, serial queue, and Swift's allocator make this feasible. Profiling with a real 50K file list recommended as a future validation step.
- **No critical issues found**. Two Important issues fixed (logging, result cap). Assessment: ready to merge.

### Session 7
- **NativeLibrary pattern scales well**: All four native libraries follow the same pattern as `ModaliserDSLLibrary`: `required init(in:)`, class var `name`, `dependencies()`, `declarations()`. Each is independently testable. Registration in `SchemeEngine` is two lines per library.
- **NSPasteboard thread safety**: Swift Testing runs tests concurrently. Tests sharing the system pasteboard crash with `NSRangeException` if run in parallel. Fixed with `@Suite(.serialized)`.
- **AXUIElement casting from AnyObject**: `AXUIElementCopyAttributeValue` returns `AnyObject?`. AXUIElement is a CFTypeRef, not a Swift class — cannot use `as AXUIElement?` directly. Must use `as! AXUIElement` force cast from the `AnyObject?`.
- **Window management two-API split**: `CGWindowListCopyWindowInfo` for enumeration (lightweight, no permissions for basic info), `AXUIElement` for manipulation (needs Accessibility permissions). Both are needed. Tests cover enumeration directly but manipulation only as procedure-exists checks (no Accessibility in test runner).
- **SearchMemory integration is minimal**: Only three changes to `ChooserCoordinator`: add `searchMemory` parameter (with default), call `saveToMemory` in `handleResult`, and add `extractField` helper. The coordinator's existing tests still pass without modification because the default `SearchMemory()` instance has no effect when `remember` is nil.
- **Alist lookup duplication**: `lookupString` (walking a Scheme alist to find a key) is now duplicated in `AppLibrary`, `WindowLibrary`, `SelectorSourceInvoker`, and `ChooserCoordinator`. Code Review 7 should extract a shared `SchemeAlistHelper`.
- **Config DSL power**: The `open-url-action` helper in config.scm shows the advantage of Scheme config — users can define helper functions. `(define (open-url-action url) (lambda () (open-url url)))` creates a reusable factory. This is impossible with YAML/JSON configs.
- **Expanded API surface**: Added `launch-app` (by name) and `open-url` beyond the original plan. `launch-app` is the most common action in global.lua — every "Open Application" key uses it. `open-url` enables Raycast URL scheme integration.
- **move-window with unit rect**: Changed from separate `first-third`, `last-third` etc. functions to a single `(move-window x y w h)` with unit fractions. More flexible — config composes arbitrary positions: `(move-window 0 0 1/3 1)` for first third, `(move-window 1/3 0 2/3 1)` for last two-thirds. Matches the reference's `hs.geometry.unitrect` approach but with a simpler API.
- **File layout**: 57 source files (+8), 30 test files (+7). New: `PasteboardLibrary` (43 lines), `ShellLibrary` (44 lines), `AppLibrary` (147 lines), `AppScanner` (49 lines), `WindowLibrary` (116 lines), `WindowEnumerator` (63 lines), `WindowManipulator` (143 lines), `SearchMemory` (89 lines).
- **265 tests total**, 30 suites (up from 211/23). All passing, zero warnings.

### Code Review 7
- **Extracted `SchemeAlistLookup`**: Alist lookup was duplicated in `AppLibrary`, `WindowLibrary`, `SelectorSourceInvoker`, and `ChooserCoordinator` (4 independent copies of the same traversal). Extracted to `SchemeAlistLookup.swift` with `lookupString`, `lookupFixnum`, and `makeAlist` static methods. All four consumers now delegate to the shared utility. `ModaliserDSLLibrary.makeAlist` also delegates to the shared helper.
- **Fixed `ownerPid` type mismatch**: `WindowLibrary` stored `ownerPid` as `.makeString(String(pid))` then re-parsed with `Int32()` in `focusWindowFunction`. Changed to `.fixnum(Int64(pid))` matching `windowId`'s storage. Added `lookupFixnum` to `SchemeAlistLookup` for type-safe fixnum retrieval.
- **Fixed config.scm parenthesis bug**: Find File selector's `(list ...)` closed prematurely after the first action — line 55 had 5 close parens instead of 4. The remaining 3 actions ("Show in Finder", "Copy Path", "Open in Zed") were orphaned arguments silently dropped by `parsePropertyArguments`. This went undetected because the DSL's tolerant parsing skips non-symbol arguments without error.
- **Added missing `z → Zed` shortcut**: Present in `global.lua` as a top-level shortcut but absent from `config.scm`. Added to match feature parity.
- **Feature parity assessment**: All `global.lua` features ported except `f.q` (Quicklinks selector) and `f.s` (Snippets selector) — both require custom backends that would need Scheme data sources. These are low-priority features suitable for Session 8 or Phase 2.
- **API design is consistent and Scheme-idiomatic**: All four libraries follow identical patterns (NativeLibrary subclass, kebab-case naming, `!` for mutations). Alist structure is uniform across `find-installed-apps` and `list-windows`. The `(modaliser <domain>)` namespace pattern is clean and predictable.
- **Silent failure pattern noted**: `activate-app`, `focus-window`, and `open-url` return `.void` silently when inputs are malformed. Acceptable for now — Scheme is a trusted input source — but should add logging if user config debugging becomes difficult.
- **`run-shell` blocks main thread**: `Process.waitUntilExit()` is synchronous. Matches reference behavior. Long-running commands could freeze the UI. Future optimization: async execution with timeout.
- **File layout**: 58 source files (+1 `SchemeAlistLookup`), 31 test files (+1 `SchemeAlistLookupTests`). **274 tests total** (up from 265), 31 suites (up from 30). All passing, zero warnings.

### Session 8
- **FocusedAppObserver is trivial by design**: Just wraps `NSWorkspace.shared.frontmostApplication?.bundleIdentifier`. No KVO observation needed — the bundle ID is read at the moment F17 is pressed, which gives the correct target app since our accessory app doesn't steal focus.
- **ModalStateMachine.enterLeader now guards against missing trees**: When local mode is requested but no app-local tree exists for the focused app (or no app is focused), `enterLeader` returns without activating. The dispatcher checks `stateMachine.isActive` after the call and only shows the overlay if activation succeeded.
- **Bundle IDs as tree scope keys**: Config uses `(define-tree 'com.apple.Safari ...)` with bundle IDs directly. The `ModaliserDSLLibrary.defineTreeFunction` already handled non-`global` symbols as `appLocal(identifier)` — no changes needed to the DSL. Users can alias bundle IDs with `define` if desired.
- **KeystrokeEmitter dual lookup**: `send-keystroke` tries character lookup first (`KeystrokeEmitter.keyCode(for:)`), then named key lookup (`keyCode(forNamedKey:)`). This means `"t"` maps to the T key, `"left"` maps to the arrow key. Named keys include arrows, return, tab, escape, delete, and F1-F12.
- **`keystroke` helper showcases Scheme config power**: `(define (keystroke mods key-name) (lambda () (send-keystroke mods key-name)))` creates a reusable factory. Config reads cleanly: `(keystroke '(cmd shift) "p")` for Cmd+Shift+P. This pattern is impossible with YAML/JSON configs.
- **Config reload via handler swap**: `KeyboardCapture.updateHandler` replaces the event handler closure without restarting the CGEvent tap. This avoids the risk of losing the tap (macOS may not grant a new one if the old one isn't cleanly removed).
- **ConfigErrorAlert for user feedback**: On config load failure, an NSAlert shows the error message. The app continues running with whatever was loaded (partial config is better than no config).
- **Launch at login via SMAppService**: Single-line `SMAppService.mainApp.register()` / `.unregister()`. Menu item shows checkmark state. Requires macOS 13+, which is the minimum for this project.
- **Config.scm cleanup**: Removed duplicate `z → Zed` top-level key. Replaced `run-shell "osascript ..."` Spotlight command with `(keystroke '(cmd) " ")`. Added `keystroke` helper near the top.
- **Clipboard history deferred**: Deferred to Phase 2 — it's a substantial standalone feature (background watcher, persistent storage, chooser UI) that doesn't block feature parity for the core modal system.
- **File layout**: 65 source files (+7), 36 test files (+5). New: `FocusedAppObserver` (11 lines), `KeystrokeEmitter` (65 lines), `InputLibrary` (72 lines), `ConfigErrorAlert` (16 lines), `LaunchAtLogin` (18 lines), `SchemeAlistLookup` (from CR7). **297 tests total** (up from 274), 34 suites (up from 31). All passing, zero warnings.

### Code Review 8 (Final)
- **Replaced deprecated NSWorkspace APIs**: `launchApplication(withBundleIdentifier:...)` and `launchApplication(_:)` in `AppLibrary` replaced with `openApplication(at:configuration:)` and `urlForApplication(withBundleIdentifier:)`. These APIs have been deprecated since macOS 10.15.
- **Eliminated force unwraps in ChooserSearchHandler**: Lines 63/65 used `textMatch!` and `subMatch!` — safe at runtime (guarded by score > 0) but fragile. Replaced with `guard let` bindings for clarity.
- **Documented AXUIElement force casts**: `WindowManipulator` lines 93/97 force-cast `AnyObject` to `AXUIElement`. These are inherent to the Accessibility API (CFTypeRef returns). Added inline comment explaining why they're safe.
- **Config.scm ergonomics assessment**: The DSL reads well. The `keystroke` helper is clean: `(keystroke '(cmd shift) "p")` for Cmd+Shift+P. The `open-url-action` helper enables Raycast integration. Bundle IDs as tree scope keys are explicit if ugly — but `define` aliases (`(define safari "com.apple.Safari")`) mitigate this. One improvement for Phase 2: a `define-app-tree` macro that takes a friendly name and bundle ID.
- **Architecture assessment**: Clean separation of concerns across 65 source files. Five native libraries follow identical patterns. Command tree registry, DSL library, and state machine are fully decoupled. UI layers (overlay, chooser) use protocol-based dependency injection. The only architectural coupling is `ModaliserAppDelegate` which wires everything together — appropriate for an app delegate.
- **Test coverage assessment**: 297 tests across 34 suites cover: DSL parsing, command tree building, state machine transitions, key dispatch, overlay coordination, chooser lifecycle, fuzzy matching, file indexing, native library functions, config loading, search memory, and end-to-end flows. Main gap: UI rendering is not tested (AppKit views are tested visually, not programmatically) — acceptable for this project size.
- **Performance assessment**: No profiling data collected (would need a running app with real workloads). Key performance decisions are sound: FuzzyMatcher uses flat-array DP (no 2D allocation), debounced search with generation counter prevents stale results, FileIndexer caps at 100K results, serial queue prevents concurrent searches. Startup should be fast — LispKit context creation + config evaluation.
- **File size assessment**: 13 files over 100 lines, all previously reviewed. Largest is `ChooserRowRenderer` (211 lines) — inherently large due to AppKit view construction verbosity. No clean extraction opportunities remain.
- **No critical or blocking issues found.** Phase 1 is complete.

## Phase 2 Items (Future)

- **Clipboard history watcher**: Background pasteboard change monitoring, persistent history, chooser UI for paste selection
- **Quicklinks and Snippets selectors**: Ports of `f.q` and `f.s` from Hammerspoon — need Scheme data source implementations
- **`define-app-tree` macro**: Friendly names for app-local trees: `(define-app-tree "Safari" 'com.apple.Safari ...)`
- **Overlay content-in-place update**: Currently recreates NSPanel on every show. Could update content view in-place for smoother transitions.
- **NSRange/character index fix**: `highlightedString` uses character indices as NSRange on UTF-16 NSAttributedString. Incorrect for multi-byte characters (emoji, CJK).
- **Async `run-shell`**: Current `waitUntilExit()` blocks the main thread. Long-running commands freeze the UI.
- **CommandTreeRegistry thread safety**: Single-threaded access is fine now, but config reload on a background thread would need synchronization.
- **State machine in Scheme (Phase 2 architecture)**: Move modal state machine and key dispatch to Scheme for full scripting control. Swift becomes purely mechanical.
