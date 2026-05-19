# State machine

How the modal moves through a command tree: lifecycle, sticky
semantics, hook gating, dispatch precedence. The canonical
implementation is
[`state-machine.sld`](../../Sources/Modaliser/Scheme/lib/modaliser/state-machine.sld);
this page is the conceptual companion.

## Modal lifecycle

```
  leader press
       │
       ▼
  ┌─────────┐  key press  ┌──────────────┐
  │  arm    │ ──────────▶ │ handle-key   │
  └─────────┘             └──┬─────┬─────┘
                             │     │
            ┌────────────────┘     └──────────────┐
            │                                     │
       command leaf                          group child
            │                                     │
       ┌────┴─────┐                          ┌────┴────┐
       │ run      │                          │ descend │
       │ action   │                          │ + show  │
       └────┬─────┘                          │ overlay │
            │                                └────┬────┘
            ▼                                     │
       ┌─────────────┐                            │
       │ transient?  │ ◀──────── back-to-arm? ────┘
       └────┬────┬───┘
            │    │
        sticky  transient
            │    │
            ▼    ▼
       reset   exit
       to      modal
       sticky
       ancestor
```

(For the actual implementation, see `modal-handle-key`,
`modal-step-back`, `modal-enter`, `modal-exit` in `state-machine.sld`.)

### Arm

`(set-leaders! …)` registers the leader keycodes with the native
hotkey system. When a leader fires, `(modal-enter tree leader-kc)`
becomes the active context:

- `modal-active?` is set to `#t`.
- The catch-all key handler is registered, so every keypress while
  the modal is up is routed through `modal-handle-key` rather than
  reaching the focused app.
- A delayed overlay-show is scheduled (or shown immediately for
  sticky roots — see "Sticky semantics" below).

### Dispatch

`modal-handle-key char` looks up the child of the current node bound
to `char`:

| Child kind | Behaviour |
|---|---|
| Command | Run `(action)`. Then transient → exit; sticky → reset to deepest sticky ancestor; `'sticky-target` set → `(enter-mode! target)`. |
| Range command (from `keys` / `key-range`) | Run `(action char)`. Same cleanup as command. |
| Group | Fire `on-leave` for the leaving node, descend (push `char` onto `modal-current-path`), fire `on-enter` for the new node, refresh overlay. |
| Selector | Exit the modal (the chooser owns input focus). Open the chooser. |
| (no match) | If any ancestor (or current group) has `'exit-on-unknown #t`, exit the modal. Otherwise swallow the key. |

### Exit

`(modal-exit)` is idempotent:

- Fires `on-leave` for the current node (only if the overlay was
  visible).
- Cancels any pending delayed overlay-show.
- Hides the overlay and unregisters the catch-all key handler.
- Clears `modal-stack` — Escape from any depth is a full teardown
  regardless of how deeply stacked the modes are.

`(modal-step-back)` is the navigational sibling — retreats one level
along `modal-current-path`. At the root of a sticky tree it pops
`modal-stack` (returning to the caller mode) or exits if the stack is
empty. At the root of a transient launcher it's a no-op.

## Transient vs sticky

The default cleanup after a command-leaf fires is **transient**: the
modal exits. Most launcher-style bindings use this — press `b`, the
browser launches, the modal closes.

