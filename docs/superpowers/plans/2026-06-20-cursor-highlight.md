# Cursor Highlight Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Modaliser-triggered momentary glowing "converging ring" drawn at the mouse cursor (plus a best-effort nudge to reveal idle-hidden cursors), bound to the space key in the global tree.

**Architecture:** A new native LispKit library `(modaliser cursor)` inside the Modaliser app exposes one procedure, `highlight-cursor`. Pure helpers (hex-colour parse, keyword-option parse) are unit-tested; an AppKit `CursorHighlightController` owns a reusable borderless overlay panel and runs a Core Animation converging-ring-with-glow animation. The config gains one `(key " " …)` binding.

**Tech Stack:** Swift, AppKit (`NSPanel`, `NSView`), Core Animation (`CAShapeLayer`, `CAAnimationGroup`), LispKit (`NativeLibrary`), swift-testing.

## Global Constraints

- New Swift file: `Sources/Modaliser/CursorLibrary.swift` (pure helpers + controller + library in one file, matching the one-file-per-library convention, e.g. `HintsLibrary.swift`).
- Scheme library name: `["modaliser", "cursor"]` → `(modaliser cursor)`.
- Single public procedure: `(highlight-cursor . keyword-args)`, returns void, never throws on bad input (fall back to defaults).
- Defaults: `color "#FFCC33"`, `size 240`, `thickness 6`, `glow 18`, `duration 0.45`, `nudge #t`.
- Pure helpers must be testable **without** a LispKit `Context` (take plain Swift types / pre-constructed `Expr` values; never require interned symbols).
- All AppKit work runs on the main thread (`DispatchQueue.main.async` from the procedure).
- Tests use **swift-testing** (`import Testing`, `@Suite`, `@Test`, `#expect`, `#require`) — NOT XCTest. See `Tests/ModaliserTests/CapturedKeyEventTests.swift`.
- Build: `swift build`. Test: `swift test`. Run filtered tests with `swift test --filter Cursor`.
- Library registration goes in `Sources/Modaliser/SchemeEngine.swift` immediately after the `AccessibilityLibrary` registration (~line 166).
- Config edit lands in `~/.config/modaliser/config.scm`; it is NOT a git repo, so it is not committed — it is applied directly and takes effect after a Modaliser **Relaunch**.
- **Deviation from spec:** the spec's `screenContaining` helper is omitted. `NSEvent.mouseLocation` is already in the global multi-display coordinate space, so a cursor-centred panel frame lands on the correct monitor with no screen lookup. (No behaviour lost.)

---

## Task 0: Feature branch

- [ ] **Step 1: Create a branch (only if on the default branch)**

