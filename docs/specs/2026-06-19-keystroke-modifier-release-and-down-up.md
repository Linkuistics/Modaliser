# Keystroke modifier release + explicit key down/up

**Date:** 2026-06-19
**Status:** Approved (design), pending implementation
**Area:** `(modaliser input)` — `InputLibrary.swift`, `KeystrokeEmitter.swift`

## Problem

`send-keystroke` cannot drive any UI whose behaviour depends on a modifier
being *released*. The trigger case is Dia's recent-tab switcher
(`company.thebrowser.dia`): it opens on `ctrl+tab` and **commits the
selection when control is released**. A config binding of
`(send-keystroke '(ctrl) "tab")` opens the switcher HUD and leaves it open
forever — the user cannot complete a selection.

### Root cause (confirmed from source)

`KeystrokeEmitter.sendKeystroke` posts only the *target key's* events, with
the modifier expressed purely as a `CGEventFlags` value on each:

```swift
keyDown.flags = flags   // tab, maskControl asserted
keyUp.flags   = flags   // tab release — STILL asserts maskControl
keyDown.post(...); keyUp.post(...)
```

No discrete modifier key event is ever posted, so the system event stream
never contains a control down→up transition. Even the target key's *keyUp*
still asserts control. Release-driven consumers (Dia's switcher, the macOS
app-switcher, any HUD that commits on modifier-up) therefore never see the
release and hang. Instantaneous shortcuts (`cmd+t`, `cmd+shift+c`) are
unaffected because they fire on keyDown and ignore modifier release — which
is why most existing bindings work today.

### Verified facts (live spike against Dia)

- A genuinely *held* control (posted via System Events `key down control`)
  keeps Dia's MRU HUD open and **walks** the selection on repeated `tab`
  (focus moved tab 7 → tab 3 across two taps).
- **Releasing control commits** the highlighted tab (focus settled on the
  walked-to tab after `key up control`).
- So Dia tracks event-flag/modifier state, not physical key hardware —
  synthetic modifier events are sufficient.

## Goals

1. **Fix** `send-keystroke` so a chord genuinely presses and releases its
   modifiers. A one-shot `(send-keystroke '(ctrl) "tab")` should open Dia's
   switcher *and commit* (flip to the most-recent tab).
2. **Add** an explicit key down/up mechanism so a modifier can be *held*
   across multiple discrete key taps and released on demand — enabling a
   sticky "walk the MRU stack" modal.

Non-goals: changing the modal/dispatch machinery; the config-side sticky
modal (Part 3) is described here for context but lands as a follow-up in the
`~/.config/modaliser` repo.

## Design

### Part 1 — Proper modifier bracketing in `KeystrokeEmitter`

Replace the flag-only emission with a bracketed chord:

```
for each modifier key (accumulating flags):  post modifierKeyDown(flags = accumulated)
post targetKeyDown(flags = allMods)
post targetKeyUp(flags = allMods)
for each modifier key in reverse (decreasing flags): post modifierKeyUp(flags = remaining)
  // final modifier-up posts with flags = [] → fully released
```

- **Modifier virtual keycodes:** control 59, shift 56, command 55, option 58
  (left-hand variants). Map from the `CGEventFlags` the library already
  parses.
- **Tagging is mandatory.** Every posted event — including the new modifier
  keyDown/keyUp — must carry `eventSourceUserData = KeyboardCapture.reInjectionMagic`,
  exactly as the current code tags the target key. Modaliser's capture tap
  (`eventMask = keyDown | keyUp`) sees these events; while a modal is active
  the catch-all suppresses any non-`cmd` key. A `control` keyDown reads as a
  non-cmd key and would be swallowed without the tag. **This is the single
  most error-prone part of Part 1.**
- **Ordering:** modifiers pressed before the key, released after, so the key
  event always observes the full modifier set, and the final state is clean
  (no asserted flags).

**Blast radius:** `send-keystroke` is a hot path (space-switch `Ctrl+1..9`,
iTerm `Cmd+Shift+C`, `Cmd+Shift+Return`). The new emission is strictly more
correct, but is a behavioural change to shared code. Mitigation: manual
re-test of each existing call site after the change (see Verification).

### Part 2 — Explicit `send-key-down` / `send-key-up`

Add two procedures to `(modaliser input)`:

```
(send-key-down mods key)   ; post a single keyDown for `key` with `mods` flags
(send-key-up   mods key)   ; post a single keyUp   for `key` with `mods` flags
```

- Same modifier-symbol parsing as `send-keystroke` (`parseModifiers`).
- Same `reInjectionMagic` tagging.
- Extend the named-key table with **modifier names** (`"ctrl"`, `"shift"`,
  `"cmd"`/`"command"`, `"alt"`/`"option"`) → their virtual keycodes, so a
  modifier can be held on its own:
  `(send-key-down '() "ctrl")` … `(send-key-up '() "ctrl")`.
- Generic (any key), not modifier-only — chosen for reusability; matches the
  "key down/up mechanism" framing.

These are the held-walk primitives.

