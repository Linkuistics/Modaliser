# herdr-jump-navigation

## Problem

Reaching a herdr target — a pane, tab, space (workspace), or agent — always
costs a drill-down: leader → drill key → digit or cycling. The five drills
consume the top level's lowercase plane for *classification* rather than
*navigation*, and their live lists largely duplicate what herdr's own sidebar
and tab bar already show on screen. Separately, the herdr-in-iTerm surface is
delivered by merged variant trees whose combinations multiply (see the
*nested-context-entry-points* decision, ADR-0013).

## Solution

The herdr entry node's top level becomes a **jump surface**: chips label every
visible target — full-size chips on the current tab's panes, **mini-chips** at
the end of each sidebar Spaces/Agents entry and just above each tab title —
and typing a target's lowercase **jump label** focuses it directly. Named
operations and the five drills move to capitals. Contexts nest: `.` steps from
the outer iTerm node into the herdr node; backspace steps outward; leader
activation lands at the innermost detected context's entry point.

## Decisions

- **Plane rule** (herdr top level): lowercase letters belong to the jump
  space, plus `b` Jump-to-Blocked (itself a jump). Capitals carry the named
  surface: `P` Panes, `T` Tabs, `S` Spaces, `W` Worktrees, `A` Agents,
  `Q` Quit. Digits remain list-row selectors inside drills and stay out of
  the jump space.
- **Jump space scope**: one flat, simultaneous space over every *visibly
  drawn* target across four axes — current tab's panes, focused workspace's
  tab bar, sidebar Spaces entries, sidebar Agents entries. Worktrees are
  excluded (no screen presence). Scrolled-away entries get no label; the
  drills cover them. Two visible targets that name the same destination (an
  agent whose pane is in the current tab) each keep their own label rather
  than collapsing to one — a redundant path to the same place is better UX
  than a target silently vanishing from the space, and it keeps the target
  set (and so label assignment) stable regardless of what else is focused
  (include-focused-targets-for-stability-k39).
- **Jump labels**: prefix-free one- or two-key lowercase sequences, assigned
  deterministically **per axis from reserved letter pools** (revised by the
  jump-space-legend-overlay-k40 grilling; the original global panes-first
  priority let the volatile current-tab pane count shift every space/agent
  label on a mere tab switch): panes own `a s d f g` (left home row — the
  most-jumped targets on the strongest reach), spaces own `q w e r t` (the
  row above), and agents-then-tabs share the remainder
  (`h i j k l m n o p u v x y z`), agents first so agent churn only ever
  shifts tab labels. One `jump-labels-assign` call per axis: the pool is
  that axis's single-key AND leader alphabet (overflow escalates to two-key
  labels led by the axis's own letters, never borrowing another pool's);
  the second-key alphabet is the full jump alphabet, shared — cross-axis
  prefix-freedom needs only disjoint first chars, so per-axis assignments
  compose. Stability contract: an axis's labels are a pure function of its
  own visible list. Visual order within an axis; still no cross-invocation
  persistence (same list ⇒ same labels). The utility itself is unchanged —
  a general parameterised function (portable tree): restrictable single-key
  alphabet, valid-leader set, valid-second-key set.
- **Narrowing (vimium-style)**: after the first key of a two-key label, all
  chips remain visible — non-matching chips dim; surviving chips dim their
  consumed first char. Backspace returns to the un-narrowed state; Escape
  exits and clears chips. A jump firing is Terminal: focus moves, the modal
  exits.
- **Chip timing** (jump-chip-paint-bypasses-overlay-delay-k46): chips —
  full-size and mini, un-narrowed and narrowed — paint the instant the
  machine comes to rest, riding the FSM state's unconditional entry/exit
  slots (authored as `'entry`/`'exit` on the herdr screen and the
  narrowing prefix states), never the overlay's show delay. Chips are the
  primary fast-jump aid: a muscle-memory press sees them; only the
  overlay's own HTML (breadcrumbs, panels, the Jump legend) keeps the
  delayed no-flash behaviour, and every other tree's `'on-enter`/
  `'on-leave` hooks stay presentation-gated as before.
