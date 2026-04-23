# Configurable overlay delay + click-outside dismissal

## Motivation

Two related UX changes for Modaliser's modal windows:

1. **Configurable overlay delay.** The "which-key" overlay appears
   `modal-overlay-delay` seconds after the leader is pressed (default 1.0s).
   The variable is already settable from user config, but there is no
   publicly-named setter — users have to know the internal symbol and use
   raw `set!`. A named setter brings it in line with `set-overlay-css!`
   and `set-leader!`.

2. **Click outside dismisses any Modaliser window.** The chooser (an
   activating panel) already dismisses on outside click via
   `NSWindow.didResignKeyNotification`. The overlay (a non-activating
   panel) does not — because a non-activating panel never becomes the key
   window, so `didResignKeyNotification` never fires. The user wants
   uniform behaviour across both panel types.

## Current state

- `modal-overlay-delay` is a module-level Scheme variable in
  `Sources/Modaliser/Scheme/core/state-machine.scm:90`, default `1.0`.
- `user-config-path` (`~/.config/modaliser/config.scm`) is included
  *after* the core Scheme modules load (`Sources/Modaliser/Scheme/root.scm:52-53`),
  so `(set! modal-overlay-delay …)` from user config already wins.
- `WebViewManager.createPanel` in `Sources/Modaliser/WebViewManager.swift`
  installs a `didResignKeyNotification` observer only when
  `activating: true`, sending `{type: "cancel"}` to the panel's message
  handler. Non-activating panels get no click-outside handling at all.
- The chooser handles `{type: "cancel"}` in its message handler
  (`Sources/Modaliser/Scheme/ui/chooser.scm:421-435`). The overlay
  currently registers no message handler at all.

## Design

### Part 1 — Configurable overlay delay

**File: `Sources/Modaliser/Scheme/core/state-machine.scm`**

Add a thin setter alongside the variable definition:

```scheme
(define modal-overlay-delay 1.0)    ;; seconds before overlay appears (0 = immediate)

;; Set the modal overlay delay, in seconds.
;; 0 = show overlay immediately. Typical values: 0.3–1.0.
(define (set-overlay-delay! seconds)
  (set! modal-overlay-delay seconds))
```

**File: `config.scm`** (project sample)

Add a commented example near the top of the config, under the leader
keys, so users discover it:

```scheme
;; Overlay delay: seconds before the which-key hint panel appears after
;; pressing the leader. 0 shows it immediately. Default is 1.0.
;; (set-overlay-delay! 0.5)
```

That's the entire Part 1 change. No Swift work.

### Part 2 — Click-outside dismisses all Modaliser windows

**Swift side: `Sources/Modaliser/WebViewManager.swift`**

Add a per-panel global mouse-down monitor for non-activating panels,
mirroring the existing `resignObservers` pattern used for activating
panels. Use `NSEvent.addGlobalMonitorForEvents` matching all three
mouse-down event types (`.leftMouseDown`, `.rightMouseDown`,
`.otherMouseDown`).

Required changes:

- Add an instance dict `private var mouseMonitors: [String: Any] = [:]`
  alongside `resignObservers`.
- In `createPanel`, after the `activating` branch, add an `else` branch
  that installs the global monitor and stores the returned opaque
  monitor object keyed by `id`. The monitor's closure calls
  `self?.messageHandlers[panelId]?(["type": "cancel"])`.
- In `closePanel`, before `orderOut`, remove the monitor with
  `NSEvent.removeMonitor` if one is present, and drop it from the dict.
- Keep the existing `resignKey` path for activating panels unchanged.

Notes on behaviour:

- `addGlobalMonitorForEvents` fires only for events in *other* apps.
  Modaliser is an accessory app whose only in-process UI is the status
  bar icon and these panels, so this is sufficient.
- Global monitors are observe-only — they cannot consume events. This
  gives desired click-through semantics: a click outside dismisses the
  overlay *and* activates whatever was clicked.
- The monitor is installed regardless of the panel's size/position;
  we don't filter by whether the click is "inside" the panel frame
  because global monitors don't see clicks inside our own process
  anyway.

**Scheme side: `Sources/Modaliser/Scheme/ui/overlay.scm`**

The overlay currently has no message handler. Add one that handles
`cancel` by calling `modal-exit`. Register it exactly once, on first
creation, to match the chooser's pattern.

Update `show-overlay`:

```scheme
(define (show-overlay node path)
  (unless overlay-open?
    (webview-create overlay-webview-id
      (list (cons 'width overlay-panel-width)
            (cons 'height overlay-panel-height)
            (cons 'activating #f)
            (cons 'floating #t)
            (cons 'transparent #t)
            (cons 'shadow #t)))
    (webview-on-message overlay-webview-id overlay-message-handler)
    (set! overlay-open? #t))
  (webview-set-html! overlay-webview-id
    (render-overlay-html node path)))
```

Add the handler near the other lifecycle functions:

```scheme
(define (overlay-message-handler msg)
  (when (equal? (alist-ref msg 'type "") "cancel")
    (modal-exit)))
```

(Uses `alist-ref` to match the chooser's idiom at `chooser.scm:421-438`.)

`modal-exit` already calls `hide-overlay` which closes the panel, which
triggers `closePanel` on the Swift side, which removes the monitor.
No extra teardown needed.

## Error handling

- `set-overlay-delay!` accepts any numeric value. Zero or negative
  values fall through the existing `(<= modal-overlay-delay 0)` branch
  in `modal-show-overlay-delayed` (state-machine.scm:102), which shows
  the overlay immediately. No explicit validation needed.
- If `addGlobalMonitorForEvents` returns `nil` (the system denied
  monitoring), we silently skip storing it. The panel still works; it
  just won't self-dismiss on outside click. This matches AppKit's
  "best-effort observer" conventions.
- The monitor's closure uses `[weak self]` to avoid a retain cycle
  between `WebViewManager` and the closure.

## Testing

Manual tests (the test suite currently exercises overlay integration
via `Tests/ModaliserTests/OverlayIntegrationTests.swift`; new checks
fit the same shape):

1. **Delay setter works from config:** add `(set-overlay-delay! 0.2)`
   to user config, press leader, verify overlay appears ~200ms later.
2. **Delay setter = 0 shows immediately:** `(set-overlay-delay! 0)`,
   press leader, verify overlay appears without perceptible delay.
3. **Click outside overlay dismisses modal:** press leader, wait for
   overlay, click in another app's window → overlay disappears, modal
   exits (subsequent keystrokes are not captured by Modaliser).
4. **Click during the delay window is a no-op for dismissal:** press
   leader, click in another app before the delay elapses. No overlay
   ever appears (expected — the delayed show-generation check already
   suppresses it). The modal stays active; the monitor was never
   installed because `webview-create` never ran. This matches the
   user's phrasing ("when a window shows, any click outside should
   dismiss it") — if no window is showing, there is nothing to
   dismiss. The existing modal exit via the next keystroke is
   unchanged.
5. **Chooser dismissal unchanged:** open a selector, click outside →
   chooser closes (verify existing behaviour still works via the
   `resignKey` path).

## Out of scope

- No change to the chooser's dismissal mechanism. It already uses
  `resignKey` which fires reliably when focus shifts elsewhere.
- No keyboard-driven "Escape dismisses" addition. That's orthogonal
  and can be pursued separately if wanted.
- No visual animation on dismiss.
