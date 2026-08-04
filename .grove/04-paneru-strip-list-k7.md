# paneru-strip-list-k7

**Kind:** impl

## Goal

Build the **Strip listing**: the active virtual workspace's windows as overlay
rows with escalating jump labels, each focusing its window. The largest leaf in
the workstream.

## Context

Build to `docs/specs/paneru-window-management.md`, which settles the
reuse-or-new call on `blocks/window-list`. **Read ADR-0024 before starting** —
it is the reason this does not use paneru's own `window focus <n>`.

The pipeline, all four stages agreed:

```
paneru query state --json      (through current-shell-runner, ADR-0023)
  └─ parse   → rows of the ACTIVE virtual workspace, in array order
               (window_id, app_name, title, focused, floating)
  └─ join    → on windowId against Modaliser's window enumeration,
               recovering the ownerPid that focus-window requires
  └─ label   → jump-labels-assign, alphabet supplied by the USER's config
               (ADR-0021 — the library cannot author it)
  └─ render  → overlay rows. NO chips.
```

Parse and join are **pure functions**, tested by direct call. That is the whole
reason the seam count is one; do not introduce a second seam for them.

Two cases the design must not lose: a **stacked** column contributes several
rows, each independently focusable — the case `window focus <n>` cannot express
at all. A row paneru reports but Modaliser's enumeration does not is **not
focusable** and degrades to a label that does nothing (ADR-0024 Consequences);
it must not raise.

## Done when

- Rows render for the active workspace only, in paneru's strip order.
- A jump label focuses the right window, verified against a canned payload
  joined to canned enumeration data.
- Parse tests cover: multiple workspaces with one active; an empty workspace; a
  `floating` window; a row with no matching enumeration entry; malformed JSON
  degrading rather than raising.
- Both check scripts pass; `swift test` green and still fully offline.

## Notes

If the design leaf left the reuse question open, resolve it here with a spike
and record the outcome back into the spec — do not let the spec and the code
disagree.

The live daemon on this machine is available for reading (`query state --json`
is read-only). Do **not** run `send-cmd` — it moves the user's real windows. Use
a captured payload as the test fixture; one was already read during `plan-k1`
and its shape is recorded in that leaf.