- **Legend** (jump-space-legend-overlay-k40): the herdr top-level screen
  carries a "Jump" legend panel — one row per assigned target, all four
  kinds, listed in stable-axis order (spaces → agents → tabs → panes):
  jump label in the key slot, a kind badge, target name as title (a
  trailing dimmed detail column was tried first but squeezed to a single
  truncated character competing with the title for a narrow panel's
  width; a badge ahead of the title has no such competition). Rows read
  the Visit's snapshotted assignment (never re-assign),
  so the legend can never disagree with the chips; display names are
  joined at render time inside the block (`workspace list` / `tab list`;
  pane and agent names from the `pane list` parse), a missing name
  degrading to the raw id. Fast jumps pay nothing — the panel only
  renders when the overlay's show-delay elapses. During narrowing the
  prefix state renders its own filtered legend: survivors only, name +
  remaining second key. Without `ui.layout` the legend shows only the
  panes axis — the other axes' *targets* (not just their chips) degrade
  away, so a legend cannot restore them.
- **Mini-chips**: the compact chip variant, letter labels only, painted by
  the same native-overlay machinery as pane/window chips. Placement: end of
  the entry's row (sidebar), just above the title (tabs). The native hint
  renderer gains per-char styling (consumed vs pending) and a dimmed chip
  state.
- **Geometry**: drawn entry rects come from the forked herdr's `ui.layout`
  socket method (ADR-0016; wire contract: `docs/specs/herdr-ui-layout.md`),
  scaled cells→pixels by the existing pane-chip pipeline against the
  **grid frame** — the pixel rect the canvas actually maps onto, measured
  from the terminal's real glyph grid (top-left character cell bounds via
  the AX text interface: grid origin + true cell size). The raw
  AXScrollArea frame is NOT that rect — it also spans the terminal's
  margins and sub-cell slack, and scaling against it drifts chips
  proportionally to the coordinate. Degradation: no `ui.layout` → no
  mini-chips; an unmeasurable grid falls back to the raw scroll-area
  frame (bounded drift, never an error); jump keys, capitals, and drills
  all still work.
- **Spaces rename**: labels only — drill title, panel headers, docs say
  "Spaces" (matching herdr's UI); code identifiers keep the `workspace` stem
  mirroring herdr's API vocabulary.
- **Context nesting**: the standardised step-in key is `.`, gated on
  detection of a running inner context; backspace from the inner entry node
  steps to the outer node (ADR-0013). The FSM refactor (explicit graph,
  entry points, entry/exit actions) underpins this; its design is
  `docs/specs/fsm-graph.md` (decision record: ADR-0015).

## Test seams

1. **Jump-label utility** — a pure function: ordered targets + constraint
   sets in, prefix-free labels out. Unit-tested through its API alone; the
   assignment logic's exhaustive coverage lives here.
2. **Geometry contract** — one function per kind returning `(id . cell-rect)`
   for drawn entries, fed canned `ui.layout` JSON in tests (the existing
   herdr-list extractor-test pattern).
3. **FSM core** — the existing seam: Scheme libraries evaluated in a real
   LispKit context; the current state-machine suite stays green as the
   refactor's regression gate.
4. **End-to-end visuals** — chip placement and narrowing verified in
   TestAnyware VMs, never against the live session.
5. **Legend rows extractor** — a pure function: the snapshotted assignment
   plus canned name JSON in, legend rows out (the `herdr-list-extract`
   pattern); the legend block is tested through it without a live herdr.
6. **Paint-pipeline geometry** — the chip paint pipeline's one live-AX
   dependency (the calibrated grid host-frame) is a parameter,
   `current-herdr-host-frame` in `blocks/herdr-list`; a test whose dispatch
   path can reach a paint hook (e.g. narrowing's `'entry`) parameterises it
   — alongside `current-herdr-list-runner` for the pipeline's own
   `pane layout`/`ui layout` queries — so no AX scan and no live herdr
   query ever run from a test. Painting itself is still verified only via
   seam 4.

## Out of scope

- **iTerm's own splits in the jump space** — reachable via the iTerm node's
  splits drill; fold in later if daily use wants it.
- **Worktrees in the jump space** — no screen presence; drill-only.
- **Cross-invocation label persistence** (a workspace "owning" a letter
  forever) — deterministic assignment from visual order is the contract.
- **Multi-list cursor/Tab cycling** in the overlay — unchanged from the
  existing overlay contract.
