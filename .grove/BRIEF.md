# Modaliser.add-paneru-controls — brief

## Goal

Make Modaliser the keyboard layer for [paneru](https://github.com/karinushka/paneru),
the sliding window manager. When paneru is installed, the user's window screen is
composed from **Paneru ops** instead of Modaliser's own **Window-layout ops**, and
carries a **Strip listing** whose rows are reachable by jump label.

The user's `paneru.toml` `[bindings]` section is empty and stays that way: paneru
has no keyboard layer of its own, and this workstream is how it gets one.

## Done when

- `lib/modaliser/wms/paneru.sld` exports the seven ops (focus west/east, swap
  west/east, grow, shrink, center) and an installation predicate, each op a
  `paneru send-cmd …` through the `(modaliser shell)` seam.
- A strip-listing block renders the active virtual workspace's windows with
  escalating jump labels, focusing by the id join of ADR-0024.
- A user can compose either screen at config load; starting Modaliser before
  paneru changes nothing.
- `check-portable-surface.sh` and `check-decision-free.sh` both pass, and
  `swift test` is green and still reaches nothing outside the process.
- `docs/reference/` describes the new surface; `examples/` carries a composable
  reference config.

## Decomposition

Requirements were settled in one grilling session (`plan-k1`) — no planning leaf
was needed, and no research pair: paneru's control surface was established
empirically against the live daemon rather than surveyed.

1. **paneru-design-chain** — the spec, review-chained because it shapes all three
   impl leaves: library surface, block design, and the reuse-vs-new call on the
   existing `window-list` block.
2. **paneru-ops** — the op library and the installation predicate.
3. **provider-state-id** — the engine prerequisite the review surfaced: an
   **Edge provider** learns the id of the state it is lowered onto, and `open`
   gains `'provider`. Added during design integration, not planning; without it
   a two-key jump label cannot mint a usable narrowing prefix state, so it
   sequences ahead of the listing.
4. **paneru-strip-list** — query → parse → join → block, with label assignment.
5. **paneru-docs** — reference docs and the example config.

## Pointers

- **ADR-0024** — targeting by window id, not column number. The load-bearing
  decision; read it before touching the listing.
- **ADR-0017** — tool-path resolution and contextual absence. The reason the
  composition predicate tests *installation*, not liveness.
- **ADR-0023** — the inert-by-default `(modaliser shell)` seam. All three outward
  calls (`command -v`, `send-cmd`, `query state`) go through it; it is the single
  test seam for this work.
- **ADR-0021** — decision-free libraries. No file under `lib/modaliser` may author
  a key or a label, so the jump alphabet arrives from the user's config.
- **ADR-0018** — configuration is one explicit value, built once at load. The
  reason the paneru/non-paneru branch is a load-time composition.
- `CONTEXT.md` → **Paneru-window-management domain** for the vocabulary.
- `muxes/zellij.sld` is the closest shape precedent (ops + wiring + detection),
  but paneru sits behind **no façade** — it is not a `(modaliser terminal)`
  backend, and the analogy stops at the file's structure.

## Notes

**Decisions taken in `plan-k1`, with the reasoning that is not obvious from the
outcome:**

1. **Composition at config load, not per keypress.** ADR-0018. Dynamic
   composition would require the *dispatch structure* to vary per render, and
   blocks today vary their data, not their keys.
2. **The predicate tests installation, not liveness** — `command -v paneru`. The
   user raised the startup-order race directly: Modaliser may launch before
   paneru. Testing liveness makes the meaning of a key depend on daemon start
   order; testing installation cannot race, and a down daemon degrades to the
   established empty-output path.
3. **Focus by id join** — ADR-0024, with the empirical id-space verification.
4. **Seven ops now, widen on demand.** Deliberately *not* the whole ~20-command
   surface: the first slice stays tight, and each further op is a config-visible
   follow-up rather than speculative library surface.
5. **Escalating jump labels** via the existing `jump-labels-assign`. Digits cap
   at ten; the live workspace already holds eleven windows.
6. **Active virtual workspace only.** Cross-workspace jumping needs a workspace
   switch before the focus and its behaviour is unverified — deliberately left
   as future work rather than guessed at.
7. **One test seam** — `current-shell-runner` — with the parse and the join as
   pure functions. Driving the seam count to one was an explicit goal, not an
   accident.
8. **`wms/` is a new category**, peer to `muxes/`, `apps/`, `tools/`. Paneru is
   not a mux and sits behind no façade; flattening it into `tools/` would hide
   that it owns the desktop rather than living inside a pane.
9. **No chips.** The listing is overlay rows only.

**Decisions taken during design integration** (`paneru-design-integrate-k5`),
correcting two the spec got wrong:

10. **The provider learns its own state id; `open` gains `'provider`.** The spec
    had claimed threading the keyword was "the whole change". It is not: a
    provided *resting* prefix state's id must read `<owner-id>/<leader>`, and no
    provider can know its owner today. Chosen over a registered tree under a
    machinery scope (herdr's shape — solves it, but costs the breadcrumb and
    backspace behaviour of the surface the grilling settled), over passing a raw
    FSM id from config, and over dropping escalation. Cheap because
    `resolve-state-def` already stamps `'id` on every def and only three
    providers exist in the tree.
11. **Two test seams, not one.** Note 7's one-seam goal survives for the *shell*
    path only. The provider also reads Modaliser's own window enumeration —
    an uncached AX sweep of every running app — so it takes an injectable
    `'enumerate`. Not an isolation fix (the suite already calls the primitive
    deliberately) but a determinism one: without it the provider test asserts
    against the developer's live desktop.

**Decided in `strip-parse-cost-k10`:**

12. **`'next 'self` stays out of the reference composition, on corrected
    reasoning.** The ≈66 ms that first ruled it out was a **debug-build**
    number; the shipped release build costs ≈34 ms for the same code, and the
    JSON read — recorded as 55% of the total — is now the smallest Scheme-side
    stage at 5 ms. The read was made ~40% cheaper anyway (a cursor-passing
    scanner in `(modaliser json)`, `substring` for unescaped literals). What
    still rules `'next 'self` out is the **tail**, not the median: the AX sweep
    ranges 8–29 ms warm with cold calls past 200 ms, and `KeyboardCapture`
    filters no auto-repeat, so a *held* Focus West queues ≈48 ms of work per
    repeat and the strip keeps sliding after release. Per *deliberate*
    repetition `'next 'self` is not more expensive than re-entering the screen —
    it is strictly better — so the ruling is about the failure mode a shipped
    default must not have, not about the cost.

**Open, deliberately deferred:** cross-workspace listing and jumping; the
remaining ~13 paneru ops; whether a floating window should be marked as such in
the listing; simplifying `muxes/herdr` onto the provider's new id argument; and
now — the two things that would reopen `'next 'self` — a cached or incremental
window enumeration in place of a per-Visit AX sweep, and auto-repeat suppression
at the capture layer. Neither is a leaf: the shipped composition is correct
without them, and both are preference calls about a surface nobody has
complained about yet.