A group can opt into **sticky** mode by setting `'sticky #t` on the
group (or on the tree root via `define-tree`'s leading keywords):

```scheme
(group "p" "Pane" 'sticky #t
  (key "h" "Left"  (λ () (focus-pane! 'left)))
  (key "j" "Down"  (λ () (focus-pane! 'down)))
  (key "k" "Up"    (λ () (focus-pane! 'up)))
  (key "l" "Right" (λ () (focus-pane! 'right))))
```

After firing `h`, the modal *resets* to the nearest sticky ancestor
(this group) instead of exiting. So `h j h h` chains four pane focus
moves on one leader press.

**Composition.** Sticky groups can nest. The reset target is always
the *deepest* sticky ancestor on the current path — nested sticky
subgroups stay sticky in their own right.

**Sticky-root overlay timing.** A tree whose root is sticky shows the
overlay *immediately* on entry (no delay). The overlay is the mode
indicator — the user must always know they're inside a sticky mode.
Transient trees use the configured delay (`set-overlay-delay!`).

### `'sticky-target` on a key

`(key K L action 'sticky-target MODE-ID)` is a declarative form of
"run the action, then enter MODE-ID." Used in the bundled iTerm tree:

```scheme
(key "h" "Left" (keystroke '(cmd alt) "left")
  'sticky-target 'iterm-panes-focus)
```

First press: `h` fires the focus-move keystroke *and* transitions into
the sticky `'iterm-panes-focus` mode. Subsequent `h j k l` presses
keep moving panes without another leader.

The overlay paints a `↻` marker on cells that carry `'sticky-target`.

`'sticky-target` overrides the surrounding tree's transient/sticky
cleanup — the binding has declared explicit modal continuity, so the
action runs and the mode switch happens regardless. If the action
itself called `(enter-mode! …)`, that wins (root identity check
before applying the declarative target).

## The mode stack (`modal-stack`)

`(enter-mode! id)` from inside an action thunk pushes the current
modal context onto `modal-stack` and switches the modal root to the
new tree. Backspace at the root of the new tree pops back to the
caller (when the new tree is sticky).

Used by the iTerm tree: pressing `h` from the dynamic-pane tree fires
the focus-left keystroke and pushes the dynamic tree onto the stack
while entering `'iterm-panes-focus`. Backspace from the focus mode
returns to the dynamic tree.

`modal-stack` is cleared by `(modal-exit)` — Escape unwinds all
stacked callers in one shot.

## `'exit-on-unknown`

By default the modal is **forgiving**: an unrecognised key is
swallowed without exiting. This avoids accidental dismissal from
typos in a deep tree.

A group can opt back into dismissal:

```scheme
(group "p" "Pane" 'sticky #t 'exit-on-unknown #t
  (key "h" "Left" …) (key "j" "Down" …) …)
```

`'exit-on-unknown` is inherited along the path: if *any* ancestor
group (or the current group) has it set, an unknown key exits the
modal. Useful for sticky focus-movement modes where the user's next
typing should reach the underlying app rather than forcing an
explicit Escape.

## Hook gating: `on-enter` / `on-leave`

Group hooks fire only when the overlay is actually visible. The
gating matters because of the overlay delay:

| Scenario | `on-enter` fires? | `on-leave` fires? |
|---|---|---|
| User presses leader, then `w` before the delay elapses | No (overlay never showed) | No |
| User presses leader, waits, then `w` after overlay is up | Yes (for descended group) | Yes (for parent group) |
| Modal exits while overlay is hidden (fast path-through) | — | No |
| Modal exits while overlay is open | — | Yes (for current node) |

This guarantees `on-leave` always pairs with an `on-enter` that
actually fired. The pane-chip overlays in `(modaliser apps iterm)` rely
on this: `on-enter` paints chips, `on-leave` clears them, and a quick
muscle-memory press through the mode never flashes chips.

## Dispatch precedence inside a group

`find-child` walks the group's children with these rules:

1. **Literal keys win over ranges.** A `(key "5" "Special" …)` sibling
   shadows the `"5"` slot of a `(keys '("1" ..) …)` range. Walking is
   in declaration order, but a literal match returns immediately; a
   range match only commits if no literal match is found.
2. **First-range wins.** If multiple ranges include the same key,
   declaration order picks the winner.
3. **Categories are transparent.** `(category "X" (key …) …)` flattens
   in dispatch — typing a child key dispatches as if the children
   were direct group siblings. Categories only affect overlay
   rendering, not key paths.

```scheme
(define-tree 'global
  (category "Apps"
    (key "b" "Browser" (λ () (launch-app "Safari"))))
  …)
```

Typing `b` from the global root fires the browser binding — the
`category` wrapper is invisible to dispatch.

## Modal state inspection

For configs that need to introspect modal state from a hook or action:

| Export (from `(modaliser state-machine)`) | Meaning |
|---|---|
| `modal-active?` | `#t` while a modal is up. |
| `modal-current-node` | The node the user is currently navigated to. |
| `modal-root-node` | The tree root. |
| `modal-current-path` | List of keys followed from the root. |
| `(modal-stack-empty?)` | Procedural — `#t` iff no callers are stacked. |
| `(modal-root-segments)` | Procedural — current breadcrumb root segments. |
| `(overlay-open?)` | Procedural — `#t` iff the overlay is visible. |

The procedural forms exist because LispKit snapshots mutable
variable imports at compile time; closures that need to see live
mutations must call through a procedure. See the comments around
`overlay-open?` in `state-machine.sld` for the full rule.

## See also

- [dsl.md](dsl.md) — the surface forms that produce nodes the state
  machine dispatches.
- [renderer-protocol.md](renderer-protocol.md) — how overlays consume
  the current node and path.