> **CORRECTED BY VERIFICATION (see Verification Results below).** The original
> design assumed two things that live testing disproved:
> 1. A modifier is held with `(send-key-down '() "ctrl")`. **Wrong** — that
>    posts the control *keycode* with empty flags, which the system does not
>    register as control *held*. The down event must assert its own flag:
>    `(send-key-down '(ctrl) "ctrl")`.
> 2. Taps go through plain `(send-keystroke '() "tab")`, "because control is
>    genuinely held." **Wrong** — raw CGEvent posting does not propagate a
>    separately-held synthetic modifier onto later independent events, so a
>    plain tab is just a tab and Dia never sees `ctrl+tab`. Each tap must
>    carry the flag itself, via `(send-key-down '(ctrl) "tab")` +
>    `(send-key-up '(ctrl) "tab")` — *not* `send-keystroke '(ctrl) …`, which
>    now brackets and would release the held control.

### Part 3 — Sticky "Recent Tabs" modal (config follow-up, not this repo)

Verified recipe (each tap carries the ctrl flag; control is held across the
whole modal and released only on exit):

```scheme
(define (dia-tab-tap)            ; one ctrl+tab without releasing control
  (send-key-down '(ctrl) "tab")
  (send-key-up   '(ctrl) "tab"))

(group "r" "Recent Tabs" 'sticky #t 'exit-on-unknown #t
  'on-enter (λ () (send-key-down '(ctrl) "ctrl") (dia-tab-tap))
  'on-leave (λ () (send-key-up   '() "ctrl"))      ; flags empty = control released
  (key "j" "Next" (λ () (dia-tab-tap)))
  (key "k" "Prev" (λ () (send-key-down '(ctrl shift) "tab")
                        (send-key-up   '(ctrl shift) "tab"))))
```

**Ergonomics note / optional Part 2 refinement:** the redundant
`(send-key-down '(ctrl) "ctrl")` is a wart — `send-key-down`/`send-key-up`
could auto-assert a modifier's own flag when the key *name* is a modifier, so
callers write `(send-key-down '() "ctrl")` and it works. Deferred; the
explicit-flag recipe above is proven and sufficient.

**Safety-critical invariant:** `on-leave` must release the held modifier on
*every* exit path — commit, Escape, unknown-key exit, and handler error. A
leaked hold is a genuinely stuck modifier (unlike the Part-1 Dia hang, which
was only Dia's UI state). To verify during Part 3: that `group` honours
`on-enter`/`on-leave` (confirmed only on `define-tree` so far), and that the
error-recovery path that deregisters the catch-all also runs `on-leave`.

## Testing & verification

- **Unit-testable (TDD):** the keycode-table additions (modifier names →
  keycodes) and modifier parsing — follow `KeystrokeEmitterTests` /
  `InputLibraryTests` patterns. Write these first.
- **Not unit-testable:** actual CGEvent posting (hits the live system).
  Verified manually:
  1. One-shot: `(send-keystroke '(ctrl) "tab")` in Dia flips to the
     most-recent tab and the HUD closes.
  2. Regression: space-switch `Ctrl+1..9`, iTerm `Cmd+Shift+C` /
     `Cmd+Shift+Return` still behave.
  3. Held walk (once Part 2 lands): down ctrl → repeated `tab` walks the
     HUD → up ctrl commits; HUD never sticks.

## Verification Results (2026-06-19, live against Dia, ad-hoc-signed build)

Driven via temporary scratch bindings in the global tree, triggered by
synthesising the F18 leader + the binding key, observed via Dia AppleScript
(`isFocused of every tab`) and `screencapture`.

- ✅ **One-shot fix.** `(send-keystroke '(ctrl) "tab")` flipped focus to the
  most-recent tab AND the switcher HUD closed (screenshot confirmed no HUD).
  This is the original bug fixed — the old flag-only chord left the HUD open.
- ✅ **Held walk.** With the corrected recipe (control held via
  `send-key-down '(ctrl) "ctrl"`; two `send-key-down/up '(ctrl) "tab"` taps
  spaced by `after-delay`; released via `send-key-up '() "ctrl"`), the HUD
  opened, stepped through tabs (screenshot caught the grid mid-walk), and
  committed on release. No stuck modifier afterward.
- ✅ **Regression.** `(send-keystroke '(cmd) "t")` opened exactly one new Dia
  tab (17 → 18) — the bracketed chord works for `cmd` shortcuts; no extra tabs
  (no stuck cmd).
- ✅ **Capture path.** All of the above were dispatched through Modaliser's own
  leader + modal, confirming the new modifier events pass the capture tap
  (tagging works) even though the ad-hoc rebuild required no permission issues
  in practice.

Two recipe corrections fell out of this (folded into Part 2/Part 3 above):
holding a modifier needs its flag asserted on the down event, and walk taps
must carry the flag themselves (a separately-held synthetic modifier does not
attach to later independent CGEvents).

## Risks

| Risk | Mitigation |
|---|---|
| Untagged modifier events suppressed by the modal catch-all | Tag every posted event with `reInjectionMagic`; assert in manual test that sends from inside a modal still land. |
| Part 1 regresses existing `send-keystroke` callers | Manual regression pass over every call site. |
| Synthetic lone modifier-up doesn't commit a flag-opened HUD | Part 1's bracketed chord always pairs down→up, so the one-shot path posts a real down first; this is the validated shape. |
| Leaked modifier hold in Part 3 | `on-leave` releases on every exit path; verify error path too. |
