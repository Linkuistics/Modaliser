# Docs Phase 3 — Modal Thinking tutorial — design

Date: 2026-05-19
Status: Approved (ready for implementation plan)

## Goal

Add the first (and likely only) Diátaxis tutorial: a single narrative
learning path that teaches the **two patterns that coexist in
Modaliser** — the *launcher* pattern (a tree the reader steps through,
which dismisses after one action) and the *modal* pattern (a sticky
tree the reader stays in until they explicitly exit, à la iTerm's
`Focus` mode).

The tutorial walks the reader through building the `w` "Windows"
leader from a one-binding stub, first as a launcher and then with a
sticky focus mode bolted on in two passes: first the explicit shape
(a sticky sub-group entered via `f`), then the iTerm shape (hjkl
bindings carrying `'sticky-target`, so the first press *both* moves
focus *and* transitions into the sticky tree — fewer presses, same
behaviour, motivates why `'sticky-target` exists). The reader feels
the difference live across all three shapes: layout-block `d` fires
and dismisses; sticky `f h h h` keeps the overlay open; sticky-target
`h h h` does both jobs in one press.

The reader ends with a working `w` overlay they keep, and the
vocabulary to read the rest of the docs as *specific instances of two
patterns they now understand*.

Phase 3 closes the Diátaxis restructure with three quadrants written
(reference, how-tos, tutorial) and one deferred-by-intent (additional
tutorials).

## Audience

**A new reader who has just done the quickstart**, arriving with a
working Modaliser install and a vague sense of what F18 does — but no
mental model yet for *why the system is shaped this way*.

Modaliser is going public next week (2026-W21), so the tutorial must
work for people who haven't touched the codebase before. Assumed prior
knowledge:

- has installed Modaliser and done the quickstart — knows F18 opens
  the global tree, has edited `~/.config/modaliser/config.scm` at
  least once, can find the menu-bar *Relaunch* item;
- is comfortable reading Scheme — recognises `lambda` / `(λ () …)` /
  `let` / `cond` without a primer (Scheme literacy is a fair
  prerequisite for editing a Scheme config; readers without it should
  bounce off the quickstart, not the tutorial);
- does **not** yet have the modaliser-specific vocabulary — doesn't
  know what an "overlay" is, what a "block" is, why selectors are
  nodes rather than actions, or what `sticky` does.

Voice: second-person, welcoming, concrete. No remedial framing on
Scheme; full hand-holding on Modaliser concepts. Each concept is
introduced once and then used naturally — reference is linked only at
the end, never paraphrased inline.

## Out of scope

