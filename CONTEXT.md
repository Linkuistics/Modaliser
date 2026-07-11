# CONTEXT — Modaliser glossary

The Ubiquitous Language for this repo. Append terms inline as they
harden. Glossary only — no implementation detail.

## Terminal-pane domain

**Pane / split** — interchangeable. The unit of focus inside a terminal
or multiplexer. Each backend has its own native term (iTerm "session",
tmux/zellij/WezTerm "pane", Kitty "window"); externally we say "pane."

**Focused pane** — the pane currently receiving keystrokes. Determined
in principle by the foreground process group of its controlling tty.

**Host terminal** — the OS-level terminal emulator (iTerm2, WezTerm,
Kitty, Ghostty, Alacritty). What macOS reports as the frontmost app.

**Multiplexer (mux)** — a process running *inside* a host terminal that
provides its own panes (tmux, zellij).

**Backend** — an implementation of the terminal-backends abstraction
for one host terminal or one multiplexer.

**Splitting backend** — a backend that exposes the directional
focus/split/move ops + digit-jump (and optionally `toggle-pane-zoom`).
Implies the terminal/mux supports native splits. See the
capability-predicates section of
`docs/how-to/terminal-pane-aware-tree.md` for the op surface.

**Detection-only backend** — a backend that exposes the detection
primitive (process running in the focused/only pane) but not the
splitting op surface. Used for host terminals without native splits;
users add a mux inside for splits.

**Focused-terminal path** — alist keyed by backend symbol with
`#(pane <id> fg <cmd>)` vector values, representing the chain from
the host terminal down through any mux to the innermost foreground
command. Each backend symbol appears at most once. See
`docs/reference/terminal-detection.md`.

**Chip** — the digit-label overlay painted on each pane by
`focus-pane-by-digit`. **Always a native macOS overlay window**
drawn by `(modaliser hints)` `hints-show`, never injected text or
escape sequences into the terminal stream. The per-backend job is
producing the `(label, screen-rect)` pairs `hints-show` consumes;
chips themselves are uniform. "Indirect and inexact" refers to
whether a backend can produce screen-accurate rects (e.g. when
cell-pixel dimensions must be derived rather than read).

**Suffix hook** — the per-app context handler installed via
`set-local-context-suffix!`; returns a string like `/nvim` that
selects a variant tree. See `docs/how-to/terminal-pane-aware-tree.md`.

**herdr** — an "agent multiplexer that lives in the terminal" (herdr.dev):
a client/server TUI run *inside* a host terminal (the user runs it in iTerm).
A **mux** backend, like tmux/zellij, but with a richer surface (workspaces,
tabs, panes, worktrees, agent status) and a JSON socket-API CLI as its control
surface (`herdr pane|tab|workspace|worktree|agent …`) rather than keystrokes.

**Workspace (herdr)** — herdr's top-level grouping, one level *above* tabs; a
set of tabs (each holding panes) for a body of work. Modaliser's own overlay
_screen_ and OS _window_ are unrelated senses — qualify as "herdr workspace"
when ambiguous.

**Worktree (herdr)** — a git worktree that herdr can create/switch/manage; herdr
ties a workspace to a worktree for agent work. Distinct from Modaliser's grove
`.grove-worktrees/` (unrelated). A worktree is **open** when a herdr workspace is
currently live on it (`herdr worktree list` reports its `open_workspace_id`),
else **dormant**; "switch to a worktree" means focus its open workspace, or open
one if dormant.

**Agent status** — herdr's per-pane state for an AI coding agent running in that
pane: `idle` / `working` / `blocked` / `unknown`. Surfaced by `herdr pane list`.
The thing "jump to a blocked agent" acts on.

**Replace tree / Augment tree** — the two herdr variant trees selected by the
suffix hook when the frontmost iTerm pane runs herdr. **Replace** (`/herdr`):
herdr is the *sole* iTerm split in the current tab, so the tree is herdr-only
(no iTerm controls). **Augment** (`/herdr+split`): the current tab has *other*
iTerm splits too, so the tree is the herdr tree *plus* an iTerm-splits drill.
Distinguished by the iTerm split count in the **current tab** — not the whole
window; a second background tab must not miscount (ADR-0013). herdr owns the
top-level `hjkl` (pane focus) in both.

## Modal-dispatch domain

