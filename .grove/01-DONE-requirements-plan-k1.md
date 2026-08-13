# plan-k1

## Goal

Establish what "top-level global music play/pause commands" means, well enough
to cut the leaves that build it.

## Context

- `Sources/Modaliser/KeystrokeEmitter.swift` — the CGEvent keystroke emitter;
  has **no** media-key path (media keys are `NSSystemDefined` subtype 8, not
  ordinary virtual keycodes).
- `Sources/Modaliser/InputLibrary.swift` → `(modaliser input)` — a native
  library *without* the `-native` quarantine suffix, already imported by the
  portable tree (`apps/dia.sld`, `apps/iterm.sld`, `muxes/herdr.sld`).
- `Sources/Modaliser/Scheme/default-config.scm:82` — the `'global` screen; `p`
  is unbound at its top level.
- `~/.config/modaliser/config.scm:213` — the user's own `'global` screen; `p`
  is unbound at its top level there too.
- ADR-0021 / `scripts/check-decision-free.sh` — the op is a **Facility** and
  must live in a library; the key `p` and the label are **Decisions** and must
  be authored in `config.scm`.

## Done when

The decisions below are settled with the human, `CONTEXT.md` carries any term
that hardened, and the tree carries the leaves that build it.

## Decisions (running log)

**Scope, stated by the human up front (not grilled).** A key `p` at the *top
level of the `'global` screen* toggles play/pause. The work lands in **both**
the project's `default-config.scm` and the user's own
`~/.config/modaliser/config.scm`, and finishes with a **minor release**
(v4.1.0 → v4.2.0) and a local install.

**Q1 — mechanism: the system media key, not AppleScript.** `p` posts the
`NSSystemDefined` subtype-8 event carrying `NX_KEYTYPE_PLAY` — what the
hardware play/pause key sends — and lets macOS route it to whoever owns Now
Playing. Chosen over `tell application "Music" to playpause` because the
AppleScript path reaches Music.app *only* (a YouTube tab in Dia and Podcasts
are both untouched), launches Music when it is not running, and pays an
osascript round-trip per press. Accepted cost: the target is implicit and
cannot be queried — macOS exposes no supported "who owns Now Playing" API
(MediaRemote is private), which is also why the hybrid fallback was rejected.

**Q2 — one primitive covering the whole media-key family; only `p` bound.**
`send-media-key` takes a symbol (`play-pause`, `next`, `previous`,
`volume-up`, `volume-down`, `mute`). The breadth is nearly free in Swift (one
lookup table) and it falls on the right side of ADR-0021: the *library* holds
the facility — what each button does is fixed by macOS — and `config.scm`
holds the decision that only `p` is bound today. Next/prev later is a config
edit, not another Swift primitive.

**Q3 — firing `p` is Terminal; the overlay closes.** The default for a key
with no `'next` edge, and consistent with every other top-level action on the
`'global` screen. `'next 'self` was considered and rejected: it would earn its
keep only once a transport cluster (next/prev/volume) sat beside it, and it
breaks the top level's one-shot convention.

**Q4 — install inside the grove, release after integration.** The grove builds
and installs from this workspace and updates `~/.config/modaliser/config.scm`
against that build, so the `data1` encoding is proven by actually pressing the
key rather than assumed. The v4.2.0 tag, cask and publish happen in the main
repo after integration: `release-build.sh` hard-requires a clean *git-tagged*
tree, which a jj workspace cannot offer, and branch integration is outside
grove's workflow either way. Recorded under **On the horizon** in the root
brief so it survives teardown.

**No ADR.** The `linkuistics:decision-records` when-to-write test needs all
three legs and the *hard to reverse* leg fails: this is one primitive behind
one key, swappable in an afternoon. The durable facts that *would* have
justified one — media keys have no virtual keycode, and the Now Playing target
is unqueryable — are now glossary entries (**Media key**, **Now Playing
target**), which is where a future session will actually meet them. A later
session should not re-litigate this into an ADR without a new leg.

**Glossary updated inline:** `CONTEXT.md` gains an *Input-emission domain*
section with **Media key** and **Now Playing target**.

## Notes

The bootstrap session cut the leaves itself rather than adding a `planning`
leaf: the path to done is two sessions long and fully visible, so a planning
session would have had nothing to discover (`driving.md`, "When not to start a
grove" applied one level down).
