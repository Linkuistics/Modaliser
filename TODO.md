# TODO

## Additional dynamic search sources

The dynamic chooser infrastructure (`'dynamic-search` callback + `chooser-push-results`) supports any external data source. Potential additions: DuckDuckGo search, dictionary/thesaurus lookup, calculator, emoji search via API, or custom REST API integration.

## Clipboard history integration

The `ClipboardHistoryLibrary`, `ClipboardHistoryStore`, and `ClipboardMonitor` Swift code exists but the clipboard monitor is never started -- the library is registered but no polling timer is created. Wire up the monitor and add a chooser selector for browsing/restoring clipboard history.

```
Read Sources/Modaliser/ClipboardHistoryLibrary.swift, ClipboardHistoryStore.swift, and ClipboardMonitor.swift. The store and monitor exist but the monitor is never instantiated with a timer. Add a `start-clipboard-monitor!` primitive to ClipboardHistoryLibrary that creates a ClipboardHistoryStore (at ~/.config/modaliser/clipboard-history/), creates a ClipboardMonitor with focusedAppBundleId wired to NSWorkspace.shared.frontmostApplication?.bundleIdentifier, and starts a repeating Timer (every 0.5s) that calls checkForChanges(). Also add a `stop-clipboard-monitor!` primitive. Call start-clipboard-monitor! from root.scm after keyboard capture starts. Then add a clipboard history selector to the default config.scm that uses get-clipboard-history as the source and restore-clipboard-entry! as the on-select action.
```

## Config reload without relaunch

The menu bar currently offers "Relaunch" to apply config changes. Implement hot config reload that re-evaluates the user config without restarting the process.

```
Read Sources/Modaliser/Scheme/root.scm and Sources/Modaliser/Scheme/core/state-machine.scm. The tree-registry is a hash table. Implement a (reload-config!) function in Scheme that: 1) clears the tree-registry hash table with (hashtable-walk tree-registry (lambda (k v) (hashtable-delete! tree-registry k))), 2) unregisters all hotkeys by iterating, 3) re-evaluates the user config file at user-config-path using (load user-config-path). Add a "Reload Config" menu item to the status bar in root.scm (above Relaunch) with action reload-config! and key-equivalent "R". Be careful to preserve the keyboard capture state -- only the trees and leader bindings should be reloaded, not the core modules.
```

## Dark mode CSS theme

The default base.css uses a light theme. Add a `@media (prefers-color-scheme: dark)` block so the overlay and chooser adapt to macOS dark mode.

```
Read Sources/Modaliser/Scheme/base.css. Add a @media (prefers-color-scheme: dark) block at the end that overrides all CSS custom properties in :root with dark-appropriate values. Use colors like --overlay-bg: rgba(35, 35, 40, 0.98), --overlay-border: rgba(80, 80, 80, 1), --color-label: rgba(220, 220, 220, 1), --color-key: rgba(100, 170, 255, 1), --color-group: rgba(255, 180, 80, 1), --color-arrow: rgba(150, 150, 150, 1), --color-header: rgba(160, 160, 160, 1), --color-separator: rgba(70, 70, 70, 1), --chooser-input-bg: rgba(50, 50, 55, 1), --chooser-input-border: rgba(80, 80, 85, 1), --chooser-selected-bg: rgba(100, 170, 255, 0.15), --chooser-action-bg: rgba(40, 40, 45, 1). Verify both the overlay and chooser render correctly in dark mode.
```

## Multi-monitor support for panel positioning

Overlay and chooser panels are currently positioned relative to the main screen. They should appear on the screen containing the focused window.

```
Read Sources/Modaliser/WebViewManager.swift, specifically the createPanel method's positioning block. Currently uses NSScreen.main for centering. Change it to: 1) get the focused window's frame using the Accessibility API (AXUIElementCreateSystemWide -> kAXFocusedApplicationAttribute -> kAXFocusedWindowAttribute -> kAXPositionAttribute + kAXSizeAttribute), 2) find which NSScreen.screens contains the center point of that frame, 3) use that screen's visibleFrame for positioning instead of NSScreen.main. Fall back to NSScreen.main if no focused window is found.
```

