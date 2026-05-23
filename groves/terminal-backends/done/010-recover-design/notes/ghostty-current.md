# Ghostty (current) — investigation notes

**Version probed:** `Ghostty 1.3.1` (same brew cask as 060;
reinstalled from a clean state).
**Classification — corrected from 060:** **splitting backend**
(via AppleScript API). 060's "detection-only" verdict was wrong
— I missed the AppleScript depth.

## Major correction to 060

User's recall ("workarounds gated on 1.4+") was off by a version
number: AppleScript support was **introduced in Ghostty 1.3.0**
per the official docs at
`https://ghostty.org/docs/features/applescript`. Brew's 1.3.1
already has it. My 060 audit probed AppleScript shallowly
(`tell application "Ghostty" to id` and `count of windows`) and
concluded "no AppleScript scriptability for panes." That was a
**process failure**: I should have run `sdef /Applications/
Ghostty.app | less` to see the full scripting dictionary up
front.

**Lesson for the abstraction design:** every Mac app the abstraction
might support should be `sdef`-checked early. The dictionary IS
the API surface.

## AppleScript object model

```
application → windows → tabs → terminals
```

A "terminal" in Ghostty AppleScript = a pane / split. Properties:
- `id` (stable UUID, opaque string)
- `name` (window/tab title — typically the cwd or a user-set OSC
  escape value)
- `working directory` (full path string)

The `application` has shortcuts: `front window`, `frontmost`.
`tab` has `focused terminal`. So the typical query for "the
focused pane" is:

```applescript
focused terminal of selected tab of front window
```

## Op surface — 12/13, full ones via AppleScript

### Operations

| Locked op            | AppleScript                                                          | Verified |
|----------------------|----------------------------------------------------------------------|----------|
| `focus-pane-h`       | `perform action "goto_split:left" on <focused>`                       | ✓ (boolean return; `false` if no neighbour) |
| `focus-pane-j`       | `perform action "goto_split:down" on <focused>`                       | ✓ (analogous) |
| `focus-pane-k`       | `perform action "goto_split:up" on <focused>`                         | ✓ |
| `focus-pane-l`       | `perform action "goto_split:right" on <focused>`                      | ✓ |
| `split-pane-h`       | `split <focused> direction left`                                      | ✓ |
| `split-pane-j`       | `split <focused> direction down`                                      | ✓ (verified `direction down` works) |
| `split-pane-k`       | `split <focused> direction up`                                        | ✓ (analogous) |
| `split-pane-l`       | `split <focused> direction right`                                     | ✓ |
| **`move-pane-{h,j,k,l}`** | **No native action.** Ghostty 1.3.1 lacks any `move_split` keybind action; `perform action` cannot invoke what doesn't exist. Same gap as WezTerm. | gap |
| `focus-pane-by-digit`| `focus <terminal-ref>` after enumerating `terminals of selected tab of front window` | ✓ |

**Move-pane is the only gap.** That makes Ghostty parallel to
WezTerm (12/13). If/when Ghostty adds `move_split` to its keybind
action vocabulary, the recipe (`perform action "move_split:<dir>"`)
slots in without any abstraction change — `perform action` is
the future-proofing path.

### Detection

| What                | AppleScript |
|---------------------|-------------|
| focused-pane object | `focused terminal of selected tab of front window` |
| focused-pane cwd    | `working directory of <focused>` |
| focused-pane title  | `name of <focused>` |
| focused-pane **foreground command** | **NOT directly exposed.** Workarounds: (a) shell sets title via OSC, AppleScript reads it via `name`; (b) Modaliser's existing `focused-nvim-socket` (terminal.sld) bypasses Ghostty entirely for nvim case; (c) walk Ghostty child process tree + correlate. |

### Other useful AppleScript commands

- `new window`, `new tab`, `split` — creation
- `focus`, `activate window`, `select tab` — focus/selection
- `close` (terminal), `close tab`, `close window` — lifecycle
- `input text "<text>" to <terminal>` — paste-style input
- `send key "<key>" with modifiers "<mods>" to <terminal>` —
  programmatic keystroke event. `mods` is comma-separated
  `shift, control, option, command`. The exact escape-hatch for
  any action Ghostty doesn't expose natively (e.g. eventual
  move_split keybind).
- `perform action "<action-string>" on <terminal>` — runs any
  Ghostty keybind action against a specific terminal. Returns
  boolean: `True when the action was performed`.

### `perform action` boolean return as adjacency probe

`perform action "goto_split:left"` returns `false` when there's
no left neighbour (verified). This is a no-cost adjacency query
without enumerating geometry. Useful when the abstraction wants
to know "can I move further in this direction" before issuing
the action.