Run:
```bash
cd ~/Development/Modaliser
git rev-parse --abbrev-ref HEAD
```
If it prints `main` (or the repo's default), create a branch:
```bash
git checkout -b feat/cursor-highlight
```
Otherwise stay on the current feature branch.

---

## Task 1: Hex colour parser (pure)

**Files:**
- Create: `Sources/Modaliser/CursorLibrary.swift`
- Test: `Tests/ModaliserTests/CursorLibraryTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `enum CursorColor { static func parse(_ hex: String) -> NSColor? }` — accepts `#RRGGBB`, `RRGGBB`, `#RGB`, `RGB`; returns nil on bad input.

- [ ] **Step 1: Write the failing test**

Create `Tests/ModaliserTests/CursorLibraryTests.swift`:
```swift
import Testing
import AppKit
@testable import Modaliser

@Suite("CursorColor")
struct CursorColorTests {
    @Test func parsesSixDigitHex() throws {
        let c = try #require(CursorColor.parse("#FF0000")?.usingColorSpace(.sRGB))
        #expect(abs(c.redComponent - 1.0) < 0.01)
        #expect(abs(c.greenComponent - 0.0) < 0.01)
        #expect(abs(c.blueComponent - 0.0) < 0.01)
    }

    @Test func parsesThreeDigitHexWithoutHash() throws {
        let c = try #require(CursorColor.parse("0f0")?.usingColorSpace(.sRGB))
        #expect(abs(c.greenComponent - 1.0) < 0.01)
        #expect(abs(c.redComponent - 0.0) < 0.01)
    }

    @Test func rejectsInvalidInput() {
        #expect(CursorColor.parse("zzz") == nil)
        #expect(CursorColor.parse("#12") == nil)
        #expect(CursorColor.parse("") == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Development/Modaliser && swift test --filter CursorColor`
Expected: FAIL — `CursorColor` is undefined (compile error).

- [ ] **Step 3: Write minimal implementation**

Create `Sources/Modaliser/CursorLibrary.swift`:
```swift
import AppKit

/// Parses hex colour strings for the cursor highlight ring.
enum CursorColor {
    /// Accepts "#RRGGBB", "RRGGBB", "#RGB", or "RGB". Returns nil on bad input.
    static func parse(_ hex: String) -> NSColor? {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        let chars = Array(s)
        let r: Int, g: Int, b: Int
        switch chars.count {
        case 3:
            guard let rr = Int(String([chars[0], chars[0]]), radix: 16),
                  let gg = Int(String([chars[1], chars[1]]), radix: 16),
                  let bb = Int(String([chars[2], chars[2]]), radix: 16) else { return nil }
            r = rr; g = gg; b = bb
        case 6:
            guard let rr = Int(String(chars[0...1]), radix: 16),
                  let gg = Int(String(chars[2...3]), radix: 16),
                  let bb = Int(String(chars[4...5]), radix: 16) else { return nil }
            r = rr; g = gg; b = bb
        default:
            return nil
        }
        return NSColor(srgbRed: CGFloat(r) / 255.0,
                       green: CGFloat(g) / 255.0,
                       blue: CGFloat(b) / 255.0,
                       alpha: 1.0)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CursorColor`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Modaliser/CursorLibrary.swift Tests/ModaliserTests/CursorLibraryTests.swift
git commit -m "feat(cursor): hex colour parser for highlight ring"
```

---

## Task 2: Highlight options parser (pure)

**Files:**
- Modify: `Sources/Modaliser/CursorLibrary.swift`
- Test: `Tests/ModaliserTests/CursorLibraryTests.swift`

**Interfaces:**
- Consumes: `CursorColor.parse(_:)` (Task 1).
- Produces:
  - `struct CursorHighlightOptions { var color: NSColor; var size: CGFloat; var thickness: CGFloat; var glow: CGFloat; var duration: Double; var nudge: Bool }`
  - `static func CursorHighlightOptions.number(_ e: Expr) -> Double?` — extracts `.fixnum`/`.flonum`, else nil.
  - `static func CursorHighlightOptions.from(_ pairs: [(String, Expr)]) -> CursorHighlightOptions` — applies defaults, overrides by key, ignores unknown keys; `nudge` is false only for `.false`, true otherwise.

- [ ] **Step 1: Write the failing test**

Append to `Tests/ModaliserTests/CursorLibraryTests.swift`:
```swift
import LispKit

@Suite("CursorHighlightOptions")
struct CursorHighlightOptionsTests {
    @Test func appliesDefaultsWhenEmpty() {
        let o = CursorHighlightOptions.from([])
        #expect(o.size == 240)
        #expect(o.thickness == 6)
        #expect(o.glow == 18)
        #expect(abs(o.duration - 0.45) < 0.0001)
        #expect(o.nudge == true)
    }

    @Test func overridesNumbersFromFixnumAndFlonum() {
        let o = CursorHighlightOptions.from([
            ("size", .fixnum(300)),
            ("duration", .flonum(0.8)),
            ("glow", .fixnum(30)),
        ])
        #expect(o.size == 300)
        #expect(o.glow == 30)
        #expect(abs(o.duration - 0.8) < 0.0001)
    }

    @Test func nudgeFalseDisablesNudge() {
        #expect(CursorHighlightOptions.from([("nudge", .false)]).nudge == false)
        #expect(CursorHighlightOptions.from([("nudge", .true)]).nudge == true)
    }

    @Test func ignoresUnknownKeywords() {
        let o = CursorHighlightOptions.from([("bogus", .fixnum(1))])
        #expect(o.size == 240)
    }

    @Test func appliesColourOverride() throws {
        let o = CursorHighlightOptions.from([("color", .makeString("#FF0000"))])
        let c = try #require(o.color.usingColorSpace(.sRGB))
        #expect(abs(c.redComponent - 1.0) < 0.01)
    }

    @Test func keepsDefaultColourOnInvalidHex() throws {
        let dflt = try #require(CursorHighlightOptions.from([]).color.usingColorSpace(.sRGB))
        let o = try #require(CursorHighlightOptions.from([("color", .makeString("nope"))]).color.usingColorSpace(.sRGB))
        #expect(abs(o.redComponent - dflt.redComponent) < 0.01)
        #expect(abs(o.greenComponent - dflt.greenComponent) < 0.01)
        #expect(abs(o.blueComponent - dflt.blueComponent) < 0.01)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CursorHighlightOptions`
Expected: FAIL — `CursorHighlightOptions` undefined.

- [ ] **Step 3: Write minimal implementation**

Append to `Sources/Modaliser/CursorLibrary.swift` (add `import LispKit` and `import CoreGraphics` at the top of the file alongside `import AppKit`):
```swift
/// Resolved parameters for one highlight flash.
struct CursorHighlightOptions {
    var color: NSColor
    var size: CGFloat
    var thickness: CGFloat
    var glow: CGFloat
    var duration: Double
    var nudge: Bool

    /// Defaults per the spec.
    static var defaults: CursorHighlightOptions {
        CursorHighlightOptions(
            color: CursorColor.parse("#FFCC33") ?? .systemYellow,
            size: 240, thickness: 6, glow: 18, duration: 0.45, nudge: true
        )
    }

    /// Extract a Double from a Scheme number (fixnum or flonum), else nil.
    static func number(_ e: Expr) -> Double? {
        switch e {
        case .fixnum(let n): return Double(n)
        case .flonum(let d): return d
        default: return nil
        }
    }

    /// Interpret keyword pairs into options. Unknown keys ignored; invalid
    /// values leave the corresponding default in place.
    static func from(_ pairs: [(String, Expr)]) -> CursorHighlightOptions {
        var o = CursorHighlightOptions.defaults
        for (key, value) in pairs {
            switch key {
            case "color":
                if let s = try? value.asString(), let c = CursorColor.parse(s) { o.color = c }
            case "size":      if let n = number(value) { o.size = CGFloat(n) }
            case "thickness": if let n = number(value) { o.thickness = CGFloat(n) }
            case "glow":      if let n = number(value) { o.glow = CGFloat(n) }
            case "duration":  if let n = number(value) { o.duration = n }
            case "nudge":     if case .false = value { o.nudge = false } else { o.nudge = true }
            default: break
            }
        }
        return o
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CursorHighlightOptions`
Expected: PASS (6 tests). Also run `swift test --filter Cursor` — all Cursor suites pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Modaliser/CursorLibrary.swift Tests/ModaliserTests/CursorLibraryTests.swift
git commit -m "feat(cursor): keyword-option parser with defaults"
```

---

## Task 3: Overlay controller — panel, glowing ring, converging animation

**Files:**
- Modify: `Sources/Modaliser/CursorLibrary.swift`

**Interfaces:**
- Consumes: `CursorHighlightOptions` (Task 2).
- Produces: `final class CursorHighlightController { func flash(_ options: CursorHighlightOptions) }` — must be called on the main thread. Owns one reusable `NSPanel`. Performs the nudge (when `options.nudge`), positions a borderless click-through panel centred on the cursor, draws a `CAShapeLayer` ring with a colour-matched glow, and runs a converge+fade animation, ordering the panel out on completion. Re-entrant: a new `flash` mid-animation replaces the previous one.

No unit test (AppKit/Core Animation visuals are not assertable here); verified by compile + the manual smoke test in Task 4/5.

- [ ] **Step 1: Write the implementation**

Append to `Sources/Modaliser/CursorLibrary.swift` (add `import QuartzCore` at the top):
```swift
/// Owns the reusable overlay panel and runs the highlight animation.
/// All methods must be called on the main thread.
final class CursorHighlightController {
    private var panel: NSPanel?
    private var generation = 0

    func flash(_ options: CursorHighlightOptions) {
        // Capture cursor position BEFORE nudging (nudge nets zero displacement).
        let center = NSEvent.mouseLocation  // global cocoa coords, bottom-left origin

        if options.nudge { Self.nudgeMouse() }

        // Panel sized so the glow blur + stroke are never clipped.
        let pad = options.glow + options.thickness
        let side = options.size + 2 * pad
        let frame = NSRect(x: center.x - side / 2, y: center.y - side / 2,
                           width: side, height: side)

        let panel = self.panel ?? Self.makePanel()
        self.panel = panel
        panel.setFrame(frame, display: false)

        guard let host = panel.contentView, let hostLayer = host.layer else { return }
        host.frame = NSRect(origin: .zero, size: frame.size)
        hostLayer.sublayers?.forEach { $0.removeFromSuperlayer() }

        // Ring layer fills the host; the circular path is inset by `pad`.
        let ring = CAShapeLayer()
        ring.frame = hostLayer.bounds
        let ringRect = CGRect(x: pad, y: pad, width: options.size, height: options.size)
        ring.path = CGPath(ellipseIn: ringRect, transform: nil)
        ring.fillColor = NSColor.clear.cgColor
        ring.strokeColor = options.color.cgColor
        ring.lineWidth = options.thickness
        ring.shadowColor = options.color.cgColor   // colour-matched "neon" glow
        ring.shadowRadius = options.glow
        ring.shadowOpacity = 1.0
        ring.shadowOffset = .zero
        ring.masksToBounds = false
        hostLayer.addSublayer(ring)

        panel.orderFrontRegardless()

        // Converge (scale large -> small about the centre) + fade near the end.
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.0
        scale.toValue = 0.15
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1.0, 1.0, 0.0]
        fade.keyTimes = [0.0, 0.6, 1.0]
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = options.duration
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.isRemovedOnCompletion = false
        group.fillMode = .forwards

        generation += 1
        let myGen = generation
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self, weak panel] in
            // Only hide if no newer flash has started.
            if self?.generation == myGen { panel?.orderOut(nil) }
        }
        ring.add(group, forKey: "converge")
        CATransaction.commit()
    }

    private static func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .screenSaver
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.hidesOnDeactivate = false
        let host = NSView()
        host.wantsLayer = true
        host.layer?.masksToBounds = false
        p.contentView = host
        return p
    }

    /// Move the cursor +1px then back, posting real mouseMoved events so a
    /// cursor hidden by idle timeout reappears. Net displacement is zero.
    private static func nudgeMouse() {
        let cocoa = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let ax = CGPoint(x: cocoa.x, y: primaryHeight - cocoa.y)  // CGEvent uses top-left origin
        let moved = CGPoint(x: ax.x + 1, y: ax.y)
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                mouseCursorPosition: moved, mouseButton: .left)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                mouseCursorPosition: ax, mouseButton: .left)?.post(tap: .cghidEventTap)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: Build succeeds with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/Modaliser/CursorLibrary.swift
git commit -m "feat(cursor): overlay controller with glowing converging ring"
```

---

## Task 4: `highlight-cursor` procedure + library registration

**Files:**
- Modify: `Sources/Modaliser/CursorLibrary.swift`
- Modify: `Sources/Modaliser/SchemeEngine.swift` (after the `AccessibilityLibrary` registration, ~line 166)

**Interfaces:**
- Consumes: `CursorHighlightController` (Task 3), `CursorHighlightOptions` (Task 2).
- Produces: `final class CursorLibrary: NativeLibrary` with name `["modaliser","cursor"]` exposing the Scheme procedure `highlight-cursor`, registered into the LispKit context.

- [ ] **Step 1: Write the library class**

Append to `Sources/Modaliser/CursorLibrary.swift`:
```swift
/// Native LispKit library providing the cursor highlight.
/// Scheme name: (modaliser cursor)
///
/// Provides: highlight-cursor
final class CursorLibrary: NativeLibrary {
    private let controller = CursorHighlightController()

