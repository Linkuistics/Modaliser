# Modaliser Phase 2 Design Spec

Implement five features plus app icon integration to extend Modaliser with clipboard history, quicklinks/snippets selectors, overlay performance improvements, async shell commands, and a full Scheme-based state machine.

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Sequencing | Foundation-first | Build infrastructure before features that depend on it |
| Data persistence | S-expr files (metadata), directories (binary) | Keeps everything in the Lisp ecosystem; LispKit read/write for free |
| Clipboard storage | Hybrid: s-expr index + per-entry directories for all UTI types | Supports images, rich text, files -- not just strings |
| Clipboard exclusion | App-based via bundle ID | FocusedAppObserver already tracks frontmost app |
| Quicklinks/Snippets source | User-edited `.scm` config files | Transparent, version-controllable; future in-app editor out of scope |
| `define-app-tree` | Dropped | "Copy bundle ID" action already exists in app finder chooser |
| Overlay update | Panel reuse with in-place subview update | Smoothness and performance |
| Async shell | Callback lambda | Idiomatic Scheme, matches existing DSL patterns |
| State machine | Full Scheme reimplementation | Maximum scripting control; Swift becomes thin event bridge |

## Implementation Order

1. App icon
2. Overlay in-place update
3. Async `run-shell` with timeout
4. Quicklinks & Snippets selectors
5. Clipboard history
6. State machine in Scheme

---

## 1. App Icon Integration

Add a 1024x1024 PNG icon to the project. Extend `build-app.sh` to generate `.icns` via `iconutil` and copy it into `Contents/Resources/`. Add `CFBundleIconFile` to `Info.plist`.

**Files touched:**
- `Info.plist` -- add `CFBundleIconFile` key
- `scripts/build-app.sh` -- generate `.icns`, copy to bundle
- `Resources/AppIcon.png` -- user-provided source image
- `Resources/AppIcon.iconset/` -- generated intermediate (gitignored)

**Process:** PNG -> `sips` to resize to all required sizes -> `iconutil --convert icns` -> copy to `.app/Contents/Resources/`

---

## 2. Overlay In-Place Update

Refactor `OverlayPanel` to reuse the NSPanel instance and update content in-place instead of destroying and recreating the panel on every navigation.

**Architecture:**
- `OverlayPanel` gains a persistent `panel: NSPanel?` and `containerView: NSView?` that survive across navigations
- The existing `showOverlay(content:theme:)` method is modified: when `panel` already exists, it updates content in-place rather than calling `dismiss()` and recreating everything. The `OverlayPresenting` protocol and `OverlayCoordinator` remain unchanged -- the coordinator already calls `showOverlay` for both initial display and updates.
- `dismissOverlay()` tears down the panel as before

**Key details:**
- Use `CATransaction.begin()` / `commit()` to batch subview changes and avoid intermediate render frames (eliminates flicker)
- Recalculate `OverlayLayout` on each update since entry count may change between groups
- Reposition panel on screen if height changes (maintain screen-center or anchor point)
- The renderers (`OverlayHeaderRenderer`, `OverlayEntryRenderer`, `OverlayFooterRenderer`) are already stateless -- they produce NSViews from data. No renderer changes needed; we just call them within the existing container instead of a new one.

**Testing:**
- Extend `OverlayCoordinatorTests` to verify overlay updates without dismiss/recreate cycle
- Test panel resize when navigating from a group with 3 entries to one with 7

---

## 3. Async `run-shell` with Timeout

Add `run-shell-async` to `ShellLibrary` -- runs a shell command on a background thread and invokes a Scheme callback lambda with the result. Optional timeout.

**Scheme interface:**
```scheme
;; Existing sync (unchanged)
(run-shell "echo hello")  ; -> "hello\n"

;; New async with callback
(run-shell-async "sleep 2 && echo done"
  (lambda (exit-code stdout stderr) ...))

;; With timeout (seconds)
(run-shell-async "long-command"
  (lambda (exit-code stdout stderr) ...)
  'timeout 10)
```

