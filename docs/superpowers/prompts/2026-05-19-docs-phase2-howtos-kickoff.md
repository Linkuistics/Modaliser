# Docs Phase 2 — How-tos — Fresh-Session Kickoff

> **For agentic workers:** This is a *kickoff* prompt for a fresh
> Claude Code session. Read it end-to-end before touching code or docs.

## Prerequisite

The **data-attrs cleanup** must be merged into `main` before this slice
starts. Verify: `grep -rE "string-append.*--[a-z]|cons 'style" Sources/Modaliser/Scheme/`
should return zero matches. If it doesn't, stop and execute
`docs/superpowers/prompts/2026-05-19-data-attrs-cleanup-kickoff.md`
first — that work touches docs adjacencies and a Phase-2 sweep should
land on top of it cleanly.

## Background

Phase 1 of the Diátaxis docs restructure shipped
(`docs/superpowers/plans/2026-05-19-docs-restructure.md`,
merge `fe298cb`): `quickstart/index.md` + a complete `reference/`
tree. Phases 2 (how-tos) and 3 (tutorials) were deferred. Two
substantive refactors have landed since Phase 1 that the existing prose
mostly absorbed (chip theming → CSS, `set-host-header!` removed,
`overlay.css` → `theme.css`, Settings menu reveals config dir).

This slice fills out `docs/how-to/` with goal-oriented walkthroughs.

## Scope

**In scope:** create `docs/how-to/` with an `index.md` overview + a
handful of focused, problem-driven walkthroughs. Each how-to assumes
the reader has done `quickstart/` and can reach for `reference/` for
form-by-form detail. The how-to itself stays narrative and
goal-oriented (Diátaxis pattern).

**Out of scope:**
- Phase 3 (tutorials) — end-to-end learning paths, deferred.
- Auto-generated docs — still hand-written for now.
- Rewriting `reference/` — those are stable. Only edit if you find a
  bug or a refactor-induced staleness.
