# local-install-k3

## Goal

Prove the **Media key** encoding on real hardware, and carry the binding into
the user's own `~/.config/modaliser/config.scm`. This is the leaf where the
work stops being plausible and starts being true.

## Context

`media-key-k2` lands the primitive and the shipped binding, verified by the
offline suite alone. That suite deliberately cannot exercise the *posting*
path (see that leaf's Notes), so nothing so far has demonstrated that macOS
actually accepts the event — a wrong `data1` packing or a wrong subtype fails
**silently**: the event posts, nothing happens, no error anywhere.

`./scripts/install.sh` builds a release bundle and copies it to
`/Applications`. It works from this workspace and needs no git tag — unlike
`release-build.sh`, which is why the v4.2.0 release is deferred until after
integration (root brief, "On the horizon"). `build-app.sh` code-signs with the
"Modaliser Dev" certificate when present, which is what preserves the
Accessibility TCC grant across rebuilds; if the grant is lost the app cannot
post events at all, and that will look exactly like a bad encoding.

The user's config is at `~/.config/modaliser/config.scm`, its `'global` screen
starting at line 213 as of this session. `p` was unbound at its top level;
re-check rather than trust that. Note the user's file is **not** a copy of the
shipped default — it composes a `windows-screen` chosen by paneru
installation — so port the binding, don't diff-and-paste.

## Done when

- A release build from this workspace is installed to `/Applications` and
  relaunched (there is no in-place config reload — the menu bar's **Relaunch**
  is the only path, by doctrine, ADR-0018).
- The human has confirmed that F18 → `p` actually toggles playback. Check it
  against at least two **Now Playing target**s — Music.app and a browser tab
  with video — since the whole argument for the media-key mechanism over
  AppleScript was that it reaches both.
- `~/.config/modaliser/config.scm` binds `p` "Play/Pause" at the `'global`
  screen's top level, as a Terminal key, and the app relaunches cleanly with
  it (a config that fails to load leaves a **Degraded boot**, ADR-0022 — check
  the status-bar menu carries no error, don't just check that keys respond).

## Notes

**This leaf is HITL in practice.** `impl` is marked AFK, but the mark predicts
rather than permits: the pass condition here is a human hearing music stop, so
stop and ask. Do not mark the leaf done on the strength of "the event posted
without throwing" — that is exactly the silent-failure shape above.

**If the encoding is wrong, fix it here.** This is an `impl` leaf and it owns
`media-key-k2`'s Swift; there is no need to cut anything new for an encoding
correction. Re-run `swift test` after any fix — the pure encoding test will
need its expected values updated with it, and a test updated to match a bug is
the failure mode to watch for.

**The user's config file is outside the repository**, so the edit to it is not
part of this grove's commit. Say so in the commit message rather than leaving
a reader to wonder why the leaf's diff is smaller than its goal.

After this leaf retires, the only work left is the release, which lives
outside this tree — the root brief's "On the horizon" carries the exact
sequence, and the finish session should surface it before teardown deletes it.
