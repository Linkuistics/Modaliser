# Scheme-First Architecture Refactoring

Refactor Modaliser so Scheme is the complete application runtime — owning event dispatch, state management, command execution, and UI rendering. Swift is reduced to a thin host providing OS-level primitives (CGEvent tap, WKWebView, accessibility APIs, shell execution). All `.scm` files live in the project directory alongside Swift sources.

## Motivation

Modaliser should be completely configurable and programmable in Scheme. Users should eventually be able to write arbitrary applications in Scheme without reference to Swift. Swift exists only because macOS system APIs require it.

## Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│  Scheme Runtime (the application)                   │
│                                                     │
│  modaliser.scm (root)                               │
│  ├── core/state-machine.scm   tree registry, nav    │
│  ├── core/event-dispatch.scm  hotkey + modal keys   │
│  ├── core/keymap.scm          keycode→char table    │
│  ├── ui/dom.scm               s-expr → HTML DSL     │
│  ├── ui/css.scm               CSS generation        │
│  ├── ui/overlay.scm           which-key overlay      │
│  ├── ui/chooser.scm           search/select UI       │
│  ├── lib/dsl.scm              key, group, selector   │
│  ├── lib/fuzzy-match.scm      fuzzy matching algo    │
│  ├── lib/util.scm             alist helpers, etc.    │
│  └── base.css                 default stylesheet     │
│                                                     │
├─────────────────── primitives boundary ─────────────┤
│                                                     │
│  Swift Host (OS primitives only)                    │
│                                                     │
│  SchemeEngine          LispKit context, load root    │
│  ModaliserAppDelegate  Minimal — create engine, load │
│  KeyboardCapture       CGEvent tap (started by Scheme)│
│                                                     │
│  Native Libraries:                                  │
│  (modaliser lifecycle) activation policy, status bar │
│  (modaliser keyboard)  hotkey reg, catch-all, capture │
│  (modaliser webview)   WKWebView lifecycle + comms   │
│  (modaliser app)       NSWorkspace, app scanning     │
│  (modaliser window)    AXUIElement window mgmt       │
│  (modaliser input)     CGEvent keystroke posting     │
│  (modaliser shell)     Process execution             │
│  (modaliser pasteboard) NSPasteboard read/write      │
│  (modaliser clipboard-history) background monitoring │
└─────────────────────────────────────────────────────┘
```

## Swift Host Layer

### App Lifecycle

`ModaliserAppDelegate` is reduced to a bootstrap stub:
1. Create `SchemeEngine`
2. Load `modaliser.scm` from the app's Scheme directory

That's it. Everything else — activation policy, status bar menu, keyboard capture, permissions — is initiated by the Scheme program via primitives. This establishes the model for writing desktop apps in Scheme: Swift provides the `NSApplication` entry point and the Scheme runtime, then hands control to Scheme.

### App Lifecycle Primitive Library — `(modaliser lifecycle)`

Provides primitives for macOS app lifecycle that Scheme calls during initialization.

**Primitives:**
- `(set-activation-policy! policy)` — sets `NSApp.setActivationPolicy`. `policy` is a symbol: `'regular` (dock icon + menu bar), `'accessory` (menu bar only, no dock icon), or `'prohibited` (no UI presence).
- `(create-status-item! title menu-alist)` — creates an `NSStatusItem` in the menu bar with the given title string. `menu-alist` is a list of menu item specs, each an alist with keys `'title`, `'action` (a Scheme lambda), and optionally `'key-equivalent`. A special `'separator` symbol creates a separator item. Returns a status item id.
- `(update-status-item! id title menu-alist)` — updates an existing status item's title and menu.
- `(remove-status-item! id)` — removes a status item.
- `(request-accessibility!)` — checks/requests Accessibility permission (wraps `AXIsProcessTrusted` + prompt). Returns `#t` if granted.
- `(request-screen-recording!)` — checks/requests Screen Recording permission. Returns `#t` if granted.
- `(relaunch!)` — relaunches the app (preserving TCC permissions for `.app` bundles).
- `(quit!)` — calls `NSApp.terminate`.

**Example usage in `modaliser.scm`:**
```scheme
(set-activation-policy! 'accessory)
(request-accessibility!)
(request-screen-recording!)

(create-status-item! "⌨"
  (list
    (list '(title . "Reload Config") '(action . reload-config) '(key-equivalent . "r"))
    'separator
    (list '(title . "Relaunch") '(action . relaunch!))
    (list '(title . "Quit Modaliser") '(action . quit!) '(key-equivalent . "q"))))
```