**Dialog command** — a command leaf whose action needs the user's keyboard
*outside* Modaliser: it raises a native prompt/confirm/info dialog (herdr
renames, the new-worktree prompt, the worktree-remove confirm, backend error
dialogs). A dialog command must release the modal key capture before its
dialog shows and must not block Scheme evaluation while the dialog is up
(ADR-0014). _Avoid_: "trigger" — ambiguous with the key that fires an action.

## Window-switching domain

**Focused window** — the frontmost OS window: the top-level window macOS routes
keystrokes to. Resolved via `NSWorkspace.frontmostApplication` → that app's AX
`kAXFocusedWindow` (falling back to `kAXMainWindow`), the cold-AX-safe path
already used by the window-layout ops (`focusedWindowAndFrame`). The
`(modaliser window)` `focused-window` primitive surfaces its identity
(`ownerPid`, `windowId`, frame) to Scheme. _Avoid_ conflating with **Focused
pane** — a split *inside* a terminal window, a different granularity.

**Window chip** — the digit-label overlay painted over an on-screen
*window* (not a terminal pane) so the user can focus that window by
typing its digit. Same overlay machinery as the pane **Chip** above
(`hints-show` native windows); the distinction is the labelled target:
a top-level OS window vs. a pane inside a terminal. Triggered by
`(window:list-block 'chips? #t)`. Source: `window-list.sld`.
_Avoid_ bare "chip" when the window-vs-pane distinction matters.

**Display** — a physical monitor (`NSScreen` / `CGDirectDisplayID`). _Never_
called a "screen": `screen` is the overlay-DSL word for a navigable overlay
level. Source: `list-displays` (`WindowLibrary.swift`).

**Display chip** — the round, letter-labelled overlay chip painted at a
display's top-right corner; the sibling of the square, digit-labelled **Window
chip**. Plain letter = move the focused window here (preserving its fraction of
the display); Shift+letter = focus this display. Painted in the `'displays`
hint group so it coexists with window chips (the `default` group) without
clobbering — the per-paint `hints-show`/`hints-show-in` only rebuild their own
group. Source: `blocks/display-list.sld`, `display-actions.sld`.

**Same-app overlap** — the failure this grove addresses: two or more
windows of the *same* application whose on-screen frames overlap, so
their window chips land on top of each other and become unreadable /
un-aimable. Observed with iTerm and Dia; treated as generic, not
app-specific.

**Chip placement** — the two-stage pipeline that turns a window into a
`(label, screen-rect)` pair for `hints-show`: (1) a Swift geometric
stage that subtracts occluder rects from the window to find a clear
fragment (`ChipPlacement.swift`), then (2) a Scheme reactive stage that
"dodges" chips which still collide (`window-list.sld`).

**Chip cascade** — the fallback tier of chip placement: when a window
has no usable visible area for an on-window chip, its chip is placed
into a **slot lattice** anchored near the occluded window's natural
corner, filling the nearest free lattice slot. Co-located same-app
windows therefore produce a local stack of chips by their cluster. The
cascade is what keeps a fully-occluded window selectable.
_Avoid_: "cascade" for the on-window dodge — that is the first tier.

**Slot lattice** — a screen-covering tiling of chip-sized cells
(step = chip side + padding) used to assign non-overlapping fallback
positions. Finite cells + the ≤10-chip cap (`default-window-labels`)
make the no-overlap invariant a counting argument, not a fixpoint.

**Strong invariant** — the correctness contract this grove enforces:
(1) no two window chips ever overlap, and (2) every listed window keeps
exactly one chip (a fully-occluded window is relocated, never dropped).
Label readability and selectability win over keeping a chip at its
window's natural corner.

## Chooser domain

**Chooser** — an activating modal panel built on a `WKWebView`, containing
a single text input above a filtered result list. The user types to filter,
selects with arrows/hjkl, activates with Enter. Sources: `chooser.scm`,
`chooser.js`, `ChooserSearchEngine.swift`. The only Modaliser surface that
hosts a focused text input.

**Chooser input** — the single `<input id="chooser-input">` element
each chooser hosts. The lone keyboard-text-entry site in Modaliser; if
clipboard paste fails anywhere in Modaliser, it fails here.
_Avoid_: "search box", "filter field" — use "chooser input."

**Standard text-editing shortcuts** — the full Cocoa class of keyboard
behaviours a focused `NSTextField` / `<input>` gives a macOS user without
opt-in: Cmd-V/C/X/A, option-arrows for word movement, Cmd-arrows for
line/document jumps, Cmd-Z/Shift-Cmd-Z undo, etc. Treated as one class
because they share an event path; failing one usually means failing all.
A chooser input should support the whole class.

