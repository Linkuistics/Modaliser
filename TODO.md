# TODO

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

## Starter config generation

When no config file exists at `~/.config/modaliser/config.scm`, root.scm silently skips it. Generate a starter config on first launch so users have something to work with.

```
Read Sources/Modaliser/Scheme/root.scm. After the (when (file-exists? user-config-path) ...) block, add an else branch that: 1) creates the ~/.config/modaliser/ directory if needed (using run-shell "mkdir -p ~/.config/modaliser"), 2) writes a minimal starter config.scm with (set-leader! 'global F18), (set-leader! 'local F17), and a global tree containing a few example commands (launch Safari, center window, find apps selector), and 3) loads it. Use (with-output-to-file user-config-path (lambda () (display starter-config-string))) for writing. Model the starter config on the existing config.scm but with only the essentials.
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