### Runtime File Loading

The `.scm` files under `Sources/Modaliser/Scheme/` are added to the Xcode/SPM target as bundled resources. At runtime, `SchemeEngine` resolves the path to `modaliser.scm` via `Bundle.main.resourceURL` (for `.app` bundles) or relative to the executable (for `swift build` dev builds). LispKit's include path is set to the Scheme directory so that `(load "core/state-machine.scm")` resolves correctly. The `base.css` file is loaded by Scheme using LispKit's file I/O (e.g. `(read-file "base.css")` from `(lispkit port)`) as a string and embedded in generated HTML.

User configuration is a Scheme-level concern, not a Swift one. The root `modaliser.scm` (or `lib/dsl.scm`) includes a Scheme function that checks for `~/.config/modaliser/config.scm` and loads it if present. This replaces the Swift `ConfigPathResolver`. If the user wants a different config location, they modify the Scheme code.

### Keyboard Primitive Library — `(modaliser keyboard)`

Replaces `KeyEventDispatcher`, `KeyCodeMapping`, `LeaderMode`.

**Primitives:**
- `(start-keyboard-capture!)` — creates and starts the CGEvent tap. Must be called after accessibility permission is granted. The tap dispatches to registered handlers (see below).
- `(stop-keyboard-capture!)` — stops and destroys the CGEvent tap.
- `(register-hotkey! keycode handler)` — registers a specific keycode. When the CGEvent tap sees this keycode on keydown, it calls `handler` (a zero-argument Scheme procedure) and suppresses the event.
- `(unregister-hotkey! keycode)` — removes a hotkey registration.
- `(register-all-keys! handler)` — registers a catch-all handler for every keydown. `handler` is called with `(keycode modifiers)` and must return `#t` to suppress or `#f` to pass through. Used when going modal.
- `(unregister-all-keys!)` — removes the catch-all handler. Used when leaving modal.
- `(keycode->char keycode)` — returns the character string for a keycode, or `#f` if unmapped.

**Constants:** `F17`, `F18`, `F19`, `F20`, `ESCAPE`, `DELETE`, `RETURN`, `TAB`, `UP`, `DOWN`, `LEFT`, `RIGHT`, `SPACE` and modifier flag constants (`MOD-CMD`, `MOD-SHIFT`, `MOD-ALT`, `MOD-CTRL`).

**CGEvent tap dispatch logic:**
1. If a catch-all handler is registered → call it with keycode and modifiers → suppress if `#t`, pass if `#f`.
2. Else if the keycode has a registered hotkey → call its handler → suppress.
3. Else → pass through.

The catch-all has priority, so when modal is active the Scheme modal key handler sees *all* keys, including leader keys. The Scheme handler is responsible for recognizing the leader key and implementing toggle behavior (calling `modal-exit` when it sees the leader keycode). This is correct: the modal key handler has full context and can decide whether a leader key press means "exit modal" or something else.

The registration-as-state pattern: modal state is expressed structurally. If the catch-all is registered, the app is modal. No separate "isActive" flag needed.

**Threading:** The CGEvent tap callback runs on the main run loop. All Scheme evaluation happens synchronously on the main thread. This threading model is preserved — the catch-all and hotkey handlers are called synchronously from the event tap, and their return value determines suppression. Async operations (like `run-shell-async`) dispatch callbacks back to the main thread.

**Error handling:** If a Scheme handler throws a runtime error, the Swift keyboard library catches it, logs via NSLog, and returns `#f` (pass through) to avoid leaving the app in a stuck modal state. For the catch-all handler, an error also triggers automatic deregistration of the catch-all (equivalent to `modal-exit`) to ensure recovery.

### WebView Primitive Library — `(modaliser webview)`

Replaces `OverlayPanel`, `ChooserWindowController`, and all associated AppKit rendering code.

**Primitives:**
- `(webview-create id options-alist)` — creates a WKWebView-backed NSPanel. Options:
  - `'activating` — boolean, whether the panel takes keyboard focus (default `#f`)
  - `'floating` — boolean, whether the panel floats above other windows (default `#t`)
  - `'width` / `'height` — dimensions in points
  - `'x` / `'y` — position (optional, defaults to screen center)
  - `'transparent` — boolean, whether the panel background is transparent (default `#f`)
  - `'shadow` — boolean (default `#t`)
