# Phase-3 Modal Thinking Tutorial — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `docs/tutorials/modal-thinking.md` per the design at
`docs/superpowers/specs/2026-05-19-docs-phase3-tutorial-modal-thinking-design.md`,
cross-linked from `quickstart/index.md` and `how-to/index.md`, link-
checked, with the user's `~/.config/modaliser/` restored to its
pre-implementation state and `swift test` green.

**Architecture:** Verify-then-write. For each tutorial step, write the
config snippet to the user's live `config.scm`, prompt the user to
relaunch + press F18, await confirmation that the verification beat
actually happens on screen, *then* write that step's prose, then
commit. Snippets the user can't actually run will never appear in the
tutorial. After all eight steps, cross-link, link-check, restore the
user's config from a backup, run `swift test`, request review, finish
the branch.

**Tech Stack:** Markdown docs, LispKit Scheme (config), Swift host
(Modaliser app), Python (internal link checker), git worktree on
branch `worktree-docs-phase3-tutorials`.

**Operating mode:** This plan is human-in-the-loop. Tasks 4–10 each
have a step that prompts the user to relaunch Modaliser and report
what they see — there is no way to verify the tutorial works without a
human pressing F18. If you (the executor) are a subagent without
user-facing channels, *stop and surface the blocker* rather than
guessing that a verification beat happened.

## Conventions for this plan

**Nested code fences in prose drafts.** Several "Write the prose"
steps below contain a markdown code block (the outer plan content)
whose body is the tutorial prose draft, *and* that prose draft itself
contains Scheme snippets fenced with triple-backticks. To keep
fences unambiguous, prose drafts in Tasks 4–11 use **four-backtick**
outer fences (` ````markdown ` … ` ```` `) so the inner three-backtick
` ```scheme ` … ` ``` ` fences pass through verbatim. The tutorial
file itself uses plain three-backtick fences everywhere — the
four-backtick wrapper is only used inside this plan to disambiguate.

---

## Task 1: Preflight — workspace, sweep, and source-of-truth pinning

**Files:**
- Read: `Sources/Modaliser/Scheme/lib/modaliser/window-actions.sld`
- Read: `Sources/Modaliser/Scheme/lib/modaliser/dsl.sld`
- Read: `Sources/Modaliser/Scheme/lib/modaliser/state-machine.sld`
- Write (scratch): `$CLAUDE_JOB_DIR/pinned-identifiers.md`

- [ ] **Step 1: Confirm worktree state**

Run:
```bash
pwd
git branch --show-current
git status --porcelain
```

Expected:
- `pwd` → ends in `.claude/worktrees/docs-phase3-tutorials`
- branch → `worktree-docs-phase3-tutorials`
- status → empty (or only untracked `.claude/` directory)

If not in the worktree, stop and surface — the rest of the plan assumes isolation.

- [ ] **Step 2: Re-run the pre-write sweep**

Run:
```bash
grep -rE "chip-options|hint-options" Sources/Modaliser/Scheme/ | grep -v "migration error" | grep -v "ax-hints.sld"
grep -rn "set-overlay-css|set-host-header" Sources/Modaliser/Scheme/
grep -rn "overlay.css" Sources/Modaliser/Scheme/
ls docs/how-to/ | wc -l
```

Expected:
- First three greps return **zero matches**.
- `ls docs/how-to/` count is `8` (index + 7 how-tos).

If any sweep is dirty, stop and fix `Sources/` or `docs/how-to/` in a separate commit *before* writing the tutorial.

- [ ] **Step 3: Pin the focus primitive used in Steps 6 and 7**

Read `Sources/Modaliser/Scheme/lib/modaliser/window-actions.sld`. Find what the library exports for moving window focus across the screen. Look for one of these (in order of preference for the tutorial):

1. A per-direction primitive: e.g. `focus-window-direction`, `window:focus-left`, `focus-left`.
2. A cycle primitive: e.g. `focus-next-window`, `window:focus-next`.

The Step 6 / Step 7 snippets in the spec use `focus-window-direction` as a placeholder. If the actual export name differs, you will substitute it consistently in both steps so the refactor in Step 7 is observably equivalent to Step 6 (same primitive, same arguments, only the wiring changes).

