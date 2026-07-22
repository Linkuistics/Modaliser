# herdr-ui-layout

The wire contract of `ui.layout`, the socket-API method the forked herdr
gains (decision: ADR-0016) and Modaliser consumes as the geometry source for
mini-chips. This spec is the reference for both sides: the fork implements
it, Modaliser's geometry-contract functions are tested against canned JSON
conforming to it, and the upstream proposal derives from it.

## Problem

Mini-chips need the *drawn* cell-rect of each visible sidebar entry (Spaces,
Agents) and tab title. herdr's socket API exposes pane rects (`pane.layout`)
but no sidebar or tab-bar geometry, and the inputs that determine the drawn
layout — section split ratio, per-list scroll offsets, group collapse, the
agents sort mode, sidebar collapse mode — are server-side UI state the API
does not expose. No computation from existing API data can reproduce the
drawn layout (ADR-0016 records why replication was rejected).

## Solution

One new read-only method, `ui.layout`, a sibling of `pane.layout`: same
request envelope, same rect struct, same coordinate space, same staleness
semantics. It reports the drawn geometry of the two chrome surfaces the API
cannot currently see — the sidebar (Spaces and Agents sections) and the tab
bar — keyed by the same public ids the list methods use, computed
server-side by the same layout arithmetic the renderer and mouse
hit-testing use. Pane rects stay with `pane.layout`.

Naming trap: the socket method is `ui.layout` (dot), but the herdr **CLI
verb** is `herdr ui layout` (space) — a separate surface implemented
alongside the method, and the one Modaliser actually shells out to.
Conflating the two cost real debugging time during development, when
mini-chips silently painted zero entries.

## Decisions

### Request

`ui.layout` takes empty params (like `session.snapshot` — there is nothing
to target):

```json
{ "id": "…", "method": "ui.layout", "params": {} }
```

### Response

The result is tagged `ui_layout`. Top-level members: `layout`, `obscured`,
`canvas`, `sidebar`, `tab_bar`:

```jsonc
{
  "type": "ui_layout",
  "layout": "desktop",                        // "desktop" | "mobile"
  "obscured": false,                          // full-screen overlay active
  "canvas": { "width": 273, "height": 74 },
  "sidebar": {
    "mode": "expanded",                       // "expanded" | "compact" | "hidden"
    "rect": { "x": 0, "y": 0, "width": 36, "height": 74 },
    "workspaces": [
      { "workspace_id": "w_1",
        "focused": true,
        "rect": { "x": 0, "y": 2, "width": 35, "height": 2 } }
    ],
    "agents": [
      { "pane_id": "w_1:p7",
        "rect": { "x": 0, "y": 40, "width": 35, "height": 1 } }
    ]
  },
  "tab_bar": {
    "rect": { "x": 36, "y": 0, "width": 237, "height": 1 },
    "workspace_id": "w_1",
    "tabs": [
      { "tab_id": "w_1:t2",
        "focused": true,
        "rect": { "x": 36, "y": 0, "width": 14, "height": 1 } }
    ]
  }
}
```

