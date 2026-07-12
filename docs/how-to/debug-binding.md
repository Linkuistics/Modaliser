# How to debug "my binding does nothing"

You wrote a `(key …)` form, relaunched, and nothing happens when you
press the key. This is the checklist for the five most common causes,
in order of frequency.

## You'll need

- Console.app (or `log stream --predicate 'process == "Modaliser"'`)
  to see Scheme error output.

## 1. Forgot to wrap a side-effecting call in `(λ () …)`

By far the most common cause. `(key K L body)` evaluates `body` at
config-load. A bare call fires once at load and never on key press:

```scheme
;; WRONG — fires once when Modaliser starts, never again
(key "b" "Browser" (launch-app "Safari"))

;; RIGHT — thunk fires on each key press
(key "b" "Browser" (λ () (launch-app "Safari")))
```

How to spot it: the action *did* fire (the app launched on Modaliser
start), but pressing the key in the overlay does nothing. The overlay
itself shows the binding fine — load-time evaluation succeeded.

Why it works for some bodies: factories like `(launcher:find-file)`
and `(web-search:google)` return a *node alist* (a pair). The `key`
macro detects that and decorates the node with your key/label —
config-load is the right moment for that work. Bare side-effecting
calls return neither a node nor a procedure, so the macro raises (or
silently does nothing on the next press if the call was for effect).

See the third-arg dispatch table in
[reference/dsl.md](../reference/dsl.md) for the full rules.

## 2. Pressed the wrong leader

The seeded config wires F18 to the global tree and F17 to the local
(per-app) tree. A binding under `(screen 'global …)` only fires
from F18; one under `(screen 'com.your.app …)` only fires from
F17 while that app is frontmost.

Check:

```bash
# Run this AFTER the app you're testing is frontmost
osascript -e 'tell application "System Events" to bundle identifier of first application process whose frontmost is true'
```

The bundle ID it prints must match the scope you used in
`screen`. Modaliser itself becomes frontmost briefly when you
trigger menu bar items — switch via the keyboard if you want a clean
read.

## 3. The overlay shows the binding but pressing the key exits

You probably added `'exit-on-unknown #t` somewhere on the path. That
keyword inherits down — once any ancestor (or the current group) has
it set, *any* unknown key exits the modal. The likely accident is a
new binding you *intended* to put inside the Walk group, but
parentheses landed it as a sibling instead:

```scheme
;; BROKEN — "h" closes early on Pane "h" because it lives
;; outside the group; the group has only j/k/l, so
;; entering Pane and pressing h is "unknown" → exit.
(group "p" "Pane" 'exit-on-unknown #t
  (key "j" "Down"  (λ () …) 'next 'self)
  (key "k" "Up"    (λ () …) 'next 'self)
  (key "l" "Right" (λ () …) 'next 'self))
(key "h" "Left" (λ () …))     ; <-- intended to be inside, isn't
```

```scheme
;; FIXED — "h" is a child of the Walk group, so it dispatches
;; normally and the modal stays inside the group.
(group "p" "Pane" 'exit-on-unknown #t
  (key "h" "Left"  (λ () …) 'next 'self)
  (key "j" "Down"  (λ () …) 'next 'self)
  (key "k" "Up"    (λ () …) 'next 'self)
  (key "l" "Right" (λ () …) 'next 'self))
```

Count closing parens. Editors with paren-matching highlights make
this trivial; without them, the failure mode is silent.

## 4. Scope collision (one tree replaces another)

Two `(screen 'global …)` calls don't merge — the second replaces
the first. If you have multiple files declaring the same scope (e.g.
your config + a bundled factory's `register!`), the later call wins.

Check the call order in `config.scm`. Bundled factories like
`(safari:register!)` are forgiving — pass `'extra-bindings (list …)`
to add without replacing. For your own trees, keep a single
`screen` call per scope.

## 5. Modal isn't even being entered

If pressing the leader produces *no overlay at all*, the leader itself
might not be set. Confirm:

- `~/.config/modaliser/config.scm` calls `(set-leaders! …)` or
  `(set-leader! …)` somewhere near the top.
- The keycode you used is one your keyboard actually emits. F18 is
  typical for split layouts and TouchID-key replacements; on a bare
  Apple keyboard you may need to remap a less-common key (Karabiner
  Elements is a common companion).
- Modaliser has Accessibility permission. If you revoked it, the
  global keyboard capture won't fire — the onboarding window
  reappears on next launch.
- `'arm-when-frontmost` isn't suppressing the leader. That option
  lists bundle IDs whose frontmost state *suppresses* leader arming
  (so the modifier-key combo reaches the inner app instead — the
  seeded config does this for Jump Desktop). If you're frontmost in
  one of those apps, the leader silently no-ops.

## When the Console has the answer

Modaliser logs to Console.app under the `Modaliser` process. LispKit
import errors, schema-validation failures inside `screen` / `panel`,
and any `(error …)` calls from your config land there. If a binding's
behaviour is genuinely mysterious, the first move is to filter
Console for `Modaliser` and reproduce the press.

## Related

- [reference/dsl.md](../reference/dsl.md) — third-arg dispatch rules
  for `(key …)`.
- [reference/state-machine.md](../reference/state-machine.md) —
  modal lifecycle and `'exit-on-unknown` inheritance.
- [add-a-binding.md](add-a-binding.md) — the smallest-binding recipe
  this guide assumes you started from.
