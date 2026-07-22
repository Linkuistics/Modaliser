# Tool path is derived from the login shell; missing tools surface contextually

## Status

accepted

## Context

GUI-launched Modaliser inherits `path_helper`'s minimal PATH, not the user's
login-shell PATH, so every mux/app backend shell-out prefixes
`modaliser-tool-path` (`(modaliser terminal)`) onto `$PATH`. That prefix was a
hardcoded three-entry constant (`/opt/homebrew/bin:/usr/local/bin:/usr/sbin`).

In 2026-07 a herdr relocation off those entries — while the binary stayed
perfectly reachable from the user's interactive shell (`~/.local/bin`) — broke
every Modaliser-side herdr op *silently* for about a day. The silence is
layered by design: backends `2>/dev/null` their shell-outs, degrade empty
output to `#f`, and guard JSON-parse failures to `#f`, because a leader press
must never raise. The result: "tool not on the path" was indistinguishable
from "no herdr session running". The same pattern is shared by every backend
(tmux, zellij, kitty, wezterm, alacritty, iTerm helpers), so the fragility
class is general, not herdr-specific.

## Decision

Two layers, attacking incidence and detectability independently:

1. **Derive, don't guess.** `modaliser-tool-path` remains a plain string
   constant (all backends bake it into their shell preambles at library
   load), but its value is *derived* at `(modaliser terminal)` load: spawn
   the user's login shell once (`/bin/zsh -lc`), capture `$PATH`, and union
   it with the previous hardcoded entries — kept as a floor — via a pure
   merge function. Any failure in the spawn degrades to the floor alone.
   Modaliser thereafter resolves tools exactly where the user's terminal
   does; a future relocation that keeps a tool on the shell PATH needs no
   Modaliser change.

2. **Detect and surface absence.** A configured backend whose tool cannot be
   resolved (`command -v` through the derived path) is detected at two
   points: once at backend configure-entry (catches a broken state at every
   relaunch, before any op fires), and lazily — memoized — when a query
   returns `#f` (distinguishes "tool gone" from "nothing running" at exactly
   the moment the ambiguity arises, and catches mid-run relocations; the
   healthy path pays nothing). Detection surfaces *contextually*: the
   overlay shows a "tool not found on the tool path" message where the
   backend's rows/lists would have rendered, plus an `os.Logger` line for
   post-hoc diagnosis. There is no global dialog or status-bar badge — a
   configured-but-deliberately-uninstalled backend on a given machine must
   not nag.

## Considered options

- **Widen the hardcoded list** (add `~/.local/bin` etc.): still guessing;
  the next nonstandard prefix (cargo, nix, a project-local bin) reopens the
  gap. Subsumed by derivation — nothing would reopen it.
- **A dynamic / re-resolvable tool path** (parameter or procedure): nothing
  currently needs runtime re-resolution, and it would force all eight
  backend preambles to become dynamic. Reopen if in-place config reload (or
  another feature needing runtime path refresh) lands.
- **Raising errors from the per-op guards:** rejected outright — a leader
  press must never raise (the guards' silence is deliberate; only the
  *interpretation* of the silence was missing).
- **Startup dialog / status-bar indicator for missing tools:** nags about
  backends deliberately absent on a machine. Reopen if contextual
  surfacing proves missable in practice.

## Consequences

- Startup pays one login-shell spawn (~50–150ms) during `(modaliser
  terminal)` load; a pathologically hanging `.zprofile` would stall launch.
  Accepted: the fallback guard covers failure, not slowness.
- The derivation glue is a thin load-time one-liner; the tested surface is
  the pure merge function plus the probe behind a `make-parameter` runner
  (the established canned-runner seam, as in `current-herdr-query-runner`).
- Blocks/drills need a render path for the "tool missing" message — backend
  health becomes visible state the overlay can consult, not just a `#f`.
