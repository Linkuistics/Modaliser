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
whole screen; that's what "maximise" means here. Step 3 wraps
`move-window` behind a grid you write as letter matrices; Steps 6 and
7 use it directly again for half-screen snaps.

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

## Step 2 — Make `w` into a menu

In Step 1 you bound `w` directly to a thunk, so pressing it fired
maximise and dismissed the overlay. But a leader is supposed to open a
*menu* — and a one-entry menu isn't really one. Here you'll replace
the thunk with an `(overlay …)` and put three bindings inside it.

Edit `config.scm`:

```scheme
(define-tree 'global
  (key "w" "Windows"
    (overlay
      (key "m" "Maximise" (λ () (move-window 0 0 1 1)))
      (key "c" "Centre"   (λ () (center-window)))
      (key "r" "Restore"  (λ () (restore-window))))))
```

No new imports are needed — `center-window` and `restore-window` come
from the same `(modaliser window)` import you added in Step 1
alongside `move-window`.

Notice what `(key "w" "Windows" (overlay …))` does: `(overlay …)`
*returns a node*, and the outer `(key …)` *decorates* it with the key
(`"w"`) and label (`"Windows"`). The same dispatch you'd use for any
sub-tree — overlays, groups, selectors — happens here.

**Relaunch. Press F18 w.** Three rows appear: *m Maximise*,
*c Centre*, *r Restore*. Press one of the letters; the action fires
and the overlay dismisses.

That's the **launcher** pattern in miniature — the reader (you) steps
into the tree, picks an entry, the entry fires, the tree disappears.
Steps 3–5 enrich the launcher; you won't change its essential shape
until Part 2.

## Step 3 — A layout block

So far the overlay's contents are all `(key …)` forms — bindings that
get one row each in the menu. Try writing a window manager with nine
move/resize bindings that way and the overlay is unreadable.

A *block* solves this. A block is a renderer-aware overlay ingredient
that brings *both* bindings *and* chrome (a diagram, a chip strip,
custom layout). `window:layout-block` is the one you want here: you
hand it a sequence of letter matrices describing the screen regions
each key should target, and it paints a grid of mini screen-diagrams
with the letters in the regions they bind to.

Replace the contents of the overlay with a `window:layout-block`, and
keep *Restore* as a loose `(key …)` so you can see a block and a key
coexisting:

```scheme
(import (modaliser dsl)
        (modaliser keyboard)
        (modaliser leader)
        (modaliser window)
        (prefix (modaliser window-actions) window:))

(define-tree 'global
  (key "w" "Windows"
    (overlay
      (window:layout-block
        (("d" "f" "g"))                  ; full thirds
        (("e" "e" #f))                   ; left two-thirds
        ((#f "t" "t"))                   ; right two-thirds
        (("m"))                          ; maximise (full cell)
        (center "c"))                    ; centre (inward arrows)
      (key "r" "Restore" (λ () (restore-window))))))
```

Each matrix is a row-major description of a panel: `(("d" "f" "g"))`
is one row of three cells (full-thirds), `(("e" "e" #f))` is one row
where the same letter spanning two adjacent cells produces one wider
binding (left two-thirds), and `#f` marks an empty cell. `(("m"))`
is a 1×1 matrix — one binding that fills the full cell, which is
exactly the `(move-window 0 0 1 1)` call you wrote literally in
Step 1. The `(center "c")` head-symbol form is the one exception —
it doesn't fit a grid, so it gets its own panel rendered with inward
arrows.

**Relaunch. Press F18 w.** You see the diagram strip with the letters
laid out spatially, and a single text row for *r Restore* underneath.
Press **d** — the window snaps to the left third. Press **e** —
left two-thirds. Press **m** — full-screen. Press **c** — centred.

Two ideas live in that snippet. First: an overlay can hold *multiple*
blocks alongside *loose* `(key …)` forms; you'll add more in Steps
4–5. Second: a block carries chrome the renderer paints (the grid),
not just a flat list of choices. Most of the visual richness in
Modaliser overlays comes from blocks — `window:layout-block` here,
`window:list-block` in Step 5, `which-key-block` automatically wrapped
around your loose keys.