If **no** per-direction primitive exists, fall back to a cycle/next/previous shape — bind `h`/`l` to previous/next and drop `j`/`k`, or bind all four to the same `focus-next-window` (the tutorial's modal point survives a less interesting action). Note the chosen identifier(s) and arguments.

- [ ] **Step 4: Confirm macro-contract line refs cited by the spec**

Open `Sources/Modaliser/Scheme/lib/modaliser/dsl.sld`. Confirm:

- Lines 39–43 (or current equivalent): the doc comment on `(key …)` describing the `'sticky-target MODE-ID` trailing keyword.
- Lines 95–107 (or current equivalent): the `key-cmd` implementation that parses the `'sticky-target` tail.

If the line numbers have shifted, update the *source-of-truth* section of the spec (`Sources/Modaliser/Scheme/lib/modaliser/dsl.sld` entry) in a separate commit. The line refs in the spec must point at the actual contract code so a future reader can navigate.

- [ ] **Step 5: Read state-machine.sld for sticky / sticky-target semantics**

Open `Sources/Modaliser/Scheme/lib/modaliser/state-machine.sld`. Note:

- What `'sticky #t` does on a group (the navigation stays inside that group after a leaf fires).
- What `'exit-on-unknown #t` does (unrecognised keys dismiss the modal instead of being swallowed).
- What `'sticky-target SYMBOL` does on a command (runs the action, then transitions modal navigation into the named sticky tree).
- Which keys count as "unknown" for `'exit-on-unknown` purposes — specifically, do parent-level bindings (e.g. the other keys inside the `w` overlay) count as known or unknown when navigation is currently inside the sticky `'window-focus` tree? This affects Step 6 and Step 7 verification language ("press Esc or any unbound key").

- [ ] **Step 6: Save the pinned identifiers and observations to scratch**

Write to `$CLAUDE_JOB_DIR/pinned-identifiers.md` (this file is **not** committed — it's a working note for the rest of the session):

```markdown
# Pinned identifiers — Modal Thinking tutorial

## Focus primitive (Steps 6, 7)
- Chosen identifier: <name>
- Argument shape: <(λ () (...)) form>
- Source: <file:lines>

## sticky / exit-on-unknown semantics
- "Unknown" key definition: <…>
- Parent-overlay keys behaviour when inside the sticky tree: <…>

## Maximise primitive (Step 1)
- Chosen identifier: <name or inline thunk>
- Source: <file:lines>

## Restore primitive (Step 2, 3)
- Chosen identifier: restore-window (per default-config.scm:90) — confirm.
- Source: <file:lines>
```

This note grounds the snippets in Tasks 5–11. Each per-step task will refer back to it.

- [ ] **Step 7: Commit if any source-of-truth line refs were updated**

If Step 4 found stale line refs and you updated the spec, commit:

```bash
git add docs/superpowers/specs/2026-05-19-docs-phase3-tutorial-modal-thinking-design.md
git commit -m "docs(superpowers): refresh source-of-truth line refs in Phase-3 tutorial spec"
```

Otherwise: no commit. Move on.

---

## Task 2: Back up the user's live config

**Files:**
- Copy: `~/.config/modaliser/config.scm` → `~/.config/modaliser/config.scm.tutorial-bak`

The implementation overwrites `~/.config/modaliser/config.scm` step-by-step to verify each snippet. The user's current config must be restored bit-for-bit at the end (Task 13).

- [ ] **Step 1: Verify the live config exists and read its byte size**

Run:
```bash
ls -l ~/.config/modaliser/config.scm
```

Expected: a single file, size in the low-thousands of bytes. If it doesn't exist, stop — Modaliser may not have been launched on this machine, in which case the "press F18" verification beats won't work either.

- [ ] **Step 2: Make the backup**

Run:
```bash
cp ~/.config/modaliser/config.scm ~/.config/modaliser/config.scm.tutorial-bak
diff -q ~/.config/modaliser/config.scm ~/.config/modaliser/config.scm.tutorial-bak
```

Expected: `diff` is silent (files identical).

- [ ] **Step 3: Confirm to the user**

Tell the user, in chat:

> "I've backed up your current `~/.config/modaliser/config.scm` to `~/.config/modaliser/config.scm.tutorial-bak`. The implementation will overwrite the live file step by step to verify each tutorial snippet, then restore the backup at the end."

Wait for the user to acknowledge (any short ack is fine). If they object, stop and ask how they'd like to verify the steps.

---

## Task 3: Create the tutorial file with frontmatter and intro

**Files:**
- Create: `docs/tutorials/modal-thinking.md`

- [ ] **Step 1: Make the directory**

Run:
```bash
mkdir -p docs/tutorials
ls -d docs/tutorials
```

Expected: directory exists.

- [ ] **Step 2: Write the intro**

Write `docs/tutorials/modal-thinking.md` with the opening that *does not* mention Diátaxis (anti-trap), names what the reader will build, and sets expectations. Draft:

```markdown
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
```

- [ ] **Step 3: Commit**

```bash
git add docs/tutorials/modal-thinking.md
git commit -m "docs(tutorials): start Modal Thinking — intro + before-you-start"
```

---

## Task 4: Tutorial Step 1 — A leader with one binding

**Files:**
- Overwrite: `~/.config/modaliser/config.scm`
- Modify: `docs/tutorials/modal-thinking.md` (append Step 1 section)

- [ ] **Step 1: Write the Step-1 config to the live file**

Overwrite `~/.config/modaliser/config.scm` with:

```scheme
;; Modaliser tutorial — Step 1 of Modal Thinking.
;;
;; Smallest possible global tree: one binding under `w` that maximises
;; the current window. Demonstrates: a leader is a hotkey that opens a
;; menu, not an action — even when the menu has only one entry.

(import (modaliser dsl)
        (modaliser leader)
        (prefix (modaliser window-actions) window:))

(set-leaders! 'global-keycode F18
              'local-keycode  F17)

(define-tree 'global
  (key "w" "Maximise" (λ () (window:maximise))))
```

Adjust the `(window:maximise)` call to whatever maximise primitive `window-actions.sld` actually exports (from your scratch note in Task 1 Step 6). If there is no zero-arg `maximise`, substitute the equivalent — e.g. `(λ () (restore-window))` swapped in temporarily and label changed.

- [ ] **Step 2: Ask the user to verify**

Tell the user, in chat:

> "I've replaced `~/.config/modaliser/config.scm` with the Step-1 snippet. Please:
> 1. Pick **Relaunch** from the menu bar icon.
> 2. Position any window so you can tell if it maximises (something not already filling the screen).
> 3. Press **F18 w**.
> 4. Did the window maximise? (yes / no / something else happened)"

Wait for the user's reply. **Do not proceed** until they confirm the behaviour matches.

- [ ] **Step 3: Write the Step-1 prose**

If the user confirmed, append to `docs/tutorials/modal-thinking.md`:

````markdown
## Step 1 — A leader with one binding

A *leader* is a hotkey that opens a menu, not an action. The menu can
have one entry, ten entries, or nested sub-menus — F18 just opens it;
what's inside is up to you. This step writes the smallest possible
global tree: one binding under `w` that maximises the current window.

Replace `~/.config/modaliser/config.scm` with:

```scheme
(import (modaliser dsl)
        (modaliser leader)
        (prefix (modaliser window-actions) window:))

(set-leaders! 'global-keycode F18
              'local-keycode  F17)

(define-tree 'global
  (key "w" "Maximise" (λ () (window:maximise))))
```

The `(λ () …)` wrap is non-negotiable. Without it, the call
`(window:maximise)` would fire once, at config-load time — the very
first time Modaliser parses the file — and `w` would be bound to
whatever that call returned. The lambda defers the call until you
press the key.

**Pick Relaunch from the menu bar icon, then press F18 w.** The
current window maximises.

That single binding is a *leader* (`F18`), opening a *tree* (the
global tree, declared with `define-tree`), containing a *command*
(`(key "w" "Maximise" …)`). Three concepts, one for every level of
the nesting you just typed. Each of the next six steps adds exactly
one more.
````

Substitute the correct identifier names from your scratch note before writing.

- [ ] **Step 4: Commit**

```bash
git add docs/tutorials/modal-thinking.md
git commit -m "docs(tutorials): Modal Thinking Step 1 — A leader with one binding"
```

---

## Task 5: Tutorial Step 2 — Make `w` into a menu

**Files:**
- Overwrite: `~/.config/modaliser/config.scm`
- Modify: `docs/tutorials/modal-thinking.md`

- [ ] **Step 1: Write the Step-2 config**

Overwrite `~/.config/modaliser/config.scm` with:

```scheme
;; Modaliser tutorial — Step 2 of Modal Thinking.

(import (modaliser dsl)
        (modaliser leader)
        (prefix (modaliser window-actions) window:))

(set-leaders! 'global-keycode F18
              'local-keycode  F17)

(define-tree 'global
  (key "w" "Windows"
    (overlay
      (key "m" "Maximise" (λ () (window:maximise)))
      (key "c" "Centre"   (λ () (window:centre)))
      (key "r" "Restore"  (λ () (restore-window))))))
```

(If `window:centre` doesn't exist by that name, use whatever centring/midpoint primitive is in `window-actions.sld`. If `restore-window` is the bundled name per `default-config.scm:90`, keep it; otherwise adjust.)

- [ ] **Step 2: Ask the user to verify**

> "Step 2 is in place. Please:
> 1. Pick **Relaunch** from the menu bar icon.
> 2. Press **F18 w**.
> 3. Do you see an overlay with three rows — *m Maximise*, *c Centre*, *r Restore* — instead of the window maximising immediately? (yes / no / something else)"

Wait for confirmation.

- [ ] **Step 3: Write the Step-2 prose**

Append:

````markdown
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
      (key "m" "Maximise" (λ () (window:maximise)))
      (key "c" "Centre"   (λ () (window:centre)))
      (key "r" "Restore"  (λ () (restore-window))))))
