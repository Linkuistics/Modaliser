# Modal Thinking — build a window-manager leader

In this tutorial you'll build a `w` "Windows" leader from a one-key
stub up to something that looks a lot like the bundled
`default-config.scm`'s window-management overlay. Along the way you'll
meet every concept Modaliser is built from — leaders, overlays,
blocks, selectors, sticky modes, sticky-target — by *using* them, not
by reading a table.

By the end you'll have:

- A working `w` overlay you can keep using day-to-day.
- The vocabulary to read the rest of the docs as specific instances of
  two patterns you now understand: the **launcher** pattern (most of
  Modaliser) and the **modal** pattern (iTerm's `Focus` mode and
  friends).

It should take 30–60 minutes if you're new to the system; less if
you're returning. Every step ends with a *Relaunch* and a *Press F18
and look* beat — you'll feel the difference each form makes.

## Before you start

- You've installed Modaliser and done the quickstart at
  [`../quickstart/`](../quickstart/index.md). F18 opens the global
  tree on your machine; you've edited `~/.config/modaliser/config.scm`
  at least once and you know how to find the **Relaunch** item in the
  menu-bar icon.
- You're comfortable reading Scheme — `(lambda …)`, `(λ () …)`, `let`,
  `cond` don't need a primer here.
- You have a backup of your current `config.scm` somewhere safe. The
  tutorial overwrites the file as it goes; if you want to keep what
  you have, copy it aside before Step 1.

## How this tutorial works

Each step adds **one** Modaliser concept, ends with a one-line config
edit, and asks you to *Relaunch* (menu-bar icon → Relaunch) and press
some keys to feel what changed. Don't read ahead — the moments of
"oh, that's what an overlay is" only land if you've felt the previous
step on your own screen.

If a step's verification doesn't behave as described, *stop and check
the snippet against what you typed* before moving on. The forms are
small; a missing parenthesis is usually the culprit.

## Step 1 — A leader with one binding

A *leader* is a hotkey that opens a menu, not an action. The menu can
have one entry, ten entries, or nested sub-menus — F18 just opens it;
what's inside is up to you. This step writes the smallest possible
global tree: one binding under `w` that maximises the current window.

Replace `~/.config/modaliser/config.scm` with:

```scheme
(import (modaliser dsl)
        (modaliser keyboard)   ; F18, F17 keycode constants
        (modaliser leader)     ; set-leaders!
        (modaliser window))    ; move-window

(set-leaders! 'global-keycode F18
              'local-keycode  F17)

(define-tree 'global
  (key "w" "Maximise" (λ () (move-window 0 0 1 1))))
```

`move-window` takes four unit fractions of the primary screen — x, y,
width, height. Pass it `0 0 1 1` and the focused window covers the
whole screen; that's what "maximise" means here. You'll meet
`move-window` again in Step 3, where Modaliser computes those four
numbers for you from a grid.

The `(λ () …)` wrap is non-negotiable. Without it, the call
`(move-window 0 0 1 1)` would fire once, at config-load time — the
very first time Modaliser parses the file — and `w` would be bound to
whatever that call returned (a void). The lambda defers the call until
you press the key.

**Pick Relaunch from the menu bar icon, then press F18 w.** The
current window maximises.

That single binding is a *leader* (`F18`), opening a *tree* (the
global tree, declared with `define-tree`), containing a *command*
(`(key "w" "Maximise" …)`). Three concepts, one for every level of
the nesting you just typed. Each of the next six steps adds exactly
one more.
