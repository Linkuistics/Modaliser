---
kind: work
---

# 090 — Cutover: drop iTerm aliases, migrate config, update docs

## Goal

The **single breaking change** in the implementation node. Drop the
12 splits-tree exports from `(modaliser apps iterm)` (per ADR-0003),
migrate the user's `config.scm:157-176` from `(iterm:focus-pane-*)`
to `(terminal:focus-pane-*)`, and update phase-1 docs to match the
new model.

Runs **after** all backends are validated. By this point the user
has had time to use `(terminal:focus-pane-*)` alongside the legacy
`(iterm:…)` calls and confirm the façade is correct.

## Context

- ADR-0003 — façade-only public surface; the iTerm splits-tree
  exports go.
- PRD § "Migration and compatibility" — exact diff for the user's
  config and the phase-1 docs to update.
- `Sources/Modaliser/Scheme/lib/modaliser/apps/iterm.sld` export
  list still has the 12 procs as of 020 (they were kept as
  aliases). Now they go.
- User's config: `~/.config/modaliser/config.scm:157-176` (12
  procedures × ~20 call sites). Per [[feedback_config_sync]], any
  edits sync to `Sources/Modaliser/Scheme/default-config.scm`.
- Per [[feedback_install_flow]], source changes need
  `./scripts/install.sh`; "Relaunch" alone restarts the stale
  `/Applications` bundle.

## Done when

- `Sources/Modaliser/Scheme/lib/modaliser/apps/iterm.sld` no longer
  exports the 12 splits-tree procedures (`focus-pane-left`/`-right`/
  `-up`/`-down`, ×focus/split/move). The internal definitions stay
  (used by the iTerm backend record); only the public export list
  changes.
- User's `~/.config/modaliser/config.scm:157-176` migrated:
  - `(iterm:focus-pane-left)` → `(terminal:focus-pane-left)` and
    the analogous 11 renames.
  - Import line adds `(prefix (modaliser terminal) terminal:)` if
    not already present.
- `Sources/Modaliser/Scheme/default-config.scm` synced to match.
- Phase-1 docs updated:
  - `docs/reference/terminal-detection.md` — fix the stale claims
    documented in the PRD (zellij has CLI; Alacritty has `alacritty
    msg`; Ghostty 1.3.0+ has AppleScript).
  - `docs/how-to/terminal-pane-aware-tree.md` — examples use the
    façade, not iTerm-specific procs. Reference the capability
    predicates for cross-backend trees.
- A new how-to (or section in the existing one) shows the
  capability-predicate pattern for generic trees:
  `(when (terminal:supports-move-pane?) ...)`.
- `./scripts/install.sh` runs cleanly. Modaliser restarts and the
  user's tree works against iTerm with no functional regression.
- `swift build` succeeds; `swift test` passes.

## Notes

- This leaf is the moment of truth for the abstraction. If the
  user's tree breaks subtly (some op routes wrong, the
  context-suffix doesn't fire, chips render in the wrong place),
  the previous leaves haven't done their job — pause and fix
  upstream rather than papering over.
- Don't try to bundle in additional polish here (e.g. README
  rewrites for the public release per [[project_public_release]]).
  Public-release prep is a separate workstream; this leaf is
  scoped to "make the abstraction the official interface."
- After this leaf completes, the 020-implement node retires:
  promote anything still relevant from its `BRIEF.md` up to the
  root grove BRIEF (likely: the new `(modaliser terminal)` module
  becomes part of the documented API; the backend modules are
  cataloged). Then `mv 020-implement/` into
  `groves/terminal-backends/done/`. The grove itself can then end
  (no live leaves remain), or grow a new node for any follow-on
  work surfaced during implementation.
