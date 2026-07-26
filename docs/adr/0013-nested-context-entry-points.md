# Nested terminal contexts resolve through one exe→tree map, entered at the innermost match

Inner terminal tools (herdr, tmux, zellij, nvim) reach the modal FSM through
a single **Terminal context map** in the configuration value: one entry per
foreground executable, mapping it to its tree (plus a backend record when
the tool supports pane ops). At leader press, any **terminal-like** screen
resolves the focused pane's detection chain (host → mux → … → innermost
foreground command); the innermost mapped context's tree activates, and the
**return stack is seeded** with one frame per outer context (outermost = the
host screen). Backspace at a tree root pops the stack — one containment
boundary per press; Escape clears it. A derived, gated `.` call edge on
every terminal-like screen steps one mapped context *inward*, symmetric with
backspace. Programmatic activation at a context tree routes through the same
resolution, so it seeds the same outward frames when the chain contains that
context. Host-specific glue an inner tool needs (canvas frames for chip
geometry) is a **capability of the host's backend record**, consumed
generically through the terminal façade at use time. Full activation
algorithm and staleness doctrine: `docs/specs/configuration-value.md`.

## Why it binds

- **Contexts compose by N+M, never N×M.** A new host costs one terminal-like
  fragment; a new inner tool costs one map entry. No compound scopes
  (`bundle-id/herdr`), no per-host step-in wiring, no per-pair attachment
  lines — and an IDE's integrated terminal joins by supplying a host backend,
  with every mapped tool working there unchanged.
- **Containment is the live chain, not config-time weaving.** Which contexts
  nest is a runtime fact; deriving entry and outward steps from the chain
  means arbitrary nesting depth works without any statically authored
  cross-context edge, and the entry table plus all specificity ranking
  machinery is deleted rather than maintained.
- **Backspace keeps its global meaning: step outward.** Entry lands at the
  innermost detected context; each backspace crosses one containment
  boundary — now via seeded return frames, so it works identically from
  leader activation, the `.` step-in, and programmatic entry.
- **Backend-DIRECT ops still bind per context tree, never the
  `(modaliser terminal)` façade.** With herdr focused the façade resolves to
  herdr, so façade pane ops on the *host* tree would drive the wrong layer.
  A property of two live backends in one window, unchanged by the map.

## Considered options

1. **Merged variant trees** (replace/augment screens chosen per press by
   split-count classification). Rejected: surface duplication, per-press
   classifier queries, one registered screen per context combination.
   Reopened by: nothing — the map strictly subsumes it.
2. **Static per-host attachment** (`(herdr:attached-to (iterm:wiring))`
   weaving mux into host at config time — the interim design on the way
   here). Rejected: one composition line per host×tool pair, static compound
   scopes, and no IDE story. Reopened by: an inner tool whose integration
   genuinely cannot be expressed host-generically even with host
   capabilities.
3. **Second-leader toggling** (leader again = outer context). Rejected: it
   relates exactly two contexts and carries no hierarchy. Reopened by:
   genuinely *peer* (non-nested) contexts, where "step out" has no meaning.
4. **Dynamic outward up-edge** (target re-resolved from the chain at each
   backspace). Rejected: re-probes detection per press, and chain drift
   would land the user somewhere they never came from; the seeded stack
   already expresses "return where you came from". Reopened by: nothing.

## Consequences

- The entry table and its specificity machinery retire (ADR-0015 reworked
  accordingly); the context-suffix hook retires with them — nvim/zellij
  variants are map entries.
- Inner-tool **facilities** (herdr's jump provider, chip entry/exit hooks,
  legend block, prefix-keystroke ops) live in the tool's own library — the
  point being that no *host* authors them. Where they are *bound* is a
  decision, so the tree naming them lives in user config (ADR-0021): the
  library ships the context-map entry, the backend record, and the
  machinery-named side trees; the user's config ships the screen.
- The chip-geometry limitation formerly framed as augment-mode's (host frame
  resolution in multi-split tabs) is a host-capability concern of the
  pane-chip pipeline, not a tree-model concern.
