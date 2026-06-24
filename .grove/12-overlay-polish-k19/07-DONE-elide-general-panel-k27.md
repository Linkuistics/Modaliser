# elide-general-panel-k27

**Kind:** planning

## Goal

Elide the explicit **"General" panel** into its parent screen as **loose
items** — unwrap `(panel "General" …)` so its children sit directly in the
`(screen …)` body and render bare in the loose region (the bare-loose-rows-k23
capability), instead of as a banded card. Requested by the user on 2026-06-24
while reviewing the overlay live, right after manual-panel-order-k24.

## Context

- **This is a config migration, not new app behaviour.** The mechanism already
  exists: bare-loose-rows-k23 made loose top-level rows (and folded top-level
  `open`s) render bare above the panel grid — no "General" card. The bundled
  `default-config.scm` is **already** migrated (its comments at ~lines 59/65/223
  note "no General card").
- **The live user config still has an explicit one.**
  `~/.config/modaliser/config.scm:62` declares `(panel "General" …)` wrapping the
  loose top-level keys (Switch Space `1..9`, Settings `,`, Highlight Cursor,
  the `w` window drill-down `open`, …). Eliding = drop the panel wrapper so
  those children become loose rows in `(screen 'global …)`.
- **A stale comment rides along.** `config.scm:57-58` still says "Loose
  top-level keys … collect into a leading 'General' panel automatically" — that
  was the *pre-k23* behaviour and must be corrected when the panel is unwrapped.
- Per `feedback_config_sync`, `config.scm` is the source that
  `default-config.scm` tracks; default-config is already in the target state, so
  the sync direction here is mostly "bring config.scm in line."
- Note `config.scm` lives under `~/.config/modaliser/` — **outside** this
  worktree, so editing it is not a grove-repo commit (it has its own CLAUDE.md).

## Design — to settle (grill first)

- **Scope.** User `config.scm` only? Also the per-app trees — e.g.
  `app-trees/com.apple.finder.scm` (its "General" card deliberately combines keys
  *and* the View/Go drill-downs in one card — eliding changes its layout, a real
  design call)? Also `docs/examples/config.scm` and any docs that still teach the
  explicit-General idiom? Recommend: settle the surface list up front.
- **Automatic vs. authored.** Is there any appetite for the *renderer* to elide a
  panel literally labelled "General" (or via a panel keyword like `'loose` /
  `'bare`)? Likely **no** — k23 already removed the auto-General concept and the
  fix is simply "don't wrap loose keys in a panel." Confirm we are NOT
  reintroducing an auto-collect rule; this is an authoring migration.

## Done when

- The explicit `(panel "General" …)` is unwrapped to loose items wherever the
  settled scope says (at least `~/.config/modaliser/config.scm`), rendering bare
  above the grid; the stale `config.scm:57-58` comment is corrected.
- Any in-repo surface in scope (default-config already done; app-trees /
  `docs/examples` per the grill) is consistent; reference docs that still teach
  the explicit-General idiom are updated.
- Verified live (install + Relaunch; the loose rows render bare, no "General"
  card). `check-portable-surface.sh` green if any `lib/modaliser` file is touched.

## Notes

- Independent of list-cursor-initial-focus-k25 and util-extraction-audit-k26.
- Small once scope is settled — likely a grill-then-do-in-one-session leaf, like
  manual-panel-order-k24 was.
