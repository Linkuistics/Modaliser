# Modaliser.top-level-global-music-play-pause-commands — brief

## Goal

Give Modaliser a **Media key** emitter, and bind `p` at the top level of the
`'global` screen to play/pause — reaching whatever currently owns the **Now
Playing target**, not one named music app.

## Done when

- `(modaliser input)` exports a `send-media-key` taking one of `play-pause`,
  `next`, `previous`, `volume-up`, `volume-down`, `mute`, and emitting the
  `NSSystemDefined` subtype-8 event for it.
- The shipped `default-config.scm` binds `p` "Play/Pause" at the `'global`
  screen's top level, as a Terminal key.
- `swift test`, `check-portable-surface.sh` and `check-decision-free.sh` are
  all green; `docs/reference/` documents the new primitive.
- A build installed from this workspace demonstrably toggles playback when the
  human presses the key, and `~/.config/modaliser/config.scm` carries the same
  binding.

## Decomposition

Two leaves, dependency-ordered. The split is by *verification surface*, not by
code location: the first is provable by the offline suite, the second only by a
human hearing music stop.

1. `media-key` — the primitive, the shipped binding, tests, docs.
2. `local-install` — release build → `/Applications`, live-verify the
   encoding, then the user's own config.

## Pointers

- Glossary terms in play: **Media key**, **Now Playing target** (new, this
  session), **Facility** / **Decision**, **Seeded config**, **Terminal**,
  **Screen** — see `CONTEXT.md`.
- ADR-0021 (decision-free libraries) is the binding constraint: the emitter is
  a **Facility** and lives in a library; the key `p` and the label
  "Play/Pause" are **Decisions** and are authored in `config.scm` only.
- ADR-0023 does *not* apply. `(modaliser input)` carries no `-native` suffix
  and is already imported by `apps/dia.sld`, `apps/iterm.sld` and
  `muxes/herdr.sld`: posting to the window server stays in-process, so it is
  not quarantined outward-reaching capability.
- `Sources/Modaliser/KeystrokeEmitter.swift` is the sibling emitter and the
  file to read first — note it posts *virtual keycodes*, which is exactly what
  a media key is not.
- No ADR was raised; `01-requirements-plan-k1.md`'s running log records why.

## On the horizon

**The v4.2.0 release, deliberately outside this tree.** `release-build.sh`
requires a clean *git-tagged* tree and reads the version from `git describe`,
which this jj workspace cannot satisfy, and integrating the branch is not
grove workflow. After integration, in `/Users/antony/Development/Modaliser`:
tag `v4.2.0` (from v4.1.0), then `release-build.sh` → inspect `dist/` →
`release-publish.sh`. Recorded here because the human asked for it as part of
this job and teardown deletes `.grove/`.

## Notes

The five unbound media buttons are deliberate: the library ships the whole
family because the marginal Swift cost is a lookup table, and binding only `p`
keeps every key choice in user space where ADR-0021 puts it.