On timeout, the process is killed (SIGTERM) and the callback receives exit-code `-1`, empty stdout, and `"timeout"` as stderr.

**Architecture:**
- `ShellLibrary` registers `run-shell-async` as a new native function (`native2R` -- command + callback + optional rest args for timeout)
- Process runs on a `DispatchQueue.global()` background thread
- Stdout and stderr captured via separate `Pipe` instances
- On completion/timeout, callback is dispatched to main thread via `DispatchQueue.main.async`
- Callback invocation: `machine.apply(callbackProc, to: .pair(exitCode, .pair(stdout, .pair(stderr, .null))))`
- The `SchemeEngine`'s `VirtualMachine` reference is needed to invoke the callback -- `ShellLibrary` already holds a `Context` reference via the NativeLibrary pattern

**Risks & mitigations:**
- Thread safety of LispKit evaluator -- all callback invocations marshalled to main thread. If LispKit's `VirtualMachine.apply` isn't safe to call from `DispatchQueue.main.async`, we may need to use the existing `Context.evaluator` entry point. Needs testing early.
- Process leak -- track active processes in a `Set<Process>` on `ShellLibrary`; terminate all on app quit.

**Testing:**
- Unit test: sync `run-shell` still works (regression)
- Unit test: `run-shell-async` with a fast command, verify callback receives correct exit code and output
- Unit test: timeout triggers, verify callback receives `-1` exit code and `"timeout"` stderr
- Integration test: verify callback executes on main thread

---

## 4. Quicklinks & Snippets Selectors

Two new selector types backed by user-edited `.scm` config files. Each file contains a list of s-expression entries. New Scheme functions load and expose them as selector sources.

**Data format -- `~/.config/modaliser/quicklinks.scm`:**
```scheme
(((name . "GitHub") (url . "https://github.com") (icon . "globe") (tags "dev"))
 ((name . "Mail") (url . "https://mail.google.com") (icon . "envelope") (tags "comms"))
 ((name . "CI Dashboard") (url . "https://ci.example.com") (tags "dev" "ops")))
```

**Data format -- `~/.config/modaliser/snippets.scm`:**
```scheme
(((name . "Email Greeting") (content . "Hi,\n\nThanks for your message.\n\nBest,\nAntony") (tags "email"))
 ((name . "Date Stamp") (content . "{{date}}") (tags "utility"))
 ((name . "Bug Template") (content . "## Steps to reproduce\n\n## Expected\n\n## Actual\n") (tags "dev")))
```

Note: Data uses standard R7RS alists (dotted pairs) so they work directly with `assoc` and are compatible with `SelectorSourceInvoker`'s expected format. The libraries transform `name` into the `text` key expected by the chooser system.

**Scheme interface:**
```scheme
(get-quicklinks)              ; -> list of alists
(get-quicklinks 'tag "dev")   ; -> filtered by tag

(get-snippets)
(get-snippets 'tag "email")

;; Template expansion for snippets
(expand-snippet "{{date}} -- {{clipboard}}")  ; -> "2026-03-20 -- <clipboard content>"
```

**Supported template placeholders (initial set):**
- `{{date}}` -- current date (ISO format)
- `{{time}}` -- current time
- `{{datetime}}` -- date and time
- `{{clipboard}}` -- current clipboard content

**Architecture:**
- New `QuicklinksLibrary` -- NativeLibrary following existing pattern. Reads and parses the `.scm` file on each call (files are small, no caching needed). Registers `get-quicklinks`. Transforms `name` to `text` key for chooser compatibility.
- New `SnippetsLibrary` -- Same pattern. Registers `get-snippets` and `expand-snippet`. Template expansion is a simple string-replace pass over known placeholders.
- Both return lists of alists that the existing `SelectorSourceInvoker` already knows how to marshal into `ChooserChoice` items.

