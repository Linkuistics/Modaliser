# How to add a binding to the global tree

You want a new key in the F18 (global) overlay — a one-tap launcher, a
keystroke replay, or a shell-command trigger.

## You'll need

- Modaliser installed and running (the menu bar icon shows up).
- `~/.config/modaliser/config.scm` — seeded on first launch.
- For form-by-form detail: [reference/dsl.md](../reference/dsl.md).

## Steps

1. **Open your config.** The menu bar icon's **Settings…** item reveals
   `~/.config/modaliser/` in Finder. Open `config.scm` in your editor.

2. **Find `(screen 'global …)`.** Everything after the leading keyword
   block is content — `(panel …)` cards holding `(key …)` rows, plus
   `(open …)` drill-downs. A loose `(key …)` written directly under the
   `screen` (outside any panel) collects into a leading **"General"**
   panel automatically, so you can drop one in without picking a card.

3. **Drop a `(key …)` form** inside a panel (or loosely, to land in
   "General"). The third argument must be either a thunk (an action) or
   a node-returning call (a selector). Side-effecting calls must be
   wrapped:

   ```scheme
   (panel "Applications"
     …
     (key "v" "Vim Notes" (λ () (launch-app "MacVim"))))
   ```

   Place it wherever you want it to read in the overlay — rows flow in
   declaration order within each panel.

4. **For keystroke replay** instead of an app launch, use
   `send-keystroke`:

   ```scheme
   (key "p" "Paste Plain" (λ () (send-keystroke '(cmd shift opt) "v")))
   ```

5. **For a shell command,** use `run-shell`:

   ```scheme
   (key "L" "Lock Screen" (λ () (run-shell "/usr/bin/pmset displaysleepnow")))
   ```

6. **Save and relaunch.** Modaliser doesn't reload in place. Pick
   **Relaunch** from the menu bar icon (or close and reopen the app).

## Verify it worked

Tap F18, wait for the overlay (default delay 0.3 s), then press your
new key. The action should fire and the modal should close.

If the overlay shows your key but pressing it does nothing, see
[debug-binding.md](debug-binding.md). The single most common cause is
forgetting the `(λ () …)` wrapper — bare `(launch-app "X")` fires once
at config-load and never again.

## Variations

**Multiple keys, one action.** Use `(keys …)` when several keys should
fire variants of one labelled action:

```scheme
(keys '("1" ..) "Switch Space"
      (λ (k i ks) (send-keystroke '(ctrl) k)))
```

This renders as a single `"1.."` row in the overlay and binds digits
`"1"` through `"9"`. The action receives the matched key, its index,
and the full keylist — branch on whichever you need.

**Submenu.** Use `(group …)` for a quick flat nested menu — a `›` row
that drills into a single list of children (reach for `(open …)`
instead when the destination wants its own grid of panels):

```scheme
(group "f" "Files"
  (key "n" "New"   (λ () (run-shell "touch ~/Desktop/untitled.txt")))
  (key "o" "Open"  (launcher:find-file))
  (key "h" "Home"  (λ () (reveal-in-finder "~"))))
```

Pressing `f` from the global root descends into the group; pressing
`Backspace` returns to the root.

The `launcher:` prefix above assumes `(import (prefix (modaliser
launchers) launcher:))` near the top of `config.scm` — already
present in the seeded default config.

## Related

- [reference/dsl.md](../reference/dsl.md) — every layout form
  (`screen`, `panel`, `open`, `fragment`) and dispatch atom, with
  signatures.
- [reference/keyboard.md](../reference/keyboard.md) — navigation keys
  inside the modal (Escape, Backspace, …).
- [add-a-per-app-tree.md](add-a-per-app-tree.md) — for bindings that
  should only fire when a specific app is frontmost.