## Step 4 — A selector

A *selector* is a fuzzy-finder bound to a key. You hand it a function
that produces the list of options each time it opens (`'source`) and a
function that runs on the chosen item (`'on-select`). The reader gets
type-to-narrow and Enter-to-select for free.

Selectors are the moment most readers' mental model snaps into place,
because of *how* they're bound. Look at the form you're about to type:

```scheme
(key "s" "Select Window"
  (selector 'prompt "Select window by name…"
            'source list-windows
            'on-select focus-window))
```

The third arg to `(key …)` is a *call* — `(selector …)`. Modaliser
evaluates it at config-load time. It returns a node — an alist
describing a selector. The `(key …)` macro sees that node and
*decorates* it with `"s"` / `"Select Window"`. The same dispatch you
saw on `(overlay …)` in Step 2.

Once you spot this pattern, every factory in the codebase reads the
same way: `(settings:actions)`, `(launcher:find-application)`,
`(web-search:google)` — they all return nodes that get decorated by
the wrapping `(key …)`.

Add the selector to your overlay (you'll already have `(modaliser window)`
in your imports — it provides `list-windows` and `focus-window`):

```scheme
(define-tree 'global
  (key "w" "Windows"
    (overlay
      (window:layout-block
        (("d" "f" "g"))
        (("e" "e" #f))
        ((#f "t" "t"))
        (("m"))
        (center "c"))
      (key "r" "Restore" (λ () (restore-window)))
      (key "s" "Select Window"
        (selector 'prompt "Select window by name…"
                  'source list-windows
                  'on-select focus-window)))))
```

**Relaunch. Press F18 w s.** You get a list of your visible windows
and an input box. The input drives *which entry in the list is
selected* — type characters from a title and the matcher walks the
list looking for the best fit. Press Enter — the action
(`focus-window`) runs against the highlighted entry and the overlay
closes.

So: input box ⇒ list selection ⇒ Enter fires `'on-select`. The input
isn't a window-focus action by itself; it's a navigator for the list
underneath it.

> The matcher is conservative: it prefers contiguous character runs
> and may need most of a title's letters before settling on the entry
> you want — short subsequence queries ("saf" for *Safari — Apple
> Developer Documentation*) often won't be enough. If you find
> yourself typing nearly the whole title, that's the matcher's
> current threshold, not a flaw in your config.

## Step 5 — The window list, with chips

Add `(window:list-block 'chips? #t)` to the bottom of the overlay:

```scheme
(overlay
  ...
  (window:list-block 'chips? #t))
```

**Relaunch. Press F18 w.** Two things happen at once: the overlay
gains a third block at the bottom listing your visible windows by
title, *and* the real windows on screen acquire little chips with
labels that match the rows in that block. The chips are the link
between "I see a row in the overlay" and "I see which window it talks
about".

You've now seen three different blocks in one overlay
(`window:layout-block`, the implicit which-key block of loose
`(key …)` forms, and `window:list-block`), plus one selector
(`Select Window`). Each fires once and the overlay dismisses; control
returns to whatever you were doing before F18.

That's Part 1 done. Everything you've built so far is the **launcher
pattern**: a tree you step through, a single action, dismiss. Most of
Modaliser looks like this — the global tree, the per-app trees, the
launchers themselves. Part 2 is one new idea: what if some bindings
*didn't* dismiss?

## Step 6 — Staying in a mode: a sticky sub-group

Everything so far has been the launcher pattern: press a key, an
action fires, the overlay dismisses. That's perfect for one-shot
gestures like *maximise* or *restore*. But what about a sequence of
actions you'd like to do without re-leading each time — flipping a
focused window through different half-screen arrangements while you
decide on a layout, say? Pressing F18 w between each press is too
many keystrokes.

Add an `(a Arrange)` sub-group inside the overlay, bound to hjkl:

