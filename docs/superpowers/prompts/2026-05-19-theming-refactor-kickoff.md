# Theming Refactor — Fresh-Session Kickoff

> **For agentic workers:** This is a *kickoff* prompt for a fresh
> Claude Code session. A previous session designed the plan; this
> session executes it. Read the plan first.

**Plan:** [`docs/superpowers/plans/2026-05-19-theming-refactor.md`](../plans/2026-05-19-theming-refactor.md)

Read it before doing anything else. The plan covers: the goal (CSS is
the chip-theming authoring surface, authored in a real `.css` file at
`~/.config/modaliser/overlay.css` — NOT through a Scheme function),
the design (a transient hidden probe WebView resolves the rules via
`getComputedStyle` and posts the resolved values back to Scheme for
caching), the current chip-painter shape (native NSPanel, unchanged),
the build sequence in seven steps, and stopping points.

---

## Scope of this session

- The chip-styling refactor only — `.chip` / `.chip.faded` CSS rules
  in `base.css`, auto-load of `~/.config/modaliser/overlay.css`,
  **deletion of `set-overlay-css!`**, the probe WebView, the new
  `(modaliser theming)` library, migration of `(modaliser blocks
  window-list)` and `(modaliser apps iterm)`, seed config update,
  doc updates.
- Do NOT extend the refactor to the chooser, overlay header, or
  per-block layout vars (font-size, padding outside chips). That's a
  separate slice if it ever lands.
- Do NOT move chip *rendering* into the WebView. Chips stay as
  native NSPanels; only the *style resolution* goes through a
  WebView (the probe).
- Do NOT generalise the probe into a "shared theme resolver"
  abstraction. It's chip-specific in this slice.
- Do NOT keep `set-overlay-css!` as an escape hatch. Authoring CSS
  via a Scheme string is exactly the surface this refactor removes.
- Do NOT add an in-process refresh API. Relaunch is the refresh path.
- Do NOT add a backwards-compat shim for `'chip-options` /
  `'hint-options`. Clean break + migration error.
- Do NOT support multi-file CSS auto-load. One canonical path;
  CSS `@import` inside that file is the multi-file story.

---

## Workflow

1. **Open a worktree** (use `superpowers:using-git-worktrees`). Branch
   name: `theming-refactor`.
2. **Read the plan in full.** The "Target surface" section is
   load-bearing — the probe HTML structure, the resolved-theme alist
   shape, the file convention, and the migration-error contract are
   all specified there.
3. **Step 1 — `.chip` defaults in `base.css`.** New `.chip { … }`
   rule using `var(--color-host-fg, white)` for `color` and
   `var(--color-host-bg, dodgerblue)` for `background` so chips
   inherit from `set-host-header!`. New `.chip.faded { background:
   #6f8baa; }`. New `:root` declarations for
   `--chip-offset-{x,y}-frac`. No Scheme changes yet. Stop, confirm
   rule shape (and the var inheritance trick) with user.
4. **Step 2 — plumb `overlay.css` + delete `set-overlay-css!`.** Add
   `user-overlay-css-path` in `root.scm`; slurp into
   `overlay-custom-css` after the user-config include. Delete
   `set-overlay-css!` from `ui/overlay.scm`. Test: temporary
   `overlay.css` with `body { background: red; }`, relaunch,
   confirm. `swift test`.
5. **Step 3 — build the probe.** New library `(modaliser theming)`
   exporting only `current-chip-theme`. Use `webview-create` for a
   1×1 offscreen transparent panel; HTML is `<style>{full CSS
   stack}</style>` + two probe divs + an inline `<script>` that
   reads `getComputedStyle` and posts the resolved values via
   `window.webkit.messageHandlers.modaliser.postMessage(…)`.
   `webview-on-message` handler parses, caches, closes the panel.
   Boot-time probe runs once from `root.scm` after step 2's
   `overlay.css` slurp. Stop, `swift test`, REPL-inspect the cache.
6. **Step 4 — migrate blocks.** Strip `default-chip-options`,
   `merge-chip-options` from `window-list.sld`; strip equivalents
   from `apps/iterm.sld`. Replace `'chip-options` / `'hint-options`
   keywords with a migration error pointing at the `.chip` CSS rule
   in `overlay.css`. Add `'chips? #t` toggle to
   `make-window-list-block`. Per-chip alists are built from
   `(current-chip-theme 'normal)` / `(current-chip-theme 'faded)`.
   `swift test`, run the app, visually verify chips.
7. **Step 5 — update the seed.** With `.chip` referencing
   `var(--color-host-bg)`, the existing `(set-host-header!
   'background the-color)` already threads chip colour through.
   Just *delete* the `'chip-options` and `'hint-options`
   keyword/value pairs from the two callsites in
   `~/.config/modaliser/config.scm`. Mirror to
   `Sources/Modaliser/Scheme/default-config.scm` per
   `feedback_config_sync.md`. The seed gets simpler, not larger.
8. **Step 6 — update docs.** Major rewrite of `reference/theming.md`
   ("edit `overlay.css`" is the canonical customisation). Drop
   `set-overlay-css!` everywhere in `reference/dsl.md`. Drop
   chip-options tables from `reference/libraries.md`, add
   `(modaliser theming)` section. One-line theming pointer in
   `quickstart/index.md`'s "What's next". Specific edits in plan
   step 6.
9. **Verify**: `swift test` (490 baseline), link checker (Python
   snippet in docs-restructure transcript), grep
   `Sources/Modaliser/Scheme/` for `chip-options` / `hint-options`
   (only migration-error strings) and `set-overlay-css` (zero
   matches).