- `category`. Earns its keep when an overlay has many groups; the
  global tree uses it but a single `w` leader does not. Out of frame.
  (The iTerm `Focus` cluster the tutorial models *is* wrapped in a
  category in `apps/iterm.sld`, but the reader meets it as a
  detail-on-arrival in Step 8's recap, not as a concept to learn.)
- Theming. Linked to `how-to/customise-theme.md` at the end.
- Per-app trees. Linked to `how-to/add-a-per-app-tree.md` at the end.
- A `docs/tutorials/index.md`. With one tutorial there is no index;
  quickstart and `how-to/index.md` link directly to the single page.
- New library work surfaced during writing. Anything missing is logged
  in `docs/superpowers/plans/` as a follow-up note, never inlined.

## Known broken — must not appear anywhere in the tutorial

These features exist in the code but do not currently work end-to-end.
They are easy to discover by reading the source, so the writer must
actively *not* document them — even as "advanced" or "see also" notes.

- **Selector "Tab to show actions for the current selection".** The
  selector machinery in `chooser.scm` / `launchers.sld` has plumbing
  for per-item actions surfaced by Tab, but the feature does not work
  today. Step 4 must describe selectors using only `'prompt`,
  `'source`, and `'on-select`. Do **not** mention `'actions`, Tab,
  or "press Tab to see what you can do with the highlighted item" in
  the tutorial, in cross-links, or in the closing recap.

If a known-broken feature here gets fixed during the writing phase,
update this section *and* mention the fix in the writing commit so
future kickoffs see it.

## File layout

```
docs/tutorials/modal-thinking.md       # the only new doc
docs/quickstart/index.md               # add "Tutorial" bullet to What's next
docs/how-to/index.md                   # add one sentence pointing at the tutorial
```

No new `index.md` under `docs/tutorials/`. With a single tutorial, a
directory index is overhead — quickstart's *What's next* and the
how-to index's introduction provide the entry points.

## Learning arc

Eight steps, in two parts. Each step adds **one** concept and ends with
a relaunch + a "press F18 and look" verification beat. Sequence is
chosen so each step's form is the simplest one that introduces the
next concept; no concept is introduced before its motivation is
visible to the reader.

**Part 1 — The launcher pattern** (Steps 1–5). Tree navigation. The
overlay dismisses after one action. This is what most of the system
looks like — global tree, layout-block, selectors, window-list.

**Part 2 — The modal pattern** (Steps 6–8). Two passes at the same
behaviour. Step 6 introduces sticky modes via the most explicit shape
(a sub-group entered through `f`). Step 7 refactors to the iTerm
shape — hjkl directly inside `w`, each carrying `'sticky-target`, with
the sticky tree registered separately — so the first press *both*
moves focus *and* transitions into the sticky tree. The reader feels
the inconvenience of needing `w f h …` first, so the refactor lands as
a relief. Step 8 names the launcher/modal contrast and points at the
iTerm `Focus` mode as the canonical example of what they just built.

### Step 1 — A leader with one binding

The reader edits `~/.config/modaliser/config.scm` and replaces (or
adds to) the global tree with a single binding under `w` that calls a
window action.

**Concept introduced:** a *leader* is a hotkey that opens a *menu*,
not an action. The menu is described by a tree.

**Form introduced:** `(define-tree 'global …)` containing one
`(key "w" "Maximise" (λ () (window:maximise)))`. The `(λ () …)` wrap
is non-negotiable — without it the call fires at config load.

**Verification:** *Pick Relaunch from the menu bar icon, then press
F18 w*. The current window maximises.

### Step 2 — Make `w` into a menu

The reader replaces the single thunk binding under `w` with an
`(overlay …)` containing three loose key forms (maximise, centre,
restore).

**Concept introduced:** an *overlay* groups bindings that share a
stem. The overlay node sits where the action used to sit; the wrapping
`(key "w" "Windows" (overlay …))` decorates the overlay with key/label.

**Form introduced:** `(overlay (key …) (key …) (key …))`.

**Verification:** *Relaunch. F18 w* now shows a three-row overlay
instead of firing maximise immediately.

### Step 3 — A layout block

The reader replaces the loose `m` / `c` / `r` keys inside the overlay
with `(window:layout-block …)`. The block paints a *grid* of move/resize
keys above the overlay's text rows.

**Concept introduced:** a *block* is a renderer-aware overlay
ingredient — it brings both bindings *and* chrome (the diagram). A
`key` brings only bindings. An overlay can hold multiple blocks.

**Form introduced:** `(window:layout-block (("d" "f" "g")) … (center "c"))`.
Restore moves to a separate `(key "r" "Restore" (λ () (restore-window)))`
in the same overlay so the reader sees a block + a loose key
coexisting.

**Verification:** *Relaunch. F18 w* now shows the diagram strip above
the text row; pressing `d/f/g/D/F/G/m/c` moves and resizes the
window.

### Step 4 — A selector

The reader adds `(key "s" "Select Window"
(selector 'prompt "Select window by name…" 'source list-windows
'on-select focus-window))` inside the same overlay.

**Concept introduced:** a *selector* is a node, not an action. It's
*decorated* by the wrapping `(key K L …)` — `(selector …)` returns a
pair, the `key` macro sees a pair, and so it stamps key/label onto it.
This is the same shape factories like `(settings:actions)` use; once
the reader gets it once, every factory in the codebase reads the same
way.

**Form introduced:** `(selector 'prompt … 'source … 'on-select …)`.

**Verification:** *Relaunch. F18 w s* opens a fuzzy-finder over visible
windows; typing narrows; Enter focuses.

### Step 5 — The window list, with chips

The reader appends `(window:list-block 'chips? #t)` to the overlay.

**Concept introduced:** the chips painted on real windows are how the
overlay *names* what's on screen so the reader can match overlay row →
window. The block is a third overlay ingredient — overlays compose
freely from blocks and keys in any order. Everything in Part 1 is the
launcher pattern: each binding fires once, the overlay dismisses,
control returns to whatever was underneath.

**Form introduced:** `(window:list-block 'chips? #t)`.

**Verification:** *Relaunch. F18 w*. Real windows on screen now wear
labels matching the rows in the overlay's bottom block. Press any
binding — the overlay closes.

### Step 6 — Staying in a mode: a sticky focus sub-group

The reader adds a new sub-group inside `w`:

```scheme
(group "f" "Focus"
       'sticky #t
       'exit-on-unknown #t
  (key "h" "Left"  (λ () (focus-window-direction 'left)))
  (key "j" "Down"  (λ () (focus-window-direction 'down)))
  (key "k" "Up"    (λ () (focus-window-direction 'up)))
  (key "l" "Right" (λ () (focus-window-direction 'right))))
```

(Exact identifier for the focus primitive — `focus-window-direction`
or whatever `window-actions.sld` actually exports — verified during
writing. If no per-direction primitive exists, the demo uses cycle-
through-windows or `select-next-window`; the *shape* of the step is
what matters.)

**Concept introduced:** `'sticky #t` keeps the modal navigation
*inside this group* after the binding fires. `'exit-on-unknown #t`
turns any non-binding key (including Esc) into a clean exit. This is
the iTerm `Focus` mode generalised — same shape, applied here to
window focus across the screen.

**Form introduced:** `(group K L 'sticky #t 'exit-on-unknown #t …)`.

**Verification:** *Relaunch. F18 w f h h h*. After the first `h`, the
overlay does **not** dismiss — it stays open, showing the four focus
bindings. Each `h` moves focus leftward. Press Esc (or any
unbound key); the overlay closes and you're back in the app.

Contrast deliberately: *F18 w d* (layout-block, Part 1) dismisses
after one press. *F18 w f h* (sticky group, Part 2) does not.

But notice the cost: to start moving focus, you press *three* keys —
`w`, `f`, `h`. That feels like one too many for a movement gesture you
might do dozens of times an hour. Step 7 fixes it.

### Step 7 — Sticky-target: fire AND enter, in one press

The reader refactors. The four hjkl bindings are *promoted* out of the
`f` sub-group and into `w` directly, each decorated with
`'sticky-target` pointing at a named sticky tree. The sticky tree
itself is registered separately with `(define-tree 'window-focus …)`.

```scheme
;; Top-level, outside (define-tree 'global …):

(define-tree 'window-focus
  'sticky #t
  'exit-on-unknown #t
  'display-name "Focus"
  (key "h" "Left"  (λ () (focus-window-direction 'left)))
  (key "j" "Down"  (λ () (focus-window-direction 'down)))
  (key "k" "Up"    (λ () (focus-window-direction 'up)))
  (key "l" "Right" (λ () (focus-window-direction 'right))))

;; Inside the `w` overlay, in place of the Step-6 (group "f" …):

(key "h" "Left"  (λ () (focus-window-direction 'left))
     'sticky-target 'window-focus)
(key "j" "Down"  (λ () (focus-window-direction 'down))
     'sticky-target 'window-focus)
(key "k" "Up"    (λ () (focus-window-direction 'up))
     'sticky-target 'window-focus)
(key "l" "Right" (λ () (focus-window-direction 'right))
     'sticky-target 'window-focus)
```

**Concept introduced:** `'sticky-target` is a *command* keyword (sits
on `(key …)`, not on a group). When the command fires, the state
machine runs the action **and then** transitions navigation into the
sticky tree named by the symbol. One key press does both jobs. The
overlay paints a marker on each cell so the reader sees which keys
are sticky-target leaders.

**Concept introduced (secondary):** sticky trees are *named, top-level
trees* — registered with `define-tree` under a symbol scope. The
launcher tree (`'global`), the per-app tree (`'com.googlecode.iterm2`),
and the sticky tree (`'window-focus`) all live in the same registry
and look structurally identical; the only difference is what
references them. Once the reader sees three trees alongside each
other, "tree" becomes the unit of mental composition.

**Form introduced:** `(define-tree 'window-focus 'sticky #t
'exit-on-unknown #t …)` as a sibling top-level form, plus
`'sticky-target SYMBOL` as a trailing keyword on `(key …)`.

**Verification:** *Relaunch. F18 w h h h*. The first `h` moves focus
left **and** the overlay swaps to the four-row focus tree. Subsequent
`h` presses keep moving. Esc exits. Compare: Step 6 needed `w f h`;
Step 7 needs `w h`. Same behaviour, one fewer press, and the iTerm
`Focus` mode in `apps/iterm.sld` is doing exactly this.

### Step 8 — Why this is "modal" (prose, no new form)

A closing step that names the two patterns the reader just built and
the contrast between them — written at a length the *idea* deserves
(probably 60–90 lines), not a length the spreadsheet permits.

- **Launcher pattern.** A tree the reader steps through. Each leaf
  fires once and the overlay dismisses. Steps 1–5 built this: the
  global tree, the layout-block, the selector, the window-list. Most
  of `default-config.scm` is this pattern.
- **Modal pattern.** A sticky tree the reader enters and stays in
  until an unrecognised key exits. Steps 6–7 built this in two passes:
  Step 6 demonstrated the explicit shape (a sub-group entered via a
  parent key), Step 7 refactored to the *sticky-target* shape that the
  rest of the system uses — the first press of a binding both runs an
  action and transitions into a separately-registered sticky tree. The
  iTerm `Focus` mode in `Sources/Modaliser/Scheme/lib/modaliser/apps/iterm.sld`
  is exactly the sticky-target shape applied to iTerm panes; the
  reader's `w h` is now structurally identical to iTerm's pane focus.

The system's design rests on these two patterns coexisting in the same
tree. Once the reader sees both, the rest of the surface area (per-app
trees, selectors, blocks, categories) is recognisable as combinations
of pieces they've already met — a per-app tree is a *launcher* tree
selected by frontmost-app; `(category …)` is a layout marker for one;
a sticky tree is the *modal* pattern with a name and a registration.

Closes with three forward links:

- `docs/how-to/sticky-mode.md` — for the longer treatment of sticky,
  `sticky-target`, and `exit-on-unknown` as recipe-shaped notes
  rather than a learning narrative.
- `docs/how-to/add-a-per-app-tree.md` — when you want different
  bindings inside one app (e.g. the iTerm `Focus` you just modelled).
- `docs/reference/dsl.md` — for the full list of forms.

## Anti-trap coverage

The kickoff lists nine anti-traps. The design addresses each:

| Anti-trap | Mitigation in this design |
|---|---|
| How-to disguised as tutorial | Every step explains *why this concept exists*, not "to do X, type Y". The step titles name concepts (*A leader with one binding*, *Make `w` into a menu*), not goals. |
| Concepts in batches | Exactly one form (or one tightly-coupled pair) per step. `sticky` and `exit-on-unknown` arrive *together* in Step 6 because they're two halves of one idea (a group you stay in until you exit). `'sticky-target` (Step 7) is held back until the reader has felt the cost of needing `w f h` first — the refactor lands as an answer to a problem they just experienced. `category` remains out of scope. |
| Skip the relaunch loop | Every step ends with "*Pick Relaunch from the menu bar icon, then press F18 w …*" — verbatim, not paraphrased. Memory `feedback_no_in_place_reload` enforces this. |
| Paraphrase reference | No keyword tables. Concepts are introduced in context. Reference is linked once, at the end of Step 8. |
| Assume reader read reference | Audience is a new reader who has just done the quickstart; reference is the *follow-up* for the curious, not a prerequisite. |
| Didn't run it yourself | The implementation plan makes "actually run every step on a backed-up `~/.config/modaliser/`" an explicit gating task. Verification beats are concrete (the window *moves*, the overlay *shows three rows*) so a wrong snippet fails loudly. |
| Open with Diátaxis framing | The tutorial opens with "you'll build a `w` window-management leader that …". Diátaxis is not named. |
| Promise reload-without-relaunch | Each verification beat says **relaunch**, never *reload*. |
| Single tutorial doesn't need an index | No `docs/tutorials/index.md`. Quickstart and `how-to/index.md` link directly to `docs/tutorials/modal-thinking.md`. |

## Cross-links

After the tutorial is written:

- `docs/quickstart/index.md` — add a "Tutorial" bullet to *What's
  next*, placed **above** the how-to bullet (a learning-oriented
  reader's natural next step after quickstart is a tutorial, not a
  recipe).
- `docs/how-to/index.md` — add one sentence near the top: "If you'd
  rather *learn the system* through a worked example, start with
  `../tutorials/modal-thinking.md`."

No back-links from individual how-tos to the tutorial — the how-to
index entry is enough; per-page back-links would clutter recipe pages.

## Length

No hard line budget. A learning experience is worth the lines it
takes; a tutorial that crams the reader is a worse artefact than one
that breathes. Each step should be as long as the *concept* needs,
including a sentence-or-two "what just happened" reflection after the
verification beat. Realistic ballpark for the whole tutorial: 400–600
lines; if it sprawls past that the writer should look for repetition,
not concepts to cut.

## Source-of-truth files

The writing pass must verify every snippet against these files (not
against Phase-2 prose):

- `Sources/Modaliser/Scheme/lib/modaliser/dsl.sld` — `key`, `overlay`,
  `selector`, `group`, `define-tree`, `λ`. Two pieces of the keyword
  tail matter for Part 2: `group`'s `'sticky` / `'exit-on-unknown`
  (Step 6) and `key`'s `'sticky-target SYMBOL` (Step 7; the macro
  contract is in `dsl.sld` lines 39–43 and 95–107). `define-tree`'s
  same `'sticky` / `'exit-on-unknown` keywords (top-level form) are
  what Step 7's `(define-tree 'window-focus …)` uses.
- `Sources/Modaliser/Scheme/lib/modaliser/state-machine.sld` —
  semantics of `'sticky`, `'exit-on-unknown`, and `'sticky-target` at
  the state-machine level. The tutorial does not surface this detail,
  but the writer must understand it to describe Step 6's and Step 7's
  verification accurately (e.g. *which* unbound keys actually exit
  the sticky tree, and how `'sticky-target` differs from
  `(enter-mode! …)`).