## Search memory persistence

Selectors accept `'remember` and `'id-field` properties in the DSL but the persistence mechanism is not implemented. Recently-selected items should be boosted to the top on subsequent opens.

```
Read Sources/Modaliser/Scheme/ui/chooser.scm and Sources/Modaliser/Scheme/lib/dsl.scm. The selector DSL accepts 'remember and 'id-field but they are never used in the chooser lifecycle. Implement search memory: 1) in open-chooser, after loading items, check if the selector has 'remember set. If so, read ~/.config/modaliser/memory/<remember-name>.json (create directory if needed). 2) Boost items whose id-field value matches a recently-selected ID to the top of the initial results. 3) In chooser-handle-select, after selecting an item, append its id-field value with a timestamp to the memory file. 4) Limit memory to 50 entries per selector, pruning oldest. Use run-shell with shell commands or add a simple file-write primitive.
```

## Wire up LaunchAtLogin

The LaunchAtLogin.swift helper exists (using SMAppService) but is not exposed to Scheme or wired into the menu bar.

```
Read Sources/Modaliser/LaunchAtLogin.swift and Sources/Modaliser/LifecycleLibrary.swift. Add two primitives to LifecycleLibrary: (launch-at-login?) which returns LaunchAtLogin.isEnabled as a boolean, and (toggle-launch-at-login!) which calls LaunchAtLogin.toggle(). Then in Sources/Modaliser/Scheme/root.scm, add a "Launch at Login" menu item to the status bar that calls toggle-launch-at-login! as its action.
```

## Overlay auto-sizing

The overlay panel uses a fixed width of 340px. Auto-size width based on the longest label in the current group.

```
Read Sources/Modaliser/Scheme/ui/overlay.scm and Sources/Modaliser/Scheme/ui/overlay.js. The overlay already auto-resizes height via the ResizeObserver in overlay.js. For width, extend the ResizeObserver callback to also report the content width. In WebViewManager.swift, add width handling to resizePanel (or add a new resizePanelBoth method). In overlay.scm, change the CSS to use width:auto with min-width:200px and max-width:500px, and let the ResizeObserver + native resize handle the panel frame.
```

## Window switcher as built-in selector

The window switcher works via list-windows + focus-window but could benefit from showing window icons (app icons via bundleId) and better cross-space support.

```
Read Sources/Modaliser/WindowCache.swift and Sources/Modaliser/Scheme/ui/chooser.scm. The WindowCache tracks focus history and provides cross-space window listing. The chooser already supports iconType "bundleId" in alists. Currently the window switcher in config.scm uses list-windows as the source and focus-window as on-select. Verify that icon rendering works correctly for bundleId-type icons in the chooser JS (check if the JS updateResults function handles icon display -- if not, add <img> rendering using NSWorkspace icon resolution via a new primitive, or use the bundleId to construct an icon URL).
```

## Forward the modal exit reason through composed on-leave hooks

