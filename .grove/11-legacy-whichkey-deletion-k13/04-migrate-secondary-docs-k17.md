# migrate-secondary-docs-k17

**Kind:** work

## Goal

Migrate the **secondary docs** — the how-to guides, the tutorial, the
quickstart, and the runnable example config — off the now-deleted authoring
forms (`define-tree` / `category` / `overlay` / `which-key-block`) onto the
layout DSL (`screen` / `panel` / `open` / `fragment`). After
[[delete-which-key-k15]] these docs teach forms that no longer exist, so a
reader copy-pasting from them lands on an unbound-variable / import error.

## Context

[[reconcile-docs-k16]] reconciled only the **reference surface** (reference
docs + `CONTEXT.md` + the design-spec note + the ADR-0012 flag-day amendment)
— this split was a **user decision on 2026-06-24** (asked: how should k16
handle the secondary docs broken by the k15 deletion; answered: do the
reference surface now, spin the secondary-doc migration into this follow-up
leaf, which defers the grove's Finish cycle). k16 deliberately left these
files alone because migrating them is a larger, semantic rewrite — not a
find-and-replace — and because some (the tutorial, the example config) are
built end-to-end around `define-tree`.

The migration is **not mechanical**. The lowering is one-to-one in spirit but
the prose/structure must change: `define-tree 'scope` → `screen 'scope`;
`category "L"` → `panel "L"` (a banded card, optionally `'span`); loose
top-level keys under a `screen` pack into a leading **"General"** panel (the
old misc-bucket auto-split is gone); `(key K L (overlay …))` drill-downs →
`(open K L …)`; explicit `which-key-block` → just a panel's rows. Ground the
new examples against `docs/reference/dsl.md` (the current authoritative
surface) and the bundled `default-config.scm` (already on the panel model).

**Files still teaching the deleted forms (re-grep at execution — line numbers
drift):**
- `docs/examples/config.scm` — a full runnable example config, `define-tree`
  throughout (`'global`, `'com.googlecode.iterm2`, `'company.thebrowser.dia`),
  a `which-key`-strip comment, and a `(modaliser blocks which-key)` import.
  Heaviest single file; the result must actually load.
- `docs/tutorials/modal-thinking.md` — the tutorial is structured around
  `define-tree 'global` and the "implicit which-key block of loose keys"
  mental model; needs a genuine rewrite to the panel mental model, not a
  token swap.
- `docs/quickstart/index.md` — "which-key overlay" framing (`:58`) and
  "every form available inside `define-tree`" (`:135`).
- `docs/how-to/add-a-binding.md` — "Find `(define-tree 'global …)`" + the
  "loose forms into one which-key block" explanation.
- `docs/how-to/add-a-per-app-tree.md` — `define-tree` is the spine of the
  recipe.
- `docs/how-to/terminal-pane-aware-tree.md` — many `define-tree` variants
  (the heaviest how-to).
- `docs/how-to/sticky-mode.md` — `'sticky #t` on `define-tree`'s keywords.
- `docs/how-to/split-your-config.md` — `define-tree` in the worked split.
- `docs/how-to/debug-binding.md` — `define-tree 'global` / `'com.your.app`
  scoping examples.

**Leave as historical record (do NOT rewrite):** the dated specs/plans under
`docs/specs/` and `docs/superpowers/` and the ADRs (`docs/adr/0011`,
`docs/adr/0012`) — they are dated snapshots / decision records and
legitimately mention the old forms. k16 added the supersession note to the
2026-06-23 design spec and the flag-day amendment to ADR-0012.

## Done when

- No how-to guide, the tutorial, the quickstart, or the example config
  presents `define-tree` / `category` / `overlay` / `which-key-block` as
  usable surface; they teach `screen` / `panel` / `open` / `fragment`.
- `docs/examples/config.scm` loads without referencing a removed form
  (drops the `(modaliser blocks which-key)` import; uses the layout DSL).
- `grep -rn 'which-key\|define-tree\|overlay\b\|which-key-block' docs/how-to/
  docs/tutorials/ docs/quickstart/ docs/examples/` returns only intentional
  references (e.g. `(open …)`/`overlay`-the-NSPanel prose, not the deleted
  `(overlay …)` form).
- Cross-doc links still resolve (e.g. dsl.md no longer has a
  `#legacy-forms-deprecated` anchor — k16 removed that section; fix any
  inbound link).

## Notes

- Audience is **external readers** meeting the panel surface fresh (public
  release; project memory) — write the examples as the *recommended* way to
  author, not as a migration from something they never used.
- Use Mermaid, never ASCII art, for any diagram (project memory).
- After this leaf retires, the `legacy-whichkey-deletion-k13` node has no live
  leaf → the grove root has none → the **Finish** cycle (deferred twice now:
  once from k9, once from k16) runs. Re-check `main` vs the branch point
  before merging (the node BRIEF Notes describe the expected fast-forward).
</content>
</invoke>