**User config usage:**
```scheme
(selector "q" "Quicklinks"
  'prompt "Open link"
  'source (lambda () (get-quicklinks))
  'on-select (lambda (link) (open-url (cdr (assoc 'url link)))))

(selector "s" "Snippets"
  'prompt "Paste snippet"
  'source (lambda () (get-snippets))
  'on-select (lambda (snip)
    (set-clipboard! (expand-snippet (cdr (assoc 'content snip))))
    (send-keystroke '(cmd) "v")))
```

**Testing:**
- Unit tests for s-expr file parsing (valid, empty, malformed)
- Unit tests for tag filtering
- Unit tests for `expand-snippet` with each placeholder type
- Integration test: round-trip from `.scm` file -> `get-quicklinks` -> ChooserChoice list

---

## 5. Clipboard History

Background monitoring of NSPasteboard changes, storing all pasteboard types (text, images, rich text, files) with metadata. Chooser selector for recall.

**Storage structure:**
```
~/.config/modaliser/clipboard-history/
  index.scm              ; s-expr metadata index
  entries/
    0001/
      public.utf8-plain-text    ; raw text
      public.png                ; image data
      public.rtf                ; rich text
    0002/
      public.utf8-plain-text
      public.html
    ...
```

**`index.scm` -- metadata only:**
```scheme
(((id . "0001") (timestamp . 1710936000) (app . "com.apple.Safari")
  (types "public.utf8-plain-text" "public.png" "public.rtf")
  (preview . "Screenshot of dashboard..."))
 ((id . "0002") (timestamp . 1710935900) (app . "com.google.Chrome")
  (types "public.utf8-plain-text" "public.html")
  (preview . "Some copied text from a page")))
```

**Config -- exclusion in `config.scm`:**
```scheme
(set-clipboard-exclude! '("com.1password.1password" "com.agilebits.onepassword7"))
(set-clipboard-history-limit! 500)
```

**Architecture:**

- **`ClipboardMonitor`** -- Polls `NSPasteboard.general.changeCount` every 500ms (NSPasteboard has no notification API). On change:
  - Enumerate all types via `NSPasteboard.general.types`
  - Check frontmost app (via `FocusedAppObserver`) against exclusion list
  - Deduplicate (skip if identical to most recent entry)
  - Write all type data to a new entry directory
  - Update index.scm
  - Enforce history limit by deleting oldest entry directories

- **`ClipboardHistoryStore`** -- Manages the directory structure, index, and cleanup. Reads index on startup, writes on each new entry.

- **`ClipboardHistoryLibrary`** -- NativeLibrary exposing:
  ```scheme
  (get-clipboard-history)            ; -> list of alists (most recent first)
  (get-clipboard-history 'limit 20)  ; -> last 20 entries
  (clear-clipboard-history!)         ; -> void, deletes all entries
  (restore-clipboard-entry! id)      ; -> void, loads all UTI data from entry
                                     ;    directory and writes to NSPasteboard
  ```

- **Wiring** -- `ModaliserAppDelegate` creates `ClipboardMonitor` on startup, passing `FocusedAppObserver` and `ClipboardHistoryStore`.

**User config usage:**
```scheme
(selector "v" "Clipboard"
  'prompt "Paste from history"
  'source (lambda () (get-clipboard-history 'limit 50))
  'on-select (lambda (entry)
    (restore-clipboard-entry! (cdr (assoc 'id entry)))
    (send-keystroke '(cmd) "v")))
```

**Testing:**
- Unit tests for `ClipboardHistoryStore`: add entry, enforce limit, dedup, s-expr index round-trip
- Unit tests for `ClipboardMonitor`: exclusion filtering, change count detection (mock NSPasteboard)
- Unit tests for `ClipboardHistoryLibrary`: Scheme function integration, including `restore-clipboard-entry!`
- Test that entry directories contain correct UTI files
- Test paste-back restores all types to NSPasteboard