```

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
````

- [ ] **Step 4: Commit**

```bash
git add docs/tutorials/modal-thinking.md
git commit -m "docs(tutorials): Modal Thinking Step 2 — Make w into a menu"
```

---

## Task 6: Tutorial Step 3 — A layout block

**Files:**
- Overwrite: `~/.config/modaliser/config.scm`
- Modify: `docs/tutorials/modal-thinking.md`

- [ ] **Step 1: Write the Step-3 config**

Overwrite with:

```scheme
;; Modaliser tutorial — Step 3 of Modal Thinking.

(import (modaliser dsl)
        (modaliser leader)
        (prefix (modaliser window-actions) window:))

(set-leaders! 'global-keycode F18
              'local-keycode  F17)

(define-tree 'global
  (key "w" "Windows"
    (overlay
      (window:layout-block
        (("d" "f" "g"))                  ; full thirds
        (("D" "F" "G")
         ("C" "V" "B"))                  ; half thirds
        (("e" "e" #f))                   ; left two-thirds
        ((#f "t" "t"))                   ; right two-thirds
        (("m"))                          ; maximise (full cell)
        (center "c"))                    ; centre (inward arrows)
      (key "r" "Restore" (λ () (restore-window))))))
```

This is structurally what `default-config.scm:69–97` ships, minus the selector and window-list (added in Steps 4–5).

- [ ] **Step 2: Ask the user to verify**

> "Step 3 is in place. Please:
> 1. Pick **Relaunch**.
> 2. Press **F18 w**.
> 3. Do you see a diagram-strip showing window-shape thirds and halves *above* a single text row reading *r Restore*? Try pressing **d** — does the current window snap to the left third? Try **D** — top-left half-third? (describe what you see)"

Wait for confirmation. If the diagram doesn't render, the user may need to confirm `window-actions.sld` exports `layout-block` under that prefix — surface the discrepancy.

- [ ] **Step 3: Write the Step-3 prose**

Append:

````markdown
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
(define-tree 'global
  (key "w" "Windows"
    (overlay
      (window:layout-block
        (("d" "f" "g"))                  ; full thirds
        (("D" "F" "G")
         ("C" "V" "B"))                  ; half thirds
        (("e" "e" #f))                   ; left two-thirds
        ((#f "t" "t"))                   ; right two-thirds
        (("m"))                          ; maximise (full cell)
        (center "c"))                    ; centre (inward arrows)
      (key "r" "Restore" (λ () (restore-window))))))
```

**Relaunch. Press F18 w.** You see the diagram strip with the letters
laid out spatially, and a single text row for *r Restore* underneath.
Press **d** — the window snaps to the left third. Press **D** —
top-left half-third. Press **m** — full-screen.

Two ideas live in that snippet. First: an overlay can hold *multiple*
blocks alongside *loose* `(key …)` forms; you'll add more in Steps
4–5. Second: a block carries chrome the renderer paints (the grid),
not just a flat list of choices. Most of the visual richness in
Modaliser overlays comes from blocks — `window:layout-block` here,
`window:list-block` in Step 5, `which-key-block` automatically wrapped
around your loose keys.
````

- [ ] **Step 4: Commit**

```bash
git add docs/tutorials/modal-thinking.md
git commit -m "docs(tutorials): Modal Thinking Step 3 — A layout block"
```

---

## Task 7: Tutorial Step 4 — A selector

**Files:**
- Overwrite: `~/.config/modaliser/config.scm`
- Modify: `docs/tutorials/modal-thinking.md`

- [ ] **Step 1: Write the Step-4 config**

Overwrite with:

```scheme
;; Modaliser tutorial — Step 4 of Modal Thinking.

(import (modaliser dsl)
        (modaliser leader)
        (modaliser window)                    ; list-windows, focus-window
        (prefix (modaliser window-actions) window:))

(set-leaders! 'global-keycode F18
              'local-keycode  F17)

(define-tree 'global
  (key "w" "Windows"
    (overlay
      (window:layout-block
        (("d" "f" "g"))
        (("D" "F" "G")
         ("C" "V" "B"))
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

- [ ] **Step 2: Ask the user to verify**

> "Step 4 is in place. Please:
> 1. Pick **Relaunch**.
> 2. Open a few windows in different apps so the selector has options.
> 3. Press **F18 w s**.
> 4. Do you see a fuzzy-finder listing visible window titles? Type a few characters to narrow, then press Enter — does the highlighted window come to the front?"

Wait for confirmation.

- [ ] **Step 3: Write the Step-4 prose**

**Important constraint:** Do NOT mention the Tab key, per-item "actions", or "press Tab to see what you can do with the highlighted item". That plumbing exists in the source but is broken (see [Known broken — must not appear anywhere in the tutorial] in the spec, and `project_selector_actions_broken.md` in auto-memory). Describe selectors using only `'prompt`, `'source`, and `'on-select`.

Append:

````markdown
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
evaluates it at config-load time. It returns a node — a Scheme pair
describing a selector. The `(key …)` macro sees the pair and
*decorates* it with `"s"` / `"Select Window"`. The same dispatch you
saw on `(overlay …)` in Step 2.

Once you spot this pattern, every factory in the codebase reads the
same way: `(settings:actions)`, `(launcher:find-application)`,
`(web-search:google)` — they all return nodes that get decorated by
the wrapping `(key …)`.

Add the selector to your overlay (add `(modaliser window)` to your
imports for `list-windows` / `focus-window`):

```scheme
(import (modaliser dsl)
        (modaliser leader)
        (modaliser window)                    ; list-windows, focus-window
        (prefix (modaliser window-actions) window:))

(define-tree 'global
  (key "w" "Windows"
    (overlay
      (window:layout-block
        (("d" "f" "g"))
        (("D" "F" "G")
         ("C" "V" "B"))
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

**Relaunch. Press F18 w s.** You get a fuzzy-finder listing your
visible windows. Type a few characters — the list narrows. Press
Enter — the highlighted window comes to the front and the overlay
closes.

The selector fired, then dismissed. Same shape as everything in
Part 1: tree → leaf → action → dismiss.
````

- [ ] **Step 4: Commit**

```bash
git add docs/tutorials/modal-thinking.md
git commit -m "docs(tutorials): Modal Thinking Step 4 — A selector"
```

---

## Task 8: Tutorial Step 5 — The window list, with chips

**Files:**
- Overwrite: `~/.config/modaliser/config.scm`
- Modify: `docs/tutorials/modal-thinking.md`

- [ ] **Step 1: Write the Step-5 config**

Overwrite with the Step-4 contents plus `(window:list-block 'chips? #t)` at the bottom of the overlay:

```scheme
;; Modaliser tutorial — Step 5 of Modal Thinking.

(import (modaliser dsl)
        (modaliser leader)
        (modaliser window)
        (prefix (modaliser window-actions) window:))

(set-leaders! 'global-keycode F18
              'local-keycode  F17)

(define-tree 'global
  (key "w" "Windows"
    (overlay
      (window:layout-block
        (("d" "f" "g"))
        (("D" "F" "G")
         ("C" "V" "B"))
        (("e" "e" #f))
        ((#f "t" "t"))
        (("m"))
        (center "c"))
      (key "r" "Restore" (λ () (restore-window)))
      (key "s" "Select Window"
        (selector 'prompt "Select window by name…"
                  'source list-windows
                  'on-select focus-window))
      (window:list-block 'chips? #t))))
```

- [ ] **Step 2: Ask the user to verify**

> "Step 5 is in place. Please:
> 1. Pick **Relaunch**.
> 2. Make sure you have at least three visible windows from different apps.
> 3. Press **F18 w** (don't press any further key).
> 4. Do you see (a) the diagram strip, (b) the *r Restore* and *s Select Window* rows, (c) a list of your visible windows at the bottom, AND (d) chips painted on the actual windows on screen that match the rows in the overlay's bottom block?"

Wait for confirmation.

- [ ] **Step 3: Write the Step-5 prose**

Append:

````markdown
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
````

- [ ] **Step 4: Commit**

```bash
git add docs/tutorials/modal-thinking.md
git commit -m "docs(tutorials): Modal Thinking Step 5 — Window-list block with chips"
```

---

## Task 9: Tutorial Step 6 — A sticky focus sub-group

**Files:**
- Overwrite: `~/.config/modaliser/config.scm`
- Modify: `docs/tutorials/modal-thinking.md`

- [ ] **Step 1: Write the Step-6 config**

Overwrite with the Step-5 contents plus a `(group "f" "Focus" 'sticky #t 'exit-on-unknown #t …)` sub-group inside the overlay. The four hjkl bindings each call the focus primitive you pinned in Task 1 Step 3 — substitute its actual identifier:

```scheme
;; Modaliser tutorial — Step 6 of Modal Thinking.

(import (modaliser dsl)
        (modaliser leader)
        (modaliser window)
        (prefix (modaliser window-actions) window:))

(set-leaders! 'global-keycode F18
              'local-keycode  F17)

(define-tree 'global
  (key "w" "Windows"
    (overlay
      (window:layout-block
        (("d" "f" "g"))
        (("D" "F" "G")
         ("C" "V" "B"))
        (("e" "e" #f))
        ((#f "t" "t"))
        (("m"))
        (center "c"))
      (key "r" "Restore" (λ () (restore-window)))
      (key "s" "Select Window"
        (selector 'prompt "Select window by name…"
                  'source list-windows
                  'on-select focus-window))
      (group "f" "Focus"
             'sticky #t
             'exit-on-unknown #t
        (key "h" "Left"  (λ () (focus-window-direction 'left)))
        (key "j" "Down"  (λ () (focus-window-direction 'down)))
        (key "k" "Up"    (λ () (focus-window-direction 'up)))
        (key "l" "Right" (λ () (focus-window-direction 'right))))
      (window:list-block 'chips? #t))))
```

> ⚠ Note: the `f` key here collides with `f` inside `window:layout-block` (full-thirds-middle). The state machine routes by *path*: F18 → w → f opens the focus sub-group; F18 → w → d → f doesn't exist. But two `f` rows in the same overlay can read confusingly. If the user finds it jarring, document the collision in the tutorial as a deliberate teaching moment ("the layout-block and the group are both keyed under `f`, but the modal state-machine distinguishes them by tree position; the overlay just shows both rows because they're at the same depth"), or substitute a non-colliding key (e.g. `n` for "navigate") in both code and prose.

- [ ] **Step 2: Ask the user to verify**

> "Step 6 is in place. Please:
> 1. Pick **Relaunch**.
> 2. Press **F18 w**. Notice the new *Focus* row (key `f`).
> 3. Press **f**. Does the overlay show four rows — *h Left*, *j Down*, *k Up*, *l Right* — and *stay open*?
> 4. Press **h** several times. Does focus move leftward across windows each time, with the overlay staying open?
> 5. Press **Esc**. Does the overlay dismiss and put you back in your previous app?
> 6. (Bonus) Did you notice the `f` collision with the layout-block's full-thirds-middle key? Was it confusing?"

Wait for confirmation. If focus doesn't actually move, the wrong primitive was pinned in Task 1 — go back, find the right one, redo Step 1 of this task.

If the user reports the `f` collision is confusing, substitute a non-colliding key (e.g. `n`) in the config and re-verify before writing prose.

- [ ] **Step 3: Write the Step-6 prose**

Append (substitute key/identifier if you changed them):

````markdown
## Step 6 — Staying in a mode: a sticky focus sub-group

Everything so far has been the launcher pattern: press a key, an
action fires, the overlay dismisses. That's perfect for one-shot
gestures like *maximise* or *restore*. But what about movements you
want to repeat — like nudging focus across windows? Pressing F18 w
between each press is too many keystrokes.

Add a sub-group inside the overlay:

```scheme
(group "f" "Focus"
       'sticky #t
       'exit-on-unknown #t
  (key "h" "Left"  (λ () (focus-window-direction 'left)))
  (key "j" "Down"  (λ () (focus-window-direction 'down)))
  (key "k" "Up"    (λ () (focus-window-direction 'up)))
  (key "l" "Right" (λ () (focus-window-direction 'right))))
```

Two new keywords are doing the work:

- **`'sticky #t`** — when a binding inside this group fires, the
  modal navigation *stays in this group* instead of dismissing the
  whole overlay. You can press another binding right away.
- **`'exit-on-unknown #t`** — any key that *isn't* one of `h/j/k/l`
  exits the modal cleanly. (Without this, unknown keys are
  swallowed — the modal stays open and you're stuck until you find
  something it recognises. Combined with `Esc` semantics, this gives
  the reader a forgiving "I'm done" gesture.)

**Relaunch. Press F18 w f h h h.** After the first `h`, the overlay
*does not dismiss* — it shows the four focus bindings and waits.
Press `h` again, again, again — focus keeps moving leftward. Press
Esc — the overlay closes and you're back in your app.

That's the **modal pattern**. The reader is now *inside* a mode and
stays until they explicitly exit. iTerm's `Focus` mode (look at
`Sources/Modaliser/Scheme/lib/modaliser/apps/iterm.sld` later) is the
same shape applied to iTerm panes.

Notice the cost, though: to start moving focus you press *three* keys
— `w`, `f`, `h`. That's one too many for a movement gesture you might
do dozens of times an hour. Step 7 fixes it with a small refactor.
````

- [ ] **Step 4: Commit**

```bash
git add docs/tutorials/modal-thinking.md
git commit -m "docs(tutorials): Modal Thinking Step 6 — Sticky focus sub-group"
```

---

## Task 10: Tutorial Step 7 — Sticky-target

**Files:**
- Overwrite: `~/.config/modaliser/config.scm`
- Modify: `docs/tutorials/modal-thinking.md`

- [ ] **Step 1: Write the Step-7 config**

Overwrite with the Step-6 contents *but* (a) remove the `(group "f" "Focus" …)` sub-group, (b) add four hjkl `(key …)` bindings directly inside the `w` overlay each carrying `'sticky-target 'window-focus`, and (c) add a top-level `(define-tree 'window-focus 'sticky #t 'exit-on-unknown #t 'display-name "Focus" …)` outside `'global`:

```scheme
;; Modaliser tutorial — Step 7 of Modal Thinking.

(import (modaliser dsl)
        (modaliser leader)
        (modaliser window)
        (prefix (modaliser window-actions) window:))

(set-leaders! 'global-keycode F18
              'local-keycode  F17)

(define-tree 'window-focus
  'sticky #t
  'exit-on-unknown #t
  'display-name "Focus"
  (key "h" "Left"  (λ () (focus-window-direction 'left)))
  (key "j" "Down"  (λ () (focus-window-direction 'down)))
  (key "k" "Up"    (λ () (focus-window-direction 'up)))
  (key "l" "Right" (λ () (focus-window-direction 'right))))

(define-tree 'global
  (key "w" "Windows"
    (overlay
      (window:layout-block
        (("d" "f" "g"))
        (("D" "F" "G")
         ("C" "V" "B"))
        (("e" "e" #f))
        ((#f "t" "t"))
        (("m"))
        (center "c"))
      (key "r" "Restore" (λ () (restore-window)))
      (key "s" "Select Window"
        (selector 'prompt "Select window by name…"
                  'source list-windows
                  'on-select focus-window))
      (key "h" "Left"  (λ () (focus-window-direction 'left))
        'sticky-target 'window-focus)
      (key "j" "Down"  (λ () (focus-window-direction 'down))
        'sticky-target 'window-focus)
      (key "k" "Up"    (λ () (focus-window-direction 'up))
        'sticky-target 'window-focus)
      (key "l" "Right" (λ () (focus-window-direction 'right))
        'sticky-target 'window-focus)
      (window:list-block 'chips? #t))))
```

- [ ] **Step 2: Ask the user to verify**

> "Step 7 is in place. Please:
> 1. Pick **Relaunch**.
> 2. Press **F18 w**. Look for four new rows — *h Left*, *j Down*, *k Up*, *l Right* — alongside everything else. They should carry a sticky-target marker (a small `↻` or similar; the renderer paints one on cells whose binding hands off to a sticky tree).
> 3. Press **h**. Two things should happen *at the same press*: focus moves left, AND the overlay swaps to show only the four focus rows.
> 4. Press **h** again. Focus keeps moving leftward; the overlay stays in the focus tree.
> 5. Press **Esc** (or any unbound key). Overlay closes.
> 6. Compare to Step 6: you used to press `w f h`. Now you press `w h`. Same end behaviour, one fewer press. Confirm this matches what you observe."

Wait for confirmation. If the renderer doesn't paint a sticky-target marker — that's worth noting but not a blocker; the prose can describe the behaviour and skip the marker detail.

- [ ] **Step 3: Write the Step-7 prose**

Append:

````markdown
## Step 7 — Sticky-target: fire AND enter, in one press

Look at iTerm's `Focus` mode — open
`Sources/Modaliser/Scheme/lib/modaliser/apps/iterm.sld` and find the
"Focus" category around line 179. It binds hjkl too, but you don't
press an `f` first when you're in iTerm; the very first `h` *both*
moves focus *and* puts you in the sticky focus tree. How?

`'sticky-target`. A trailing keyword on a `(key …)` binding: when the
binding fires, the state machine (a) runs the action, then (b)
transitions modal navigation into the sticky tree named by the
symbol. One key press does two jobs. The overlay paints a small
marker on each cell so you can tell which keys are sticky-target
leaders.

The refactor: take the four hjkl bindings out of the `(group "f" …)`
in Step 6, give them `'sticky-target 'window-focus`, and put them
directly into the `w` overlay. Register a *separate* sticky tree
named `'window-focus` for the modal navigation to land in:

```scheme
;; A new top-level form, outside (define-tree 'global …):

(define-tree 'window-focus
  'sticky #t
  'exit-on-unknown #t
  'display-name "Focus"
  (key "h" "Left"  (λ () (focus-window-direction 'left)))
  (key "j" "Down"  (λ () (focus-window-direction 'down)))
  (key "k" "Up"    (λ () (focus-window-direction 'up)))
  (key "l" "Right" (λ () (focus-window-direction 'right))))

;; Inside the `w` overlay, in place of the (group "f" …) you wrote
;; in Step 6:

(key "h" "Left"  (λ () (focus-window-direction 'left))
     'sticky-target 'window-focus)
(key "j" "Down"  (λ () (focus-window-direction 'down))
     'sticky-target 'window-focus)
(key "k" "Up"    (λ () (focus-window-direction 'up))
     'sticky-target 'window-focus)
(key "l" "Right" (λ () (focus-window-direction 'right))
     'sticky-target 'window-focus)
```

**Relaunch. Press F18 w h h h.** The very first `h` moves focus left
*and* swaps the overlay to the four-row focus tree; subsequent `h`
keys keep moving. Esc exits. Compare: Step 6 needed `w f h`; Step 7
needs `w h`.

Two concepts arrived together here. The obvious one is
`'sticky-target` — fire-and-enter as a single press. The other is
quieter but more useful: **sticky trees are *named, top-level trees***
registered with their own `define-tree`. The launcher tree
(`'global`), a per-app tree (e.g. `'com.googlecode.iterm2`), and a
sticky tree (`'window-focus`) are all sibling top-level forms — they
look structurally identical; the only difference is what *references*
them. Once you've seen three trees alongside each other, "tree"
becomes the unit of mental composition for the whole system.

iTerm's pane Focus mode is doing exactly what you just wrote, applied
to AppleScript pane-focus instead of macOS window-focus. Your `w h`
is now structurally identical to iTerm's per-app pane Focus.
````

- [ ] **Step 4: Commit**

```bash
git add docs/tutorials/modal-thinking.md
git commit -m "docs(tutorials): Modal Thinking Step 7 — Sticky-target refactor"
```

---

## Task 11: Tutorial Step 8 — Why this is "modal" (recap prose)

**Files:**
- Modify: `docs/tutorials/modal-thinking.md`

No config edit. No verification beat. Pure prose.

- [ ] **Step 1: Write the recap**

Append:

````markdown
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
key exits. Step 6 built it the explicit way (a parent key `f` opening
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
structurally identical to your `w` overlay's hjkl + `'window-focus`
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
````

- [ ] **Step 2: Commit**

```bash
git add docs/tutorials/modal-thinking.md
git commit -m "docs(tutorials): Modal Thinking Step 8 — Recap and where to go next"
```

---

## Task 12: Cross-link from quickstart and how-to

**Files:**
- Modify: `docs/quickstart/index.md`
- Modify: `docs/how-to/index.md`

- [ ] **Step 1: Read the current quickstart "What's next" section**

Open `docs/quickstart/index.md` and locate the "What's next" section (or whatever the closing list of forward links is called). Identify the existing how-to bullet.

- [ ] **Step 2: Add a Tutorial bullet *above* the how-to bullet**

Edit `docs/quickstart/index.md` and insert, immediately above the existing how-to bullet:

```markdown
- **Tutorial** — [Modal Thinking — build a window-manager leader](../tutorials/modal-thinking.md). 30–60 minutes; the
  natural next step if you want to *understand* the system rather than
  look up recipes for specific tasks.
```

Adjust the surrounding indentation/style to match the existing list (the existing how-to bullet shows the conventions for this file).

- [ ] **Step 3: Read the current how-to/index.md intro**

Open `docs/how-to/index.md`. Identify the introductory paragraph(s) at the top of the file.

- [ ] **Step 4: Add a sentence pointing at the tutorial**

Edit the introduction to include, near its end (one sentence, no block, no header):

```markdown
If you'd rather *learn the system* through a worked example before reaching for recipes, start with the tutorial: [Modal Thinking — build a window-manager leader](../tutorials/modal-thinking.md).
```

- [ ] **Step 5: Commit**

```bash
git add docs/quickstart/index.md docs/how-to/index.md
git commit -m "docs: cross-link Modal Thinking tutorial from quickstart and how-to index"
```

---

## Task 13: Restore the user's config from backup

**Files:**
- Copy: `~/.config/modaliser/config.scm.tutorial-bak` → `~/.config/modaliser/config.scm`

- [ ] **Step 1: Restore**

Run:
```bash
cp ~/.config/modaliser/config.scm.tutorial-bak ~/.config/modaliser/config.scm
diff -q ~/.config/modaliser/config.scm ~/.config/modaliser/config.scm.tutorial-bak
```

Expected: `diff` is silent.

- [ ] **Step 2: Ask the user to relaunch and confirm**

> "I've restored your original `~/.config/modaliser/config.scm` from the backup. Please:
> 1. Pick **Relaunch**.
> 2. Press **F18** — confirm your usual global tree appears (not the tutorial's stripped-down `w`-only tree).
> 3. Did everything come back?"

Wait for confirmation. If the user reports their tree is missing or wrong, restore again from the backup and investigate — do **not** proceed until the user is back to a working config.

- [ ] **Step 3: Remove the backup**

Only if the user confirmed their config is back to normal:

```bash
rm ~/.config/modaliser/config.scm.tutorial-bak
ls ~/.config/modaliser/config.scm.tutorial-bak 2>&1 | head -1
```

Expected: the second command reports "No such file or directory".

---

## Task 14: Write the internal link checker

**Files:**
- Create: `$CLAUDE_JOB_DIR/linkcheck.py`

The Phase-2 plan wrote one in a previous job's scratch dir which is now gone. Rewrite it from scratch — same logic.

- [ ] **Step 1: Write the script**

Create `$CLAUDE_JOB_DIR/linkcheck.py`:

```python
#!/usr/bin/env python3
"""
Internal-link checker for docs/{quickstart,reference,how-to,tutorials}/.

Walks the four trees, regex-extracts markdown links, resolves relative
paths, fails on missing targets. Skips fenced code (```) and inline
code (`...`) so JS call signatures and Scheme snippets aren't misread
as links.

Run from the repo root.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOTS = ["docs/quickstart", "docs/reference", "docs/how-to", "docs/tutorials"]

# [label](target) — capture the target only. Greedy avoidance for ).
LINK = re.compile(r"\[(?:[^\]]*)\]\(([^)]+)\)")
FENCE = re.compile(r"^\s*```")
INLINE_CODE = re.compile(r"`[^`]*`")


def strip_code(md: str) -> str:
    """Strip fenced and inline code so links inside snippets don't trigger."""
    out_lines: list[str] = []
    in_fence = False
    for line in md.splitlines():
        if FENCE.match(line):
            in_fence = not in_fence
            out_lines.append("")  # keep line count for error reporting
            continue
        if in_fence:
            out_lines.append("")
            continue
        out_lines.append(INLINE_CODE.sub("", line))
    return "\n".join(out_lines)


def check(repo_root: Path) -> int:
    failures: list[tuple[Path, int, str, str]] = []
    files = []
    for root in ROOTS:
        d = repo_root / root
        if d.is_dir():
            files.extend(sorted(d.rglob("*.md")))

    for md_path in files:
        text = md_path.read_text(encoding="utf-8")
        text = strip_code(text)
        for ln, line in enumerate(text.splitlines(), 1):
            for m in LINK.finditer(line):
                target = m.group(1).strip()
                # Skip external links and pure fragments
                if target.startswith(("http://", "https://", "mailto:", "#")):
                    continue
                # Strip fragments and query strings
                path_part = target.split("#", 1)[0].split("?", 1)[0]
                if not path_part:
                    continue
                resolved = (md_path.parent / path_part).resolve()
                if not resolved.exists():
                    failures.append((md_path, ln, target, str(resolved)))

    if failures:
        for md_path, ln, target, resolved in failures:
            rel = md_path.relative_to(repo_root)
            print(f"{rel}:{ln}: broken link → {target!r} (resolved to {resolved})", file=sys.stderr)
        return 1
    print(f"OK — checked {len(files)} files, no broken internal links.")
    return 0


if __name__ == "__main__":
    sys.exit(check(Path.cwd()))
```

- [ ] **Step 2: Make it executable and verify it parses**

```bash
chmod +x "$CLAUDE_JOB_DIR/linkcheck.py"
python3 -c "import ast; ast.parse(open('$CLAUDE_JOB_DIR/linkcheck.py').read())"
echo $?
```

Expected: `0` (the script parses cleanly).

---

## Task 15: Run the link checker and fix any failures

**Files:**
- Possibly modify: any `.md` under `docs/{quickstart,reference,how-to,tutorials}/`

- [ ] **Step 1: Run the link checker**

```bash
cd $(git rev-parse --show-toplevel)
python3 "$CLAUDE_JOB_DIR/linkcheck.py"
echo "exit=$?"
```

Expected: `OK — checked N files, no broken internal links.` and `exit=0`.

- [ ] **Step 2: Fix any broken links**

If there are broken links, the output names the file, line, and resolved path. For each:

- If the link points at a file that exists but the relative path is wrong, fix the relative path.
- If the link points at a file that doesn't exist, either create the file (rare — usually a typo) or remove/replace the link.
- If the link points into a tutorial section anchor (e.g. `modal-thinking.md#step-3-a-layout-block`), the checker won't validate the anchor (only file existence). Anchor-only links are out of scope.

Re-run the checker after each fix until it's green.

- [ ] **Step 3: Commit fixes (if any)**

```bash
git add docs/
git commit -m "docs: fix broken internal links found by linkcheck"
```

If no fixes were needed, skip this commit.

---

## Task 16: Run `swift test`

**Files:** None (read-only verification).

- [ ] **Step 1: Run the test suite**

```bash
swift test 2>&1 | tail -40
```

Expected: tests pass. No code was touched in this implementation, so the suite should be green.

If something fails, investigate — it's almost certainly unrelated to the tutorial. Surface the failure to the user; do not proceed to code-review or finish.

---

## Task 17: Request code review

**Files:** None.

- [ ] **Step 1: Invoke the code-review skill**

Use `superpowers:requesting-code-review`. The focus prompt is:

> Review the new `docs/tutorials/modal-thinking.md` and its cross-links
> (`docs/quickstart/index.md`, `docs/how-to/index.md`). The tutorial
> teaches the launcher and modal patterns by building a `w` window-
> management leader step-by-step on a live `~/.config/modaliser/`.
>
> Reviewer focus:
> - Does the tutorial **teach** (vs. recite recipes)? Each step should
>   explain *why this concept exists*, not "to do X, type Y".
> - Are concepts introduced one at a time? Each step's "Form
>   introduced" should add exactly one new form (or one tightly-coupled
>   pair like `sticky`/`exit-on-unknown`).
> - Does **every code snippet** correspond to something that actually
>   works against the current `lib/modaliser/dsl.sld` /
>   `window-actions.sld` / `state-machine.sld`? In particular, does
>   the focus primitive used in Steps 6–7 match what
>   `window-actions.sld` actually exports?
> - Did the author actually run every step end-to-end? Signs they
>   didn't: verification beats that don't describe a visible change;
>   snippets with typos that wouldn't survive a real LispKit parse;
>   "you'll see" promises with no concrete observation.
> - Does Step 4 avoid mentioning Tab / selector actions? (Known broken
>   plumbing — must not appear.)
> - Are the cross-links correct? Quickstart's *Tutorial* bullet should
>   sit above the how-to bullet in *What's next*; `how-to/index.md`
>   should mention the tutorial near its intro.
> - The internal link checker is green; no need to re-run it.

- [ ] **Step 2: Address review feedback**

Apply review fixes inline. Each substantive fix gets its own commit so the history reads.

---

## Task 18: Drop the kickoff prompt (housekeeping)

**Files:**
- Delete: `docs/superpowers/prompts/2026-05-19-docs-phase3-tutorials-kickoff.md`

Precedent: commit `86ac695` ("docs(superpowers): drop kickoff prompts for completed slices").

- [ ] **Step 1: Delete the prompt**

```bash
git rm docs/superpowers/prompts/2026-05-19-docs-phase3-tutorials-kickoff.md
```

- [ ] **Step 2: Commit as a separate housekeeping commit**

```bash
git commit -m "docs(superpowers): drop Phase-3 tutorial kickoff prompt (completed)"
```

---

## Task 19: Finishing the development branch

**Files:** All changes on `worktree-docs-phase3-tutorials`.

- [ ] **Step 1: Invoke the finishing skill**

Use `superpowers:finishing-a-development-branch`. Recent project convention (per the kickoff and `c9822fd`) is: **local merge → push to main**, not a PR — this is a single-author docs slice.

When the skill asks for a finishing-commit message, declare the Diátaxis closure:

> docs: complete Diátaxis restructure — Phase-3 Modal Thinking tutorial
>
> Three quadrants written (reference, how-to, tutorial) and one
> deferred by intent (additional tutorials). The tutorial closes the
> conceptual gap the other quadrants can't: launcher pattern (Steps
> 1–5) and modal pattern (Steps 6–7, via the iTerm-shape sticky-target
> refactor in Step 7), built live on a backed-up `~/.config/modaliser/`
> with every snippet verified end-to-end.

- [ ] **Step 2: Confirm the merge landed**

After the skill completes:

```bash
git log --oneline -10 main
```

Expected: the tutorial and cross-link commits appear on `main`, in order.

---

## Self-review checklist (executor reads this before starting)

Before you start Task 1, skim this list once. Don't tick boxes — these are red flags to watch for, not steps:

- **Don't paraphrase reference.** No keyword tables. No exhaustive
  lists of all the trailing keywords on `(group …)`. The tutorial
  introduces what it uses; reference is linked at the end.
- **Don't introduce concepts in batches.** Each step adds one form
  (or one tightly-coupled pair — `sticky` + `exit-on-unknown` in
  Step 6). If a step's prose ends up using a form not yet seen, move
  the form's first mention to *that step* or earlier.
- **Don't skip the relaunch loop.** Every config edit gets a
  *Relaunch* prompt. Memory `feedback_no_in_place_reload` enforces
  this.
- **Don't mention Tab on selectors.** See *Known broken* in the spec
  and `project_selector_actions_broken.md` in auto-memory.
- **Don't promise hot-reload.** Reload = Relaunch.
- **Don't ship a snippet you didn't run.** The verify-then-write
  structure of Tasks 4–10 is load-bearing. If a snippet doesn't
  produce the verification beat on the live system, fix the snippet
  before writing prose — don't paper over.
- **Don't open with Diátaxis framing.** The reader doesn't care; they
  want to know what they'll build.