- `(webview-close id)` — closes and destroys the panel.
- `(webview-set-html! id html-string)` — replaces the entire HTML content.
- `(webview-eval id js-string)` — evaluates arbitrary JavaScript in the webview. Returns the result as a string.
- `(webview-on-message id handler)` — registers a handler for messages from JavaScript. JS sends messages via `window.webkit.messageHandlers.modaliser.postMessage(data)`. Handler receives the message data parsed from JSON to Scheme values.
- `(webview-set-style! id css-string)` — convenience to inject/replace a `<style id="dynamic">` block without replacing all HTML.

**NSPanel configuration:**
- Non-activating panels: `[.borderless, .nonactivatingPanel]`, level `.floating`, `hidesOnDeactivate = false`
- Activating panels: `[.borderless]`, level `.floating`, becomes key window for text input
- Both: opaque = false, background = clear (for transparent windows), shadow configurable

### Existing OS Libraries

**Keep as-is** (with supporting files):
- `AppLibrary` — add `(focused-app-bundle-id)`. Supporting: `AppScanner`
- `WindowLibrary` — pure AXUIElement wrappers. Supporting: `WindowCache`, `WindowEnumerator`, `WindowManipulator`
- `InputLibrary` — CGEvent keystroke posting. Supporting: `KeystrokeEmitter`
- `ShellLibrary` — Process execution
- `PasteboardLibrary` — NSPasteboard read/write. Supporting: `PasteboardReading`

**Keep with trimming:**
- `ClipboardHistoryLibrary` — keep background monitoring and store, but any file I/O for persistence moves to Scheme. Supporting: `ClipboardHistoryStore`, `ClipboardMonitor`

**Keep (app infrastructure):**
- `main.swift` — app entry point (4 lines, creates NSApplication and delegate)
- `KeyboardCapture`, `CapturedKeyEvent`, `KeyboardCaptureError`, `KeyCode` — CGEvent tap mechanics
- `AccessibilityPermission`, `AccessibilityPermissionAlert` — TCC permission handling
- `LaunchAtLogin` — status bar menu support
- `SchemeAlistLookup` — shared alist builder/reader used by retained native libraries

**Delete** (Scheme handles file I/O / logic moves to Scheme):
- `QuicklinksLibrary`
- `SnippetsLibrary` — date/time formatting primitives (`snippets--current-date`, etc.) move to a new `(modaliser datetime)` native library or are replaced by LispKit's `(lispkit date-time)` facilities. Evaluate in Phase 5.
- `IconLoader` — icon rendering moves to HTML/CSS in WebView

### Swift Code to Delete

All dispatch/UI/bridge code:
- `KeyEventDispatcher`, `SchemeModalBridge`, `CommandExecutor`
- `CommandNode`, `CommandNodeBuilder`, `CommandTreeRegistry`
- `OverlayPanel`, `OverlayCoordinator`, `OverlayNotifier`, `OverlayPresenting`
- `OverlayContent`, `OverlayContentBuilder`, `OverlayEntry`, `OverlayLayout`
- `OverlayTheme`, `ThemeConfigParser`, `OverlayHeaderRenderer`, `OverlayEntryRenderer`, `OverlayFooterRenderer`
- `ChooserWindowController`, `ChooserCoordinator`, `ChooserPresenting`
- `ChooserWindowBuilder`, `ChooserKeyboardHandler`, `ChooserFooterRenderer`
- `ChooserActionPanel`, `ChooserActionPanelHandler`, `ChooserRowRenderer`
- `ChooserSearchHandler`, `ChooserSearchMode`, `ChooserChoice`, `ChooserResult`
- `SelectorSourceInvoker`, `FuzzyMatcher`, `FocusedAppObserver`
- `SearchMemory`, `KeyablePanel`, `VerticalCenteringCell`, `FileIndexer`
- `ModaliserDSLLibrary`, `SchemeStateMachineLibrary`
- `LeaderMode`, `KeyDispatchResult`, `KeyCodeMapping`, `KeyEventHandlingResult`
- `ConfigPathResolver`, `ConfigSetup`, `ConfigErrorAlert`

## Scheme Layer

### File Layout

All `.scm` files under `Sources/Modaliser/Scheme/`. Swift loads only `modaliser.scm`.

