# Paneru windows are targeted by window id, not by column number

## Status

accepted

## Context

Modaliser drives [paneru](https://github.com/karinushka/paneru), an external
sliding window manager, and shows a **Strip listing** — the windows on the
active virtual workspace, in strip order, each reachable by a jump label.
Pressing a label must focus that window.

Paneru offers an obvious mechanism for this and it does not work. Its only
targeting command is

    paneru send-cmd window focus <n>

where `<n>` is a **1-based column index counting from the left**. But the
`paneru query state --json` payload that sources the listing carries no column
field at all. Each window object is exactly:

    { "window_id": 321, "bundle_id": "…", "app_name": "…",
      "title": "…", "focused": true, "floating": false }

So a column number is not *derivable* from a listed window. Using one means
assuming the row's position in the `windows` array equals its column number —
which holds only while every column contains exactly one window and no window
floats. Paneru supports **stacked** columns (several windows sharing one
column, `window stack`) and unmanaged **floating** windows, and both break the
assumption. Neither is visible in the payload, so the failure is silent: the
label lands on a *different real window* than the row it was drawn beside, and
nothing reports an error. A window manager's jump surface that occasionally
focuses the wrong window is worse than not having one.

The alternative is to ignore paneru's targeting entirely and focus the window
natively. Modaliser already does this: `focus-window` (`WindowLibrary.swift`)
takes a choice-alist and focuses by `windowId`, and it is the mechanism behind
the existing window-switching chips. It requires an `ownerPid` alongside the
id — it no-ops without one — and paneru's payload reports no pid.

The question was whether the two id spaces even coincide. They do, and this was
verified empirically rather than assumed: `paneru query state --json` on a live
daemon reported window ids 29354, 23141, 20786, 23552, 10804, 27020, 239, 310,
21448, 276 and 317, and `CGWindowListCopyWindowInfo` on the same machine
returned that exact set as its `kCGWindowNumber` values. Modaliser's own ids
come from `_AXUIElementGetWindow` (`WindowEnumerator.swift:49`), which yields
the `CGWindowID`. All three are one number space.

## Decision

**The strip listing sources its rows from paneru and its focusing from
Modaliser, joined on `windowId`.**

Paneru contributes what only paneru knows — which windows are on the active
virtual workspace, and in what strip order. Modaliser contributes what only
Modaliser has — the `ownerPid` that `focus-window` needs. A row is focusable
because its `window_id` matched a window in Modaliser's own enumeration; the
join is the whole mechanism.

    paneru query state --json          Modaliser window enumeration
      window_id: 23552          ──join──►  windowId:  23552
      app_name:  Telegram        on id     ownerPid:  4471
      title:     Thomas                        │
      (strip position 4)                       ▼
                                         (focus-window alist)

`window focus <n>` is not used for targeting a listed window. It remains
available as an ordinary **Paneru op** for the cases where a *column* really is
what the user means.

The join is a **pure function** over two lists, and the payload parse is a pure
function over a string. Neither is a new test seam: both are tested by direct
call.

The two sides they join reach outward by different routes, and only one of them
is a shell call. Paneru's side goes through the existing `(modaliser shell)`
runner (ADR-0023). Modaliser's side is the window enumeration, which is an AX
sweep — so whatever gathers the two for the join takes the enumeration as an
injected argument, canned in a test rather than swept live. See
`docs/specs/paneru-window-management.md` → **Test seams**.

## Consequences

Jump labels are exact. A stacked column lists its windows as separate rows and
each label focuses its own window — the case `window focus <n>` cannot express
at all, since a column number does not name a window within a stack. Floating
windows are listed and reachable on the same terms, though they occupy no
column.

Focus flows the way paneru already expects. Paneru observes the focus change
through the accessibility notifications it is already subscribed to and scrolls
the strip to the newly focused window, so the visible result is the same as if
its own command had run.

A row that paneru reports but Modaliser's enumeration does not is **not
focusable** and is the one new failure mode. It is a genuine possibility —
Modaliser enumerates the current space, and the two sources snapshot at
slightly different instants. It degrades to a row whose label does nothing,
which is the established shape of degradation here (ADR-0017, ADR-0023): quiet,
local, and never an error reaching a leader press.

This couples the listing to Modaliser's window enumeration as well as to
paneru's query. That is a real cost — two sources must both be healthy for a
row to work, where `window focus <n>` needed only one — and it is accepted
because the single-source alternative is silently wrong rather than merely
unavailable.

Should paneru later report a column index per window, this decision is worth
revisiting only if the id join has caused actual trouble: a column index would
remove the second source but would still not name a window inside a stack.