10. **Code review**: invoke `superpowers:requesting-code-review`.
    Focus areas in plan step 7.
11. **Finish**: `superpowers:finishing-a-development-branch`.

---

## Anti-traps

- **Don't keep `set-overlay-css!` as a "convenience escape hatch."**
  The whole point of this slice is moving CSS authoring out of Scheme
  strings. Delete the procedure outright. Users who really need
  programmatic CSS generation can write a build step that emits
  `overlay.css` before launch.
- **Don't keep the legacy `'chip-options` / `'hint-options` keyword
  as a "deprecated but working" path.** Strip them, raise a migration
  error pointing at the `.chip` CSS rule in `overlay.css`.
- **The probe's CSS stack MUST match the overlay's exactly.** The
  overlay concatenates `overlay-base-css` + `extra-css` (asset files)
  + `overlay-custom-css` (now sourced from `overlay.css`) +
  `host-header-css` in `ui/overlay.scm:551-555`. The probe HTML uses
  the same order. Any divergence and computed values drift from what
  a real chip would have if it lived in the overlay.
- **The probe is async; the cache may be cold on first chip paint.**
  Seed the cache with hard-coded defaults matching `base.css`'s
  `.chip` declarations so `(current-chip-theme)` before the probe
  returns always works. The first post-probe paint will then update
  to the resolved values.
- **Wire the boot-time probe after the user config has loaded AND
  `overlay.css` has been slurped.** Place it in `root.scm` after the
  `(include "~/.config/modaliser/config.scm")` line and after the new
  `overlay.css` slurp — not at library init.
- **Don't write `(set-cdr! …)` to update the theme cache alist.**
  Per memory `feedback_lispkit_no_mutable_pairs`, LispKit excludes
  it. Build a fresh alist from the probe's payload and `set!` the
  cell.
- **JS-side colour conversion.** `getComputedStyle` returns colours
  as `rgb(...)` / `rgba(...)` strings. The probe's `<script>` must
  convert to hex (`#rrggbb` or `#rrggbbaa`) before posting back —
  that's the format `HintsLibrary.swift`'s existing colour parser
  handles. Avoid changing the Swift parser.
- **JS-side numeric conversion.** `getComputedStyle` returns
  lengths as `"56px"`. Strip the `px` and parse via `parseFloat`
  before posting; the chip painter expects bare numbers.
- **Don't auto-load multiple files.** One canonical path
  (`~/.config/modaliser/overlay.css`). Multi-file users compose with
  CSS `@import` inside that file or symlink it.

---

## Pre-work context (already done, don't redo)

- The DSL overhaul (key macro, categories, λ, undecorated selector,
  auto-pack) is on main (`22365b2`).
- The docs restructure to Diátaxis layout is on main (`fe298cb`).
  `docs/reference/theming.md` documents the *current* CSS surface;
  this refactor extends it.
- `docs/configuration.md` and `docs/scheme-api.md` are deleted —
  don't look for them.
- The `--color-*` host-header surface (`set-host-header!`,
  `host-header-css`) is the precedent to mirror. Read its plumbing in
  `state-machine.sld` (the cell + thunk pattern) and `ui/overlay.scm`
  (where the CSS string is concatenated into the `<style>` block).

Nothing to re-implement. Just execute the plan against current code.

---

## Definition of done

- `base.css` declares `.chip { … }` (using `var(--color-host-bg, …)`
  and `var(--color-host-fg, …)` for inheritance from
  `set-host-header!`) and `.chip.faded { background: … }`, plus
  `:root` declarations for the two positioning-hint custom
  properties.
- `~/.config/modaliser/overlay.css` is auto-loaded by `root.scm` if
  it exists, concatenated into the overlay's CSS stack at the same
  slot the deleted `set-overlay-css!` used to fill.
- `set-overlay-css!` is **deleted** from `ui/overlay.scm`. The
  variable `overlay-custom-css` survives (still the slot for user
  CSS in the stack); only the setter goes.
- `(modaliser theming)` exists as a new library exporting only
  `current-chip-theme`.
- The probe WebView is created once at boot from `root.scm`, loads
  the same CSS stack the overlay loads, posts resolved values via
  `webview-on-message`, then closes its panel. No exported refresh
  API; relaunch is the refresh path.
- `(modaliser blocks window-list)` and `(modaliser apps iterm)` no
  longer accept `'chip-options` / `'hint-options`. Passing them raises
  a one-line migration error pointing at the `.chip` CSS rule in
  `overlay.css`.
- `make-window-list-block` accepts `'chips? #t` to enable chip
  painting; absence disables it (replaces the implicit "presence of
  `'chip-options`" toggle).
- Chip painters (`paint-and-snapshot!` in window-list, the
  `hints-show` call in iterm's `on-enter`) build their per-chip
  alists from `(current-chip-theme 'normal)` / `(current-chip-theme
  'faded)`.
- The native chip painter receives a complete per-chip alist from
  Scheme; `HintsLibrary.swift` is unchanged.
- Seed config + canonical user config no longer thread chip styling
  through any callsite: the `'chip-options` and `'hint-options`
  keyword/value pairs are deleted; the existing `set-host-header!`
  call threads the theme colour into chips via the
  `var(--color-host-bg)` reference in `base.css`.
- `docs/reference/{theming,libraries,dsl}.md` and
  `docs/quickstart/index.md` are updated.
- `swift test` is green (490 baseline).
- `grep -rE "chip-options|hint-options" Sources/Modaliser/Scheme/`
  returns only migration-error strings.
- `grep -rn "set-overlay-css" Sources/Modaliser/Scheme/` returns zero
  matches.
- All relative cross-links in the edited docs resolve.
