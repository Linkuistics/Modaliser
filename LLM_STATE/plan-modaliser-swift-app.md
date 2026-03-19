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
(import (modaliser dsl))
(import (modaliser app))

;; Theme
(set-theme!
  (make-theme
    #:font "Menlo"
    #:font-size 15
    #:bg-color '(0.99 0.97 0.93)
    #:accent-color '(0.13 0.38 0.73)
    #:label-color '(0.22 0.22 0.22)))

;; Leader keys
(set-leader! 'global "F18")
(set-leader! 'local "F17")

;; Global command tree
(define-tree 'global
  (key "s" "Safari"
    (lambda () (launch-app "Safari")))
  (group "f" "Find"
    (key "a" "Find Apps"
      (selector
        #:prompt "Find app…"
        #:source find-installed-apps
        #:on-select activate-app
        #:remember "apps"
        #:id-field "bundleId"
        #:actions
          (list
            (action "Open" #:key 'primary #:run activate-app)
            (action "Show in Finder" #:key 'secondary #:run reveal-in-finder)
            (action "Copy Path" #:run (lambda (c) (set-clipboard! (assoc-ref c 'path))))
            (action "Copy Bundle ID" #:run (lambda (c) (set-clipboard! (assoc-ref c 'bundleId)))))))
    (key "f" "Find File"
      (selector
        #:prompt "Find file…"
        #:file-roots '("~")
        #:on-select open-file
        #:actions
          (list
            (action "Open" #:key 'primary #:run open-file)
            (action "Show in Finder" #:key 'secondary #:run reveal-in-finder)
            (action "Copy Path" #:run (lambda (c) (set-clipboard! (assoc-ref c 'path))))
            (action "Open in Zed" #:run (lambda (c) (open-with "Zed" (assoc-ref c 'path))))))))
  (group "w" "Windows"
    (key "c" "Center" (lambda () (center-window)))
    (key "m" "Maximize" (lambda () (maximize-window)))
    (key "s" "Switch Window"
      (selector
        #:prompt "Select window…"
        #:source list-windows
        #:on-select focus-window))))
```

## Progress

### Phase 1: Swift host + Scheme config/actions

- [x] **Session 1: Project scaffold + keyboard capture**
  - [x] Create SPM executable project with LispKit dependency
  - [x] NSApplication setup (accessory app, no dock icon)
  - [x] CGEvent tap for global hotkey capture (F17/F18)
  - [x] Verify Accessibility permission flow
  - [x] Test: pressing F18 prints to console
  - [ ] Commit and stop

- [ ] **Code Review 1**
  - [ ] Review project structure, CGEvent tap implementation
  - [ ] Verify clean separation of concerns
  - [ ] Check error handling for permission denial
  - [ ] Update plan with findings

- [ ] **Session 2: LispKit integration + Scheme DSL**
  - [ ] Set up LispKit context with custom environment
  - [ ] Design DSL macros: `key`, `group`, `selector`, `action`, `define-tree`, `set-leader!`, `set-theme!`
  - [ ] Implement `(modaliser dsl)` Scheme library
  - [ ] Implement `(modaliser app)` native library (launch-app, open-file, set-clipboard!, shell basics)
  - [ ] Load and evaluate config.scm, build internal command tree representation
  - [ ] Write sample config.scm with a few commands
  - [ ] Test: config loads, command tree is traversable from Swift
  - [ ] Commit and stop

- [ ] **Code Review 2**
  - [ ] Review LispKit integration pattern
  - [ ] Review DSL ergonomics — is the config pleasant to write?
  - [ ] Check Scheme↔Swift data marshalling
  - [ ] Update plan with findings

- [ ] **Session 3: Modal state machine**
  - [ ] Implement modal state: enter/exit leader, current node tracking, path breadcrumb
  - [ ] Key dispatch: look up child in current group, descend or execute
  - [ ] Command execution: call Scheme lambdas from Swift
  - [ ] Group navigation: descend into subgroups, step back on delete
  - [ ] Exit on escape, leader key re-press, or command execution
  - [ ] Guard: block leader key when chooser is open
  - [ ] Test: F18 → key sequences execute Scheme actions (launch apps, etc.)
  - [ ] Commit and stop

- [ ] **Code Review 3**
  - [ ] Review state machine correctness
  - [ ] Check edge cases (rapid key presses, re-entry, focus loss)
  - [ ] Verify Scheme lambda execution is robust (error handling)
  - [ ] Update plan with findings

- [ ] **Session 4: Which-key overlay**
  - [ ] Port OverlayWindow.swift from modal-chooser (passive floating NSPanel)
  - [ ] Port ChooserTheme.swift (read theme from Scheme config)
  - [ ] Wire overlay show/hide to modal state machine (with configurable delay)
  - [ ] Render: header breadcrumb (with app icon for local mode), sorted entries, footer
  - [ ] Styling: blue keys, orange groups with "…", grey arrows, esc/del footer
  - [ ] Ensure overlay never steals keyboard focus
  - [ ] Test: F18 → overlay appears after delay, updates on navigation, hides on exit
  - [ ] Commit and stop

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