- `Sources/Modaliser/Scheme/lib/modaliser/leader.sld` —
  `set-leaders!` shape (already covered in quickstart, only verified
  here).
- `Sources/Modaliser/Scheme/lib/modaliser/window-actions.sld` —
  `window:maximise`, `window:layout-block`, `restore-window`, **and
  the focus primitive Steps 6 and 7 bind.** If a per-direction
  `focus-window-direction` does not exist, Steps 6/7 fall back to
  whatever does (e.g. cycle, next/previous) — the *shape* of those
  steps is sticky / exit-on-unknown / sticky-target, not the specific
  primitive. Steps 6 and 7 must call the *same* primitive so the
  refactor in Step 7 is observably equivalent.
- `Sources/Modaliser/Scheme/lib/modaliser/blocks/window-list.sld` —
  `make-window-list-block` and the `'chips?` option.
- `Sources/Modaliser/Scheme/lib/modaliser/launchers.sld` and
  `Sources/Modaliser/Scheme/ui/chooser.scm` — `selector` / `list-windows`
  / `focus-window` end-to-end. **Note:** this code carries plumbing
  for Tab-driven per-item actions on the highlighted selector entry,
  which does **not work today**. See *Known broken* above; Step 4 may
  describe only `'prompt` / `'source` / `'on-select`.