```
Sources/Modaliser/Scheme/
├── modaliser.scm              # Root — loads all modules, registers hotkeys
├── core/
│   ├── state-machine.scm      # Tree hash table, navigation, enter/exit
│   ├── event-dispatch.scm     # Hotkey handlers, modal key handler
│   └── keymap.scm             # Keycode → character mapping table
├── ui/
│   ├── dom.scm                # S-expression → HTML generation
│   ├── css.scm                # CSS generation helpers
│   ├── overlay.scm            # Which-key overlay (WebView-based)
│   └── chooser.scm            # Search/select UI (WebView-based, Phase 4)
├── lib/
│   ├── dsl.scm                # key, group, selector, action, define-tree
│   ├── fuzzy-match.scm        # Fuzzy matching (Phase 4)
│   └── util.scm               # Alist helpers, string operations
└── base.css                   # Default stylesheet
```

### State Machine (`core/state-machine.scm`)

Replaces `SchemeStateMachineLibrary`. Ported from the current Scheme-in-Swift-strings to a proper `.scm` file.

Key changes from current design:
- **Hash table for trees** instead of global-tree + app-trees alist. All trees keyed by scope string.
- `(register-tree! scope . children)` — accepts either a symbol or string for scope. Internally converts symbols to strings via `symbol->string`. Wraps children in a root group node, stores in the hash table.
- `(lookup-tree scope)` — retrieves a tree. Accepts symbol or string. Returns `#f` if none.
- **Side-effecting navigation**: `modal-handle-key` directly executes actions (calls lambdas), directly updates/shows/hides the overlay, directly opens the chooser. No result tags returned to Swift. This is the fundamental change — the state machine owns the full dispatch loop.

State:
```scheme
(define tree-registry (make-hashtable string-hash string=?))
(define modal-active? #f)
(define modal-current-node #f)
(define modal-root-node #f)
(define modal-current-path '())
(define modal-leader-keycode #f)  ;; tracks which leader key activated modal, for toggle
```

### Event Dispatch (`core/event-dispatch.scm`)

The entry point for all keyboard interaction. Replaces `KeyEventDispatcher` and `SchemeModalBridge`.

```scheme
;; Called from lib/dsl.scm's set-leader!
;; Registers a hotkey that, when pressed:
;;   1. Gets focused app bundle ID via (focused-app-bundle-id)
;;   2. Looks up tree: app-specific first, then "global" fallback
;;   3. Calls modal-enter with the tree and the leader keycode

;; modal-enter:
;;   1. Stores the leader keycode in modal-leader-keycode
;;   2. Sets state (active node, root, path)
;;   3. Calls (register-all-keys! modal-key-handler)
;;   4. Calls (show-overlay ...)

;; modal-key-handler receives (keycode modifiers):
;;   - Leader keycode (toggle) → modal-exit, return #t
;;   - Escape → modal-exit, return #t
;;   - Delete → modal-step-back, return #t
;;   - Cmd+anything → pass through (#f)
;;   - Otherwise → keycode→char → modal-handle-key, return #t
;;   Returns #t to suppress, #f to pass

;; modal-exit:
;;   1. Calls (unregister-all-keys!)
;;   2. Calls (hide-overlay)
;;   3. Resets state (including modal-leader-keycode)
```

### DOM DSL (`ui/dom.scm`)

Hiccup/SXML-style HTML generation. Pure functions — no side effects.

```scheme
;; Core: (element tag attrs . children) → HTML string
;; Convenience: (div attrs . children), (span attrs . children), etc.
;; Text is auto-escaped.
;; Attributes alist: '((class "foo") (id "bar") (style "color:red"))
;; Children can be strings (text nodes) or nested element calls.

;; Example:
;; (div '((class "overlay"))
;;   (h1 '() "Global")
;;   (ul '()
;;     (li '() (span '((class "key")) "s") " Safari")))
;; →
;; "<div class=\"overlay\"><h1>Global</h1><ul><li><span class=\"key\">s</span> Safari</li></ul></div>"
```

### CSS Helpers (`ui/css.scm`)

```scheme
;; (css-rule selector properties-alist) → CSS string
;; (css-rules . rules) → concatenated CSS string
;; (inline-style properties-alist) → "prop: val; prop: val" string

;; Example:
;; (css-rule ".key" '((background "#333") (padding "2px 6px") (border-radius "3px")))
;; → ".key { background: #333; padding: 2px 6px; border-radius: 3px; }"
```

### Overlay (`ui/overlay.scm`)

Replaces the entire Swift overlay subsystem. Theming is handled via CSS — the base stylesheet provides defaults, and user config can override styles by providing custom CSS rules.

