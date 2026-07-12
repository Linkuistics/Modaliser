# How to set up a Walk

A **Walk** is a collection of bindings that keeps firing — press the
leader once, then chain multiple key presses without re-arming. The
canonical use is focus-movement: `h j k l` to walk between window
panes, mark to mark, or split to split, all on a single leader tap.

Unlike the old "sticky mode" flag, a Walk isn't a group-level switch —
it's *derived* from each member leaf declaring a cyclic `'next 'self`
edge (ADR-0015). A binding that omits `'next` is **Terminal** and
exits normally; one that declares `'next 'self` re-arms the collection
in place.

## You'll need

- A handful of related actions that feel like *one tool* the user
  reaches for repeatedly. A Walk adds value when 2+ presses in a
  row are the norm.
- For the modal lifecycle and dispatch rules:
  [reference/state-machine.md](../reference/state-machine.md).

## Steps

1. **Wrap the related bindings in a `(group …)`**, and give each
   member key `'next 'self`:

   ```scheme
   (group "p" "Pane"
     (key "h" "Left"  (λ () (send-keystroke '(cmd alt) "left"))  'next 'self)
     (key "j" "Down"  (λ () (send-keystroke '(cmd alt) "down"))  'next 'self)
     (key "k" "Up"    (λ () (send-keystroke '(cmd alt) "up"))    'next 'self)
     (key "l" "Right" (λ () (send-keystroke '(cmd alt) "right")) 'next 'self))
   ```

   Pressing F18 → `p` enters the group; subsequent `h j k l` presses
   fire the focus-move keystrokes and each one's `'next 'self` re-arms
   the group in place instead of exiting. The overlay border picks up
   the Walk accent so the user always sees they're inside one.

2. **Add `'exit-on-unknown #t`** if typing a non-binding key should
   hand control back to the underlying app. Without this, unknown keys
   are swallowed (forgiving default — protects against typos in deep
   trees):

   ```scheme
   (group "p" "Pane" 'exit-on-unknown #t
     (key "h" "Left"  (λ () (send-keystroke '(cmd alt) "left")) 'next 'self)
     …)
   ```

   `'exit-on-unknown` is inherited along the path, so you can also set
   it on a tree root and every descendant inherits it.

3. **Save and relaunch.**

## Escape conventions

A Walk always honours two exits:

| Key | Effect |
|---|---|
| `Escape` | Full teardown from any depth, regardless of mode stack. |
| `Backspace` | At the Walk's root, exit the mode (or pop to the caller mode if the stack is non-empty). At deeper depths, retreat one level. |

With `'exit-on-unknown #t`, *any* non-binding key also exits — useful
for movement modes where users expect typing to resume normally as
soon as they start typing prose.

## Verify it worked

Press the leader, then your Walk's key. Confirm:

- The overlay shows the Walk border accent (thicker, host-coloured).
- Pressing a bound key fires the action and the overlay *stays up*.
- Pressing `Escape` (or `Backspace` at the root) dismisses cleanly.

## Variations

**A whole leader as a Walk.** There's no tree-level flag anymore — a
`screen`'s root becomes a Walk the same way any group does, by its
member keys declaring `'next 'self`. Useful when the local leader for
an app should keep one binding fired in a row. Loose keys render bare
in the loose region above the panel grid (no card):

```scheme
(screen 'my.app
  'exit-on-unknown #t
  'display-name "MyApp"
  (key "h" "Left" … 'next 'self)
  …)
```

The overlay shows immediately on entry (Walk roots skip the delay —
the overlay *is* the mode indicator).

**Fire-and-cross via `'next`.** Sometimes you want a binding in a
transient tree to fire its action *and* drop the user into a Walk.
`'next` on a `(key …)` does both in one press — a **cross edge** into
the registered Walk, distinct from the **cyclic edge** (`'next 'self`)
the Walk's own members use to keep cycling:

```scheme
;; In the transient app tree:
(key "h" "Left" (λ () (send-keystroke '(cmd alt) "left"))
  'next 'my-pane-focus)

;; Plus the registered Walk destination — its own members carry
;; 'next 'self, not 'next 'my-pane-focus:
(screen 'my-pane-focus
  'exit-on-unknown #t
  'display-name "Focus"
  (key "h" "Left"  (λ () (send-keystroke '(cmd alt) "left"))  'next 'self)
  (key "j" "Down"  … 'next 'self)
  (key "k" "Up"    … 'next 'self)
  (key "l" "Right" … 'next 'self))
```

The overlay paints a `↻` marker on any cell carrying `'next` — cross
or cyclic alike. On the *first* press of `h`, both the action *and*
the mode-transition happen — the binding's own action fires before the
modal crosses into the Walk. From the second press onward, `hjkl`
dispatch against the Walk's own bindings (each re-arming via its own
`'next 'self`). The bundled `(modaliser apps iterm)` uses this pattern
— see its `.sld` for a worked example.

When the entry keys and the destination keys are the same list (as
above), `(walk …)` packages both halves in one form — it registers the
mode tree (decorating each member `'next 'self`) *and* returns the
entry keys decorated with `'next MODE-ID`, so you write the list once
and splice it into any parent. See
[reference/dsl.md](../reference/dsl.md#walk-mode-id-display-name-key).

**Nested Walks.** Groups compose freely — a nested group is a Walk in
its own right if its own members declare `'next 'self`, independent of
any ancestor. There's no "deepest sticky ancestor" concept anymore
(that was the old flag-based reset target); each leaf's `'next` says
exactly where firing it goes.

## Related

- [reference/state-machine.md](../reference/state-machine.md) — the
  `'next` edge, Terminal nodes, Walk semantics, hook gating,
  `modal-stack`.
- [reference/dsl.md](../reference/dsl.md) — `(group …)`, `(screen …)`,
  `(walk …)`, the `'next` keyword.
- [add-a-per-app-tree.md](add-a-per-app-tree.md) — per-app trees that
  pair well with focus-movement Walks.
