# Task: Scheme-First Architecture Refactoring

Refactor Modaliser so Scheme is the complete application runtime. Swift is reduced to a thin
host providing OS-level primitives. Scheme owns event dispatch, state management, command
execution, UI rendering, app lifecycle, and status bar. See full design spec at
`docs/superpowers/specs/2026-03-22-scheme-first-architecture-design.md`.

## Session Continuation Prompt

```
You MUST first read `LLM_CONTEXT/index.md` and `LLM_CONTEXT/coding-style.md`.

Please continue working on the task outlined in `LLM_STATE/plan-scheme-first-architecture.md`.
Review the file to see current progress, then continue from the next incomplete step.
Read the design spec at `docs/superpowers/specs/2026-03-22-scheme-first-architecture-design.md`
for full architectural context. After completing each step, update the plan file with:
1. Mark the step as complete [x]
2. Add any learnings discovered
```

## Progress

### Phase 1: Foundation — Swift Primitives + Scheme Boot

- [x] 1.1 Create `LifecycleLibrary` (`(modaliser lifecycle)`)
  - [x] `(set-activation-policy! policy)` — wraps `NSApp.setActivationPolicy`
  - [x] `(create-status-item! title menu-alist)` — creates NSStatusItem with menu
  - [x] `(update-status-item! id title menu-alist)` / `(remove-status-item! id)`
  - [x] `(request-accessibility!)` / `(request-screen-recording!)`
  - [x] `(relaunch!)` / `(quit!)`
  - [x] Unit tests for LifecycleLibrary
- [x] 1.2 Create `KeyboardLibrary` (`(modaliser keyboard)`)
  - [x] `(start-keyboard-capture!)` / `(stop-keyboard-capture!)`
  - [x] `(register-hotkey! keycode handler)` / `(unregister-hotkey! keycode)`
  - [x] `(register-all-keys! handler)` / `(unregister-all-keys!)`
  - [x] `(keycode->char keycode)` — port KeyCodeMapping table
  - [x] Key code and modifier constants (F17, F18, ESCAPE, DELETE, MOD-CMD, etc.)
  - [x] CGEvent tap dispatch: catch-all priority → hotkey → pass through
  - [x] Error handling: catch Scheme errors, deregister catch-all on failure
  - [x] Unit tests for KeyboardLibrary
- [x] 1.3 Create `WebViewLibrary` (`(modaliser webview)`)
  - [x] `(webview-create id options-alist)` — WKWebView-backed NSPanel
  - [x] `(webview-close id)` — destroy panel
  - [x] `(webview-set-html! id html-string)` — set content
  - [x] `(webview-eval id js-string)` — evaluate JavaScript
  - [x] `(webview-on-message id handler)` — JS→Scheme message bridge
  - [x] `(webview-set-style! id css-string)` — inject/replace style block
  - [x] Non-activating vs activating panel configuration
  - [x] Unit tests for WebViewLibrary
- [x] 1.4 Add `(focused-app-bundle-id)` to `AppLibrary`
  - [x] Implement and test
- [x] 1.5 Modify `KeyboardCapture` for registration-based dispatch
  - [x] Refactor CGEvent tap callback to check handler registrations
  - [x] Support start/stop lifecycle from Scheme
  - [x] Tests for new dispatch logic
- [ ] 1.6 Reduce `ModaliserAppDelegate` to bootstrap stub
  - [ ] Remove activation policy, status bar, config loading, dispatcher wiring
  - [ ] Just: create SchemeEngine, load modaliser.scm
- [x] 1.7 Configure `SchemeEngine` for `.scm` file loading
  - [x] Set LispKit include path to Scheme directory
  - [x] Resolve root .scm path for both .app bundle and swift build
  - [ ] Remove NativeLibrary imports for DSL/state-machine (deferred to step 1.9)
  - [x] Register new libraries (LifecycleLibrary, KeyboardLibrary, WebViewLibrary)
- [x] 1.8 Write Scheme core files
  - [x] `Sources/Modaliser/Scheme/modaliser.scm` — root: set activation policy, permissions, status bar, load modules, start capture
  - [x] `Sources/Modaliser/Scheme/core/state-machine.scm` — tree hash table, register-tree!, lookup-tree, modal-enter, modal-handle-key, modal-step-back, modal-exit (side-effecting)
  - [x] `Sources/Modaliser/Scheme/core/event-dispatch.scm` — modal-key-handler with leader toggle, escape, delete, cmd passthrough
  - [x] `Sources/Modaliser/Scheme/core/keymap.scm` — keycode→character mapping table
  - [x] `Sources/Modaliser/Scheme/lib/dsl.scm` — key, group, define-tree, set-leader!
  - [x] `Sources/Modaliser/Scheme/lib/util.scm` — alist helpers
