# Overlay Delay + Click-Outside Dismiss Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose `modal-overlay-delay` via a named Scheme setter, and dismiss any Modaliser window on an outside mouse click.

**Architecture:** Add `set-overlay-delay!` Scheme wrapper. For non-activating panels, install a global `NSEvent` mouse-down monitor in `WebViewManager` that fires the same `{type: "cancel"}` message handler flow the chooser already uses on `resignKey`. The overlay registers a Scheme message handler that calls `modal-exit` on cancel.

**Tech Stack:** Swift (AppKit / WebKit), LispKit Scheme. Tests use Swift Testing via `swift test`.

**Spec:** `docs/superpowers/specs/2026-04-23-overlay-delay-and-click-outside-dismiss-design.md`

---

## File Structure

**Modify:**
- `Sources/Modaliser/Scheme/core/state-machine.scm` — add `set-overlay-delay!` setter next to the `modal-overlay-delay` define (line 90).
- `Sources/Modaliser/Scheme/ui/overlay.scm` — add `overlay-message-handler` procedure; register it from `show-overlay`.
- `Sources/Modaliser/WebViewManager.swift` — add `mouseMonitors` dict, install global `NSEvent` monitor for non-activating panels in `createPanel`, remove in `closePanel`.
- `config.scm` (project sample) — add commented example of `set-overlay-delay!`.
- `Tests/ModaliserTests/OverlayIntegrationTests.swift` — add tests for the setter and the overlay `cancel` handler.

No new files.

---

## Task 1: Add `set-overlay-delay!` Scheme setter

**Files:**
- Modify: `Sources/Modaliser/Scheme/core/state-machine.scm:90`
- Modify: `Tests/ModaliserTests/OverlayIntegrationTests.swift`

- [ ] **Step 1: Write the failing test**

Add this test method inside `struct OverlayIntegrationTests { ... }` in `Tests/ModaliserTests/OverlayIntegrationTests.swift`, for example after the existing `unmatchedKeyClosesOverlay` test (around line 250, before the "Overlay HTML content verification" MARK):

```swift
// MARK: - Delay configuration

@Test func setOverlayDelayUpdatesVariable() throws {
    let engine = try loadAllModules()
    // loadAllModules sets modal-overlay-delay to 0 as a side effect.
    try engine.evaluate("(set-overlay-delay! 0.75)")
    #expect(try engine.evaluate("modal-overlay-delay") == .flonum(0.75))

    try engine.evaluate("(set-overlay-delay! 0)")
    #expect(try engine.evaluate("modal-overlay-delay") == .fixnum(0))
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter setOverlayDelayUpdatesVariable`
Expected: FAIL with an error like `unbound identifier: set-overlay-delay!`.

- [ ] **Step 3: Add the setter**

In `Sources/Modaliser/Scheme/core/state-machine.scm`, replace the single line at line 90:

```scheme
(define modal-overlay-delay 1.0)    ;; seconds before overlay appears (0 = immediate)
```

with:

```scheme
(define modal-overlay-delay 1.0)    ;; seconds before overlay appears (0 = immediate)

;; Public setter: call from user config to adjust the which-key overlay delay.
;; 0 shows the overlay immediately. Typical values: 0.3–1.0 seconds.
(define (set-overlay-delay! seconds)
  (set! modal-overlay-delay seconds))
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter setOverlayDelayUpdatesVariable`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Modaliser/Scheme/core/state-machine.scm Tests/ModaliserTests/OverlayIntegrationTests.swift
git commit -m "Add set-overlay-delay! Scheme setter"
```

---

## Task 2: Document the setter in the project config sample

**Files:**
- Modify: `config.scm` (project root)

- [ ] **Step 1: Add the commented example**

In `/Users/antony/Development/Modaliser/config.scm`, locate the "Leader keys" block near the top:

```scheme
;; Leader keys
(set-leader! 'global F18)
(set-leader! 'local F17)
```

Immediately after those two lines, insert:

```scheme

;; Overlay delay: seconds before the which-key hint panel appears after
;; pressing the leader. 0 shows it immediately. Default is 1.0.
;; (set-overlay-delay! 0.5)
```

- [ ] **Step 2: Commit**

```bash
git add config.scm
git commit -m "Document set-overlay-delay! in sample config"
```

No test for this task — it's a documentation change to the sample config. The user can copy this to `~/.config/modaliser/config.scm` separately when they want to use it (per their config-sync workflow).

---

## Task 3: Add overlay message handler for the `cancel` message

**Files:**
- Modify: `Sources/Modaliser/Scheme/ui/overlay.scm`
- Modify: `Tests/ModaliserTests/OverlayIntegrationTests.swift`

Context: the chooser already handles `{type: "cancel"}` messages from the Swift side (`ui/chooser.scm:421-438`). The overlay currently registers no message handler. Task 3 adds one and wires it into `show-overlay`. Task 4 adds the Swift-side trigger that actually sends the message.

This task is Scheme-only — no Swift changes — so it's unit-testable by stubbing `webview-on-message`.

- [ ] **Step 1: Write the failing test**

Update the `loadAllModules` helper in `Tests/ModaliserTests/OverlayIntegrationTests.swift` (around line 16) to also stub `webview-on-message`. Replace the stubs block inside `loadAllModules`:

```swift
try engine.evaluate("""
    (define webview-create-calls '())
    (define webview-close-calls '())
    (define webview-set-html-calls '())
    (define (webview-create id opts)
      (set! webview-create-calls (cons id webview-create-calls)) id)
    (define (webview-close id)
      (set! webview-close-calls (cons id webview-close-calls)))
    (define (webview-set-html! id html)
      (set! webview-set-html-calls (cons (cons id html) webview-set-html-calls)))
    """)
```

with:

```swift
try engine.evaluate("""
    (define webview-create-calls '())
    (define webview-close-calls '())
    (define webview-set-html-calls '())
    (define webview-message-handlers (make-hashtable string-hash string=?))
    (define (webview-create id opts)
      (set! webview-create-calls (cons id webview-create-calls)) id)
    (define (webview-close id)
      (set! webview-close-calls (cons id webview-close-calls)))
    (define (webview-set-html! id html)
      (set! webview-set-html-calls (cons (cons id html) webview-set-html-calls)))
    (define (webview-on-message id handler)
      (hashtable-set! webview-message-handlers id handler))
    (define (webview-dispatch-message id msg)
      (let ((h (hashtable-ref webview-message-handlers id #f)))
        (when h (h msg))))
    """)
```

Then add this test method to the suite (place it in the existing "Overlay lifecycle with modal" section, e.g. after `unmatchedKeyClosesOverlay` around line 249):

```swift
@Test func overlayCancelMessageExitsModal() throws {
    let engine = try loadAllModules()
    try engine.evaluate("""
        (define-tree 'global
          (key "s" "Safari" (lambda () 'ok)))
        """)

    try engine.evaluate("(modal-enter (lookup-tree \"global\") F18)")
    #expect(try engine.evaluate("overlay-open?") == .true)
    #expect(try engine.evaluate("modal-active?") == .true)

    // Simulate the Swift side sending a cancel message for an outside click.
    try engine.evaluate("""
        (webview-dispatch-message "modaliser-overlay" '((type . "cancel")))
        """)

    #expect(try engine.evaluate("overlay-open?") == .false)
    #expect(try engine.evaluate("modal-active?") == .false)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter overlayCancelMessageExitsModal`
Expected: FAIL — the test will get a `#f` message handler (the overlay never registered one via `webview-on-message`, so `webview-dispatch-message` finds nothing), so modal stays active. Assertion on `modal-active? == false` fails.

- [ ] **Step 3: Add the overlay message handler**

In `Sources/Modaliser/Scheme/ui/overlay.scm`, find the "Overlay Lifecycle (Side-Effecting)" section near the bottom (around line 176). Add the handler immediately before `(define (show-overlay node path) …)`:

```scheme
;; Handle messages posted from the overlay panel. Currently the only
;; message is {type: "cancel"} sent by WebViewManager when the user clicks
;; outside the panel — exit the modal so the overlay hides.
(define (overlay-message-handler msg)
  (when (equal? (alist-ref msg 'type "") "cancel")
    (modal-exit)))
```

Then modify `show-overlay` to register the handler on panel creation. Replace:

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
    (set! overlay-open? #t))
  (webview-set-html! overlay-webview-id
    (render-overlay-html node path)))
```

with:

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

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter overlayCancelMessageExitsModal`
Expected: PASS.

- [ ] **Step 5: Run the full overlay suite to check for regressions**

Run: `swift test --filter OverlayIntegrationTests`
Expected: all tests PASS (10+ existing tests plus the 2 new ones from Tasks 1 & 3).

- [ ] **Step 6: Commit**

```bash
git add Sources/Modaliser/Scheme/ui/overlay.scm Tests/ModaliserTests/OverlayIntegrationTests.swift
git commit -m "Wire overlay to exit modal on cancel message"
```

---

## Task 4: Install global mouse-down monitor for non-activating panels

**Files:**
- Modify: `Sources/Modaliser/WebViewManager.swift`

This task is Swift-only. `NSEvent.addGlobalMonitorForEvents` requires a running `NSApplication` GUI session, so per the existing test-infrastructure comment (`WebViewLibraryTests.swift:54-56`) it is verified by manual integration testing — not by automated tests. The prior two tasks have already put the Scheme side in place so that the monitor's `cancel` message has a receiver.

- [ ] **Step 1: Add the mouse-monitors dict**

In `Sources/Modaliser/WebViewManager.swift`, locate the property block at the top of the class (lines 9-13):

```swift
private var panels: [String: NSPanel] = [:]
private var webViews: [String: WKWebView] = [:]
private var messageHandlers: [String: (Any) -> Void] = [:]
private var resignObservers: [String: NSObjectProtocol] = [:]
private var previousApps: [String: NSRunningApplication] = [:]
```

Add one additional line so the block becomes:

```swift
private var panels: [String: NSPanel] = [:]
private var webViews: [String: WKWebView] = [:]
private var messageHandlers: [String: (Any) -> Void] = [:]
private var resignObservers: [String: NSObjectProtocol] = [:]
private var previousApps: [String: NSRunningApplication] = [:]
private var mouseMonitors: [String: Any] = [:]
```

- [ ] **Step 2: Install the monitor for non-activating panels**

In `createPanel`, find the `if activating { … } else { panel.orderFront(nil) }` block (around lines 73-91). Replace the `else` branch only — keep the `if activating { … }` branch unchanged. Replace:

```swift
} else {
    panel.orderFront(nil)
}
```

with:

```swift
} else {
    panel.orderFront(nil)
    // Non-activating panels never become key, so resignKey never fires.
    // Use a global mouse-down monitor to detect clicks in other apps and
    // dispatch the same {type: "cancel"} message activating panels send.
    let panelId = id
    let monitor = NSEvent.addGlobalMonitorForEvents(
        matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    ) { [weak self] _ in
        self?.messageHandlers[panelId]?(["type": "cancel"])
    }
    if let monitor {
        mouseMonitors[id] = monitor
    }
}
```

- [ ] **Step 3: Tear down the monitor in closePanel**

In `closePanel`, locate the observer-removal block (lines 101-103):

```swift
if let observer = resignObservers.removeValue(forKey: id) {
    NotificationCenter.default.removeObserver(observer)
}
```

Immediately after that block, add:

```swift
if let monitor = mouseMonitors.removeValue(forKey: id) {
    NSEvent.removeMonitor(monitor)
}
```

- [ ] **Step 4: Build to confirm no compile errors**

Run: `swift build`
Expected: build succeeds with no errors.

- [ ] **Step 5: Run the existing test suite to confirm no regressions**

Run: `swift test`
Expected: all tests PASS — including the two tests added in Tasks 1 and 3.

- [ ] **Step 6: Commit**

```bash
git add Sources/Modaliser/WebViewManager.swift
git commit -m "Dismiss non-activating panels on outside mouse click

Install a global NSEvent mouse-down monitor for each non-activating
panel, dispatching {type: \"cancel\"} to the panel's message handler.
Activating panels keep their existing resignKey notification path."
```

---

## Task 5: Manual verification in the installed app

**Files:** none

Because `NSEvent` global monitors and `NSPanel` behaviour are not exercisable in unit tests, the final validation is manual and runs against the installed bundle (the sample `config.scm` in the repo seeds the user's active config via the project's existing install flow).

- [ ] **Step 1: Reinstall the app with the new code**

Run: `./scripts/install.sh`
Expected: script completes. Per the user's usual workflow, this rebuilds and installs the `.app` bundle into `/Applications` so the updated Scheme bundle is picked up.

- [ ] **Step 2: Verify delay setter works (manual)**

Edit `~/.config/modaliser/config.scm` and add near the top (after the `set-leader!` calls):

```scheme
(set-overlay-delay! 0.2)
```

Restart Modaliser. Press the global leader (F18 by default). Expected: the which-key overlay appears after roughly 200ms — noticeably faster than the 1-second default.

Change it to `(set-overlay-delay! 0)` and restart. Expected: overlay appears immediately with no perceptible delay.

Revert to whatever value you want to keep (or remove the line).

- [ ] **Step 3: Verify click-outside dismisses the overlay (manual)**

Set `(set-overlay-delay! 0)` so the overlay appears immediately, restart Modaliser, then:

1. Press F18. Overlay appears.
2. Click anywhere in another application's window. Expected: overlay disappears; next keystroke is NOT captured by Modaliser (confirms `modal-exit` ran).
3. Press F18 again, click on a different app's menu bar item. Expected: overlay disappears.
4. Press F18, then press a key (e.g. `s`) to run an action. Expected: action fires and overlay closes normally (confirms the existing happy path still works).

- [ ] **Step 4: Verify chooser behaviour is unchanged (manual)**

Press F18, then `f` `a` (Find → Find Apps) to open the chooser. Expected: chooser appears as before.
Click outside the chooser. Expected: chooser disappears (this was already working via `resignKey` and should not have regressed).

- [ ] **Step 5: Confirm nothing is left uncommitted**

Run: `git status`
Expected: clean working tree (all Task 1-4 changes are already committed).

No final commit for Task 5; it is verification-only.

---

## Deployment note

These changes take effect only after the app bundle is rebuilt and relaunched (`./scripts/install.sh`). The project-level `config.scm` is a sample — users who want the new `set-overlay-delay!` setter in their live config must add the line to `~/.config/modaliser/config.scm` themselves (or copy from the project sample per their existing workflow).
