# How to set up a sticky mode

A sticky group keeps firing — press the leader once, then chain
multiple key presses without re-arming. The canonical use is
focus-movement: `h j k l` to walk between window panes, mark to mark,
or split to split, all on a single leader tap.

## You'll need

- A handful of related actions that feel like *one tool* the user
  reaches for repeatedly. Sticky mode adds value when 2+ presses in a
  row are the norm.
- For the modal lifecycle and dispatch rules:
  [reference/state-machine.md](../reference/state-machine.md).

## Steps

1. **Wrap the related bindings in a `(group …)`** with `'sticky #t`:

   ```scheme
   (group "p" "Pane" 'sticky #t
     (key "h" "Left"  (λ () (send-keystroke '(cmd alt) "left")))
     (key "j" "Down"  (λ () (send-keystroke '(cmd alt) "down")))
     (key "k" "Up"    (λ () (send-keystroke '(cmd alt) "up")))
     (key "l" "Right" (λ () (send-keystroke '(cmd alt) "right"))))
   ```

   Pressing F18 → `p` enters the group; subsequent `h j k l` presses
   fire the focus-move keystrokes and the modal *resets to the group's
   root* instead of exiting. The overlay border picks up the
   sticky-mode accent so the user always sees they're inside a mode.

2. **Add `'exit-on-unknown #t`** if typing a non-binding key should
   hand control back to the underlying app. Without this, unknown keys
   are swallowed (forgiving default — protects against typos in deep
   trees):

   ```scheme
   (group "p" "Pane" 'sticky #t 'exit-on-unknown #t
     (key "h" "Left"  (λ () (send-keystroke '(cmd alt) "left")))
     …)
   ```

   `'exit-on-unknown` is inherited along the path, so you can also set
   it on a sticky tree root and every descendant inherits it.

3. **Save and relaunch.**

## Escape conventions

A sticky mode always honours two exits:

| Key | Effect |
|---|---|
| `Escape` | Full teardown from any depth, regardless of mode stack. |
| `Backspace` | At the sticky group's root, exit the mode (or pop to the caller mode if the stack is non-empty). At deeper depths, retreat one level. |

With `'exit-on-unknown #t`, *any* non-binding key also exits — useful
for movement modes where users expect typing to resume normally as
soon as they start typing prose.

## Verify it worked

Press the leader, then your sticky group's key. Confirm:

- The overlay shows the sticky border accent (thicker, host-coloured).
- Pressing a bound key fires the action and the overlay *stays up*.
- Pressing `Escape` (or `Backspace` at the root) dismisses cleanly.

## Variations

**Sticky tree (whole leader).** Set `'sticky #t` on `define-tree`'s
leading keywords for a tree that is *always* sticky — useful when the
local leader for an app should keep one binding fired in a row:

```scheme
(define-tree 'my.app
  'sticky #t
  'exit-on-unknown #t
  'display-name "MyApp"
  (key "h" "Left" …)
  …)
```

The overlay shows immediately on entry (sticky roots skip the delay —
the overlay *is* the mode indicator).

**Fire-and-switch via `'sticky-target`.** Sometimes you want a binding
in a transient tree to fire its action *and* drop the user into a
sticky mode. `'sticky-target` on a `(key …)` does both in one press:

```scheme
;; In the transient app tree:
(key "h" "Left" (λ () (send-keystroke '(cmd alt) "left"))
  'sticky-target 'my-pane-focus)

;; Plus the registered sticky destination:
(define-tree 'my-pane-focus
  'sticky #t
  'exit-on-unknown #t
  'display-name "Focus"
  (key "h" "Left"  (λ () (send-keystroke '(cmd alt) "left")))
  (key "j" "Down"  …)
  (key "k" "Up"    …)
  (key "l" "Right" …))
```

The overlay paints a `↻` marker on the `'sticky-target` cell. On
the *first* press of `h`, both the action *and* the mode-transition
happen — the binding's own action fires before the modal switches
into the sticky tree. From the second press onward, `hjkl` dispatch
against the sticky tree's own bindings. The bundled `(modaliser apps
iterm)` uses this pattern — see its `.sld` for a worked example.

**Nested sticky.** Sticky groups compose. The reset target after a
leaf fires is always the *deepest* sticky group on the current path,
so nested subgroups stay sticky in their own right.

## Related

- [reference/state-machine.md](../reference/state-machine.md) — sticky
  semantics, hook gating, `modal-stack`.
- [reference/dsl.md](../reference/dsl.md) — `(group …)`, `(define-tree
  …)`, `'sticky-target` keyword.
- [add-a-per-app-tree.md](add-a-per-app-tree.md) — per-app trees that
  pair well with focus-movement sticky modes.
