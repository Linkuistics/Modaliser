# prune-stale-backend-refs-k8

**Kind:** work

## Goal

Prune the dangling references to the **deleted** terminal-backends ADRs (0002–0008) and
`docs/prd/terminal-backends.md` across the codebase. Pre-existing debt, unrelated to
herdr — scoped here so the herdr leaves stay focused.

## Context

Read the root `BRIEF.md`. Independent of the other leaves (can run anytime). When the
terminal-backends grove finished, its `docs/prd/terminal-backends.md` and ADRs 0002–0008
were deleted, but code comments still cite them. Live ADRs are `0009`–`0012`;
`docs/prd/` does not exist.

Find them: grep for `ADR-000[2-8]`, bare `000[2-8]`, `docs/prd/terminal-backends`,
`terminal-backends.md`, "PRD" across `Sources/`, `docs/`, `CLAUDE.md`,
`CONTEXT.md`. Known culprits: `terminal.sld` (header + ADR-0006/0008 mentions),
`tmux.sld` (ADR-0006/0007 mentions), `apps/iterm.sld`, `muxes/zellij.sld`, CLAUDE.md.

For each: rewrite to reference what actually exists (e.g. point at the live doc or the
new `docs/adr/0013-…`), or remove the citation if the referenced rationale is gone.
Do **not** fabricate replacement ADRs — if a genuinely-durable decision is now
undocumented, note it for a real ADR rather than papering over.

Watch the portability gate: comments in `lib/modaliser/**` must avoid the literal
lispkit-parenthesis string (`check-portable-surface.sh` greps for it) — don't
reintroduce it while editing comments.

## Done when

- No dangling references to nonexistent terminal-backends ADRs/PRD remain
  (grep clean).
- `scripts/check-portable-surface.sh` green; `swift build` green (comment-only edits
  shouldn't affect it, but confirm).

## Notes
