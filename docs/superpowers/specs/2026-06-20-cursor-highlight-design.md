# Cursor Highlight — Design

**Date:** 2026-06-20
**Status:** Approved (pending spec review)
**Repos touched:** `~/Development/Modaliser` (Swift app + this spec) and
`~/.config/modaliser` (one config binding).

## Problem

On a large monitor the mouse cursor is easy to lose, and some apps hide it.
Manually shaking the pointer to invoke macOS's "locate" feature is slow and
awkward on a small trackpad. The user wants a Modaliser-triggered action that
**highlights the cursor** (so it's instantly findable) and makes a best-effort
attempt to **reveal a hidden cursor**.

Reference inspiration: Cursor Pro (appahead.studio) — a bright highlight around
the pointer.

## Scope & non-goals

- **In scope:** a momentary, GPU-animated **converging ring with a colored
  glow** drawn at the current cursor location, triggered from Scheme config;
  plus a best-effort synthetic "nudge" that reveals cursors hidden by idle
  timeout.
- **Out of scope / honest limitation:** truly *forcing* a cursor visible when
  another process has deliberately hidden it (fullscreen video players, games
  that capture the pointer). macOS cursor visibility is reference-counted
  per-process; another process cannot reliably override it. The ring still
  marks the spot even when the cursor glyph itself stays hidden.

## Architecture

The feature is a **native library inside the Modaliser app**, not a separate
process. Modaliser is already resident with a running event loop and an
established Scheme↔Swift bridge (e.g. `run-shell`, `send-keystroke`), so this
follows the same pattern as every other `(modaliser …)` library. Benefits over
an external helper: no second process, no LaunchAgent, no separate
code-signing, no cold-launch latency, instant response.

### Components

1. **`Sources/Modaliser/CursorLibrary.swift`** — new `NativeLibrary` subclass,
   Scheme name `["modaliser","cursor"]`. Exposes one procedure,
   `highlight-cursor`. Follows the `ShellLibrary` / `WebViewLibrary` shape
   (`name`, `dependencies`, `declarations`, `Procedure(...)`).

2. **Library registration** — two lines in
   `Sources/Modaliser/SchemeEngine.swift` after `AccessibilityLibrary`
   (~line 166):
   ```swift
   try context.libraries.register(libraryType: CursorLibrary.self)
   try context.environment.import(CursorLibrary.name)
   ```

3. **`CursorHighlightController`** (a class, or nested in `CursorLibrary`) —
   owns a single reusable overlay panel and drives the animation. Single
   instance so a re-trigger replaces an in-flight flash cleanly.

4. **Config binding** in `~/.config/modaliser/config.scm` — import
   `(modaliser cursor)` and add a global-tree entry on the space key.

### The overlay (Swift)

Reuses the borderless-panel precedent from `HintsLibrary.swift`:

- `NSPanel`, `styleMask: [.borderless, .nonactivatingPanel]`,
  `backing: .buffered`, `defer: false`.
- `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = false`,
  `ignoresMouseEvents = true` (click-through), `hidesOnDeactivate = false`.
- `level = .screenSaver` and
  `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary,
  .ignoresCycle]` — so it floats over normal apps, other Spaces, and fullscreen
  apps **without stealing focus** (same class of problem the which-key overlay
  solves).
- Content: a layer-backed `NSView` whose layer hosts a **`CAShapeLayer`** with
  a circular path, colored `strokeColor`, `fillColor = clear`, and configurable
  `lineWidth`.

**Positioning.** Read `NSEvent.mouseLocation` (AppKit, bottom-left origin).
Select the `NSScreen` whose frame contains that point (`screenContaining(point:)`,
falling back to `.main`). The panel frame is centered on the cursor, sized to
`size + 2 * glow + thickness` so the glow blur is never clipped. Staying in
AppKit coordinates throughout means no Y-flip is required.

**Glow.** A "neon" glow rather than a drop shadow: on the shape layer (or its
host layer), `shadowColor = ringColor`, `shadowOpacity = 1`,
`shadowOffset = .zero`, `shadowRadius = glow`, and `masksToBounds = false` on
all containing layers so the blur is visible.

**Animation — converging ring.** A `CAAnimationGroup` on the shape layer:
- `transform.scale` from ~1.0 → ~0.15 (large ring collapses onto the point),
  pulling the eye inward to the exact location;
- `opacity` fades to 0 over roughly the final 40% of the duration;
- `duration ≈ 0.45s`, ease-out timing.
On completion the panel is `orderOut`. If `highlight-cursor` fires again mid
animation, the controller removes the in-flight animation and restarts at the
new cursor location.

### The unhide nudge (Swift)

When `nudge` is enabled (default), *before* showing the ring, post a synthetic
relative mouse move of **+1px then −1px** via `CGEvent` (the
`CGEvent(mouseEventSource:…, mouseType: .mouseMoved, …)` pattern already used in
`AccessibilityLibrary.swift`). Net displacement is zero, so a precise pointer
position is preserved, but the movement wakes a cursor hidden by idle timeout.
This costs **no new permission**: the Modaliser app already holds Accessibility
(it synthesizes keystrokes and clicks). Documented limitation: this will not
defeat apps that deliberately capture/hide the pointer.

## Scheme API

Keyword-argument style consistent with `set-leaders!` and `run-shell-async`.
The bare call works; all keywords are optional and fall back to defaults.

```scheme
(highlight-cursor)                          ; all defaults
(highlight-cursor 'color "#FFCC33"          ; ring + glow colour (hex string)
                  'size 240                 ; start diameter, px
                  'thickness 6              ; stroke width, px
                  'glow 18                  ; glow blur radius, px
                  'duration 0.45            ; seconds
                  'nudge #t)                ; reveal idle-hidden cursors
```

| Keyword     | Type    | Default     | Meaning                                  |
|-------------|---------|-------------|------------------------------------------|
| `color`     | string  | `"#FFCC33"` | Ring stroke + glow colour (hex).         |
| `size`      | number  | `240`       | Starting ring diameter in px.            |
| `thickness` | number  | `6`         | Ring stroke width in px.                 |
| `glow`      | number  | `18`        | Glow (shadow) blur radius in px.         |
| `duration`  | number  | `0.45`      | Animation length in seconds.             |
| `nudge`     | boolean | `#t`        | Whether to do the reveal nudge.          |

- Returns `void`.
- Invalid `color` (unparseable hex) → fall back to the default colour and emit
  an `NSLog` warning; never throw.
- Unknown keywords (and non-numeric numeric args) are ignored, each with an
  `NSLog` warning so typos are visible.
- All AppKit work is marshalled onto the main thread (AppKit requirement);
  `highlight-cursor` is safe to call from any thread / a key handler.

## Config wiring (`~/.config/modaliser/config.scm`)

1. Add `(modaliser cursor)` to the top-level `(import …)` block.
2. Add a global-tree entry. The space key matches the DSL key string `" "`
   (keycode 49 → `" "` per `KeyboardLibrary.keyCodeToCharacter`). Because
   `(highlight-cursor)` is an inline side-effecting call, it **must** be wrapped
   in `(λ () …)` (the `key` dispatch gotcha):

   ```scheme
   (key " " "Highlight Cursor" (λ () (highlight-cursor)))
   ```

   So the gesture is: **F18 (global leader) → space**.

(The config directory is not a git repo, so only this spec — in the app repo —
is committed. The config edit is applied directly and takes effect after a
Modaliser Relaunch.)

## Error handling

- Bad `color` / bad keyword values → default + `log`, never throw.
- No screen found for the cursor point → fall back to `NSScreen.main`; if still
  nil, no-op.
- Panel/layer creation failure → no-op (the nudge, if enabled, may still have
  helped).
- Nudge always restores the original position, so it cannot disturb a
  precisely-placed pointer.

## Testing

The design deliberately extracts the *pure* logic into free functions so it is
unit-testable, leaving only the un-assertable AppKit shell.

- **Unit tests** (swift-testing, following `Tests/ModaliserTests/`):
  - `parseHexColor(_:)` — valid `#RGB`/`#RRGGBB`, invalid input → nil/default.
  - keyword-argument parsing — defaults applied, overrides honoured, unknown
    keywords ignored, wrong types rejected gracefully.
  - `screenContaining(point:)` — point on primary, point on a second screen,
    point outside all screens → fallback.
- **Manual verification** (no automated path for the visual):
  1. Build the app, Relaunch.
  2. Press F18 → space; confirm a glowing amber ring converges on the cursor.
  3. Repeat over: a normal windowed app, a fullscreen app, and the second
     monitor.
  4. Let the cursor idle-hide, then trigger; confirm the nudge reveals it.
  5. Trigger twice in quick succession; confirm the second flash replaces the
     first without artifacts.

## Build sequence

1. Add `CursorLibrary.swift` with pure helpers (`parseHexColor`,
   keyword parsing, `screenContaining`) + the `highlight-cursor` procedure
   stub (nudge + controller call).
2. Add `CursorHighlightController` (panel, positioning, glow, converging
   animation).
3. Register the library in `SchemeEngine.swift`.
4. Write unit tests for the pure helpers.
5. Manual verification per above.
6. Apply the config binding in `~/.config/modaliser/config.scm`; Relaunch and
   confirm the F18→space gesture.