- `(show-overlay node path)` — creates WebView (if not open), renders node's children as HTML using DOM DSL, sets content.
- `(update-overlay node path)` — re-renders and updates content in existing WebView.
- `(hide-overlay)` — closes WebView.
- `(render-overlay-html node path)` — pure function, returns full HTML document string with embedded CSS.

The current `set-theme!` functionality is replaced by CSS customization. Users can define custom styles in their config that get injected into the overlay's `<style>` block, or provide a custom CSS file.

### User DSL (`lib/dsl.scm`)

Pure Scheme replacements for the current `ModaliserDSLLibrary` Swift functions:

- `(key k label action)` → alist with `kind: command`
- `(group k label . children)` → alist with `kind: group`
- `(selector k label . props)` → alist with `kind: selector`
- `(action name . props)` → alist
- `(define-tree scope . children)` → calls `register-tree!`
- `(set-leader! key-constant)` → calls `register-hotkey!` with a handler that does focused-app lookup and tree selection. The handler looks up the focused app's bundle ID, checks for an app-specific tree, falls back to `"global"`.

These maintain surface-level API compatibility with the current `config.scm` syntax, so user configs need minimal or no changes.

### Chooser Input Architecture (Phase 4)

The chooser WebView is an *activating* panel — it takes keyboard focus. All input is handled in JavaScript:
- An `<input>` element captures search text. JS `input` events fire `postMessage` to Scheme with the query string.
- Keyboard events (`keydown`) are intercepted in JS. Navigation keys (up/down/return/escape/cmd+return) are sent to Scheme via `postMessage`. Regular text input flows normally to the `<input>` element.
- Scheme receives messages, runs fuzzy matching, and pushes updated HTML back via `webview-set-html!` or incremental DOM updates via `webview-eval`.

This keeps all interaction logic in Scheme/JS with no Swift event monitors.

## Migration Phases

### Phase 1: Foundation

**Swift work:**
- Create `LifecycleLibrary` (`(modaliser lifecycle)`) — activation policy, status bar, permissions, quit/relaunch
- Create `KeyboardLibrary` (`(modaliser keyboard)`) — start/stop capture, hotkey registration, catch-all, keycode→char, key constants
- Create `WebViewLibrary` (`(modaliser webview)`) — WebView lifecycle and communication primitives
- Add `(focused-app-bundle-id)` to `AppLibrary`
- Modify `KeyboardCapture` to support registration-based dispatch (started/stopped by Scheme)
- Reduce `ModaliserAppDelegate` to bootstrap stub — create engine, load `modaliser.scm`. No activation policy, no status bar, no capture start.
- Configure `SchemeEngine` to set LispKit include path and load `.scm` files from Scheme directory

**Scheme work:**
- `modaliser.scm` — root loader. Sets activation policy, requests permissions, creates status bar, starts keyboard capture, loads user config.
- `core/state-machine.scm` — tree registry, navigation (side-effecting, no result tags)
- `core/event-dispatch.scm` — hotkey handlers, modal key handler with leader toggle
- `core/keymap.scm` — keycode→character table
- `lib/dsl.scm` — `key`, `group`, `define-tree`, `set-leader!`
- `lib/util.scm` — alist helpers

**Swift deletions:** `KeyEventDispatcher`, `SchemeModalBridge`, `CommandExecutor`, `CommandNode`, `CommandNodeBuilder`, `CommandTreeRegistry`, `ModaliserDSLLibrary`, `SchemeStateMachineLibrary`, `LeaderMode`, `KeyDispatchResult`, `KeyEventHandlingResult`, `KeyCodeMapping`, `FocusedAppObserver`, `ConfigPathResolver`, `ConfigSetup`, `ConfigErrorAlert`, `AccessibilityPermissionAlert` (replaced by Scheme-driven permission flow)

**End state:** App launches → Scheme sets up everything (activation policy, status bar, permissions, capture) → press F18 → modal navigation → action lambdas fire → escape/delete/leader-toggle work. Verified via NSLog. No overlay UI yet.

### Code Review Session 1

Review Phase 1 changes. Verify: Swift↔Scheme boundary is clean, registration-as-state works, leader toggle works, no latency issues, error recovery is solid.

### Phase 2: DOM DSL + Overlay

**Swift work:** Minimal — may need to tune NSPanel options.

**Scheme work:**
- `ui/dom.scm` — full s-expression→HTML DSL
- `ui/css.scm` — CSS generation helpers
- `ui/overlay.scm` — overlay show/hide/update using WebView primitives
- `base.css` — default stylesheet (replaces `OverlayTheme`)
- Wire overlay into `event-dispatch.scm` and `state-machine.scm`

