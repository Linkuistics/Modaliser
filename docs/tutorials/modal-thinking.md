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
