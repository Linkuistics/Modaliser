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

herdr itself has since left this ADR's scope entirely: it is driven over its
Unix socket, not its CLI (ADR-0020), so there is no binary to resolve, its
backend record carries no `tool-name`, and its query result distinguishes
"unreachable" from "nothing to list" on its own. The incident above remains
this ADR's motivating case, but the backends it governs are now the
CLI-native ones.

## Decision

Two layers, attacking incidence and detectability independently:

1. **Derive, don't guess.** `modaliser-tool-path` remains a plain string
   constant, but its value is *derived* at `(modaliser terminal)` load: spawn
   the user's login shell once (`/bin/zsh -lc`), capture `$PATH`, and union
   it with the previous hardcoded entries — kept as a floor — via a pure
   merge function. Any failure in the spawn degrades to the floor alone.
   Modaliser thereafter resolves tools exactly where the user's terminal
   does; a future relocation that keeps a tool on the shell PATH needs no
   Modaliser change.

   That spawn — like every shell-out this ADR governs, including Layer 2's
   `command -v` probes — now goes through the `(modaliser shell)` seam
   (ADR-0023), which is inert until `root.scm` installs a runner. Hence the
   ordering constraint recorded there: the install must precede the import of
   `(modaliser terminal)`, or the derivation silently yields the floor.

   The **preamble** built from it is a second constant, `tool-path-prefix`,
   exported from the same library and imported by every CLI-driven module
   rather than rebuilt in each. It is built once because the value must be
   **single-quoted**, and that is not obvious: the derived path comes from
   the user's login shell, so a segment of it may contain a space (VSCode's
   Copilot extension puts `~/Library/Application Support/…` on PATH). The
   unquoted form word-splits, and `export` is a POSIX *special* builtin whose
   error **aborts the whole command line** — so nothing after the `;` runs,
   the caller reads the empty result as "the tool told us nothing", and every
   op in every CLI-driven module silently no-ops while looking exactly like a
   missing binary. That is the Layer 2 ambiguity this ADR exists to close,
   arriving from Layer 1's own construction; ten modules each carried the
   unquoted form for a year before a machine with a space in its PATH found
   it.

2. **Detect and surface absence.** A configured backend whose tool cannot be
   resolved (`command -v` through the derived path) is detected at two
   points: once at backend install (catches a broken state at every
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
  currently needs runtime re-resolution. It would now be one change rather
  than one per module, since the preamble is shared — but the argument
  against it is unchanged. Reopen if in-place config reload (or another
  feature needing runtime path refresh) lands.
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
- The **shape of the preamble is now a tested surface too**, and its test
  carries a negative control: it runs both the quoted and the unquoted form
  in a real shell and asserts the first reaches its command *and that the
  second still does not*. Without the second half the test would pass on any
  machine whose PATH holds no space — which is to say it would prove
  nothing, and that is exactly how the unquoted form survived to be found by
  hand.
- Blocks/drills need a render path for the "tool missing" message — backend
  health becomes visible state the overlay can consult, not just a `#f`.
  `backend-tool-missing?` is that consultable state; since herdr left Layer 2
  it has no current consumer, because the CLI-native backends drive no live
  list of their own. It stays as the surfacing point for the first one that
  does, and Layer 2's `log-line` on a missing tool is unaffected.