---

## 6. State Machine in Scheme

Reimplement `ModalStateMachine` in Scheme. Swift's `KeyEventDispatcher` becomes a thin bridge that forwards key events to Scheme and acts on the returned result. This is the largest feature and should be treated as its own sub-phase within Phase 2.

**Scheme-side -- core state machine:**
```scheme
;; State
(define current-mode #f)
(define current-node #f)
(define current-path '())
(define active? #f)

;; Called by Swift on leader key press
(define (modal-enter mode bundle-id)
  (set! current-mode mode)
  (set! current-node (lookup-tree mode bundle-id))
  (set! current-path '())
  (set! active? #t)
  '(activated))

;; Called by Swift on each keypress while modal is active
(define (modal-handle-key key)
  (let ((child (assoc key (tree-children current-node))))
    (cond
      ((not child) '(no-binding))
      ((command? child)
       (set! active? #f)
       (list 'execute (command-action child)))
      ((group? child)
       (set! current-node child)
       (set! current-path (append current-path (list key)))
       '(navigated))
      ((selector? child)
       (set! active? #f)
       (list 'open-selector (selector-config child))))))

;; Called by Swift on escape or after command execution
(define (modal-exit)
  (set! active? #f)
  (set! current-node #f)
  (set! current-path '())
  '(deactivated))

;; Called by Swift on delete key
(define (modal-step-back)
  (if (null? current-path)
    (begin (modal-exit) '(deactivated))
    (begin
      (set! current-path (drop-right current-path 1))
      (set! current-node (navigate-to-path current-path))
      '(navigated))))
```

**Swift side -- bridge:**

- New `SchemeModalBridge` class translates between Swift and Scheme:
  - Calls `modal-enter`, `modal-handle-key`, `modal-exit`, `modal-step-back` via `SchemeEngine`
  - Parses returned s-expression lists into existing `KeyDispatchResult` enum
  - Wraps all calls in try/catch with fallback to `modal-exit` on error

- `KeyEventDispatcher` replaces `ModalStateMachine` calls with `SchemeModalBridge` calls. Continues to act on `KeyDispatchResult` as before -- overlay updates, command execution, chooser opening all stay in Swift.

**What stays in Swift:**
- `KeyboardCapture` (CGEvent tap -- must be native)
- `KeyEventDispatcher` (event routing, delegates decisions to Scheme)
- `CommandExecutor` (calls `machine.apply` to run command lambdas)
- Overlay system (all AppKit rendering)
- Chooser system (all AppKit UI)

**What moves to Scheme:**
- Modal state (active, current node, path, mode)
- Navigation logic (key lookup, group traversal, step-back)
- Tree storage and lookup (currently `CommandTreeRegistry`)
- `define-tree` stores trees in Scheme-side data structures rather than building Swift `CommandNode` enums

**Migration path:**
- Phase 1: Implement Scheme state machine alongside Swift one. Config flag `(set-state-machine! 'scheme)` to opt in.
- Phase 2: Once stable, remove Swift `ModalStateMachine` and make Scheme the default.

**What this unlocks for users:**
- Conditional bindings based on runtime state
- Dynamic trees modified at runtime
- Custom navigation by overriding `modal-handle-key`
- Hooks by wrapping the default handler

**Testing:**
- Port all existing `ModalStateMachineTests` to test the Scheme implementation via `SchemeEngine`
- Test `SchemeModalBridge` translation of each result type
- Integration test: full key event -> Scheme -> result -> Swift action cycle
- Regression: ensure overlay and chooser still work identically

**Risks:**
- Performance -- Scheme evaluation per keypress. Should be fine (human-speed, ~ms budget), but needs benchmarking.
- Error recovery -- If Scheme state machine throws, Swift must catch and reset to idle.
- Startup ordering -- State machine must be loaded before any key events arrive. Config loading already blocks, so this should be safe.
