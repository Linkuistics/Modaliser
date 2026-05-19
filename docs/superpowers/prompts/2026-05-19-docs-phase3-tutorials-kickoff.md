# Docs Phase 3 — Tutorials — Fresh-Session Kickoff

> **For agentic workers:** This is a *kickoff* prompt for a fresh
> Claude Code session. Read it end-to-end before touching docs.

## Prerequisite

Phase 2 (how-tos) must be in `main`. Verify:
`ls docs/how-to/ | wc -l` should report 8 files (index + 7 how-tos).
If not, the Phase-2 work hasn't landed; stop and investigate.

## Background

The Diátaxis docs restructure has shipped Phases 1 and 2:

- **Phase 1 — Reference** (`fe298cb`): `docs/reference/` with full
  form-by-form coverage of DSL, state machine, libraries, theming,
  keyboard, library system, portability, renderer protocol.
- **Phase 2 — How-tos** (`fc18ac6`, `c9822fd`): 7 task-oriented
  walkthroughs under `docs/how-to/` covering bindings, per-app trees,
  config splitting, sticky modes, fuzzy-finders, theming, debugging.

Phase 3 fills the last Diátaxis quadrant: **tutorials**. Learning-
oriented, narrative, hand-holding — the opposite quadrant from
reference, distinct from how-tos in audience and shape.

A quickstart (`docs/quickstart/index.md`) already exists but is
deliberately ~5 minutes: install → first edit → relaunch. A tutorial
is a longer, more substantial learning path — 30–60 minutes — where
the reader builds something real and ends with a working artefact
they'd actually keep using.

## First-class question for the brainstorm

Modaliser is currently single-user. Tutorials are aimed at *teaching
new people* — they pay off when someone unfamiliar with the system
needs to ramp up. For a solo repo the audience is essentially
future-self after time away, plus anyone the project might attract
later.

**Decide in the brainstorm:**