```scheme
(group "a" "Arrange"
       'sticky #t
       'exit-on-unknown #t
  (key "h" "Left half"   (λ () (move-window 0    0    0.5  1)))
  (key "j" "Bottom half" (λ () (move-window 0    0.5  1    0.5)))
  (key "k" "Top half"    (λ () (move-window 0    0    1    0.5)))
  (key "l" "Right half"  (λ () (move-window 0.5  0    0.5  1))))
```

(The four `move-window` calls are the same primitive you wrote
literally in Step 1, just with different fractions — each takes the
focused window to one half of the screen.)

Two new keywords are doing the work:

- **`'sticky #t`** — when a binding inside this group fires, the
  modal navigation *stays in this group* instead of dismissing the
  whole overlay. You can press another binding right away.
- **`'exit-on-unknown #t`** — any key that *isn't* one of `h/j/k/l`
  exits the modal cleanly. Without this, unknown keys are
  swallowed — the modal stays open and you're stuck until you find
  something it recognises. Combined with `Esc` semantics, this gives
  the reader a forgiving "I'm done" gesture.

**Relaunch. Press F18 w a h l j k.** After the first `h`, the overlay
*does not dismiss* — it shows the four half-snap bindings and waits.
Press `l` — the window flips to the right half, overlay still open.
Press `j`, `k` — bottom half, top half. Press Esc — the overlay
closes and you're back in your app.

That's the **modal pattern**. The reader is now *inside* a mode and
stays until they explicitly exit. iTerm's `Focus` mode (look at
[`Sources/Modaliser/Scheme/lib/modaliser/apps/iterm.sld`](../../Sources/Modaliser/Scheme/lib/modaliser/apps/iterm.sld) later) is the
same shape applied to iTerm pane navigation.

Notice the cost, though: to start arranging a window you press *three*
keys — `w`, `a`, `h`. That's one too many for something you might do
dozens of times an hour. Step 7 fixes it with a small refactor.

## Step 7 — Sticky-target: fire AND enter, in one press

Look at iTerm's `Focus` mode — open
[`Sources/Modaliser/Scheme/lib/modaliser/apps/iterm.sld`](../../Sources/Modaliser/Scheme/lib/modaliser/apps/iterm.sld) and find the
"Focus" category around line 179. It binds hjkl too, but you don't
press an `a` first when you're in iTerm; the very first `h` *both*
moves pane-focus *and* puts you in the sticky focus tree. How?

`'sticky-target`. A trailing keyword on a `(key …)` binding: when the
binding fires, the state machine (a) runs the action, then (b)
transitions modal navigation into the sticky tree named by the
symbol. One key press does two jobs. The overlay can paint a small
marker on each cell so you can tell which keys are sticky-target
leaders.

The refactor: take the four hjkl bindings out of the `(group "a" …)`
in Step 6, give them `'sticky-target 'window-arrange`, and put them
directly into the `w` overlay. Register a *separate* sticky tree
named `'window-arrange` for the modal navigation to land in:

```scheme
;; A new top-level form, outside (define-tree 'global …):

(define-tree 'window-arrange
  'sticky #t
  'exit-on-unknown #t
  'display-name "Arrange"
  (key "h" "Left half"   (λ () (move-window 0    0    0.5  1)))
  (key "j" "Bottom half" (λ () (move-window 0    0.5  1    0.5)))
  (key "k" "Top half"    (λ () (move-window 0    0    1    0.5)))
  (key "l" "Right half"  (λ () (move-window 0.5  0    0.5  1))))

;; Inside the `w` overlay, in place of the (group "a" …) you wrote
;; in Step 6:

(key "h" "Left half"   (λ () (move-window 0    0    0.5  1))
     'sticky-target 'window-arrange)
(key "j" "Bottom half" (λ () (move-window 0    0.5  1    0.5))
     'sticky-target 'window-arrange)
(key "k" "Top half"    (λ () (move-window 0    0    1    0.5))
     'sticky-target 'window-arrange)
(key "l" "Right half"  (λ () (move-window 0.5  0    0.5  1))
     'sticky-target 'window-arrange)
```

