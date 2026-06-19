# Keystroke Modifier Release + Explicit Key Down/Up Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `send-keystroke` genuinely press *and release* its modifiers (so release-driven UIs like Dia's recent-tab switcher commit), and add `send-key-down` / `send-key-up` primitives for holding a modifier across taps.

**Architecture:** Centralise CGEvent posting in one tagged helper inside `KeystrokeEmitter`. Rework `sendKeystroke` to bracket the target key with real modifier keyDown/keyUp events. Add `sendKeyDown`/`sendKeyUp` emitters and expose them through `(modaliser input)`, with modifier names added to the keycode table so a modifier can be held on its own.

**Tech Stack:** Swift, CoreGraphics (`CGEvent`), LispKit (`NativeLibrary`), swift-testing.

**Spec:** `docs/specs/2026-06-19-keystroke-modifier-release-and-down-up.md`

## Global Constraints

- Every posted `CGEvent` MUST set `eventSourceUserData = KeyboardCapture.reInjectionMagic` (so Modaliser's own capture tap passes it through instead of the modal catch-all suppressing it).
- Modifier virtual keycodes (left-hand): control `59`, shift `56`, command `55`, option `58`.
- Posting tap: `.cghidEventTap`; event source: `CGEventSource(stateID: .combinedSessionState)` — matching existing `KeystrokeEmitter`.
- Plain keys (no modifiers) MUST keep current behaviour: a bare keyDown/keyUp with empty flags.
- Error message for an unknown key MUST contain the substring `unknown key` (existing test depends on it).
- Build: `swift build`. Test: `swift test --filter <Name>`. Installable app for manual checks: `scripts/build-app.sh`.

---

### Task 1: Modifier names in the keycode table

**Files:**
- Modify: `Sources/Modaliser/KeystrokeEmitter.swift` (the `namedKeyToKeyCode` dictionary, ~line 63)
- Test: `Tests/ModaliserTests/KeystrokeEmitterTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `KeystrokeEmitter.keyCode(forNamedKey:)` resolves `"ctrl"/"control"→59`, `"shift"→56`, `"cmd"/"command"→55`, `"alt"/"option"→58`.

- [ ] **Step 1: Write the failing test**

Add to `KeystrokeEmitterTests.swift`:

```swift
@Test func namedKeyModifiers() {
    #expect(KeystrokeEmitter.keyCode(forNamedKey: "ctrl") == 59)
    #expect(KeystrokeEmitter.keyCode(forNamedKey: "control") == 59)
    #expect(KeystrokeEmitter.keyCode(forNamedKey: "shift") == 56)
    #expect(KeystrokeEmitter.keyCode(forNamedKey: "cmd") == 55)
    #expect(KeystrokeEmitter.keyCode(forNamedKey: "command") == 55)
    #expect(KeystrokeEmitter.keyCode(forNamedKey: "alt") == 58)
    #expect(KeystrokeEmitter.keyCode(forNamedKey: "option") == 58)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter KeystrokeEmitter/namedKeyModifiers`
Expected: FAIL (`keyCode(forNamedKey: "ctrl")` returns `nil`).

- [ ] **Step 3: Add the modifier names**

In `KeystrokeEmitter.swift`, add to the `namedKeyToKeyCode` dictionary:

```swift
"control": 59, "ctrl": 59,
"shift": 56,
"command": 55, "cmd": 55,
"option": 58, "alt": 58,
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter KeystrokeEmitter/namedKeyModifiers`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Modaliser/KeystrokeEmitter.swift Tests/ModaliserTests/KeystrokeEmitterTests.swift
git commit -m "feat(input): map modifier names to keycodes in KeystrokeEmitter"
```

---

### Task 2: `modifierKeyCodes(in:)` bracket-order helper

**Files:**
- Modify: `Sources/Modaliser/KeystrokeEmitter.swift`
- Test: `Tests/ModaliserTests/KeystrokeEmitterTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `static func modifierKeyCodes(in flags: CGEventFlags) -> [(CGKeyCode, CGEventFlags)]` — the modifier (keycode, flag) pairs present in `flags`, in stable order control → shift → option → command. Used by Task 3 to bracket a chord.

- [ ] **Step 1: Write the failing test**

Add to `KeystrokeEmitterTests.swift`:

```swift
@Test func modifierKeyCodesSingleFlag() {
    #expect(KeystrokeEmitter.modifierKeyCodes(in: .maskControl).map(\.0) == [59])
}

@Test func modifierKeyCodesMultipleFlagsAreOrdered() {
    let codes = KeystrokeEmitter.modifierKeyCodes(in: [.maskCommand, .maskControl, .maskShift]).map(\.0)
    #expect(codes == [59, 56, 55])  // control, shift, command — stable order, not insertion order
}

@Test func modifierKeyCodesEmpty() {
    #expect(KeystrokeEmitter.modifierKeyCodes(in: []).isEmpty)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter KeystrokeEmitter/modifierKeyCodes`
Expected: FAIL (method does not exist — compile error).

- [ ] **Step 3: Implement the helper**

In `KeystrokeEmitter.swift`:

```swift
/// Modifier (virtual keycode, flag) pairs present in `flags`, in a stable
/// order (control, shift, option, command). A chord brackets the target key
/// with these as real keyDown/keyUp events so release-driven consumers see a
/// down->up modifier transition.
static func modifierKeyCodes(in flags: CGEventFlags) -> [(CGKeyCode, CGEventFlags)] {
    let ordered: [(CGEventFlags, CGKeyCode)] = [
        (.maskControl, 59),
        (.maskShift, 56),
        (.maskAlternate, 58),
        (.maskCommand, 55),
    ]
    return ordered.compactMap { flag, code in flags.contains(flag) ? (code, flag) : nil }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter KeystrokeEmitter/modifierKeyCodes`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Modaliser/KeystrokeEmitter.swift Tests/ModaliserTests/KeystrokeEmitterTests.swift
git commit -m "feat(input): add modifierKeyCodes bracket-order helper"
```

---

### Task 3: Centralise posting + bracket `sendKeystroke` (Part 1 fix)

**Files:**
- Modify: `Sources/Modaliser/KeystrokeEmitter.swift:11-33` (rework `sendKeystroke`, add private `post`)
- Test: existing suite must stay green (`swift test`)

**Interfaces:**
- Consumes: `modifierKeyCodes(in:)` (Task 2), `KeyboardCapture.reInjectionMagic`.
- Produces: `static func post(_ keyCode: CGKeyCode, keyDown: Bool, flags: CGEventFlags)` (private); reworked `sendKeystroke(keyCode:flags:)` that brackets modifiers.

> Posting hits the live system and is not unit-testable. The automated gate is "compiles + existing tests pass"; behaviour is verified manually in Task 5.

- [ ] **Step 1: Replace the body of `sendKeystroke` and add `post`**

Replace `KeystrokeEmitter.sendKeystroke(keyCode:flags:)` (lines 11-33) with:

```swift
/// Post a single keyboard event, tagged so Modaliser's own capture tap
/// passes it through instead of the modal catch-all suppressing it.
private static func post(_ keyCode: CGKeyCode, keyDown: Bool, flags: CGEventFlags) {
    let source = CGEventSource(stateID: .combinedSessionState)
    guard let event = CGEvent(keyboardEventSource: source,
                              virtualKey: keyCode, keyDown: keyDown) else { return }
    event.flags = flags
    event.setIntegerValueField(.eventSourceUserData,
                               value: KeyboardCapture.reInjectionMagic)
    event.post(tap: .cghidEventTap)
}

/// Send a keystroke with optional modifier flags. Modifiers are posted as
/// real keyDown events (accumulating flags) before the key and released as
/// keyUp events after it, so the chord ends fully released — a down->up
/// transition release-driven UIs (e.g. Dia's recent-tab switcher) require.
static func sendKeystroke(keyCode: CGKeyCode, flags: CGEventFlags = []) {
    let mods = modifierKeyCodes(in: flags)
    var acc: CGEventFlags = []
    for (code, bit) in mods {
        acc.insert(bit)
        post(code, keyDown: true, flags: acc)
    }
    post(keyCode, keyDown: true, flags: flags)
    post(keyCode, keyDown: false, flags: flags)
    for (code, bit) in mods.reversed() {
        acc.remove(bit)
        post(code, keyDown: false, flags: acc)
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 3: Run the full suite**

Run: `swift test`
Expected: PASS (no posting-dependent tests exist; `InputLibraryTests` / `KeystrokeEmitterTests` stay green).

- [ ] **Step 4: Commit**

```bash
git add Sources/Modaliser/KeystrokeEmitter.swift
git commit -m "fix(input): bracket send-keystroke modifiers with real key events

Modifiers were asserted only as flags on the target key, never released,
so release-driven UIs (Dia's recent-tab switcher) opened and hung. Post
real modifier keyDown/keyUp around the key so the chord ends released."
```

---

### Task 4: `send-key-down` / `send-key-up` (Part 2)

**Files:**
- Modify: `Sources/Modaliser/KeystrokeEmitter.swift` (add `sendKeyDown`/`sendKeyUp`)
- Modify: `Sources/Modaliser/InputLibrary.swift` (register + implement procedures, DRY the key resolution)
- Test: `Tests/ModaliserTests/InputLibraryTests.swift`

**Interfaces:**
- Consumes: `KeystrokeEmitter.post` (Task 3), `keyCode(for:)`/`keyCode(forNamedKey:)`, `parseModifiers`.
- Produces: Scheme `(send-key-down mods key)` and `(send-key-up mods key)`, both `→ void`, throwing `unknown key '<k>'` for unresolved keys.

- [ ] **Step 1: Write the failing tests**

Add to `InputLibraryTests.swift`:

```swift
@Test func sendKeyDownIsProcedure() throws {
    let engine = try SchemeEngine()
    #expect(try engine.evaluate("(procedure? send-key-down)") == .true)
}

@Test func sendKeyUpIsProcedure() throws {
    let engine = try SchemeEngine()
    #expect(try engine.evaluate("(procedure? send-key-up)") == .true)
}

@Test func sendKeyDownThrowsForUnknownKey() throws {
    let engine = try SchemeEngine()
    do {
        try engine.evaluate(#"(send-key-down '() "nonexistent_key")"#)
        Issue.record("Expected error for unknown key")
    } catch {
        #expect("\(error)".contains("unknown key"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "Input Library"`
Expected: FAIL (`send-key-down` unbound).

- [ ] **Step 3: Add the emitters**

In `KeystrokeEmitter.swift`, after `sendKeystroke`:

```swift
/// Post a lone keyDown for `keyCode` with `flags` held. Pairs with
/// `sendKeyUp` to hold a modifier across multiple taps.
static func sendKeyDown(keyCode: CGKeyCode, flags: CGEventFlags = []) {
    post(keyCode, keyDown: true, flags: flags)
}

/// Post a lone keyUp for `keyCode`, releasing a hold started by `sendKeyDown`.
static func sendKeyUp(keyCode: CGKeyCode, flags: CGEventFlags = []) {
    post(keyCode, keyDown: false, flags: flags)
}
```

- [ ] **Step 4: Register and implement the procedures**

In `InputLibrary.swift`, add to `declarations()`:

```swift
self.define(Procedure("send-key-down", sendKeyDownFunction))
self.define(Procedure("send-key-up", sendKeyUpFunction))
```

Replace `sendKeystrokeFunction` and add the two new functions, sharing a resolver:

```swift
private func resolveKey(_ modsExpr: Expr, _ keyExpr: Expr) throws -> (CGKeyCode, CGEventFlags) {
    let keyString = try keyExpr.asString()
    let flags = parseModifiers(modsExpr)
    guard let keyCode = KeystrokeEmitter.keyCode(for: keyString)
            ?? KeystrokeEmitter.keyCode(forNamedKey: keyString) else {
        throw RuntimeError.custom("eval", "unknown key '\(keyString)'", [keyExpr])
    }
    return (keyCode, flags)
}

private func sendKeystrokeFunction(_ modsExpr: Expr, _ keyExpr: Expr) throws -> Expr {
    let (keyCode, flags) = try resolveKey(modsExpr, keyExpr)
    KeystrokeEmitter.sendKeystroke(keyCode: keyCode, flags: flags)
    return .void
}

private func sendKeyDownFunction(_ modsExpr: Expr, _ keyExpr: Expr) throws -> Expr {
    let (keyCode, flags) = try resolveKey(modsExpr, keyExpr)
    KeystrokeEmitter.sendKeyDown(keyCode: keyCode, flags: flags)
    return .void
}

private func sendKeyUpFunction(_ modsExpr: Expr, _ keyExpr: Expr) throws -> Expr {
    let (keyCode, flags) = try resolveKey(modsExpr, keyExpr)
    KeystrokeEmitter.sendKeyUp(keyCode: keyCode, flags: flags)
    return .void
}
```

Also update the library header comment (line 7) to `Provides: send-keystroke, send-key-down, send-key-up`.

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter "Input Library"`
Expected: PASS (including the pre-existing `sendKeystrokeThrowsForUnknownKey`, whose message still contains `unknown key`).

- [ ] **Step 6: Update library reference doc**

In `docs/reference/libraries.md`, change the `(modaliser input)` row to:
`Keystroke synthesis: send-keystroke, send-key-down, send-key-up.`

- [ ] **Step 7: Commit**

```bash
git add Sources/Modaliser/KeystrokeEmitter.swift Sources/Modaliser/InputLibrary.swift Tests/ModaliserTests/InputLibraryTests.swift docs/reference/libraries.md
git commit -m "feat(input): add send-key-down / send-key-up primitives"
```

---

### Task 5: Manual verification & regression (live system)

**Files:** none (verification only). Posting behaviour cannot be unit-tested; this task is the real gate for it.

**Interfaces:**
- Consumes: the installed app built from this branch.

- [ ] **Step 1: Build and install the app**

Run: `scripts/build-app.sh` (then install/relaunch per the repo's normal flow).
Expected: app launches; Console.app (filter "Modaliser") shows no load errors.

- [ ] **Step 2: One-shot ctrl-tab commits in Dia**

With Dia frontmost, evaluate the equivalent of `(send-keystroke '(ctrl) "tab")` from a binding (or temporarily bind a key to it).
Expected: focus flips to the most-recent tab AND the switcher HUD closes (no hang). This is the core fix.

- [ ] **Step 3: Regression — existing keystroke callers**

Verify each still works:
- Global tree: `Ctrl+1..9` space switching.
- iTerm tree: `Cmd+Shift+C` (Copy Mode), `Cmd+Shift+Return` (Toggle Zoom).
- Any browser tree: `Cmd+T` new tab.
Expected: all behave exactly as before.

- [ ] **Step 4: Held walk via the new primitives**

From a scratch binding, run in sequence: `(send-key-down '() "ctrl")`, then `(send-keystroke '() "tab")` two or three times, then `(send-key-up '() "ctrl")`.
Expected: Dia's HUD opens, walks deeper on each tab, and commits to the highlighted tab on release. No stuck modifier afterward (test by typing normally).

- [ ] **Step 5: Record results**

Note pass/fail for each check in the PR description. If Step 2 or 4 fails, STOP and revisit the spec's "synthetic modifier-up" risk before proceeding to the config-side modal.

---

## Out of scope (follow-up, different repo)

Part 3 — the sticky "Recent Tabs" modal — lands in `~/.config/modaliser/config.scm`, not here. It depends on these primitives and on confirming `group` honours `on-enter`/`on-leave` with a guaranteed release on every exit path. Tracked separately once this branch is verified.

## Self-review notes

- **Spec coverage:** Part 1 → Tasks 2-3; Part 2 → Tasks 1, 4; tagging constraint → Global Constraints + Task 3 `post`; regression risk → Task 5 Step 3; held-walk validation → Task 5 Step 4. Part 3 explicitly deferred.
- **Type consistency:** `post`, `modifierKeyCodes(in:)`, `sendKeyDown`/`sendKeyUp`, `resolveKey` names are used identically across tasks.
- **No placeholders:** every code step shows full code; every run step shows command + expected result.