- New library work. If a how-to surfaces missing bundled functionality
  (e.g. "how to add a per-app tree" needs a generic app-launcher
  helper that doesn't exist), file a follow-up note in the plan
  rather than adding the helper.

## Pre-write sweep (mandatory)

Two recent refactors changed user-facing surfaces. Before writing
*any* how-to that touches theming or per-app configuration, sanity-
check the current state of these:

```bash
# Should return only migration-error strings in 2 .sld files
grep -rE "chip-options|hint-options" Sources/Modaliser/Scheme/

# Should return zero matches
grep -rn "set-overlay-css|set-host-header" Sources/Modaliser/Scheme/

# Confirm the user-CSS file path is theme.css (not overlay.css)
grep -rn "theme.css\|overlay.css" Sources/Modaliser/Scheme/
```

If any how-to draft uses `set-host-header!`, `set-overlay-css!`,
`'chip-options`, `'hint-options`, or `overlay.css` (the file name),
the writer is leaning on the historical Phase-1 docs that pre-date the
refactors. Rewrite against the *current* code.

## Diátaxis how-to pattern

Each how-to is a *recipe* for a specific user goal, not a learning
narrative (that's tutorials) or an exhaustive specification (that's
reference). Format roughly:

```
# How to <goal>

<one-paragraph motivation: when you'd want this>

## You'll need

- <prerequisite: a Modaliser install, an existing config.scm, …>
- <reference pointers: link into reference/ for the forms used>

## Steps

1. <imperative step>
2. <imperative step>
   ```scheme
   <minimum working snippet>
   ```
3. <…>

## Verify it worked

<one or two checks: press F18, look for X, run swift test, …>

## Related

- <links to related how-tos, reference sections, libraries>
```

Keep each how-to under ~120 lines. If a topic grows past that, split
it or move the conceptual half into a reference cross-link.

## Candidate how-tos

Triage with the user before writing — they pick which set of ~5-8 to
ship as Phase 2 v1. Candidates, grouped by frequency:

**Configuration basics**
- How to add a binding to the global tree
- How to add a per-app tree (using `(define-tree 'com.bundle.id …)`
  directly; cross-link to `apps/safari` and `apps/iterm` as bundled
  examples)
- How to split your config across files (the `~/.config/modaliser/`
  layout: `config.scm`, `theme.css`, user `.sld` libraries, `sys/`
  mirror — already documented in `reference/library-system.md`; the
  how-to is the task-oriented spin)

**Modal navigation**
- How to set up a sticky mode (focus-mode pattern, `'sticky` +
  `'exit-on-unknown`, escaping conventions)
- How to make a key both fire an action AND enter a sticky mode
  (`'sticky-target`)
- How to bind a digit range (`(keys '("1" ..) …)` and the
  `(matched-key index keylist)` callback)

**Selectors and search**
- How to add a fuzzy-finder for a custom data source (`(selector
  'prompt 'source 'on-select)`)
- How to add a dynamic-search selector (web search, file search —
  point at `(modaliser web-search)` and `(modaliser launchers)`)

**Theming**
- How to customise the overlay theme (`theme.css` — colours, fonts;
  reference `reference/theming.md` for the full variable inventory)
- How to recolour chips (the `.chip` rule; how `--color-host-bg`
  threads everywhere)
- How to switch to a dark theme (worked example based on the dark-mode
  block in `reference/theming.md`)

**Custom blocks / advanced**
- How to compose an overlay with multiple blocks (`(overlay
  (which-key-block …) (window:list-block …) …)`)
- How to write a custom block renderer (link out to
  `reference/renderer-protocol.md`)

**Operational**
- How to reload / relaunch after a config edit (menu bar "Relaunch",
  the leader `,` → `r` Reload binding; *not* "Edit" because that opens
  the config dir, not the file)
- How to debug "my binding does nothing" (common pitfalls: forgot
  `(λ () …)` around a side-effecting call, scope mismatch, leader not
  set, app focus state)

## Workflow

1. **Open a worktree.** `superpowers:using-git-worktrees`, branch
   `docs-phase2-howtos`. Verify base is local `main` (data-attrs
   cleanup should already be in main per Prerequisite above).
2. **Run the pre-write sweep** above. If anything is amiss, stop and
   fix `Sources/` before writing prose.
3. **Triage the candidate list** with the user. Pick a Phase-2 v1 set
   (suggest 6–8 how-tos). Don't write all of them; how-tos accrete
   over time and the cost of stale prose is real.
4. **Create `docs/how-to/index.md`** — short navigation page listing
   each how-to with a one-line summary. Group by the headings above.
5. **Write each chosen how-to** in `docs/how-to/<slug>.md` following
   the Diátaxis pattern above. Verify every code snippet against the
   .sld it exercises — don't trust phase-1 prose unconditionally.
6. **Cross-link from `quickstart/index.md`** — its "What's next" list
   currently points only at reference. Add a "How-to guides" bullet.
7. **Cross-link from `reference/` pages** where the how-to amplifies a
   bare reference entry (e.g. `reference/dsl.md`'s `(selector …)`
   section can link to "How to add a fuzzy-finder for a custom data
   source").
8. **Run the link checker** (Python snippet from the docs-restructure
   transcript) — verify all internal links resolve.
9. **Verify against `swift test`** — no code touched, but run it to
   confirm the worktree's clean (catches any accidental edits to .sld
   files when adapting snippets).
10. **Code review.** `superpowers:requesting-code-review` (yes — docs
    benefit from review for accuracy + audience-fit). Focus: does
    every snippet reflect the current code? Are how-tos goal-oriented
    (not narrative)? Any reliance on removed APIs?
11. **Finish.** `superpowers:finishing-a-development-branch`.

## Anti-traps

- **Don't write tutorials disguised as how-tos.** A how-to assumes the
  reader knows the basics; it gives them a recipe. A tutorial holds
  the reader's hand through learning the basics. If a draft starts
  with "let's learn about …", it's a Phase-3 tutorial, not a how-to.
- **Don't lift Phase-1 prose into how-tos without re-grounding.** The
  reference docs already have signatures, keyword tables, and worked
  snippets. A how-to that's a paraphrase of reference adds noise.
  Anchor on a specific user *goal* the reference doesn't directly
  address.
- **Don't document removed APIs.** `set-host-header!`,
  `set-overlay-css!`, `'chip-options`, `'hint-options` are gone. The
  recent refactors removed them. If a candidate how-to depends on
  one, rewrite it against the current surface (`theme.css`,
  `'chips? #t`, etc.) or drop the candidate.
- **Don't pre-populate `docs/tutorials/`.** Phase 3 is a separate
  slice. Phase 2 leaves that directory alone (it doesn't even need to
  exist yet — Diátaxis tooling doesn't require empty placeholder
  folders).
- **Each how-to verifies against code, not against prose.** Open the
  relevant `.sld` and check the exported names, keyword set, return
  shapes. The reference docs are usually accurate, but trust-but-
  verify when copying a snippet.
- **No code edits.** This is a docs slice. If a how-to reveals a
  missing helper or a real bug, write the finding into a follow-up
  note in `docs/superpowers/plans/` rather than fixing it inline.

## Source-of-truth files for accuracy checks

For each how-to topic, the writer reads:

- DSL forms: `Sources/Modaliser/Scheme/lib/modaliser/dsl.sld`
- State machine / sticky / scope: `Sources/Modaliser/Scheme/lib/modaliser/state-machine.sld`
- Leader: `Sources/Modaliser/Scheme/lib/modaliser/leader.sld`
- Selectors / chooser: `Sources/Modaliser/Scheme/lib/modaliser/launchers.sld`,
  `Sources/Modaliser/Scheme/lib/modaliser/web-search.sld`,
  `Sources/Modaliser/Scheme/ui/chooser.scm`
- Themes / chips: `Sources/Modaliser/Scheme/base.css`,
  `Sources/Modaliser/Scheme/lib/modaliser/theming.sld`,
  `~/.config/modaliser/theme.css` (user-side)
- Per-app trees: `Sources/Modaliser/Scheme/lib/modaliser/apps/{safari,chrome,iterm}.sld`
- Blocks: `Sources/Modaliser/Scheme/lib/modaliser/blocks/*.sld`,
  `Sources/Modaliser/Scheme/lib/modaliser/window-actions.sld`
- Settings menu: `Sources/Modaliser/Scheme/lib/modaliser/settings-menu.sld`
- Bundled config: `Sources/Modaliser/Scheme/default-config.scm`,
  `~/.config/modaliser/config.scm`

Existing reference pages (the Phase-1 output) live in `docs/reference/`
and are the inverse-direction cross-links from each how-to.

## Definition of done

- `docs/how-to/index.md` exists, lists each how-to with a one-line
  summary, and is linked from `docs/quickstart/index.md`'s
  "What's next".
- The agreed Phase-2 v1 set of how-tos exist in `docs/how-to/<slug>.md`,
  each following the Diátaxis pattern.
- Every code snippet in every how-to compiles in current Modaliser
  (cross-reference the relevant `.sld`).
- Internal cross-links resolve (link-checker green).
- No how-to mentions a removed API (`set-host-header!`,
  `set-overlay-css!`, `'chip-options`, `'hint-options`, `overlay.css`
  file name).
- `swift test` is green (sanity-check no inadvertent code edits).
- Phase-3 (tutorials) remains untouched and is noted as next-up in the
  finishing report.