**Relaunch. Press F18 w h l j k.** The very first `h` snaps the window
to the left half *and* swaps the overlay to the four-row Arrange tree;
subsequent presses keep snapping the same window through the other
halves. Esc exits. Compare: Step 6 needed `w a h`; Step 7 needs `w h`.

Two concepts arrived together here. The obvious one is
`'sticky-target` — fire-and-enter as a single press. The other is
quieter but more useful: **sticky trees are *named, top-level trees***
registered with their own `define-tree`. The launcher tree
(`'global`), a per-app tree (e.g. `'com.googlecode.iterm2`), and a
sticky tree (`'window-arrange`) are all sibling top-level forms — they
look structurally identical; the only difference is what *references*
them. Once you've seen three trees alongside each other, "tree"
becomes the unit of mental composition for the whole system.

iTerm's pane Focus mode is doing exactly what you just wrote, applied
to AppleScript pane-focus instead of window arrangement. Your `w h`
is structurally identical to iTerm's per-app pane Focus — same
sticky-target plumbing, different action surface.

## Step 8 — Why this is "modal"

You just built two patterns. Both live in the same `w` overlay; both
are the same DSL forms, composed differently. Naming them explicitly
is what closes the conceptual loop.

### The launcher pattern (Steps 1–5)

A tree the reader steps through. Each leaf fires once and the overlay
dismisses. Steps 1–5 built this from the ground up: a one-binding
leader, an overlay, a layout-block, a selector, a window-list. Most
of what ships in `default-config.scm` is this pattern — the global
tree, per-app trees, instant-app launchers, the search category.

When a feature should be "type X, get Y, done", this is the shape.

### The modal pattern (Steps 6–7)

A sticky tree the reader enters and stays inside until an unrecognised
key exits. Step 6 built it the explicit way (a parent key `a` opening
a sticky sub-group). Step 7 refactored to the *sticky-target* shape
the rest of the system uses (a binding both fires and transitions
into a separately-registered sticky tree, in one key press). The two
forms are equivalent for the same end state; sticky-target costs one
less keystroke per session.

When a feature should be "stay in this tiny vocabulary until I tell
you to leave", this is the shape. The canonical example is iTerm's
pane Focus — open
[`Sources/Modaliser/Scheme/lib/modaliser/apps/iterm.sld`](../../Sources/Modaliser/Scheme/lib/modaliser/apps/iterm.sld) and read
the `Focus` category alongside the `focus-mode-tree` definition. It's
structurally identical to your `w` overlay's hjkl + `'window-arrange`
tree.

### Why this matters

The system's surface area looks bigger than it is because there are
two patterns multiplying through every layer. Per-app trees? Launcher
pattern, with the tree selected by frontmost-app. `(category …)`?
A layout marker for one launcher overlay. Selectors? A launcher leaf
that runs a fuzzy-finder before firing `'on-select`. Sticky modes?
The modal pattern, scoped to a named tree. Sticky-target? The modal
pattern's polite way of saying "first press does both jobs."

Once you can name *which* pattern a thing is, the rest of the docs
read as combinations of forms you've already met.

## Where to go next

- [How to add a binding](../how-to/add-a-binding.md) — recipe for
  adding a one-shot launcher leaf to the global tree.
- [How to add a per-app tree](../how-to/add-a-per-app-tree.md) — give
  one application its own bindings under F17.
- [How to add a sticky mode](../how-to/sticky-mode.md) — recipe
  treatment of `'sticky`, `'sticky-target`, and `'exit-on-unknown`,
  for when you want to write your own.
- [How to customise the theme](../how-to/customise-theme.md) — colours,
  fonts, and chip styling via `~/.config/modaliser/theme.css`.
- [DSL reference](../reference/dsl.md) — every form, exhaustively.

## Restoring your config

The tutorial overwrote `~/.config/modaliser/config.scm` as it went.
If you'd like to go back to what you had before Step 1, copy your
backup back:

```bash
cp ~/.config/modaliser/config.scm.tutorial-bak ~/.config/modaliser/config.scm
```

Then pick **Relaunch** from the menu bar icon. Or keep the `w` overlay
you just built — it's a real config, not a throwaway.