    public required init(in context: Context) throws {
        try super.init(in: context)
    }

    public override class var name: [String] {
        ["modaliser", "cursor"]
    }

    public override func dependencies() {
        self.`import`(from: ["lispkit", "base"], "define")
    }

    public override func declarations() {
        self.define(Procedure("highlight-cursor", highlightCursorFunction))
    }

    /// (highlight-cursor ['color hex] ['size px] ['thickness px]
    ///                   ['glow px] ['duration secs] ['nudge bool]) -> void
    private func highlightCursorFunction(_ args: Arguments) throws -> Expr {
        let exprs = Array(args)
        var pairs: [(String, Expr)] = []
        var i = 0
        while i < exprs.count {
            if case .symbol(let sym) = exprs[i], i + 1 < exprs.count {
                pairs.append((sym.identifier, exprs[i + 1]))
                i += 2
            } else {
                i += 1
            }
        }
        // Warn (don't throw) on an unparseable colour so a typo is visible.
        for (k, v) in pairs where k == "color" {
            if let s = try? v.asString(), CursorColor.parse(s) == nil {
                NSLog("CursorLibrary: ignoring invalid colour '%@'", s)
            }
        }
        let options = CursorHighlightOptions.from(pairs)
        DispatchQueue.main.async { [controller] in
            controller.flash(options)
        }
        return .void
    }
}
```

- [ ] **Step 2: Register the library**

In `Sources/Modaliser/SchemeEngine.swift`, immediately after the two `AccessibilityLibrary` lines (~line 166), add:
```swift
try context.libraries.register(libraryType: CursorLibrary.self)
try context.environment.import(CursorLibrary.name)
```

- [ ] **Step 3: Build and run the full test suite**

Run: `swift build && swift test`
Expected: Build succeeds; all tests pass (existing suites + the Cursor suites).

- [ ] **Step 4: Manual smoke test from the app**

Build/run the app the way you normally run the dev build, then Relaunch so it loads the new binary. In the LispKit REPL/scratch (or by temporarily wiring a key), evaluate:
```scheme
(import (modaliser cursor))
(highlight-cursor)
```
Expected: a glowing amber ring converges on the current cursor location and fades within ~0.45s. Try `(highlight-cursor 'color "#33CCFF" 'size 320 'glow 28)` and confirm colour/size change.

- [ ] **Step 5: Commit**

```bash
git add Sources/Modaliser/CursorLibrary.swift Sources/Modaliser/SchemeEngine.swift
git commit -m "feat(cursor): expose (highlight-cursor) and register library"
```

---

## Task 5: Config binding + end-to-end verification

**Files:**
- Modify: `~/.config/modaliser/config.scm` (NOT committed — different, non-git directory)

**Interfaces:**
- Consumes: the `(modaliser cursor)` library and `highlight-cursor` procedure (Task 4).
- Produces: a global-tree binding on the space key.

- [ ] **Step 1: Add the import**

In `~/.config/modaliser/config.scm`, add `(modaliser cursor)` to the top-level `(import …)` block (e.g. on its own line near `(modaliser shell)`):
```scheme
        (modaliser cursor)
```

- [ ] **Step 2: Add the global-tree binding**

Inside `(define-tree 'global …)`, add a binding on the space key. `(highlight-cursor)` is an inline side-effecting call, so it MUST be wrapped in `(λ () …)` (the `key` dispatch gotcha):
```scheme
  (key " " "Highlight Cursor" (λ () (highlight-cursor)))
```
(Place it as a loose key near `(key "," "Settings" …)`, or inside a category — your preference.)

- [ ] **Step 3: Apply and verify the gesture**

Relaunch Modaliser (menu bar icon → Relaunch). Then:
1. Press **F18** (global leader) → **space**. Confirm the glowing ring converges on the cursor.
2. Move the mouse to the **second monitor** and repeat; confirm the ring appears on that monitor.
3. Open a **fullscreen** app and repeat; confirm the ring floats above it without changing focus.
4. Let the cursor **idle-hide** (or use an app that hides it on idle), then trigger; confirm the nudge brings the cursor glyph back and the ring marks it.
5. Trigger twice rapidly; confirm the second flash cleanly replaces the first (no stuck/leftover ring).

- [ ] **Step 4: Confirm no errors**

Open Console.app, filter for "Modaliser"; confirm no errors were logged during the above (a deliberate `(highlight-cursor 'color "bogus")` should log the "invalid colour" warning and still flash with the default colour).

---

## Self-Review

**Spec coverage:**
- Native `(modaliser cursor)` library + registration → Tasks 1–4. ✓
- Glowing converging ring overlay (panel, level, collection behaviour, click-through, CAShapeLayer + glow, converge+fade) → Task 3. ✓
- Best-effort unhide nudge (CGEvent, no new permission, net-zero) → Task 3. ✓
- Scheme API with all six keywords + defaults + void + no-throw + main-thread → Tasks 2 & 4. ✓
- Invalid colour → default + log → Task 2 (default) & Task 4 (log). ✓
- Config binding on space (`" "`), wrapped in `(λ () …)` → Task 5. ✓
- Unit tests for colour parse + keyword parse → Tasks 1 & 2. ✓
- Manual verification (normal/fullscreen/multi-monitor/idle-hidden/re-trigger) → Task 5. ✓
- `screenContaining` helper → intentionally omitted (documented under Global Constraints). ✓

**Placeholder scan:** No TBD/TODO; all code steps contain full code; all commands have expected output. ✓

**Type consistency:** `CursorColor.parse` (Tasks 1,2,4), `CursorHighlightOptions.from`/`.number`/`.defaults` (Tasks 2,4), `CursorHighlightController.flash` (Tasks 3,4), `CursorLibrary.name`/`highlight-cursor` (Task 4) — names/signatures match across tasks. ✓
