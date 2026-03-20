# Modaliser

A Scheme-scriptable modal keyboard system for macOS. Press a leader key to enter a command tree, then type key sequences to execute actions — launch apps, manage windows, search files, and more.

Replaces Hammerspoon with a standalone native Swift app. Configuration and actions are defined in Scheme (via [LispKit](https://github.com/objecthub/swift-lispkit)), so the config file IS code — actions are lambdas, and users can define helper functions inline.

## Requirements

- macOS 14+
- Swift 5.9+ / Xcode 15+
- Accessibility permissions (for global keyboard capture)
- [`fd`](https://github.com/sharkdp/fd) (optional, for file search)

## Install

```bash
./scripts/build-app.sh    # builds .build/release/Modaliser.app
./scripts/install.sh      # builds and copies to /Applications
```

For development:

```bash
swift build
swift test
.build/debug/Modaliser
```

On first launch, macOS will prompt for Accessibility permissions. The app runs as an accessory (no dock icon) with a `⌨` menu bar icon.

## Configuration

On first launch, Modaliser creates `~/.config/modaliser/config.scm` with a starter config. Edit this file, then use **Reload Config** from the menu bar icon to apply changes.

You can also click **Reveal Config in Finder** from the menu bar to open the config directory.

### Leader Keys

Two leader keys activate two independent command trees:

- **F18** — Global commands (always available)
- **F17** — App-local commands (context-sensitive to the focused app)

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
      'remember "apps"
      'id-field "bundleId"
      'actions
        (list
          (action "Open" 'key 'primary
            'run (lambda (c) (activate-app c)))
          (action "Show in Finder" 'key 'secondary
            'run (lambda (c) (reveal-in-finder c)))))))
```

### App-Local Commands

Define trees scoped to specific apps using their bundle ID. These activate when pressing F17 while that app is focused.

```scheme
;; Helper for keystroke emulation
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

```scheme
(set-theme!
  'font "Menlo"
  'font-size 15
  'bg '(0.12 0.12 0.14)
  'fg '(0.85 0.85 0.85)
  'accent '(0.4 0.6 1.0)
  'show-delay 0.3)
```

### Selectors

Selectors present a searchable chooser UI. Options:

| Property | Description |
|----------|-------------|
| `'prompt` | Search field placeholder text |
| `'source` | Zero-arg procedure returning a list of alists |
| `'on-select` | One-arg procedure called with the chosen alist |
| `'remember` | Name for search memory persistence |
| `'id-field` | Alist key used as the ID for search memory |
| `'actions` | List of `(action ...)` forms for the action panel |
| `'file-roots` | List of directory paths for file search mode |

Each choice alist should have at least `text` (display name). Optional: `subText`, `icon`, `iconType` (`"path"` or `"bundleId"`).

### File Search

Selectors with `'file-roots` use `fd` to index files in the background. The chooser starts empty and populates as indexing completes. Search is fuzzy with path-aware matching — typing `/` enables matching against the full path.

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
| `(set-leader! mode keycode)` | Set leader key |
| `(set-theme! props...)` | Set overlay/chooser theme |
| `F17` `F18` `F19` `F20` | Key code constants |

### App Management — `(modaliser app)`

| Function | Description |
|----------|-------------|
| `(find-installed-apps)` | Scan /Applications, returns list of alists |
| `(activate-app alist)` | Launch/focus app from choice alist |
| `(launch-app name)` | Launch/focus app by name |
| `(reveal-in-finder alist)` | Show in Finder from choice alist |
| `(open-with app-name path)` | Open file with specific app |
| `(open-url url-string)` | Open URL in default handler |

### Window Management — `(modaliser window)`

| Function | Description |
|----------|-------------|
| `(list-windows)` | List visible windows as alists |
| `(focus-window alist)` | Focus a window from choice alist |
| `(center-window)` | Center the focused window |
| `(move-window x y w h)` | Move to unit rect (0.0-1.0 fractions) |
| `(toggle-fullscreen)` | Toggle fullscreen on focused window |
| `(restore-window)` | Restore to saved frame |

### Input — `(modaliser input)`

| Function | Description |
|----------|-------------|
| `(send-keystroke mods key)` | Emit a keystroke. mods: `'(cmd alt shift ctrl)`, key: `"t"`, `"left"`, etc. |

### Shell — `(modaliser shell)`

| Function | Description |
|----------|-------------|
| `(run-shell command)` | Run via `/bin/zsh -c`, returns stdout |

### Clipboard — `(modaliser pasteboard)`

| Function | Description |
|----------|-------------|
| `(get-clipboard)` | Read clipboard as string |
| `(set-clipboard! text)` | Write string to clipboard |

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
| Cmd+K | Open action panel |
| Cmd+1-9 | Select by index |
| Escape | Cancel |
| Delete (in actions) | Back to results |

## Menu Bar

The `⌨` menu provides:

- **Reload Config** — Re-evaluate config.scm without restarting
- **Reveal Config in Finder** — Open the config directory
- **Launch at Login** — Toggle auto-start
- **Quit Modaliser**

## License

Private project.