- [ ] 1.9 Delete replaced Swift code
  - [ ] `KeyEventDispatcher`, `SchemeModalBridge`, `CommandExecutor`
  - [ ] `CommandNode`, `CommandNodeBuilder`, `CommandTreeRegistry`
  - [ ] `ModaliserDSLLibrary`, `SchemeStateMachineLibrary`
  - [ ] `LeaderMode`, `KeyDispatchResult`, `KeyEventHandlingResult`, `KeyCodeMapping`
  - [ ] `FocusedAppObserver`, `ConfigPathResolver`, `ConfigSetup`, `ConfigErrorAlert`
  - [ ] `AccessibilityPermissionAlert`
  - [ ] Remove corresponding test files
- [ ] 1.10 Integration testing
  - [ ] End-to-end: engine loads modaliser.scm, Scheme sets up app, registers hotkeys
  - [ ] Hotkey press → Scheme handler fires → modal enter → key navigation → action lambda → modal exit
  - [ ] Leader toggle (press leader while modal → exit)
  - [ ] Error recovery (Scheme error in handler → catch-all deregistered)
  - [ ] Verify via NSLog output (no UI yet)

### Code Review Session 1

- [ ] 1.R Review Phase 1 changes
  - [ ] Swift↔Scheme boundary clean and minimal
  - [ ] Registration-as-state pattern works correctly
  - [ ] Leader toggle behavior correct
  - [ ] No latency issues with catch-all handler
  - [ ] Error recovery solid
  - [ ] LifecycleLibrary primitives work (activation policy, status bar, permissions)
  - [ ] Update plan with findings

### Phase 2: DOM DSL + Overlay

- [ ] 2.1 Write DOM DSL (`ui/dom.scm`)
  - [ ] Core `(element tag attrs . children)` → HTML string
  - [ ] Convenience functions: div, span, ul, li, h1, h2, p, a, input, button, etc.
  - [ ] HTML entity escaping for text content
  - [ ] Attribute rendering (class, id, style, data-*, event handlers)
  - [ ] `(html head body)` → full document wrapper
  - [ ] Tests via SchemeEngine
- [ ] 2.2 Write CSS helpers (`ui/css.scm`)
  - [ ] `(css-rule selector properties-alist)` → CSS string
  - [ ] `(css-rules . rules)` → concatenated CSS
  - [ ] `(inline-style properties-alist)` → style attribute value
  - [ ] Tests
- [ ] 2.3 Create `base.css`
  - [ ] Default overlay styling (dark theme, rounded corners, key badges)
  - [ ] Default chooser styling (search field, result list, action panel)
  - [ ] CSS variables for theming
- [ ] 2.4 Write overlay (`ui/overlay.scm`)
  - [ ] `(show-overlay node path)` — create WebView if needed, render content
  - [ ] `(update-overlay node path)` — re-render in existing WebView
  - [ ] `(hide-overlay)` — close WebView
  - [ ] `(render-overlay-html node path)` — pure function, returns HTML document
  - [ ] Overlay positioning (screen center, top 20%)
  - [ ] Show-delay support (if desired, implemented in Scheme with timers or immediate)
- [ ] 2.5 Wire overlay into state machine and event dispatch
  - [ ] `modal-enter` → `show-overlay`
  - [ ] `modal-handle-key` navigated → `update-overlay`
  - [ ] `modal-exit` → `hide-overlay`
  - [ ] `modal-step-back` → `update-overlay` or `hide-overlay`
- [ ] 2.6 Delete Swift overlay code
  - [ ] `OverlayPanel`, `OverlayCoordinator`, `OverlayNotifier`, `OverlayPresenting`
  - [ ] `OverlayContent`, `OverlayContentBuilder`, `OverlayEntry`, `OverlayLayout`
  - [ ] `OverlayTheme`, `ThemeConfigParser`
  - [ ] `OverlayHeaderRenderer`, `OverlayEntryRenderer`, `OverlayFooterRenderer`
  - [ ] Remove corresponding test files
- [ ] 2.7 Integration testing
  - [ ] Overlay appears on modal enter with correct key list
  - [ ] Overlay updates on navigation (shows children of selected group)
  - [ ] Overlay dismisses on escape/action/leader-toggle
  - [ ] Overlay positioning and styling match or improve on current
  - [ ] No flicker during updates

### Code Review Session 2

- [ ] 2.R Review Phase 2 changes
  - [ ] DOM DSL is clean, composable, handles edge cases
  - [ ] CSS approach is flexible (base.css + dynamic styles)
  - [ ] Overlay rendering performance acceptable
  - [ ] WebView lifecycle correct (no leaks, proper cleanup)
  - [ ] Visual fidelity vs current overlay
  - [ ] Update plan with findings

### Phase 3: Config Migration

- [ ] 3.1 Complete `lib/dsl.scm`
  - [ ] `(selector k label . props)` → alist with kind: selector
  - [ ] `(action name . props)` → alist
  - [ ] Verify surface-level API compatibility with existing config.scm
- [ ] 3.2 CSS-based theming
  - [ ] Replace `set-theme!` with CSS customization mechanism
  - [ ] Document how users override styles (custom CSS in config, CSS variables)
