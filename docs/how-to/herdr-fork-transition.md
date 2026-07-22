# Transition the daily herdr to (and from) the ui.layout fork

**Maintainer-only, temporary.** This is not something a Modaliser user ever
needs to do: it's the bridge that unblocks mini-chip development while
`ui.layout` is upstream-only in a fork (ADR-0016), and it retires once the
upstream PR lands and mainline herdr ships the method. Runbook for moving
the locally-running herdr server between the Homebrew binary and the
`AntonyBlakey/herdr` fork (branch `ui-layout`) without losing live
workspaces, and for handing it back. Background: ADR-0016, the wire
contract in `docs/specs/herdr-ui-layout.md`.

**This is a live-server operation.** Never trial a step here against the
daily session before it has been rehearsed end-to-end in a TestAnyware VM.
The forward swap and the rollback are done step-by-step with Antony present
watching each command — see the grove leaf `live-swap-k19` for that gate.

## Why live handoff, not stop/restart

herdr already has a mechanism for this exact problem: `server.live_handoff`
(`src/server/handoff.rs`, `src/server/headless.rs::perform_live_handoff`).
The running server spawns the target executable, hands its pane PTYs across
as file descriptors (`SCM_RIGHTS`) along with a session snapshot, waits for
the new process to report ready and commit, then exits. Pane child
processes (shells, dev servers, agents) are never signalled — they keep
running unattached to any server the whole time. This is the same machinery
`herdr update --handoff` uses for ordinary version upgrades; we're just
pointing it at a locally-built exe instead of a downloaded release.

Do **not** use `herdr server stop` as anything but a deliberate last resort:
it terminates every pane and agent process (see CONTEXT.md, Stop vs Detach).

herdr's own integration suite (`tests/live_handoff.rs`) now covers this
mechanism heavily — pane survival, keyboard protocol, plugins, agent
sessions, HTTP servers in panes, multiple named sessions, and rollback on a
bad `expected_protocol` or a forced import failure. What it does *not*
cover: every one of those tests hands off to the *same* built exe re-execing
itself. This runbook's forward direction imports a genuinely different
binary at a different path — that cross-binary path is the gap the VM
rehearsal (grove leaf `vm-rehearsal-k18`) exists to close before this is
ever run against the daily server.

## Preconditions

- The fork build to import has already passed `just ci`
  (`~/Development/herdr`, branch `ui-layout`).
- Both the current daily server and the fork build report the same wire
  protocol. Check:

  ```sh
  herdr status --json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["server"]["protocol"])'
  ```

  and compare against the fork's `PROTOCOL_VERSION` (`src/protocol/wire.rs`
  in the fork checkout). At the time this runbook was written both are
  `16` — ADR-0016's "no wire bump" assumption. **If these ever differ,
  stop and re-derive this runbook** rather than passing a looser
  `--expected-protocol`; a protocol mismatch during handoff means the two
  binaries don't agree on the wire format and the guard exists precisely to
  catch that before it corrupts a live session.
- `docs/specs/herdr-ui-layout.md` is what the fork should be answering after
  the swap; know its shape well enough to eyeball a real response.

## Forward: Homebrew → fork

**As of `homebrew-publish-k20` (2026-07-17), step 1 is `brew install
linkuistics/taps/linkuistics-herdr`, not a raw `cargo build`.** The formula
(`linkuistics/homebrew-taps` → `Formula/linkuistics-herdr.rb`) builds from
source, pinned via `revision:` to a specific fork commit, and already sets
`ZIG` to `zig@0.15` — the manual-build steps below are kept for reference
(rebuilding the formula itself, or building outside Homebrew entirely) but
are no longer the normal path. The binary lands in the Cellar and is linked
to `/opt/homebrew/bin/herdr` — the **same path both Modaliser's
`modaliser-tool-path` and a plain interactive shell already resolve**, which
is what makes this the fix for a real regression, not just convenience: see
`modaliser-tool-path-robustness-k21` for the fragility this exposed.

1. Bump the fork build to import:

   - **Normal path**: after rebasing `~/Development/herdr`'s `ui-layout`
     branch and confirming `just ci` green, edit
     `Formula/linkuistics-herdr.rb` in the local
     `linkuistics/homebrew-taps` tap checkout — bump `revision:` to the new
     commit SHA and `version` to match (e.g.
     `0.7.4-uilayout.<short-sha>`) — then:

     ```sh
     brew reinstall linkuistics/taps/linkuistics-herdr
     ```

     This produces a fresh Cellar build at
     `/opt/homebrew/Cellar/linkuistics-herdr/<version>/bin/herdr`, linked to
     `/opt/homebrew/bin/herdr`.

   - **Manual fallback** (bypassing the formula — e.g. iterating on a build
     issue before committing a formula bump):

     ```sh
     cd ~/Development/herdr
     git checkout ui-layout && git pull --ff-only origin ui-layout
     ZIG="$(brew --prefix zig@0.15)/bin/zig" just ci
     ZIG="$(brew --prefix zig@0.15)/bin/zig" cargo build --release
     ```

     The binary lands at `~/Development/herdr/target/release/herdr`. The
     `ZIG` override is load-bearing if the build host's `zig` on PATH has
     been upgraded past the vendored `libghostty-vt`'s required version
     (checked in `build.rs`, currently 0.15.2) — a plain `brew upgrade zig`
     elsewhere on the machine silently breaks the herdr build with a `does
     not meet the required build version` panic. `brew install zig@0.15`
     (keg-only, coexists with a newer `zig`) fixes it without touching the
     system-wide `zig`.

     A second, similar gotcha: `just lint`/`just ci` invoke plain `cargo`,
     which on this machine resolves to Homebrew's `cargo` (ahead of
     rustup's shim on PATH) rather than the version `rust-toolchain.toml`
     pins — a newer Homebrew `rustc`/`cargo` can surface *new* clippy lints
     on old, unrelated code that the pinned version doesn't flag, failing
     the pre-commit hook for reasons that have nothing to do with the
     change being committed. Put `~/.cargo/bin` first on `PATH` (rustup's
     shim reads `rust-toolchain.toml` and dispatches to the pinned
     toolchain) before running `just`/`cargo`/`git commit` here.

