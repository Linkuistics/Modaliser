# Per-leader passthrough and modifier-aware leaders

## Problem

Modaliser is installed on both a host machine and a remote work machine that
the user views via Jump Desktop. When Jump Desktop is frontmost on the host,
the host's Modaliser captures the leader keys before they can reach the
remote machine, so the remote Modaliser is unreachable.

Two capabilities are needed:

1. **Per-leader passthrough by frontmost app.** A specific leader keycode
   should pass through to the OS (and therefore through Jump Desktop to the
   remote machine) when a configured app is frontmost, while continuing to
   capture normally otherwise.

2. **Modifier-aware leaders.** A separate "escape" leader, distinguished by
   a modifier (e.g. `Shift+F18`), must always be captured locally so the
   user can still drive the host's Modaliser while remoting.

## User-facing API

`set-leader!` gains two optional keyword arguments:

```scheme
;; Passthrough leaders — sent to remote when Jump Desktop is frontmost
(set-leader! 'global F18
             'passthrough-when-frontmost '("com.jumpdesktop.Jump-Desktop"))
(set-leader! 'local F17
             'passthrough-when-frontmost '("com.jumpdesktop.Jump-Desktop"))

;; Escape leaders — always grab locally
(set-leader! 'global F18 'modifiers '(shift))
(set-leader! 'local F19 'modifiers '(shift))
```

- `'modifiers <symbol-list>` — required modifier mask. Symbols are drawn
  from `cmd`, `shift`, `alt`, `ctrl`. Omitted means no modifiers (exact
  match: zero modifiers required *and* none present).
- `'passthrough-when-frontmost <string-list>` — list of bundle IDs. When
  the leader fires and the frontmost application's bundle ID is in this
  list, the event passes through to the OS instead of being captured.
  Empty list or omitted is equivalent: always capture.

Keyword args may appear in any order and are independent. Both single-arg
(`(set-leader! keycode ...)`) and two-arg (`(set-leader! mode keycode ...)`)
forms accept the new keywords as trailing args.

Re-calling `set-leader!` for the same `(keycode, modifiers)` pair
overwrites both the handler and the passthrough list. Different modifier
combinations on the same keycode are independent registrations.

### Multiple leaders per mode

Already supported and unchanged: each `set-leader!` call registers one
hotkey, so calling it twice with different keycodes (or, now, different
keycode+modifier combinations) registers two leaders that open the same
tree.

## Architecture

The decision of suppress-vs-pass must be made synchronously inside the
CGEvent tap (`KeyboardLibrary.swift:122`), because returning to the tap
late results in an already-delivered keystroke. Scheme handler evaluation
is deliberately deferred to the next main-loop tick to avoid WKWebView
deadlocks. Therefore: **the passthrough rule lives in Swift**, fed by a
static list registered from Scheme. No Scheme call happens on the event
tap thread.

The change layers are:

```
set-leader!           ─ Scheme dsl.scm
  └─ register-hotkey! ─ Scheme primitive (KeyboardLibrary)
       └─ HotkeyEntry on KeyboardHandlerRegistry
            └─ dispatch checks frontmost bundle ID synchronously
```

The catch-all path (modal-active dispatch) is untouched. Passthrough is a
property of the leader/hotkey layer only. Once the modal is active
locally, the catch-all owns dispatch as today, regardless of frontmost.

## Components

### `KeyboardHandlerRegistry`

Replace `hotkeyHandlers: [CGKeyCode: () -> Void]` with:

```swift
struct HotkeyKey: Hashable {
    let keyCode: CGKeyCode
    let modifiers: CGEventFlags  // normalized to [cmd, shift, alt, ctrl]
}

struct HotkeyEntry {
    let handler: () -> Void
    let passthroughBundleIds: [String]   // empty = always capture
}

var hotkeyHandlers: [HotkeyKey: HotkeyEntry] = [:]
```

`CGEventFlags` is not `Hashable` out of the box; use its `rawValue`
internally if needed (e.g. wrap as a `UInt64` field). The set of relevant
bits is fixed to `[.maskShift, .maskControl, .maskAlternate, .maskCommand]`.

Add an injectable frontmost lookup for testability:

```swift
var frontmostBundleId: () -> String? = {
    NSWorkspace.shared.frontmostApplication?.bundleIdentifier
}
```

### `KeyboardHandlerRegistry.dispatch`

```swift
func dispatch(keyCode: CGKeyCode, modifiers: CGEventFlags) -> KeyboardDispatchResult {
    if let catchAll = catchAllHandler {
        let shouldSuppress = catchAll(keyCode, modifiers)
        return shouldSuppress ? .suppress : .passThrough
    }

    let normalized = modifiers.intersection(
        [.maskShift, .maskControl, .maskAlternate, .maskCommand])
    let key = HotkeyKey(keyCode: keyCode, modifiers: normalized)

    if let entry = hotkeyHandlers[key] {
        if !entry.passthroughBundleIds.isEmpty,
           let bundleId = frontmostBundleId(),
           entry.passthroughBundleIds.contains(bundleId) {
            return .passThrough
        }
        entry.handler()
        return .suppress
    }

    return .passThrough
}
```

Notes:
- Modifier normalization masks off Caps Lock, function-key, numpad bits.
- Lookup is exact-match on the normalized modifier mask.
- The frontmost lookup is only performed when an entry exists *and* it has
  a non-empty passthrough list.

### `KeyboardLibrary.registerHotkeyFunction`

Extend the Scheme primitive signature:

```scheme
(register-hotkey! keycode handler [modifier-mask [passthrough-bundle-ids]])
```