**Swift deletions:** `OverlayPanel`, `OverlayCoordinator`, `OverlayNotifier`, `OverlayPresenting`, `OverlayContent`, `OverlayContentBuilder`, `OverlayEntry`, `OverlayLayout`, `OverlayTheme`, `ThemeConfigParser`, `OverlayHeaderRenderer`, `OverlayEntryRenderer`, `OverlayFooterRenderer`

**End state:** Full modal navigation with WebView-rendered which-key overlay.

### Code Review Session 2

Review DOM DSL, overlay rendering, WebView lifecycle. Check for flicker, positioning, theme fidelity.

### Phase 3: Config Migration

**Scheme work:**
- Complete `lib/dsl.scm` — `selector`, `action` functions
- Migrate existing `config.scm` to work with new architecture
- CSS-based theming to replace `set-theme!`

**Swift deletions:** `SchemeAlistLookup` (if no longer needed by retained libraries — audit first)

**End state:** Existing user config works on new architecture with minimal changes.

### Code Review Session 3

Review DSL design, config compatibility, overall Scheme file structure.

### Phase 4: Chooser as WebView

**Scheme work:**
- `ui/chooser.scm` — search input, result list, keyboard nav, action panel, all as HTML
- `lib/fuzzy-match.scm` — port fuzzy matching from Swift to Scheme
- Wire selector handling into state machine

**Swift deletions:** `ChooserWindowController`, `ChooserCoordinator`, `ChooserPresenting`, `ChooserWindowBuilder`, `ChooserKeyboardHandler`, `ChooserFooterRenderer`, `ChooserActionPanel`, `ChooserActionPanelHandler`, `ChooserRowRenderer`, `ChooserSearchHandler`, `ChooserSearchMode`, `ChooserChoice`, `ChooserResult`, `SelectorSourceInvoker`, `FuzzyMatcher`, `SearchMemory`, `KeyablePanel`, `VerticalCenteringCell`, `FileIndexer`, `IconLoader`

**End state:** Full feature parity with current app, entirely Scheme-driven.

### Code Review Session 4

Review chooser implementation, fuzzy match performance, WebView input handling.

### Phase 5: Cleanup

- Delete `QuicklinksLibrary`, `SnippetsLibrary` — move logic to Scheme
- Address date/time formatting: evaluate LispKit's `(lispkit date-time)` as replacement for Swift `DateFormatter` primitives, or create a small `(modaliser datetime)` native library
- Final audit: every remaining Swift file should be an OS primitive or app infrastructure
- Update `LLM_README.md` to reflect new architecture

### Code Review Session 5

Final architecture review. Verify Swift layer is minimal. Review Scheme file organization.

## Testing Strategy

- **Swift primitives**: Unit tests for each NativeLibrary (registration, deregistration, WebView lifecycle, message passing)
- **Scheme modules**: Integration tests via `SchemeEngine` — load `.scm` files, exercise functions, verify behavior. Tests call Scheme functions via `evaluate()` and check results.
- **End-to-end**: Existing test patterns adapted — simulate key events, verify Scheme state, verify WebView content via `webview-eval`.
- **Error recovery**: Tests that inject Scheme errors during modal handling and verify the app recovers (catch-all deregistered, overlay closed).

## Risks and Mitigations

- **Fuzzy match performance in Scheme**: The current Swift `FuzzyMatcher` uses DP. Scheme may be slower for large lists (1000+ items). Mitigation: benchmark in Phase 4; if too slow, keep fuzzy matching as a Swift primitive.
- **WebView latency for overlay**: `webview-set-html!` involves HTML parsing and layout. Current overlay uses pre-laid-out NSViews. Mitigation: measure in Phase 2; if slow, use `webview-eval` for incremental DOM updates instead of full HTML replacement.
- **WKWebView text input for chooser**: The activating WebView must handle text input via HTML `<input>` and JS event listeners. The JS↔Scheme message bridge adds latency to each keystroke. Mitigation: debounce search queries in JS (not Scheme) to reduce round-trips; only send complete query strings, not individual keystrokes.
- **LispKit `(load ...)` paths**: Need to resolve file paths relative to the root `.scm` file location. Mitigation: `SchemeEngine` sets LispKit's include path to the Scheme directory at initialization.
- **Scheme error in catch-all handler**: Could leave the app stuck in modal. Mitigation: Swift catches Scheme errors, deregisters catch-all, logs error. Scheme-side `modal-exit` also used as a safety reset.
