# Configuration

This doc covers Modaliser's user-facing DSL: how to define keybindings, organize them into trees, scope them per-app, theme the overlay, build selectors with search, and use the bundled stdlib libraries. For library-system mechanics (splitting configs across files, `sys/` mirror, lookup order) see [user libraries](user-libraries.md). For the full function reference see the [Scheme API](scheme-api.md).

## The config file

On first launch, Modaliser seeds `~/.config/modaliser/config.scm` from a bundled default (`Sources/Modaliser/Scheme/default-config.scm`). On every subsequent launch it loads that user file. Edit it, then pick **Relaunch** from the menu bar icon to apply changes.

`config.scm` is plain Scheme. The bundled libraries are imported R7RS-style:

```scheme
(import (modaliser dsl)
        (modaliser app)
        (modaliser input)
        (modaliser leader)
        (prefix (modaliser apps safari)     safari:)
        (prefix (modaliser apps iterm)      iterm:)
        (prefix (modaliser window-actions)  window:))
```

`(modaliser dsl)` carries the DSL forms (`key`, `group`, `selector`, `action`, `define-tree`). Other libraries surface native primitives (`launch-app`, `send-keystroke`, …) or factory builders (`safari:register!`, `window:actions`). The bundled stdlib uses bare-name exports (`register!`, `actions`, `tree`); import them with `(prefix …)` so call sites read as `<lib>:<verb>` and bare names from different libraries don't collide.

See [user libraries](user-libraries.md) for the full lookup-path / `sys/` story and the complete list of bundled libraries.

## Leader keys

Two leader keys activate two independent command trees:

- **Global** (default F18) — always available.
- **Local** (default F17) — context-sensitive to the focused app.

The newer interface is in `(modaliser leader)`:

```scheme
(import (modaliser leader))

(set-leaders! 'global-keycode F18
              'local-keycode  F17
              'arm-when-frontmost '("com.p5sys.jump.mac.viewer"))
```

`'arm-when-frontmost` lists bundle IDs that suppress leader arming — useful for remote-desktop apps where the modifiers belong to the remote machine.

The older one-leader-at-a-time form is still exported from `(modaliser dsl)`:

```scheme
(set-leader! 'global F18)
(set-leader! 'local  F17)
```

## Commands

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

### Group / define-tree keywords

Both `(group ...)` and `(define-tree ...)` accept optional leading keyword/value pairs before children:

| Keyword | Description |
|---------|-------------|
| `'on-enter THUNK` | Runs when the modal navigates into this group/tree, *and* the overlay panel becomes visible. Does **not** fire when fast keypresses race past the overlay's display delay. |
| `'on-leave THUNK` | Runs when the modal navigates out of this group/tree (or exits) while the overlay is visible. Paired one-for-one with `on-enter`. |
| `'sticky BOOL` | Firing a command leaf at or below this group returns navigation to this group instead of exiting the modal. Composes with sticky ancestors. |
| `'exit-on-unknown BOOL` | Unrecognised keys at or below this group dismiss the modal instead of being swallowed. Useful for sticky focus-movement modes where typing a non-binding key should hand control back to the underlying app. |
| `'renderer SYMBOL` | Picks an overlay renderer for this group. `'diagram` shows the windows-diagram overlay; default is the standard which-key list. |
| `'panels LIST` | Renderer-specific: passed to the chosen renderer. The diagram renderer takes a list of panel-specs. |
| `'dynamic-data-fn THUNK` | Renderer-specific: thunk called on every render to merge live data (e.g. the windows-list with visibility flags) into the renderer payload. |

`(key …)` accepts an optional trailing `'sticky-target MODE-ID` to transition the modal into a named sticky mode after firing. The overlay paints a `↻` marker on the cell so users can see which keys are mode-transitions.

## App-local commands

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

For common apps the bundled stdlib ships factory libraries that build sensible default trees with one call:

```scheme
(import (prefix (modaliser apps safari) safari:)
        (prefix (modaliser apps chrome) chrome:)
        (prefix (modaliser apps iterm)  iterm:))

(safari:register!)              ; defaults
(chrome:register!
  'extra-bindings               ; customise with extra keys
    (list (key "/" "Search" (lambda () (send-keystroke '(cmd) "f")))))
(iterm:register!
  'hint-options                 ; chip styling for the pane chooser
    (list (cons 'background "dodgerblue")))
```

## Theme

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

The host header (a small label at the top of every overlay identifying the current machine) is themed separately:

```scheme
(set-host-header! 'background "dodgerblue")          ; opt-in colour
;; 'name defaults to (run-shell "hostname -s"); 'foreground defaults to
;; "white" when 'background is set.
```

## Overlay delay

The command overlay appears after a configurable delay (default 1 second). Fast key sequences (e.g. leader → s to launch Safari) execute without the overlay ever appearing. Each keystroke resets the timer. Once the overlay has appeared, subsequent navigation within that session updates immediately.

```scheme
(set-overlay-delay! 0.3)         ; seconds (0 = show immediately)
```

`set-overlay-delay!` is re-exported from `(modaliser dsl)`.

## Selectors

Selectors present a searchable chooser UI. Two modes are available.

**Static selectors** load items upfront and fuzzy-match locally:

| Property | Description |
|----------|-------------|
| `'prompt` | Search field placeholder text |
| `'source` | Zero-arg procedure returning a list of alists |
| `'on-select` | One-arg procedure called with the chosen alist |
| `'file-roots` | List of directory paths for file search mode |
| `'actions` | List of `(action …)` forms for the action panel |

**Dynamic selectors** fetch results from external sources on each keystroke:

| Property | Description |
|----------|-------------|
| `'prompt` | Search field placeholder text |
| `'dynamic-search` | One-arg procedure called with the query string on each input |
| `'on-select` | One-arg procedure called with the chosen alist |

The dynamic-search callback is responsible for fetching results and pushing them to the chooser via `(chooser-push-results items)`. Each item is an alist with at least `'text`. A generation counter discards stale responses from earlier queries.

Each choice alist should have at least `text` (display name). Optional: `path`, `kind`, `search-url`.

### File search

Selectors with `'file-roots` use `FileManager.enumerator` to index files and directories in parallel across specified roots. Directories are scanned up to 4 levels deep, skipping common noise directories (`.git`, `node_modules`, `.build`, etc.). Search is fuzzy with path-aware matching.

```scheme
(selector "f" "Find File"
  'prompt "Find file..."
  'file-roots (list "~")
  'on-select (lambda (c)
    (run-shell (string-append "/usr/bin/open \"" (cdr (assoc 'path c)) "\""))))
```

`(modaliser launchers)` ships ready-made selectors that build on this pattern:

```scheme
(import (prefix (modaliser launchers) launcher:))

(define-tree 'global
  (launcher:find-application)    ; ⌥ + a → searchable installed-apps selector
  (launcher:find-file))          ; ⌥ + f → searchable home-dir file selector
```

### Web search

`(modaliser web-search)` packages a Google search selector (autocomplete from Google's Suggest API + pinned "Search Google for '…'" item, opens the selected result in the default browser):

```scheme
(import (prefix (modaliser web-search) web-search:))

(define-tree 'global
  (web-search:google))           ; binds "g" by default; opts to override
```

Suggestions appear after typing 3+ characters. Below that threshold, only the pinned search item is shown.

## Windows-diagram overlay

`(modaliser window-actions)` ships the windows-manager group as a diagrammatic overlay: each direction key sits visually at the screen region it targets, plus Center (inward arrows), Maximise (filled cell), a Named selector, a numbered window picker (1..) that paints chips on the actual on-screen windows, and Restore.

Minimal call uses the defaults:

```scheme
(import (prefix (modaliser window-actions) window:))

(define-tree 'global
  (window:actions))              ; binds "w"; full default layout
```

Customise by overriding the panels matrix or chip styling:

```scheme
(window:actions
  'panels (list
    (window:divisions '(("d" "f" "g")))                ; full thirds
    (window:divisions '(("D" "F" "G") ("C" "V" "B")))  ; half thirds
    (window:divisions '(("e" "e" #f)))                 ; left two-thirds
    (window:divisions '((#f "t" "t")))                 ; right two-thirds
    (window:divisions '(("m")))                        ; maximise (full cell)
    (window:center-panel "c"))                         ; center (inward arrows)
  'chip-options (list (cons 'background "dodgerblue")))
```

The numbered chips (1..0) are placed at the top-left of each on-screen window. Each chip's background is saturated when the window is visible at the chip's anchor point and desaturated when occluded — translucent overlay utilities (HazeOver, f.lux) are skipped in the visibility test so they don't falsely dim chips. Window-number assignment is deterministic by (y, x) position so the same arrangement always produces the same digits across leader presses.

## AX hint flows

`(modaliser ax-hints)` provides generic primitives for "see a chip, type a letter, focus that thing" UX over any AX-introspectable app — used by `(modaliser apps iterm)` and reusable for any other app:

```scheme
(import (modaliser ax-hints)
        (modaliser hints))

(define iterm-pane-labels
  (list "a" "s" "d" "f" "g" ";" "q" "w" "e" "r" "t" "y" "u" "i" "o" "p"))

(define iterm-pane-hint-options
  (list (cons 'font-size 56) (cons 'padding 16)
        (cons 'color "#cc0000") (cons 'background "#ffffff")))

(define (rebuild-iterm-tree!)
  (let ((panes (ax-find-labelled "com.googlecode.iterm2" "AXScrollArea"
                                  iterm-pane-labels)))
    (apply define-tree 'com.googlecode.iterm2
      'on-enter (lambda () (hints-show (ax-target-hints panes iterm-pane-hint-options)))
      'on-leave (lambda () (hints-hide))
      (append
        (ax-target-bindings panes "Pane " ax-click-handle)
        (list (key "z" "Toggle Zoom" (lambda () (send-keystroke '(cmd shift) "return"))))))))

;; Re-fire on every leader press so the tree tracks live layout changes.
(set-local-context-suffix!
  (lambda (bundle-id)
    (when (equal? bundle-id "com.googlecode.iterm2") (rebuild-iterm-tree!))
    #f))

(rebuild-iterm-tree!)  ;; pre-register so lookups succeed before first leader
```

The same pattern works for Safari tabs (`role = "AXTab"`), Finder windows, etc. — only the bundle-id, role, and static keys change. See `(modaliser apps iterm)` source for the production version of this pattern.