- Is a tutorial worth writing now? (Yes → proceed with Scope below.)
- Or defer Phase 3 until there's a second user or a long absence?
  (No → write a short `docs/superpowers/plans/` note explaining the
  deferral and close out the Diátaxis restructure as "3-quadrant
  complete by intent.")

Don't paper over this — Phase 2 dropped migration notes for the same
"single-user" reason, and the same logic could apply here. If you
proceed, the brainstorm should also pin down *who* the tutorial is
for: future-self vs. hypothetical new user. The framing differs.

## Scope (if proceeding)

**In scope:** create `docs/tutorials/` with one (recommended) or two
tutorials — each a complete, narrative learning path. If multiple,
add an `index.md`; if just one, the single page can live as
`docs/tutorials/<slug>.md` and be linked directly from quickstart.

**Out of scope:**

- More how-tos. Phase 2 is complete. Anything goal-oriented is a
  how-to and goes there.
- Reference revisions. Phase 1 is stable; only edit on bug or
  refactor-induced staleness.
- New library work. If a tutorial surfaces missing functionality,
  write a follow-up `plans/` note rather than expanding the bundled
  libraries inline.
- Multiple tutorials in a kitchen-sink dump. Diátaxis is explicit:
  tutorials are expensive to author and maintain — few and excellent
  beats many and stale.

## Pre-write sweep (mandatory)

Phase 2 (how-tos) and the recent refactors (data-attrs cleanup, chip
theming → CSS, `theme.css` rename) landed before this slice. Re-run
the Phase-2 sweep to confirm nothing has drifted:

```bash
# Should return only migration-error strings (in 2 .sld files)
grep -rE "chip-options|hint-options" Sources/Modaliser/Scheme/

# Should return zero matches
grep -rn "set-overlay-css|set-host-header" Sources/Modaliser/Scheme/

# Confirm the user-CSS file path is theme.css (not overlay.css)
grep -rn "theme.css\|overlay.css" Sources/Modaliser/Scheme/

# Confirm the existing how-tos are still in main
ls docs/how-to/
```

If any of these reveal drift, stop and fix `Sources/` or
`docs/how-to/` before writing the tutorial.

## Diátaxis tutorial pattern

Each tutorial is a *single coherent learning narrative*, not a recipe
or a spec. The distinguishing characteristics:

| Property | Tutorial | How-to | Reference |
|---|---|---|---|
| Mode | Learning | Problem-solving | Looking up |
| Audience | Beginner | Has a specific goal | Knows the system |
| Path | Linear, no branching | Goal-determined | Random-access |
| Concepts | Introduced one at a time | Assumed | Named exhaustively |
| End state | Working artefact + understanding | Goal achieved | — |
| Author cost | High (must re-run end-to-end) | Medium | Low (write once) |

Suggested shape:

```
# <Tutorial title>

<one-paragraph "what you'll build and why">

## Before you start

- <prerequisite: Modaliser installed, leader bound, …>
- <minimum existing knowledge — usually "you've done the quickstart">

## Step 1 — <named milestone>

<narrative explaining the goal of this step>

<concrete instruction>

   ```scheme
   <minimum working snippet>
   ```

<relaunch + observe>

<one-paragraph "what just happened" — making the concept explicit>

## Step 2 — <named milestone>

…

## What you built

<recap: the final config / behaviour, with one screenshot or
ASCII-art impression if useful>

## Where to go next

- <how-to link, e.g. "to add more bindings, see how-to/add-a-binding">
- <reference link, only when the reader is now likely to want exhaustive detail>
```

Keep each tutorial under ~300 lines. If it grows past, that's a sign
the scope is too large — split into two tutorials, or move some
content into a referenced how-to.

## Candidate tutorials

Triage with the user before writing — pick **one** for v1 (or at most
two). Candidates, ordered by likely value:

1. **"Modal Thinking — Build a Window Manager from Scratch"**
   Teaches the mental model of modes. Reader starts from a minimal
   config and builds a `w` leader that contains a sticky pane group,
   a layout block, and a "select window by name" selector. Touches:
   `group`, `sticky`, `sticky-target`, `exit-on-unknown`, `selector`,
   `category`, `overlay`. End state: a window-management leader the
   reader will actually use. Concepts arrive one at a time, each with
   "press F18, see what changed" verification.

2. **"A Configuration from Zero"**
   Reader empties `config.scm` (after backing it up) and rebuilds an
   ergonomic config from blank, choosing apps and keystrokes that
   match their workflow. Most comprehensive — touches leaders,
   define-tree, per-app trees, theming, the relaunch loop. Risk: gets
   long quickly; mitigate by ending at "you have a workable personal
   config" rather than "you have everything in default-config.scm".

3. **"Your Personal Launcher"**
   Narrower scope: build a selector-based launcher over the user's
   own data (e.g. notes directory, projects list). Touches selectors,
   alist items, MRU. Risk: overlaps with `how-to/fuzzy-finder.md`
   without enough new narrative content. Probably better folded into
   #1 or #2 as a single step.

**Recommendation:** #1 (Modal Thinking). It teaches what makes
Modaliser different from a hotkey app — the modal vocabulary — which
is precisely the conceptual gap a tutorial should close. #2 risks
becoming a "kitchen sink" that reads more like a guided how-to chain.
#3 is too narrow.

## Workflow

1. **Open a worktree.** `superpowers:using-git-worktrees`, branch
   `docs-phase3-tutorials`. Use native `EnterWorktree` (the harness
   default base is `origin/main`; if local `main` is ahead, fast-
   forward with `git merge --ff-only main` before starting).
2. **Run the pre-write sweep** above. Stop and fix `Sources/` or
   `docs/how-to/` if anything has drifted since Phase 2.
3. **Brainstorm** with the user.
   `superpowers:brainstorming` is mandatory here — tutorials are a
   different surface from how-tos, not just more of them. Resolve the
   "is this worth writing?" question first; if yes, pick one
   candidate from the list above.
4. **Run it yourself.** Before writing prose, actually do every step
   in a clean shell on a backed-up `~/.config/modaliser/`. Note where
   you stumble; those are the moments the tutorial must address.
5. **Write the tutorial** at `docs/tutorials/<slug>.md` following the
   Diátaxis pattern above. Every snippet verified against the .sld
   sources, not against Phase-2 prose.
6. **Add `docs/tutorials/index.md`** only if there are 2+ tutorials.
   For a single tutorial, link directly from quickstart's "What's
   next" and from `how-to/index.md`'s introduction.
7. **Cross-link from quickstart** — add a "Tutorials" bullet to its
   "What's next" list, placed above the how-to bullet (tutorials are
   the natural next step after quickstart for a learning-oriented
   reader).
8. **Cross-link from `how-to/index.md`** — add one sentence near the
   top: "If you'd rather *learn the system* through a worked example,
   start with the tutorial."
9. **Run the link checker** — the Phase-2 transcript wrote one at
   `/Users/antony/.claude/jobs/<id>/linkcheck.py`. That temp dir is
   gone; rewrite the same logic (walk
   `docs/{quickstart,reference,how-to,tutorials}/`, regex out
   markdown links, resolve relative paths, fail on missing targets;
   skip fenced code and inline code so JS call signatures aren't
   misread as links).
10. **`swift test`** — sanity check that no code was inadvertently
    touched.
11. **Code review** — `superpowers:requesting-code-review`. Focus:
    does the tutorial actually teach (vs. recite recipes)? Does every
    code snippet run? Are concepts introduced one at a time? Did the
    author actually run the tutorial?
12. **Finish.** `superpowers:finishing-a-development-branch`. Recent
    project convention is local merge → push to main.

## Anti-traps

- **Don't write a how-to disguised as a tutorial.** If a draft starts
  with "to do X, do Y; to do Z, do W", it's a chain of recipes. A
  tutorial has *narrative continuity* — each step builds on the
  reader's growing understanding from the previous step.
- **Don't introduce concepts in batches.** "Now we'll add a sticky
  group, a selector, and an overlay" trains nothing. One concept,
  one demonstration, one "press F18 and look" verification, then
  move on.
- **Don't skip the relaunch loop.** Modaliser doesn't reload in
  place. Every config edit in the tutorial must be followed by
  "Pick **Relaunch** from the menu bar icon" so the reader builds
  the muscle memory.
- **Don't paraphrase reference.** A tutorial that quotes the keyword
  table from `reference/dsl.md` is wasting words. Use the keyword in
  context; the reader can look up the full table later.
- **Don't assume the reader has read reference.** Tutorial readers
  are new. Inline the minimum needed for the current step; link to
  reference at the end of the tutorial, not throughout it.
- **Run it yourself, every step.** A tutorial whose author didn't
  actually run it will have small lies — a `(λ () …)` placement off,
  a relaunch missed, a path mis-spelled. The cost of these in a
  tutorial is much higher than in a how-to because the reader has no
  prior model to spot the error against.
- **Don't open with framing about Diátaxis.** Readers don't care
  about the docs taxonomy; they care about Modaliser. Open with
  what they'll build.
- **Don't promise reload-without-relaunch or hot-reload anywhere.**
  Reload = relaunch. Past attempts to build in-place reload were
  dropped and aren't coming back.

## Source-of-truth files for accuracy checks

For each tutorial topic, the writer reads:

- DSL forms: `Sources/Modaliser/Scheme/lib/modaliser/dsl.sld`
- State machine: `Sources/Modaliser/Scheme/lib/modaliser/state-machine.sld`
- Leader: `Sources/Modaliser/Scheme/lib/modaliser/leader.sld`
- Selectors: `Sources/Modaliser/Scheme/lib/modaliser/launchers.sld`,
  `Sources/Modaliser/Scheme/lib/modaliser/web-search.sld`,
  `Sources/Modaliser/Scheme/ui/chooser.scm`
- Theming: `Sources/Modaliser/Scheme/base.css`,
  `Sources/Modaliser/Scheme/lib/modaliser/theming.sld`
- Per-app trees: `Sources/Modaliser/Scheme/lib/modaliser/apps/{safari,chrome,iterm}.sld`
- Blocks: `Sources/Modaliser/Scheme/lib/modaliser/blocks/*.sld`,
  `Sources/Modaliser/Scheme/lib/modaliser/window-actions.sld`
- Settings menu (relaunch + config dir): `Sources/Modaliser/Scheme/lib/modaliser/settings-menu.sld`,
  `Sources/Modaliser/Scheme/root.scm`
- Bundled config (for the "what does default look like" baseline):
  `Sources/Modaliser/Scheme/default-config.scm`

Existing user-facing docs to cross-link to:

- `docs/quickstart/index.md`
- `docs/how-to/` (all 7 + index)
- `docs/reference/` (all 8 pages)

## Definition of done

- One (or two) tutorials exist under `docs/tutorials/<slug>.md`.
- Each tutorial follows the Diátaxis pattern (narrative, single path,
  concepts introduced one at a time).
- Every code snippet has been actually run by the author end-to-end
  on a clean `~/.config/modaliser/`.
- Quickstart's "What's next" has a "Tutorials" bullet above the
  how-to bullet.
- `how-to/index.md` mentions tutorials as the learning-oriented
  alternative near its introduction.
- Internal-link checker green for all of
  `docs/{quickstart,reference,how-to,tutorials}/`.
- No tutorial mentions a removed API (`set-host-header!`,
  `set-overlay-css!`, `'chip-options`, `'hint-options`, `overlay.css`
  as a file name).
- `swift test` is green.
- The Phase-3 kickoff prompt
  (`docs/superpowers/prompts/2026-05-19-docs-phase3-tutorials-kickoff.md`)
  is dropped in a follow-up housekeeping commit (precedent: `86ac695`).
- If the brainstorm decided to *defer* Phase 3 instead of writing it,
  a short note lives in `docs/superpowers/plans/` explaining why, and
  the Diátaxis restructure is declared "3 quadrants complete by
  intent."