2. Confirm the running server's protocol matches (see Preconditions), then
   run the handoff directly against the running daily server — this uses
   the client socket the currently-active `herdr` binary already talks to,
   so it doesn't matter yet whether `herdr` on PATH means Homebrew or a
   manual build:

   ```sh
   herdr server live-handoff \
     --import-exe /opt/homebrew/Cellar/linkuistics-herdr/<version>/bin/herdr \
     --expected-protocol 16 \
     --expected-version 0.7.4
   ```

   (Substitute `~/Development/herdr/target/release/herdr` for `--import-exe`
   if using the manual fallback build instead.)

   `--expected-version` is optional and checked against the *importing*
   binary's own reported version (`crate::build_info::version()`), not a
   comparison of old vs. new — it's a safety net against accidentally
   importing the wrong exe. If the fork build ever reports a different
   version string (e.g. a preview/dev channel suffix), the handoff fails
   closed rather than silently importing something unverified; when that
   happens, fix the value passed here, not the fork's version reporting.

3. On success, the CLI prints where the new server's log lives
   (`herdr-server.log` under the herdr data dir) — tail it if anything looks
   off. Confirm:

   ```sh
   herdr status --json
   ```

   still shows `running: true`, same protocol, and (the definitive
   fork-vs-stock signal, since `version`/`protocol` don't change) that
   `ui.layout` now answers where it previously wouldn't have:

   ```sh
   python3 - <<'PY'
   import json, socket
   s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
   s.connect("/Users/antony/.config/herdr/herdr.sock")
   s.sendall(json.dumps({"id": "verify", "method": "ui.layout", "params": {}}).encode() + b"\n")
   print(s.recv(65536).decode())
   PY
   ```

   A stock Homebrew server has no `ui.layout` handler and errors; the fork
   returns the `canvas`/`sidebar`/`tab_bar` shape from
   `docs/specs/herdr-ui-layout.md`.

4. Confirm every workspace and pane that was live before the handoff is
   still there and responsive (attach, or `herdr status` per session).

5. **Superseded by `homebrew-publish-k20` (2026-07-17).** `herdr` on PATH is
   now resolved by Homebrew alone: `brew install linkuistics/taps/linkuistics-herdr`
   links its Cellar build to `/opt/homebrew/bin/herdr`, and the manual
   `~/.local/bin/herdr` symlink from the original 2026-07-16 transition has
   been removed (`rm ~/.local/bin/herdr`) — there is no longer a
   PATH-shadowing copy to keep in sync. This is deliberate, not just tidier:
   `/opt/homebrew/bin` is on `modaliser-tool-path`
   (`terminal.sld`) and `~/.local/bin` never was, so a manual-symlink-only
   setup leaves Modaliser's own herdr shell-outs silently unable to find the
   binary (see `modaliser-tool-path-robustness-k21`) — the exact regression
   the original 2026-07-16 transition introduced and this one fixes.
   `which herdr` and `brew upgrade --dry-run herdr` (stock, should still
   error `herdr not installed`) confirm no leftover manual copy remains.

## Rollback: fork → Homebrew

Same `server.live_handoff` mechanism, reversed, plus one extra step because
`linkuistics-herdr` and stock `herdr` are two different formulas that both
want to link the same `bin/herdr` name — Homebrew refuses to link a second
one on top without the first stepping aside first:

```sh
brew uninstall linkuistics-herdr   # stock herdr is not installed alongside it
brew install herdr
brew_herdr="$(brew --cellar herdr)/$(brew list --versions herdr | awk '{print $2}')/bin/herdr"
herdr server live-handoff \
  --import-exe "$brew_herdr" \
  --expected-protocol 16 \
  --expected-version "$(brew list --versions herdr | awk '{print $2}')"
```

Note this fetches *whatever Homebrew currently ships*, not necessarily the
exact `0.7.4` build that was running before the forward swap — check its
`--expected-protocol` still matches (16 at time of writing) before trusting
this path; if it doesn't, stop and re-derive per the Preconditions section
above.

Verify the same way as the forward direction (`herdr status --json`; this
time `ui.layout` should go back to erroring, confirming the stock binary is
back in control). Once confirmed, remove the `linkuistics-herdr.rb` formula
from `linkuistics/homebrew-taps` (ADR-0016's option-3 exit) — its whole
reason to exist is gone once stock `herdr` has `ui.layout`.

## Costs while running the fork (ADR-0016)

No `herdr update` self-updates while the fork is the daily binary — it
rebases on upstream releases manually instead
(`git fetch upstream && git merge upstream/master` on `ui-layout`, as done
partway through this grove). Re-run `just ci` after any rebase before this
runbook's forward direction is used again.