- `Sources/Modaliser/Scheme/lib/modaliser/apps/iterm.sld` — the
  canonical sticky-target focus mode and the *direct structural
  template for Step 7*. The transient tree's hjkl bindings (lines
  179–187) each carry `'sticky-target sticky-id` and the separately-
  registered `focus-mode-tree` (lines 197–212) is the sticky tree
  itself, with `'sticky #t` / `'exit-on-unknown #t` / `'display-name`.
  Step 7's snippet generalises this shape from iTerm panes to macOS
  windows; the writer must match the iTerm shape closely enough that
  the closing line of Step 7 ("the iTerm `Focus` mode is doing exactly
  this") is literally true.
- `Sources/Modaliser/Scheme/default-config.scm` — the bundled `w`
  leader (lines 69–97) is the closest existing artefact to the
  tutorial's destination. Snippets must remain compatible with the
  forms used there. Note: the shipped `w` does **not** include either
  a sticky sub-group or sticky-target hjkl bindings; Steps 6 and 7
  both go beyond `default-config.scm`, which is fine — the tutorial's
  end state is a *superset* of the default, demonstrating the same
  forms iTerm uses but applied to global window focus.

## Verification gates

The implementation plan must include:

1. **Pre-write sweep** rerun on the worktree (already green as of
   2026-05-19, but a refresher in the writing session catches drift).
2. **Author runs every step end-to-end** on a backed-up
   `~/.config/modaliser/config.scm`. Each verification beat must
   actually verify on screen — "the window maximises", "the overlay
   shows three rows", etc.
3. **Internal-link checker** — Phase 2 wrote one at
   `/Users/antony/.claude/jobs/<id>/linkcheck.py`; that scratch dir is
   gone, so the plan rewrites it from scratch. Walks
   `docs/{quickstart,reference,how-to,tutorials}/`, regex-extracts
   markdown links, resolves relative paths, fails on missing targets,
   skips fenced code and inline code.
4. **`swift test`** — sanity check that no code was touched.
5. **`superpowers:requesting-code-review`** — focus prompt: does the
   tutorial *teach* (vs. recite recipes)? Does every snippet run? Are
   concepts introduced one at a time? Did the author actually run it?

## Definition of done

- `docs/tutorials/modal-thinking.md` exists and follows the
  step-by-step arc above (length set by the material, not a budget).
- Every code snippet has been actually run by the author end-to-end
  on a clean `~/.config/modaliser/`.
- `docs/quickstart/index.md` has a *Tutorial* bullet above the how-to
  bullet in its *What's next* list.
- `docs/how-to/index.md` mentions the tutorial as the learning-oriented
  alternative near its introduction.
- Internal-link checker green across
  `docs/{quickstart,reference,how-to,tutorials}/`.
- No mention of removed APIs (`set-host-header!`, `set-overlay-css!`,
  `'chip-options`, `'hint-options`, `overlay.css`).
- `swift test` green.
- Phase-3 kickoff prompt
  (`docs/superpowers/prompts/2026-05-19-docs-phase3-tutorials-kickoff.md`)
  dropped in a follow-up housekeeping commit (precedent: `86ac695`).
- Diátaxis restructure declared "3 quadrants written + 1 deferred by
  intent" in the finishing commit message.
