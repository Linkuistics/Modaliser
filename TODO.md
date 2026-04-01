# TODO

## Clipboard history integration

The `ClipboardHistoryLibrary`, `ClipboardHistoryStore`, and `ClipboardMonitor` Swift code exists but the clipboard monitor is never started -- the library is registered but no polling timer is created. Wire up the monitor and add a chooser selector for browsing/restoring clipboard history.

```
Read Sources/Modaliser/ClipboardHistoryLibrary.swift, ClipboardHistoryStore.swift, and ClipboardMonitor.swift. The store and monitor exist but the monitor is never instantiated with a timer. Add a `start-clipboard-monitor!` primitive to ClipboardHistoryLibrary that creates a ClipboardHistoryStore (at ~/.config/modaliser/clipboard-history/), creates a ClipboardMonitor, and starts a repeating timer (every 0.5s) that calls checkForChanges(). Also add a `stop-clipboard-monitor!` primitive. Call start-clipboard-monitor! from root.scm after keyboard capture starts. Then add a clipboard history selector to the default config that uses get-clipboard-history as the source and restore-clipboard-entry! as the action.
```

## Config reload without relaunch

The menu bar currently offers "Relaunch" to apply config changes. Implement hot config reload that re-evaluates the user config without restarting.

```
Read Sources/Modaliser/Scheme/root.scm and Sources/Modaliser/Scheme/core/state-machine.scm. The tree-registry is a hash table. Implement a (reload-config!) function in Scheme that: 1) clears the tree-registry hash table, 2) re-evaluates the user config file at user-config-path using (include). Add reload-config! as a menu bar action (replacing or supplementing Relaunch). Be careful to preserve the current keyboard capture state -- only the trees and theme should be reloaded, not the core modules.
```

## Starter config generation

When no config file exists at `~/.config/modaliser/config.scm`, root.scm silently skips it. Generate a starter config on first launch.

```
Read Sources/Modaliser/Scheme/root.scm. After the (when (file-exists? user-config-path) ...) block, add an else branch that: 1) creates the ~/.config/modaliser/ directory if needed (using run-shell "mkdir -p ..."), 2) writes a minimal starter config.scm with a global tree containing a few example commands (launch Safari, center window, find apps selector), and 3) loads it. Use (with-output-to-file user-config-path (lambda () (display starter-config-string))) for writing.
```

## Multi-monitor support for panel positioning

Panels are currently positioned relative to the main screen. Support positioning relative to the screen containing the focused window.

```
Read Sources/Modaliser/WebViewManager.swift, specifically the createPanel method. Currently uses NSScreen.main for positioning. Change it to detect which screen contains the frontmost window (using NSScreen.screens and checking which frame contains the mouse location or the focused window's frame via the Accessibility API) and position the panel centered on that screen instead.
```

## Dark mode CSS theme

The default base.css uses a light theme. Add a dark theme that activates via `@media (prefers-color-scheme: dark)`.

```
Read Sources/Modaliser/Scheme/base.css. Add a @media (prefers-color-scheme: dark) block that overrides all CSS custom properties in :root with dark-appropriate values. Use colors like --overlay-bg: rgba(35, 35, 40, 1), --color-label: rgba(220, 220, 220, 1), --color-key: rgba(100, 170, 255, 1), --color-group: rgba(255, 180, 80, 1), etc. Test that both the overlay and chooser look correct in dark mode.
```

## Window tiling presets

Add more window management primitives for common tiling layouts (halves, quarters).

```
Read Sources/Modaliser/WindowManipulator.swift and Sources/Modaliser/WindowLibrary.swift. The move-window primitive already supports unit-rect positioning (0.0-1.0 fractions). Add convenience Scheme functions in a new lib/window-presets.scm file: (left-half), (right-half), (top-half), (bottom-half), (top-left-quarter), (top-right-quarter), (bottom-left-quarter), (bottom-right-quarter), (center-two-thirds). Each should call move-window with the appropriate fractions. Include this file from root.scm.
```

## Search memory persistence

Selectors support a `'remember` property and `'id-field` for search memory, but the persistence mechanism is not implemented.

```
Read Sources/Modaliser/Scheme/ui/chooser.scm. The selector DSL accepts 'remember and 'id-field properties but they are never used in the chooser lifecycle. Implement search memory: when a selector has 'remember set, save the selected item's id-field value to a file (~/.config/modaliser/memory/<remember-name>.scm). On next open, boost items whose id matches recently-selected IDs to the top of the initial results list (before any query is typed). Store as a simple list of IDs with timestamps, limited to 50 entries per selector.
```

## Overlay auto-sizing

The overlay panel has a fixed width of 340px. Auto-size based on content.

```
Read Sources/Modaliser/Scheme/ui/overlay.scm. The overlay already auto-resizes height via the ResizeObserver in overlay.js. For width, either: 1) change the overlay CSS to use width:auto with min/max-width constraints and let the ResizeObserver report both width and height, updating WebViewManager.resizePanel to handle width changes too, or 2) calculate the needed width in Scheme based on the longest label and set overlay-panel-width dynamically before creating the panel.
```