## Overlay-presentation domain

**Layout spec** — the presentation-first authoring surface (the new config
shape): a tree of **screens**. It is the *authored* artifact; the operational
model is *extracted* from it (ADR-0011). _Avoid_: calling it the "command tree" —
that's the derived IR below, not what the user writes.

**Operational node-tree (IR)** — the internal `(kind . group)` / `(kind .
command)` node-alist tree the state machine dispatches. Since ADR-0011 it is a
**compile target / intermediate representation**, not authored by hand: the
layout spec *lowers* to it, annotating nodes with presentation metadata
(`panel`, `span`, `screen`). The dispatch engine (`state-machine.sld`) consumes
it unchanged.

**Screen** — one navigable level of the overlay: a **loose region** above a
**grid of panels**. A top-level screen is *registered* under a scope **symbol**
(the tree-root name a leader or `enter-mode!` targets); a deeper level is
declared **inline** by an `open`, which carries its own body rather than
referencing a registered screen by name. On lowering, a screen's root becomes a
tree-root group and an `open` becomes a navigable `group`, both carrying
`'renderer 'panel-grid`. The overlay is a tree of screens, one shown at a time.
_Avoid_: implying `open` resolves a named screen — drill-down sub-screens are
anonymous and inline.

**Loose region** — everything in a screen/open body *not* wrapped in a
`(panel …)`: loose command rows, folded top-level `open`s (each a drill row),
and loose **live lists** / diagrams. Rendered **bare** (header-less, no card)
**above** the panel grid, in declaration order — visual parity with a plain
`(group …)` or the Settings overlay. _Avoid_: "General panel" — there is no
auto-collecting card; the loose rows are the screen's own inline rows.

**Panel** — a strongly-separated, banded card in a screen's grid; one declared
visual grouping. Holds command rows and/or an embedded **live list**. Remains
**transparent for dispatch** (keys keep their paths — it lowers through to a
`category`-equivalent, not a navigable level). Carries a width **span**.
_Avoid_: "category" when speaking of the authored surface — `category` is the
old operational-first primitive; the authored unit is now a `panel`.

**Span** — a panel's width hint: `narrow` (1 column, default) | `wide` (2) |
`full` (all). A panel holding a live list auto-promotes to `wide` unless an
explicit span is given. Spans are relative to the **balanced** column count
(below): `wide` = 2 of the chosen columns, `full` = all of them.

**Column balancing** — the renderer chooses the overlay body's column count by
**aspect-ratio balance**, not by maximizing what fits: a JS pass measures the
rendered content and picks the count whose grid shape is closest to a target
width:height ratio (≈ 1.4). An authored `'cols N` hard-pins instead (the only
override). The **loose region** and the **grid of panels** share one overlay
**width** but pack into *different* counts — a bare key-row is narrower than a
panel card, so loose rows columnize into more columns than the panels to fill the
same width; loose **blocks** (diagram, live list) stay full-width. _Avoid_:
"auto-fit columns" as the live behaviour — CSS auto-fit is only the no-JS
fallback now; the default is the JS balance.

**Row order** — a panel's row-ordering mode: `keys` (key-sorted, default) |
`declared` (declaration order). Authored via the `'order` keyword on `panel`,
or on `screen` / `open` as a grid-wide default; resolved **panel-explicit >
screen/open default > `keys`**. Presentation only — dispatch is key-addressed
and order-independent. The **loose region** is always `declared`. A
`sticky-set`'s **latched walk** (the registered sticky-mode tree) also takes an
`'order` keyword, opting its rows out of the default key-sort so the walk reads
in the same grouped order as its declaration-ordered entry point.

**Live list** — a dynamic-list block (`window-list`, `iterm-panes`,
`iterm-tabs`) placed inside a panel, or **loose** in a screen/open body (then it
renders bare in the **loose region**). Supports a **selection cursor** (`↑↓` /
`k j` move, `⏎` activate) alongside the immediate `1–9` digit-jump selectors.
The first live list a screen renders owns the cursor — a loose list, serialized
first, wins over a panel list (multi-list `Tab` cycling is a non-goal). Distinct
from the **Chip** overlays it can paint.