## Chip rendering — same gap as kitty

AppleScript does **not** expose per-terminal geometry. The
`terminal` class properties are `id`, `name`, `working directory`
— no position, no size, no cell offset.

For chip rendering as `hints-show` overlays:

1. Ghostty.app window AX frame — macOS AX (Modaliser production
   has TCC).
2. Per-terminal cell offset and size — **not exposed** by
   AppleScript or any CLI. Workarounds:
   - **AX subview discovery on Ghostty.app** — if Ghostty exposes
     per-pane NSView subviews via AX (parallel to iTerm), we read
     frames directly. Untested in this probe (Bash shell lacks
     TCC). Most likely path; needs verification.
   - **Topology reconstruction from `perform action` adjacency
     probes** — for each terminal, probe `goto_split:<dir>` for
     each of 4 directions to learn topology, BFS from a corner
     to build a grid, derive cell offsets from cell dims.
     Heavyweight; many calls. Bad fallback.
3. Cell-pixel dimensions — derive from font config + measurement,
   same as iTerm/kitty.

## Timing caveat (production-relevant)

`working directory` of a freshly-split terminal returns empty
until the underlying shell starts and emits its first prompt.
A `split` + immediate `working directory` query sequence reads
`""`. After 1 second the cwd populates. Production code must
retry-on-empty or wait. (My probe verified this — first read after
split returned empty for all freshly-created terminals; second
read after `sleep 1` returned populated cwds for all.)

## Probe environment

```applescript
osascript <<'EOF'
tell application "Ghostty"
  activate
  set t to focused terminal of selected tab of front window
  set t2 to split t direction right
  -- ... etc
end tell
EOF
```

Ghostty.app is AppleScript-driven directly; no detached / mux-
server mode needed. The GUI does briefly show on `activate`, but
once the AppleScript drives subsequent ops, no further focus
disruption.

## Anomalies / surprises

1. **Phantom terminals from prior sessions.** After 3 `split`
   commands the terminal count was **7**, not 3. Ghostty appears
   to restore terminals from prior session state (or another tab)
   that my queries also enumerate. Production code must filter to
   the current tab/window of interest, not "all terminals of the
   application."
2. **Boolean return from `perform action`** doesn't distinguish
   "invalid action name" from "no-op because preconditions
   failed." Both return `false`. Validation must come from
   matching action strings against known Ghostty actions
   (`ghostty +list-keybinds`).
3. **`name` field can be the cwd OR an emoji OR a program name** —
   depends on what's set the title last. For default Ghostty it
   defaults to `cwd`; right after `split` and before shell
   initialisation it was `👻`.

## Surprises / departures from 060

1. **060 said "no AppleScript scriptability for panes." WRONG.**
   AppleScript is the rich pane-control surface. Skipped because
   I only probed two trivial AppleScript queries instead of
   reading the SDEF.
2. **060 said "Ghostty 1.3.1 has ~4-6/13 ops." Actually 12/13** —
   only move-pane is missing. Splits in all 4 directions are
   native (no compose-then-move dance like iTerm/kitty).
3. **060's recommendation of "treat as detection-only" is wrong.**
   With AppleScript, Ghostty is a full splitting backend
   (modulo move-pane gap shared with WezTerm).

## Open verification items

- AX subview discovery for Ghostty.app (chip rect derivation).
  Critical unknown for the chip-rendering story. Production has
  TCC; probe via Modaliser code.
- Whether `terminal.name` reliably reflects the foreground command
  with default shell config, or requires explicit OSC-setting in
  user's rc files.
- Multi-window/multi-tab disambiguation — current probes restrict
  to "selected tab of front window"; abstraction needs to handle
  multi-window Ghostty installations cleanly.

## Capability matrix row

| Backend       | Type           | Detection                                       | 13-op surface | Mechanism                              | Chip render |
|---------------|----------------|-------------------------------------------------|---------------|----------------------------------------|-------------|
| Ghostty 1.3.1 | host w/ splits | ✓ AppleScript `focused terminal of selected tab of front window` (+ cwd / name properties; foreground command via title-OSC or external) | 12/13 (no move-pane) — same gap as WezTerm | AppleScript: `split direction <dir>`, `focus <ref>`, `perform action "<keybind>" on <ref>` | `hints-show` with rects from window AX + AX-subview-discovery (untested) OR adjacency-probed topology |

## Verdict for 080

Ghostty 1.3.1 (brew cask current) ships **alongside WezTerm in the
"splitting backend with 12-op surface" tier**, not detection-only.
The move-pane gap is shared. The abstraction's surface-split
decision (full-13 vs 12-without-move-pane vs detection-only)
applies to both equivalently.

Update root BRIEF capability matrix accordingly.
