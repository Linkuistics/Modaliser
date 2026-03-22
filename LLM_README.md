# Modaliser — LLM Development Context

Scheme-scriptable modal keyboard system for macOS. SPM executable, LispKit for config/scripting, CGEvent tap for keyboard capture, AppKit for UI.

## Architecture

```
Swift Host Layer (mechanical)
├── main.swift               App entry point (4 lines)
├── ModaliserAppDelegate     Lifecycle, wiring, menu bar, config reload
├── KeyboardCapture          CGEvent tap → CapturedKeyEvent
├── KeyEventDispatcher       Leader keys, escape, delete, key→character mapping
├── SchemeModalBridge         Calls Scheme state machine, parses s-exprs to KeyDispatchResult
├── CommandExecutor           Calls Scheme lambdas via machine.apply
├── FocusedAppObserver       NSWorkspace.frontmostApplication for local mode
│
├── OverlayPanel + renderers  Which-key overlay (NSPanel, nonactivating)
├── OverlayCoordinator        Show delay, lifecycle
├── OverlayNotifier           State machine → coordinator bridge
│
├── ChooserWindowController   Search/select UI (NSPanel, activating)
├── ChooserCoordinator        Source invocation, result dispatch, search memory
├── FuzzyMatcher              DP fuzzy match (MATCH=16, GAP=-3, CONSECUTIVE=4)
├── FileIndexer               fd-based file indexing with 100K cap
│
├── SchemeEngine              LispKit context, library registration, eval
├── ModaliserDSLLibrary       key, group, selector, action, define-tree, set-leader!
├── CommandNodeBuilder         Scheme alist → Swift CommandNode conversion (on-demand for overlay)
├── CommandTreeRegistry       Stores leader keys and theme
├── SchemeAlistLookup         Shared alist traversal (lookupString/Fixnum/makeAlist)
├── SchemeStateMachineLibrary (modaliser state-machine) — THE state machine (Scheme-side)
│
└── Native Libraries (all follow NativeLibrary pattern)
    ├── AppLibrary             (modaliser app)    — find-installed-apps, activate-app, launch-app, open-url
    ├── WindowLibrary          (modaliser window) — list-windows, focus-window, center-window, move-window
    ├── InputLibrary           (modaliser input)  — send-keystroke (CGEvent posting)
    ├── ShellLibrary           (modaliser shell)  — run-shell, run-shell-async
    ├── PasteboardLibrary      (modaliser pasteboard) — get-clipboard, set-clipboard!
    ├── QuicklinksLibrary      (modaliser quicklinks) — get-quicklinks from ~/.config/modaliser/quicklinks.scm
    ├── SnippetsLibrary        (modaliser snippets) — get-snippets, expand-snippet
    └── ClipboardHistoryLibrary (modaliser clipboard-history) — clipboard monitoring, history, restore
```

## Key Patterns

- **DSL alists**: DSL functions return Scheme alists; `define-tree` stores them in the Scheme state machine. `CommandNodeBuilder` converts alists → Swift `CommandNode` on-demand for overlay rendering.
- **NativeLibrary**: `required init(in:)`, `class var name`, `dependencies()`, `declarations()`. Registry injection via `lookup()` post-init.
- **Protocol DI**: `OverlayPresenting` / `ChooserPresenting` abstract NSPanel for testing
- **Result-returning state machine**: `handleKey` returns `KeyDispatchResult`, caller acts on it. State machine runs in Scheme; `SchemeModalBridge` translates s-expr results to Swift types.
- **Three-layer dispatch**: `KeyboardCapture` → `KeyEventDispatcher` → `SchemeModalBridge` → Scheme
- **Scheme round-tripping**: `ChooserChoice.schemeValue: Expr` retains original alist through selection cycle
- **Debounced search**: Serial queue, 30ms debounce, generation counter for stale result invalidation

## LispKit Specifics

- R7RS-based, no `#:keyword` syntax. DSL uses `'symbol value` alternating pairs.
- `environment.import(BaseLibrary.name)` for core bindings (define, lambda, etc.)
- Procedure overloads: `native3` (3 args), `native2R` (2+rest), `native1R` (1+rest). `Arguments` = `ArraySlice<Expr>`.
- Call Scheme lambda: `machine.apply(proc, to: .null)` (zero args) or `machine.apply(proc, to: .pair(arg, .null))` (one arg)
- CGEvent tap callback must be free function. Bridge via `Unmanaged<KeyboardCapture>` userInfo pointer.

## Config

Loaded from `~/.config/modaliser/config.scm` (fallback: `./config.scm`). See `config.scm` in repo root for full example.

```scheme
(set-leader! 'global F18)
(set-leader! 'local F17)
(define (keystroke mods key) (lambda () (send-keystroke mods key)))

(define-tree 'global
  (key "s" "Safari" (lambda () (launch-app "Safari")))
  (group "w" "Windows"
    (key "c" "Center" (lambda () (center-window)))))

(define-tree 'com.apple.Safari           ; app-local by bundle ID
  (group "t" "Tabs"
    (key "n" "New Tab" (keystroke '(cmd) "t"))))
```

## File Stats

~73 source files, ~43 test files, 362 tests, 42 suites. Largest files are chooser UI (~200 lines, AppKit verbosity).

## Known Constraints

- **AXUIElement force casts**: `WindowManipulator` uses `as! AXUIElement` — inherent to Accessibility API (CFTypeRef)
- **NSRange/character index**: `highlightedString` uses char indices on UTF-16 NSAttributedString — incorrect for emoji/CJK
- **CommandTreeRegistry not thread-safe**: Fine for single-threaded access; needs sync if config reload moves off main thread
- **HID key codes are physical positions**: US ANSI layout. Same physical key = same shortcut on AZERTY/Dvorak.

## Phase 2 (Completed)

1. **App icon** — 1024px PNG → .icns via sips/iconutil, bundled in .app
2. **Overlay in-place update** — Panel reuse with CATransaction batching, no flicker
3. **Async run-shell** — `run-shell-async` with callback, timeout, process tracking
4. **Quicklinks & Snippets** — User-edited .scm files, Scheme-driven file I/O, tag filtering
5. **Clipboard history** — Background polling, full UTI storage, s-expr index, app exclusion
6. **State machine in Scheme** — All navigation logic in Scheme; Swift is thin bridge. 0.651ms/key latency.