**Selection cursor** — the movable highlight over a live list's rows: `↑↓` / `k j`
move it (clamped, no wrap), `⏎` activates the highlighted row. Its activation
label *is* the row's digit, so `⏎` dispatches through the same digit-jump path the
immediate `1–9` selectors use — the cursor adds only a pointer, no separate
action. State lives in `(modaliser list-cursor)`, owned by the first live list a
screen renders; the focused row is marked `.is-focused` (accent bar + tint).
On the pass that first claims the cursor (overlay open) it **seeds** to the
currently-focused row (see **Cursor seed**), else row 0.
Distinct from a **Selector** (the chooser-opening node) and from the digit
**selectors** (immediate direct-jump keys).

**Cursor seed** — the once-per-open derivation of the **Selection cursor**'s
opening row: a list block MAY carry a `cursor-initial-index-fn` thunk returning
the **Focused** item's row index (tabs/panes/windows), consulted *only* on the
claiming pass so the focus probe runs once per overlay open, never per re-render.
A non-negative integer seeds that row; anything else (`#f`, out-of-range, no
thunk) falls back to row 0. Mechanism: `list-cursor-offer!` + `seed-index` in
`(modaliser list-cursor)`.

**Open** — the authored drill-down affordance: `(open KEY LABEL body…)`. A row
that navigates *into* a sub-screen (its own body). A **top-level** open folds
into the parent's **loose region** as a single "→ LABEL" drill row; an open
declared *inside* a panel is an accent group-row in that panel. Lowers to a
navigable `group` carrying `'renderer 'panel-grid`. The only navigable layout
form (a `panel`, by contrast, is transparent — it never changes key paths).

**Fragment** — a reusable, named chunk of layout (panels or command rows) spliced
into multiple screens/panels for DRY (e.g. a shared `window-actions` set). Built
on `expand-splices` — the same splice mechanism `sticky-set` already uses for
keys — so nothing downstream sees the fragment; the result is identical to
writing its contents inline.

## Window-layout domain

**Window-layout op** — a `w`-menu action that repositions or resizes the
*focused* OS window (thirds, halves, two-thirds, maximise, center,
fullscreen, restore) via the Accessibility API. Changes geometry, not
focus — distinct from the window-switching chips, which only change which
window is focused. Sources: `WindowManipulator.swift`, `window-actions.sld`.
_Avoid_: bare "window movement" when precision matters — it is the colloquial
name (and this grove's name) but conflates geometry with focus-switching.

**EUI flip** (AXEnhancedUserInterface flip) — the disable→write→restore dance
Modaliser performs around AX position/size writes for apps that set
`AXEnhancedUserInterface` (Electron and some others). While that flag is on,
AX geometry writes silently no-op; Modaliser flips it off, issues the writes,
then restores it. Source: `withResizableApp`.

**EUI-settle race** — _[REFUTED as this grove's failure cause — see 010
diagnosis and **Cold-AX resolution gap**.]_ The original hypothesis: on some
machines the Electron app has not finished applying the EUI-off transition
before Modaliser issues/restores the geometry writes, so they are dropped.
Investigation showed the layout-op failure occurs **upstream of any geometry
write** (resolution returns nil), is independent of the settle delay, and
afflicts apps (Dia) that never enter the EUI flip. The EUI flip itself remains
real — Chromium apps that honor `AXEnhancedUserInterface=true` do ignore
setFrame while it is on — but it is orthogonal to the window-not-moving bug.
_Avoid_: blaming the `usleep(50_000)` settle delay for layout ops not working.

**Cold-AX resolution gap** — the confirmed root cause of this grove's failure.
Chromium/Electron apps keep their accessibility engine **dormant** until an
assistive client activates it (via `AXEnhancedUserInterface`/
`AXManualAccessibility` = true, or sustained AX tree queries), and let it lapse
when idle. While dormant, `AXUIElementCreateSystemWide()` +
`kAXFocusedApplicationAttribute` returns `kAXErrorNoValue (-25212)`, so
`focusedWindowAndFrame()` resolves to `nil` and the layout op silently no-ops.
Native apps always expose an AX interface, so they never hit this — explaining
the Electron-only, intermittent, per-app symptom. Resolving the frontmost app
via `NSWorkspace.frontmostApplication` (a window-server API, a11y-independent)
+ the app element's `kAXFocusedWindow` works regardless of a11y state.
Source: `WindowManipulator.focusedWindowAndFrame`.