- `modifier-mask`: integer bitmask of `MOD-CMD | MOD-SHIFT | MOD-ALT | MOD-CTRL`.
  Defaults to `0`.
- `passthrough-bundle-ids`: Scheme list of strings. Defaults to empty.

Convert the modifier mask to `CGEventFlags` (filtered to the four primary
bits), and the passthrough list to `[String]`, before storing on the
registry.

`unregister-hotkey!` becomes `(unregister-hotkey! keycode [modifier-mask])`
to remove a specific binding. Unregistering with no modifier removes the
no-modifier binding only — different modifier combinations are
independent.

### `dsl.scm` — `set-leader!`

Rewrite to parse trailing keyword pairs:

```scheme
(define (modifier-symbols->mask syms)
  (let loop ((s syms) (mask 0))
    (cond
      ((null? s) mask)
      ((eq? (car s) 'cmd)   (loop (cdr s) (bitwise-or mask MOD-CMD)))
      ((eq? (car s) 'shift) (loop (cdr s) (bitwise-or mask MOD-SHIFT)))
      ((eq? (car s) 'alt)   (loop (cdr s) (bitwise-or mask MOD-ALT)))
      ((eq? (car s) 'ctrl)  (loop (cdr s) (bitwise-or mask MOD-CTRL)))
      (else (loop (cdr s) mask)))))

(define (set-leader! . args)
  ;; Leading-arg disambiguation: if the first arg is the symbol 'global or
  ;; 'local, the form is (mode keycode . keyword-pairs); otherwise it's
  ;; (keycode . keyword-pairs) with mode = #f. Note: only 'global and
  ;; 'local count as a mode — other symbols (e.g. 'modifiers) belong to
  ;; the keyword-pair tail.
  (let-values (((mode keycode tail)
                (if (and (pair? args)
                         (symbol? (car args))
                         (or (eq? (car args) 'global) (eq? (car args) 'local)))
                  (values (car args) (cadr args) (cddr args))
                  (values #f (car args) (cdr args)))))
    ;; Walk tail as (key value key value ...) pairs.
    (let loop ((rest tail) (mod-mask 0) (passthrough '()))
      (cond
        ((null? rest)
         (register-hotkey! keycode
                           (make-leader-handler keycode mode)
                           mod-mask
                           passthrough))
        ((eq? (car rest) 'modifiers)
         (loop (cddr rest) (modifier-symbols->mask (cadr rest)) passthrough))
        ((eq? (car rest) 'passthrough-when-frontmost)
         (loop (cddr rest) mod-mask (cadr rest)))
        (else
         (error "set-leader!: unknown keyword" (car rest)))))))
```

## Behaviour change

Today, `hotkeyHandlers` lookup is keycode-only — pressing `Shift+F18`
fires the plain `F18` leader because modifiers are ignored on the hotkey
path. After this change, lookup is exact-match: `Shift+F18` with no
`Shift+F18` binding falls through (passes to the OS) rather than firing
`F18`. This is the correct semantics for the new feature, but is a small
breaking change for any existing config that relied on loose matching.
Document in the changelog/release notes.

## Edge cases

- **Frontmost app changes mid-modal**: irrelevant. Once modal is active,
  the catch-all owns dispatch; passthrough only applies on the
  hotkey/leader path.
- **Leader pressed while modal already active**: catch-all sees it, the
  existing `modal-key-handler` exits modal when the keycode equals
  `modal-leader-keycode`. Unchanged behaviour.
- **Empty passthrough list** (`'()`): equivalent to omitting the keyword.
  Always capture.
- **Unknown bundle ID in list**: simply doesn't match. No validation, no
  warning.
- **Caps Lock / function-key bits set on incoming event**: masked off by
  the normalization step before lookup.

## Files touched

- `Sources/Modaliser/KeyboardHandlerRegistry.swift` — `HotkeyKey`,
  `HotkeyEntry`, normalized-modifier dispatch, injectable frontmost
  lookup.
- `Sources/Modaliser/KeyboardLibrary.swift` — `register-hotkey!` accepts
  optional modifier mask and passthrough list; `unregister-hotkey!`
  accepts optional modifier mask.
- `Sources/Modaliser/Scheme/lib/dsl.scm` — `set-leader!` rewrite,
  `modifier-symbols->mask` helper.
- `Sources/Modaliser/Scheme/default-config.scm` — add a commented-out
  example showing the Jump Desktop pattern (passthrough leader + Shift
  escape leader).
- `Tests/` — new `KeyboardHandlerRegistryTests` covering:
  - exact modifier match (Shift+F18 fires only the Shift+F18 binding;
    plain F18 binding does not fire on Shift+F18)
  - passthrough returns `.passThrough` when frontmost matches, handler
    not invoked
  - passthrough captures normally when frontmost does not match
  - empty passthrough list captures normally
  - modifier normalization (Caps Lock bit set on incoming event still
    matches a no-modifier binding)

## Testing

Inject `frontmostBundleId` on the registry to stub `NSWorkspace` in
tests. The registry is already independent of the CGEvent tap, so
dispatch can be exercised with synthetic `(keyCode, modifiers)` pairs.

Manual verification on the host machine:
1. With Jump Desktop frontmost, press the configured passthrough leader —
   the host's modal does not open; the remote's modal opens (visible in
   the Jump Desktop window).
2. With Jump Desktop frontmost, press `Shift+<leader>` — the host's modal
   opens locally; subsequent keys are captured locally and not forwarded
   to the remote.
3. With any other app frontmost, press the leader — host's modal opens
   as before.
