# Modaliser

> Scheme-scriptable modal keyboard system for macOS.

---

Press a leader key to enter a command tree, then type key sequences to execute actions -- launch apps, manage windows, run shell commands, search files, and more.

Configuration is written in Scheme (via [LispKit](https://github.com/objecthub/swift-lispkit)). The config file is code: actions are lambdas, and users can define helper functions inline.

## Architecture

Modaliser is a native Swift macOS app, but the majority of its logic lives in Scheme. On launch, Swift creates a LispKit Scheme runtime and loads `root.scm`, which bootstraps the entire application: activation policy, permissions, status bar, keyboard capture, and user config.

The UI is rendered in WKWebView-backed NSPanels controlled from Scheme. Two panel types exist:

- **Overlay** -- a non-activating floating panel showing available keybindings at the current position in the command tree (which-key style)
- **Chooser** -- an activating panel with a search input, fuzzy-filtered result list, and optional action panel (used by selectors)

Swift provides native libraries that Scheme calls into: keyboard capture, window management, app management, shell execution, clipboard, input emulation, fuzzy matching, clipboard history, WebView management, and app lifecycle.

Incremental DOM updates use a Display PostScript-inspired pattern: Scheme builds data, pushes JSON to JavaScript, and JS renders directly into the DOM. Full-page HTML replacement is avoided except for structural changes like toggling the action panel.

## Requirements

- macOS 14+
- Swift 5.9+ / Xcode 15+
- Accessibility permissions (for global keyboard capture)
- Screen Recording permissions (for reading window titles)

## Install

```bash
./scripts/build-app.sh    # builds .build/release/Modaliser.app
./scripts/install.sh      # builds and copies to /Applications
```

The build script code-signs with a "Modaliser Dev" certificate if available (preserves Accessibility TCC permissions across rebuilds), otherwise falls back to ad-hoc signing.

For development:

```bash
swift build
swift test
.build/debug/Modaliser
```

On first launch, macOS will prompt for Accessibility and Screen Recording permissions. The app runs as an accessory (no dock icon) with a menu bar icon.

## Configuration

On launch, Modaliser loads `~/.config/modaliser/config.scm` if it exists. Edit this file, then use **Relaunch** from the menu bar icon to apply changes.

You can also click **Settings** from the menu bar to open the config file directly.

### Leader Keys

Two leader keys activate two independent command trees:

- **F18** -- Global commands (always available)
- **F17** -- App-local commands (context-sensitive to the focused app)

```scheme
(set-leader! 'global F18)
(set-leader! 'local F17)
```

### Commands

Three types of command nodes: **keys** (execute an action), **groups** (contain children), and **selectors** (open a searchable chooser).

```scheme
(define-tree 'global

  ;; Key: press "s" to launch Safari
  (key "s" "Safari"
    (lambda () (launch-app "Safari")))

  ;; Group: press "w" to enter the Windows group
  (group "w" "Windows"
    (key "c" "Center" (lambda () (center-window)))
    (key "m" "Maximise" (lambda () (toggle-fullscreen)))
    (key "d" "First Third" (lambda () (move-window 0 0 1/3 1))))

  ;; Selector: press "f" then "a" to search apps
  (group "f" "Find"
    (selector "a" "Find Apps"
      'prompt "Find app..."
      'source find-installed-apps
      'on-select activate-app
      'actions
        (list
          (action "Open" 'key 'primary
            'run (lambda (c) (activate-app c)))
          (action "Show in Finder" 'key 'secondary
            'run (lambda (c) (reveal-in-finder c)))))))
```

### App-Local Commands

Define trees scoped to specific apps using their bundle ID. These activate when pressing the local leader key while that app is focused.

```scheme
(define (keystroke mods key-name)
  (lambda () (send-keystroke mods key-name)))

(define-tree 'com.apple.Safari
  (group "t" "Tabs"
    (key "n" "New Tab" (keystroke '(cmd) "t"))
    (key "w" "Close Tab" (keystroke '(cmd) "w"))))

(define-tree 'dev.zed.Zed
  (group "p" "Pane"
    (key "h" "Focus Left" (keystroke '(cmd alt) "left"))
    (key "l" "Focus Right" (keystroke '(cmd alt) "right"))))
```

### Theme

The UI is styled with CSS custom properties defined in `base.css`. Users can override styles by calling `(set-overlay-css! css-string)` in their config:

```scheme
(set-overlay-css! "
  :root {
    --overlay-bg: rgba(30, 30, 35, 1);
    --color-label: rgba(220, 220, 220, 1);
    --color-key: rgba(100, 160, 255, 1);
    --color-group: rgba(255, 180, 80, 1);
  }
")
```

### Selectors

Selectors present a searchable chooser UI with fuzzy matching. Options:

| Property | Description |
|----------|-------------|
| `'prompt` | Search field placeholder text |
| `'source` | Zero-arg procedure returning a list of alists |
| `'on-select` | One-arg procedure called with the chosen alist |
| `'file-roots` | List of directory paths for file search mode |
| `'actions` | List of `(action ...)` forms for the action panel |

Each choice alist should have at least `text` (display name). Optional: `subText`, `icon`, `iconType` (`"path"` or `"bundleId"`), `path`, `kind`.

### File Search

Selectors with `'file-roots` use `FileManager.enumerator` to index files and directories in parallel across specified roots. Directories are scanned up to 4 levels deep, skipping common noise directories (.git, node_modules, .build, etc.). Search is fuzzy with path-aware matching.

```scheme
(selector "f" "Find File"
  'prompt "Find file..."
  'file-roots (list "~")
  'on-select (lambda (c) (run-shell (string-append "/usr/bin/open \"" (cdr (assoc 'path c)) "\""))))
```

## Available Scheme Functions

### DSL (auto-imported)

| Function | Description |
|----------|-------------|
| `(key k label action)` | Define a command |
| `(group k label children...)` | Define a group |
| `(selector k label props...)` | Define a selector |
| `(action name props...)` | Define a selector action |
| `(define-tree scope children...)` | Register a command tree |
| `(set-leader! mode keycode)` | Set leader key for a mode |
| `(set-overlay-css! css-string)` | Inject custom CSS after base styles |
| `F17` `F18` `F19` `F20` | Key code constants |
| `ESCAPE` `DELETE` `RETURN` `TAB` `SPACE` | Key code constants |
| `UP` `DOWN` `LEFT` `RIGHT` | Arrow key code constants |

### App Management -- `(modaliser app)`

| Function | Description |
|----------|-------------|
| `(find-installed-apps)` | Scan installed apps via Spotlight, returns list of alists |
| `(activate-app alist)` | Launch/focus app from choice alist |
| `(launch-app name)` | Launch/focus app by name or bundle ID |
| `(reveal-in-finder alist)` | Show in Finder from choice alist |
| `(open-with app-name path)` | Open file with specific app |
| `(open-url url-string)` | Open URL in default handler |
| `(focused-app-bundle-id)` | Get bundle ID of the frontmost app |
| `(index-files root-paths)` | Scan directories, returns list of alists with text/path/kind |

### Window Management -- `(modaliser window)`

| Function | Description |
|----------|-------------|
| `(list-windows)` | List visible windows as alists |
| `(focus-window alist)` | Focus a window from choice alist |
| `(center-window)` | Center the focused window |
| `(move-window x y w h)` | Move to unit rect (0.0-1.0 fractions of screen) |
| `(toggle-fullscreen)` | Toggle fullscreen on focused window |
| `(restore-window)` | Restore to saved frame |

### Input -- `(modaliser input)`

| Function | Description |
|----------|-------------|
| `(send-keystroke mods key)` | Emit a keystroke. mods: `'(cmd alt shift ctrl)`, key: `"t"`, `"left"`, etc. |

### Shell -- `(modaliser shell)`

| Function | Description |
|----------|-------------|
| `(run-shell command)` | Run via `/bin/zsh -c`, returns stdout |
| `(run-shell-async command callback)` | Run in background, callback receives `(exit-code stdout stderr)` |

### Clipboard -- `(modaliser pasteboard)`

| Function | Description |
|----------|-------------|
| `(get-clipboard)` | Read clipboard as string |
| `(set-clipboard! text)` | Write string to clipboard |

### Clipboard History -- `(modaliser clipboard-history)`

The Swift primitives for clipboard history exist but the clipboard monitor is not yet started at runtime. See TODO.md for wiring instructions.

| Function | Description |
|----------|-------------|
| `(get-clipboard-history)` | Get clipboard history entries as alists |
| `(clear-clipboard-history!)` | Clear all history |
| `(restore-clipboard-entry! id)` | Restore a history entry to the clipboard |
| `(set-clipboard-exclude! bundle-ids)` | Exclude apps from clipboard monitoring |
| `(set-clipboard-history-limit! n)` | Set max history entries |

### Lifecycle -- `(modaliser lifecycle)`

| Function | Description |
|----------|-------------|
| `(set-activation-policy! policy)` | Set app activation policy (`'regular`, `'accessory`, `'prohibited`) |
| `(create-status-item! title menu-items)` | Create a menu bar item |
| `(request-accessibility!)` | Request Accessibility permissions |
| `(request-screen-recording!)` | Request Screen Recording permissions |
| `(relaunch!)` | Relaunch the application |
| `(quit!)` | Quit the application |

### WebView -- `(modaliser webview)`

| Function | Description |
|----------|-------------|
| `(webview-create id options)` | Create a WKWebView-backed NSPanel |
| `(webview-close id)` | Close and destroy a panel |
| `(webview-set-html! id html)` | Set full HTML content |
| `(webview-eval id js)` | Evaluate JavaScript in a panel |
| `(webview-on-message id handler)` | Register a message handler for JS postMessage |
| `(webview-set-style! id css)` | Inject or replace a dynamic style block |

### Fuzzy Matching -- `(modaliser fuzzy)`

| Function | Description |
|----------|-------------|
| `(fuzzy-match query target)` | Match query against target, returns `(score (indices...))` or `#f` |
| `(fuzzy-filter query texts)` | Filter and rank a list of strings by fuzzy match score |

## Keyboard Reference

### Modal Navigation

| Key | Action |
|-----|--------|
| F18 | Toggle global modal |
| F17 | Toggle app-local modal |
| Escape | Exit modal |
| Delete | Step back one level |
| Any letter/digit | Execute command or descend into group |

### Chooser

| Key | Action |
|-----|--------|
| Up/Down | Navigate items |
| Return | Select (primary action) |
| Cmd+Return | Secondary action |
| Tab | Toggle action panel |
| Escape | Cancel |

## Menu Bar

The menu bar icon provides:

- **Settings** -- Open config.scm in default editor
- **Relaunch** -- Restart the application (applies config changes)
- **Quit Modaliser**

## License

Apache License 2.0 -- see [LICENSE](LICENSE) for details.