Ids follow herdr's public formats: workspace `w_<n>`, pane
`<workspace_id>:p<n>`, tab `<workspace_id>:t<n>` (tab ids key on the stable
tab *number*, not the tab's current index, so they survive reordering).

### Coordinate space

All rects are **absolute whole-terminal cells** — origin `(0,0)` at the
top-left of the full client canvas, the exact space `pane.layout` pane rects
already use — and reuse `pane.layout`'s rect struct
(`{x, y, width, height}`, unsigned 16-bit cells). `canvas` is the full
terminal size in cells, reported explicitly so consumers scale cells to
pixels without inferring the canvas from other rects (Modaliser's pane-chip
pipeline currently infers it from `pane.layout`'s `area`; against a fork it
should prefer `canvas`).

### Drawn/visible entries only

An entry appears in the response iff herdr drew it in the last-composed
frame:

- Scrolled-away entries are omitted. The capital drills cover them.
- Workspaces folded inside a collapsed worktree group are omitted (not
  drawn).
- A partially-drawn entry — a tab clipped at the tab bar's right edge, a
  multi-row sidebar entry clamped at its section boundary — reports its
  **truncated drawn rect verbatim**, with no flag. The contract is "drawn
  geometry": a chip placed inside the rect lands on visible cells by
  construction, and consumers never need the natural (unclipped) size.
- Entries are listed in **visual order** — top-to-bottom for sidebar
  sections, left-to-right for tabs. Deterministic jump-label assignment
  depends on this ordering contract.

### Layout paths: desktop and mobile

`layout` names the rendering path. Below a width threshold (configurable;
default 64 columns) herdr composes a separate **mobile** layout with no
sidebar and no tab bar — navigation happens through a header menu and the
navigator overlay instead. In mobile, `sidebar` reports `mode: "hidden"`
with empty lists and `tab_bar` reports a zero rect with empty tabs; the
`layout` field is what tells a consumer this is the mobile path rather than
a genuinely empty desktop UI. Mobile header/switcher geometry is not
reported (out of scope below).

### Sidebar modes

`sidebar.mode` names the sidebar rendering path within the desktop layout;
the same entry schema applies in all three:

- **`expanded`** — the normal two-section sidebar: Spaces above Agents,
  split by the user-draggable ratio. Both sections report their visible
  entries with their (variable, multi-row) drawn heights.
- **`compact`** — the narrow collapsed strip, one row per entry. Entries
  are drawn, so they are reported: flat one-row rects for both kinds.
  Whether a consumer paints chips on a strip this narrow is consumer
  policy, not a schema gap.
- **`hidden`** — nothing drawn: `rect` has zero width and both lists are
  empty.

`sidebar.rect` is the sidebar's full drawn extent. The section divider,
sort-toggle chip, and section headers are chrome, not entries, and are not
reported.

### Tab bar absence

The tab bar is not always drawn: herdr drops it when a workspace has a
single tab and `hide_tab_bar_when_single_tab` is set, when the terminal is
too short, and in the mobile layout. When not drawn, `tab_bar.rect` is zero
and `tabs` is empty — the mirror of the hidden sidebar. `tab_bar
.workspace_id` still names the focused workspace (which always exists).

### Identity and per-entry fields

Entries carry the same public ids the list methods use — `workspace_id` for
Spaces entries, `pane_id` for Agents entries (the join key against pane
chips and `agent.list`), `tab_id` for tabs — plus `focused` on workspace
and tab entries (mirroring `pane.layout`'s per-pane `focused`; the focused
workspace, the active tab). Nothing else: no labels, no agent status, no
cross-references — those belong to the list methods. A geometry method
stays a geometry method.

Two deliberate consequences: a response may contain **zero** `focused:
true` entries (the focused workspace can be scrolled away or folded — a
consumer must not assume exactly one); and agent entries carry **no**
focused flag by design (the focused agent is derivable through its pane).

`tab_bar.workspace_id` names the workspace whose tabs the bar is showing
(the focused one). Tab-bar chrome — scroll buttons, the new-tab button — is
not reported.

### Occlusion

`obscured` is true while a full-canvas overlay — onboarding, release notes,
settings, keybinding help, the navigator — is drawn over the reported
surfaces; the rects remain those of the UI beneath. Consumers that paint
on-screen decorations should not paint while `obscured` is true. Smaller
transient dialogs (confirms) may still overlap reported rects without
setting the flag — the same accepted exposure `pane.layout` has today.
Floating popup panes never overlap the sidebar or tab bar (they float
within the terminal area only).

### Staleness and detachment

Like `pane.layout`, the response reflects the server's last-composed view
state, unconditionally — no attachment flag, no error. Two documented
consequences of how the server composes:

- **Detached**: with no foreground client, the server composes at a
  fallback 80×24 size, so detached geometry (including `canvas`) is
  synthetic, not a frozen copy of the last real terminal.
- **Multiple clients**: the reported geometry is the **foreground**
  client's (the server composes per client; the foreground client's frame
  is the one whose view state the API reads — `pane.layout` behaves the
  same way).

Consumers that only act on visible UI (Modaliser paints chips only when
herdr is frontmost in the terminal it overlays) are unaffected by either.

### Compatibility and probing

The method is purely additive: no wire-protocol version bump, no change to
any existing method. Two guarantees make probing trivial:

- On a **supporting** server, `ui.layout` never returns an error: it has no
  target to miss and no unavailable state — the view state always exists.
  (Contrast `pane.layout`, whose targeted lookups can fail.)
- On a server **without** the method, request parsing fails and the server
  answers with its catch-all structured error (code `invalid_request` — not
  a distinct method-not-found — and, as of protocol 16, an **empty** `id`
  field; raw-socket consumers must not correlate the probe reply by id.
  Consumers driving the herdr CLI are unaffected).

Together: a consumer may treat **any** error from a `ui.layout` call as
"not supported" and degrade, with no risk of misclassifying a supporting
server. For Modaliser, degradation means mini-chips simply do not paint;
jump keys, capitals, and drills are unaffected (ADR-0016).

## Test seams

1. **Fork-side (Rust)** — unit tests on the handler against constructed
   app state: sidebar modes (all three), desktop vs mobile layout, tab-bar
   absence, `obscured` under each full-screen overlay, scroll/clip
   truncation, visual ordering, id mapping, and the small-terminal edge.
   Runs under herdr's standard check (`just ci`).
2. **Modaliser-side (Scheme)** — one geometry-contract function per kind
   returning `(id . cell-rect)` for drawn entries, fed canned `ui.layout`
   JSON conforming to this spec (the existing herdr-list extractor-test
   pattern; seam already agreed in `herdr-jump-navigation.md`).

## Out of scope

- **Pane rects** — stay with `pane.layout` (ADR-0016).
- **Worktrees** — no screen presence; drill-only.
- **Chrome geometry** — section divider, sort toggle, headers, tab scroll
  buttons, new-tab button, status bar, the mobile header/menu and
  navigator overlay: none are chip targets. (Mobile navigation geometry
  would be a separate proposal if ever wanted.)
- **Occlusion reporting for transient dialogs** — only full-canvas
  overlays set `obscured`; small confirms share `pane.layout`'s accepted
  exposure.
- **Change notification** — no `ui.layout`-updated event; consumers poll at
  paint time.
- **Writing UI state** — `ui.layout` is read-only; no API for setting the
  sidebar split, scroll, or collapse.