`modal-exit` passes a reason (`'confirm` on Return, `'cancel` on Escape/leader/unknown, `'exit`/`'navigate` otherwise) and `run-on-leave` forwards it to any `on-leave` hook whose arity includes 1 (`procedure-arity-includes?`). This reaches *raw* hooks — those on a `(group …)` or a blockless `register-tree!`/`define-tree` root — but **not** hooks on `(overlay …)` or any block-composed tree, because `(modaliser dsl)` `compose-hooks` flattens the user hook into a fixed nullary `(lambda () …)` wrapper before the state machine ever sees it. Two consequences for composed hooks: (1) the reason is silently dropped (the wrapper's arity is 0, so `run-on-leave` calls it with no args); (2) a user who writes the 1-arg form `'on-leave (λ (reason) …)` on an overlay/define-tree gets an **arity error at leave time**, because the wrapper invokes the inner hook as `(user-thunk)` with zero args. `compose-hooks` can't do the arity check itself because `dsl.sld` is deliberately host-portable (imports only `(scheme …)`/`(modaliser …)`; `procedure-arity-includes?` is a `(lispkit core)` extension). Net effect is minor — a commit/cancel sub-mode (e.g. the Dia Recent-Tabs walk) is naturally a `(group …)`, which works — but the contract is uneven and the overlay case is a latent runtime footgun. Fix it by injecting the arity check into `dsl` rather than importing it.

```
Read Sources/Modaliser/Scheme/lib/modaliser/dsl.sld (compose-hooks ~line 423, and its callers in overlay ~396 and define-tree ~496), Sources/Modaliser/Scheme/lib/modaliser/state-machine.sld (run-on-leave, which already uses (only (lispkit core) procedure-arity-includes?)), and Sources/Modaliser/Scheme/root.scm (boot wiring). Goal: make compose-hooks forward the modal exit reason to a user on-leave hook that accepts one argument, while keeping dsl.sld host-portable (no (lispkit core) import) and leaving 0-arg user hooks and all block on-leave-fns (which are always nullary) untouched. Approach: in dsl.sld add a mutable host-injected predicate, e.g. (define hook-applies-reason? (lambda (proc) #f)) plus a setter (set-hook-applies-reason!) exported from the library. Change compose-hooks to return a variadic wrapper (lambda args ...) that calls the user-thunk via (if (and (pair? args) (hook-applies-reason? user-thunk)) (apply user-thunk args) (user-thunk)) and always calls block-thunks with no args. At boot (root.scm, after libraries load) call (set-hook-applies-reason! (lambda (p) (procedure-arity-includes? p 1))) so the host supplies the LispKit-backed check. Because the wrapper is now variadic, run-on-leave's (procedure-arity-includes? thunk 1) will be true for composed hooks, so it passes the reason in; the wrapper then forwards only to user hooks that actually accept it. Verify: (a) existing 0-arg overlay/define-tree on-leave teardowns (e.g. window-list chip cleanup via on-leave-fn, the (lambda () (hints-hide)) hooks in the mux/term libs) still fire on exit; (b) a 1-arg on-leave on an (overlay …) now receives the reason instead of erroring; (c) the bundled test suites for state-machine and event-dispatch stay green. Ship as a patch release (v2.3.1).
```

## Robustness in the face of config problems

A user config that fails to load — a Scheme syntax error, a runtime error during
evaluation, or a reference to DSL forms the running binary doesn't provide (the new
`screen`/`panel`/`open` forms against an older binary, or the now-deleted
`define-tree`/`category`/`overlay`/`which-key-block` forms against a current one) —
currently degrades to a **silent lock**: the status-bar menu items all show disabled
and the app is inert, with no surfaced error. It is especially easy to hit around the
edit-config → Relaunch loop and across version skew (a config authored for a different
binary than the one running). With the public release approaching, a bad config must
never wedge the app. This is its own future grove.

Goal: graceful degradation. Catch config load/eval failure, keep the status-bar menu
fully functional so the user can recover (Open Config / Reveal in Finder / Relaunch /
Reset to bundled default), and surface the actual error (notification, a "Config
error: …" menu item, or a fallback overlay) instead of locking. Design it alongside
the "Config reload without relaunch" item above — a failed hot-reload must also leave
the previous good state intact rather than half-applying.

```
Read Sources/Modaliser/Scheme/root.scm (the config load path and status-bar
construction) and Sources/Modaliser/SchemeEngine.swift (how LispKit evaluation errors
propagate into Swift). Trace what happens when evaluating the user config raises: does
the status bar still get built? Do its menu actions get installed? Goal: (1) wrap
user-config evaluation so a raise is caught and recorded, not fatal; (2) always build a
minimal, fully-enabled status-bar menu (Open Config, Reveal Config in Finder, Relaunch,
Reset to bundled default, and a "Config error: …" item when load failed) regardless of
config outcome; (3) surface the error (os.Logger with the subsystem + a user-visible
notification or menu item); (4) on a failed config, fall back to the bundled
default-config.scm so leader capture still works in a known-good state. Coordinate with
the hot-reload item so reload failures are transactional — keep the prior good trees /
leader bindings if the new config doesn't evaluate cleanly. Start the grove with a
grilling pass to settle the recovery UX (notify vs fall-back-to-default vs both) and
where the error is surfaced.
```