- [ ] 3.3 Migrate existing `config.scm`
  - [ ] Adapt config to work with new architecture
  - [ ] Verify all existing key bindings, groups, selectors work
  - [ ] User config loading from `~/.config/modaliser/config.scm`
- [ ] 3.4 Audit and potentially delete `SchemeAlistLookup`
  - [ ] Check which retained libraries still use it
  - [ ] Delete if no longer needed, or keep if still used
- [ ] 3.5 Integration testing
  - [ ] Existing config produces same behavior as before refactoring
  - [ ] Theme customization via CSS works

### Code Review Session 3

- [ ] 3.R Review Phase 3 changes
  - [ ] DSL API compatibility verified
  - [ ] Config migration smooth
  - [ ] Theming approach is user-friendly
  - [ ] Update plan with findings

### Phase 4: Chooser as WebView

- [ ] 4.1 Write chooser UI (`ui/chooser.scm`)
  - [ ] HTML structure: search input + result list + action panel
  - [ ] Keyboard navigation: up/down/return/escape/cmd+return via JS→Scheme messages
  - [ ] Search input: JS input events → Scheme via postMessage
  - [ ] Result rendering: highlighted matches, selected row styling
  - [ ] Action panel: toggle with tab, action list rendering
  - [ ] CSS styling in base.css
- [ ] 4.2 Port fuzzy matcher (`lib/fuzzy-match.scm`)
  - [ ] DP algorithm from FuzzyMatcher.swift → Scheme
  - [ ] Benchmark against Swift version for 1000+ item lists
  - [ ] If too slow: keep as Swift primitive in a native library
- [ ] 4.3 Wire selector handling into state machine
  - [ ] `modal-handle-key` on selector node → open chooser WebView
  - [ ] Chooser result → execute on-select callback
  - [ ] Chooser cancel → return to idle
- [ ] 4.4 Source invocation
  - [ ] Call source lambdas from Scheme (replaces SelectorSourceInvoker)
  - [ ] File indexing: evaluate whether FileIndexer stays as Swift primitive or moves to Scheme (shell out to `fd`)
- [ ] 4.5 Delete Swift chooser code
  - [ ] `ChooserWindowController`, `ChooserCoordinator`, `ChooserPresenting`
  - [ ] `ChooserWindowBuilder`, `ChooserKeyboardHandler`, `ChooserFooterRenderer`
  - [ ] `ChooserActionPanel`, `ChooserActionPanelHandler`, `ChooserRowRenderer`
  - [ ] `ChooserSearchHandler`, `ChooserSearchMode`, `ChooserChoice`, `ChooserResult`
  - [ ] `SelectorSourceInvoker`, `FuzzyMatcher`, `SearchMemory`
  - [ ] `KeyablePanel`, `VerticalCenteringCell`, `FileIndexer`, `IconLoader`
  - [ ] Remove corresponding test files
- [ ] 4.6 Integration testing
  - [ ] Selector opens chooser with search field focused
  - [ ] Typing filters results with fuzzy matching
  - [ ] Arrow keys navigate, return selects, escape closes
  - [ ] Actions panel works (tab toggle, cmd+return for secondary)
  - [ ] File selector with background indexing works
  - [ ] Search memory (recent queries) works or is reimplemented

### Code Review Session 4

- [ ] 4.R Review Phase 4 changes
  - [ ] Chooser interaction feels responsive
  - [ ] Fuzzy match performance acceptable
  - [ ] WebView text input reliable
  - [ ] JS↔Scheme message bridge clean
  - [ ] Update plan with findings

### Phase 5: Cleanup

- [ ] 5.1 Delete `QuicklinksLibrary` and `SnippetsLibrary`
  - [ ] Move any remaining logic to Scheme
  - [ ] Address date/time formatting: evaluate `(lispkit date-time)` vs new `(modaliser datetime)` library
- [ ] 5.2 Final Swift audit
  - [ ] Every remaining Swift file is an OS primitive or bootstrap infrastructure
  - [ ] No dispatch logic, no UI rendering, no command tree management in Swift
  - [ ] Clean up any dead code, unused imports, orphaned files
- [ ] 5.3 Update documentation
  - [ ] Update `LLM_README.md` to reflect new architecture
  - [ ] Update or create Scheme-level documentation
- [ ] 5.4 Full regression test
  - [ ] All modal navigation works
  - [ ] All overlay rendering works
  - [ ] All chooser/selector functionality works
  - [ ] All native library primitives work
  - [ ] App lifecycle (launch, relaunch, quit, launch-at-login) works

### Code Review Session 5

- [ ] 5.R Final architecture review
  - [ ] Swift layer is minimal and clean
  - [ ] Scheme file organization is logical
  - [ ] The primitives form a coherent "desktop app in Scheme" foundation
  - [ ] No regressions from pre-refactoring functionality
  - [ ] Update plan with findings

## Learnings

(To be filled in during implementation sessions)
