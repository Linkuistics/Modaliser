# Modaliser

> Scheme-scriptable modal keyboard system for macOS.

---

Press a leader key to enter a command tree, then type key sequences to execute actions -- launch apps, manage windows, run shell commands, search files, and more.

Configuration is written in Scheme (via [LispKit](https://github.com/objecthub/swift-lispkit)). The config file is code: actions are lambdas, and users can define helper functions inline.

## Architecture

Modaliser is a native Swift macOS app, but the majority of its logic lives in Scheme. On launch, Swift creates a LispKit Scheme runtime and loads `root.scm`, which bootstraps the entire application: activation policy, permissions, status bar, keyboard capture, and user config.

The UI is rendered in WKWebView-backed NSPanels controlled from Scheme. Two panel types exist:

- **Overlay** -- a non-activating floating panel showing available keybindings at the current position in the command tree (which-key style)
- **Chooser** -- an activating panel with a search input, fuzzy-filtered result list, and optional action panel (used by selectors). Supports both static sources (fuzzy-matched locally) and dynamic sources (results fetched from external APIs)

Swift provides native libraries that Scheme calls into: keyboard capture, window management, app management, shell execution, HTTP requests, clipboard, input emulation, fuzzy matching, clipboard history, WebView management, and app lifecycle.

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

On first launch, Modaliser presents an onboarding window for Accessibility (with a deep-link button into System Settings, polling for the grant and auto-relaunching when it lands) and then triggers macOS's native Screen Recording prompt (which has its own Open System Settings affordance and Quit & Reopen flow). After both are granted, the app runs as an accessory (no Dock icon) with a menu bar icon.

## Configuration

On first launch, Modaliser seeds `~/.config/modaliser/config.scm` from a bundled default (`Sources/Modaliser/Scheme/default-config.scm`). On every launch it loads that user file. Edit it, then use **Relaunch** from the menu bar icon to apply changes.

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

Selectors present a searchable chooser UI. Two modes are available:

**Static selectors** load items upfront and fuzzy-match locally:

| Property | Description |
|----------|-------------|
| `'prompt` | Search field placeholder text |
| `'source` | Zero-arg procedure returning a list of alists |
| `'on-select` | One-arg procedure called with the chosen alist |
| `'file-roots` | List of directory paths for file search mode |
| `'actions` | List of `(action ...)` forms for the action panel |

**Dynamic selectors** fetch results from external sources on each keystroke:

| Property | Description |
|----------|-------------|
| `'prompt` | Search field placeholder text |
| `'dynamic-search` | One-arg procedure called with the query string on each input |
| `'on-select` | One-arg procedure called with the chosen alist |

The dynamic-search callback is responsible for fetching results and pushing them to the chooser via `(chooser-push-results items)`. Each item is an alist with at least `'text`. A generation counter discards stale responses from earlier queries.

Each choice alist should have at least `text` (display name). Optional: `path`, `kind`, `search-url`.

### File Search

Selectors with `'file-roots` use `FileManager.enumerator` to index files and directories in parallel across specified roots. Directories are scanned up to 4 levels deep, skipping common noise directories (.git, node_modules, .build, etc.). Search is fuzzy with path-aware matching.

```scheme
(selector "f" "Find File"
  'prompt "Find file..."
  'file-roots (list "~")
  'on-select (lambda (c) (run-shell (string-append "/usr/bin/open \"" (cdr (assoc 'path c)) "\""))))
```

### Web Search

A built-in Google search selector is available via `web-search-handler` and `web-search-on-select`. It fetches autocomplete suggestions from Google's Suggest API, prepends a pinned "Search Google for '...'" item, and opens the selected result in the default browser.

```scheme
(selector "g" "Google Search"
  'prompt "Search Google…"
  'dynamic-search web-search-handler
  'on-select web-search-on-select)
```

Suggestions appear after typing 3+ characters. Below that threshold, only the pinned search item is shown.

## Available Scheme Functions

### DSL (auto-imported)

| Function | Description |
|----------|-------------|
| `(key k label action)` | Define a command |
| `(group k label [keyword value]... children...)` | Define a group |
| `(selector k label props...)` | Define a selector |
| `(action name props...)` | Define a selector action |
| `(define-tree scope [keyword value]... children...)` | Register a command tree |
| `(set-leader! mode keycode)` | Set leader key for a mode |
| `(set-overlay-css! css-string)` | Inject custom CSS after base styles |
| `F17` `F18` `F19` `F20` | Key code constants |
| `ESCAPE` `DELETE` `RETURN` `TAB` `SPACE` | Key code constants |
| `UP` `DOWN` `LEFT` `RIGHT` | Arrow key code constants |

Both `(group ...)` and `(define-tree ...)` accept optional leading keyword/value pairs before children:

| Keyword | Description |
|---------|-------------|
| `'on-enter THUNK` | Runs when the modal navigates into this group/tree, *and* the overlay panel becomes visible. Does **not** fire when fast keypresses race past the overlay's display delay. |
| `'on-leave THUNK` | Runs when the modal navigates out of this group/tree (or exits) while the overlay is visible. Paired one-for-one with `on-enter`. |

Useful for showing/hiding ancillary UI (e.g. pane-hint chips) that should accompany the overlay.

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

### HTTP -- `(modaliser http)`

| Function | Description |
|----------|-------------|
| `(http-get url callback)` | Async HTTP GET. Calls `(callback response-string)` on success, `(callback #f)` on error |

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
| `(ensure-permissions! perms)` | Block until each TCC permission in the list is granted. Pollable permissions (e.g. `accessibility`) are surfaced via an in-app onboarding panel; cached ones (`screen-recording`) are handed off to macOS's native prompt |
| `(relaunch!)` | Relaunch the application |
| `(quit!)` | Quit the application |
| `(after-delay seconds callback)` | Call `(callback)` on the main thread after a delay |

### WebView -- `(modaliser webview)`

| Function | Description |
|----------|-------------|
| `(webview-create id options)` | Create a WKWebView-backed NSPanel |
| `(webview-close id)` | Close and destroy a panel |
| `(webview-set-html! id html)` | Set full HTML content |
| `(webview-eval id js)` | Evaluate JavaScript in a panel |
| `(webview-on-message id handler)` | Register a message handler for JS postMessage |
| `(webview-set-style! id css)` | Inject or replace a dynamic style block |

### Hints -- `(modaliser hints)`

Generic on-screen labels drawn at arbitrary screen rectangles. Used today for iTerm pane chips; the library itself is app-agnostic and reusable for any future "pick one of these visible targets" flow.

| Function | Description |
|----------|-------------|
| `(hints-show hint-list)` | Open one transparent floating panel per entry. Each entry is an alist with required `'label`, `'x`, `'y`, `'w`, `'h` (AX coords, top-left origin) and optional `'color`, `'background`, `'font-size`, `'padding`, `'corner-radius`, `'border-width`, `'border-color` |
| `(hints-hide)` | Close all hint panels |

### Accessibility -- `(modaliser accessibility)`

Macros around the macOS Accessibility API for cases where Scheme needs to round-trip element references (e.g. "find these elements, then later click one"). Element pointers are stored in a Swift-side cache keyed by integer handle; each `ax-find-elements` call invalidates prior handles.

| Function | Description |
|----------|-------------|
| `(ax-find-elements bundle-id role)` | Walk the AX tree of `bundle-id`'s focused window. Returns a list of alists `((handle . N) (x . N) (y . N) (w . N) (h . N))` for every descendant whose AXRole equals `role`, sorted top-to-bottom then left-to-right. Returns `()` if the app isn't running |
| `(ax-click-handle handle)` | Activate the handle's owning app and synthesize a left-click at the centre of the handle's frame. Cursor position is saved and warped back. No-op for stale handles |

### AX hint flows -- `lib/ax-hints.scm`

Auto-loaded. Generic primitives for "see a chip, type a letter, focus that thing" UX over any AX-introspectable app — used by the bundled iTerm tree and reusable for any other app.

| Function/Variable | Description |
|-------------------|-------------|
| `(ax-find-labelled bundle-id role labels)` | Probe AX for elements of `role` inside `bundle-id`'s focused window, pair them with `labels` in reading order. Returns `((label . elem-alist) ...)`. Truncates at the shorter of the two lists |
| `(ax-target-bindings labelled-elements label-prefix action-fn)` | Convert that list into `(key ...)` entries. Each fires `(action-fn handle)` where handle is the AX handle from the elem alist. Display label = `label-prefix ++ label` |
| `(ax-target-hints labelled-elements opts)` | Convert that list into the alist shape `hints-show` consumes. `opts` is an alist of chip appearance (offset, size, colour, padding, border) — see `default-hint-options` for the shape |
| `default-hint-options` | Sensible smallish defaults. Override per-tree by passing your own opts alist |

End-to-end pattern (from `default-config.scm`):

```scheme
(define iterm-pane-labels
  (list "a" "s" "d" "f" "g" ";" "q" "w" "e" "r" "t" "y" "u" "i" "o" "p"))

(define iterm-pane-hint-options
  (list (cons 'font-size 56) (cons 'padding 16)
        (cons 'color "#cc0000") (cons 'background "#ffffff") ...))

(define (rebuild-iterm-tree!)
  (let ((panes (ax-find-labelled "com.googlecode.iterm2" "AXScrollArea"
                                  iterm-pane-labels)))
    (apply define-tree 'com.googlecode.iterm2
      'on-enter (lambda () (hints-show (ax-target-hints panes iterm-pane-hint-options)))
      'on-leave (lambda () (hints-hide))
      (append
        (ax-target-bindings panes "Pane " ax-click-handle)
        (list (key "z" "Toggle Zoom" (keystroke '(cmd shift) "return")) ...)))))

;; Re-fire on every leader press so the tree tracks live layout changes.
(define (local-context-suffix bundle-id)
  (when (equal? bundle-id "com.googlecode.iterm2") (rebuild-iterm-tree!))
  #f)

(rebuild-iterm-tree!)  ;; pre-register so lookups succeed before first leader
```

Same pattern works for Safari tabs (`role = "AXTab"`), Finder windows, etc. — only the bundle-id, role, and static keys change.

### Fuzzy Matching -- `(modaliser fuzzy)`

| Function | Description |
|----------|-------------|
| `(fuzzy-match query target)` | Match query against target, returns `(score (indices...))` or `#f` |
| `(fuzzy-filter query texts)` | Filter and rank a list of strings by fuzzy match score |

### Dynamic Chooser (auto-imported)

| Function | Description |
|----------|-------------|
| `(chooser-push-results items)` | Push a list of item alists to the open chooser |

### Web Search (auto-imported)

| Function | Description |
|----------|-------------|
| `(web-search-handler query)` | Dynamic-search callback for Google autocomplete |
| `(web-search-on-select item)` | Opens the selected search result in the default browser |
| `(google-suggest-url query)` | Build Google Suggest API URL |
| `(google-search-url query)` | Build Google search URL |
| `(parse-google-suggestions response)` | Parse Google Suggest JSON into a list of strings |
| `(build-web-search-results query suggestions)` | Build chooser items with pinned search item |
| `(url-encode str)` | RFC 3986 percent-encoding with UTF-8 support |

### Overlay Delay

The command overlay appears after a configurable delay (default 1 second). This allows fast key sequences (e.g. leader → s to launch Safari) to execute without the overlay ever appearing. Each keystroke resets the timer. Once the overlay has appeared, subsequent navigation within that session updates immediately.

```scheme
(set! modal-overlay-delay 0.5)  ;; seconds (0 = show immediately)
```

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
