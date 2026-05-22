# Terminal-pane-aware trees & remote-desktop docs — design

**Date:** 2026-05-22
**Status:** Draft for review

## Goal

Document two capabilities that are implemented in Modaliser but currently
undocumented:

1. **Terminal-pane-aware local trees** — varying an app-local (F17) tree by
   what is running in the focused terminal split. The **primary case is a
   terminal's native splits** (e.g. iTerm panes), where the focused split's own
   program is directly detectable at per-split granularity. A **secondary case
   reaches through a multiplexer** (zellij/tmux). Both can interact with the
   focused program (nvim) to decide tree contents.
2. **The pass-and-arm leader mechanism** — letting a host and a remote
   Modaliser coexist when both capture the same trigger keys (Jump Desktop /
   VNC / RDP).

Audience: external readers (public release). Tone matches the existing
`docs/how-to/` and `docs/reference/` guides.

## Out of scope — follow-up phase

The user intends, **after** these docs land, to build first-class
per-terminal / per-multiplexer detection into the library (`terminal.sld`
gaining WezTerm / Kitty / tmux / zellij / Ghostty backends). This spec covers
**documentation only**. The non-iTerm detection is therefore presented as
config-level `run-shell` recipes. The docs should be written so they need
only light revision once library support exists (e.g. a recipe becomes "call
`(terminal:focused-pane-command)`" instead of an inline `run-shell`).

## Verified facts the docs rest on

Earlier feasibility assumptions in this conversation were wrong twice; these
are the load-bearing facts, each traced to source.

### The suffix-hook mechanism

- `(modaliser event-dispatch)` exports `set-local-context-suffix!`. It installs
  a hook `(lambda (bundle-id) → suffix-string-or-#f)`.
- On every local-leader press, `resolve-app-tree` (`event-dispatch.sld:82`)
  calls the hook; a returned suffix like `/nvim` makes it look up the tree
  registered under `"com.googlecode.iterm2/nvim"`, falling back to the plain
  `"com.googlecode.iterm2"` tree.
- Variant trees are registered with `(define-tree 'com.googlecode.iterm2/nvim …)`.

### iTerm factory

- `(iterm:register!)` (`apps/iterm.sld:542`) installs the suffix hook for you —
  `context-suffix-handler` (`apps/iterm.sld:523`) probes the focused pane and
  returns `/nvim`, `/zellij`, or `/zellij+nvim`.
- Inlining the iTerm tree by hand (as the user's `config.scm:142` does) keeps
  the bindings but **drops the hook install** — focused-pane detection is
  silently lost. `'install-context-suffix? #f` plus a hand-composed handler
  calling `(context-suffix-handler bid …)` is the documented escape hatch.

### Detection primitives — `(modaliser terminal)`

- `focused-terminal-foreground-command` → the command string of the foreground
  **process group** of the focused terminal split's tty. **iTerm2-only** today;
  it obtains the tty via `tell current session of current window` — iTerm's
  *focused* split — so for **iTerm native splits it yields the actual program
  in the focused split** (vim, htop, lazygit, plain shell — anything), at full
  per-split granularity. The process-group-of-the-tty model means one probe
  answers "what is in the focused split" for any program (`terminal.sld:1-7`,
  `terminal.sld:28-37`).
- That per-split granularity holds only for **native splits**. When a
  multiplexer (zellij/tmux) does the splitting, the host tty's foreground
  process is the multiplexer itself — the probe sees `zellij`, not the focused
  zellij pane's contents.
- nvim RPC: `focused-nvim-socket` scans all running nvim processes (`lsof`) and
  picks the one reporting `g:modaliser_focused == 1`. This is **terminal- and
  multiplexer-agnostic** — it needs no host-tty probe. `nvim-remote-expr` /
  `nvim-remote-send` query / act on the focused nvim.
- The nvim side requires `g:modaliser_focused`, maintained by `FocusGained` /
  `FocusLost` autocmds. This setup is undocumented anywhere in the repo today —
  the how-to must supply it.
- `(modaliser app)` exposes `focused-app-bundle-id` but **no** focused-app PID;
  process-tree recipes must get the PID via `run-shell` (e.g. `osascript`).

### Capability matrix — host terminals

| Terminal  | Native-split focused-pane detection               | Notes                                   |
|-----------|---------------------------------------------------|-----------------------------------------|
| iTerm2    | Yes — AppleScript (`focused-terminal-foreground-command`) | Only terminal with library support today |
| WezTerm   | Yes — `wezterm cli list` (tty/pid per pane)       | DIY recipe                              |
| Kitty     | Yes — `kitty @ ls`; needs `allow_remote_control`  | DIY recipe, opt-in                      |
| Ghostty   | No external pane API                              | Delegate splitting to a multiplexer     |
| Alacritty | No IPC; no splits by design                       | Single pane only; process-tree walk     |

### Capability matrix — multiplexers

| Multiplexer | Focused-pane query                                              | Notes                                              |
|-------------|-----------------------------------------------------------------|----------------------------------------------------|
| tmux        | Yes — `tmux display-message -p '#{pane_current_command}'` / `#{pane_tty}` | Finest granularity; host-terminal-independent |
| zellij      | No per-pane tty/command query comparable to tmux                | Detect "zellij running" + nvim-via-RPC; a non-nvim focused zellij pane is not resolvable |

**Practical conclusion — two cases, native splits first:**

- **Native splits** — the primary case (e.g. iTerm panes, the user's daily
  driver). The terminal exposes the focused split's tty, so
  `focused-terminal-foreground-command` resolves the actual focused-split
  program at full granularity. Supported today for iTerm; achievable for
  WezTerm/Kitty via their CLIs; unavailable for Ghostty/Alacritty.
- **Multiplexer panes** — the secondary case (some users run tmux/zellij inside
  any terminal). Detection is delegated to the multiplexer: tmux gives per-pane
  detail (`display-message`); zellij gives only "zellij is running" plus, via
  RPC, the focused nvim.

The how-to leads with native splits; the multiplexer case is documented as an
additional path, not the default framing.

### The arm mechanism — `KeyboardHandlerRegistry.swift`

- The leader hotkey is registered with `armBundleIds`, from `set-leaders!`'s
  `'arm-when-frontmost` list.
- Leader pressed while the frontmost app ∈ `armBundleIds`: the registry enters
  `.armed`, starts a timer (`armWindow`, default **0.5 s**, set from Scheme via
  `(set-arm-delay! seconds)`), and **passes the keystroke through** to the
  window. The local handler does not fire.
- Same leader pressed again within the window: disarm, post a magic-tagged
  synthetic Escape to the window, then fire the local handler → local modal
  opens.
- Any other key within the window: disarm, pass through (key flows to the
  remote).
- Timer expiry: disarm.
- Net behaviour: **single tap → the remote machine's Modaliser; double tap →
  the host's Modaliser** (the Escape cleans up the remote modal the first tap
  opened).

## Deliverable — three documents

### Doc 1 — `docs/how-to/terminal-pane-aware-tree.md` (how-to, recipe)

Short, in the style of existing how-tos. Reader goal: make F17 show different
bindings when nvim is focused in the terminal.

Sections:
- When you'd want this.
- The mechanism in brief — suffix hook + variant trees (defers internals to
  Doc 2).
- The quick path — `(iterm:register!)` installs the hook; register
  `'com.googlecode.iterm2/nvim` etc.
- If you inlined your iTerm tree — re-add the hook (the user's exact
  situation), via `set-local-context-suffix!` or `'install-context-suffix? #f`.
- Worked example (native iTerm splits) — a custom `set-local-context-suffix!`
  handler that probes the focused split with `focused-terminal-foreground-command`
  and returns a suffix per program (`/nvim`, `/lazygit`, `#f`, …), with matching
  `(define-tree 'com.googlecode.iterm2/nvim …)` variant trees. Then the
  nvim-depth bit: a binding using `nvim-remote-expr` to reflect live nvim state.
  This is the original ask — bindings that change with what is running in the
  focused iTerm split.
- Verify / troubleshoot.
- Related links.

### Doc 2 — `docs/reference/terminal-detection.md` (reference / explanation)

The internals plus per-terminal recipes.

Sections:
- The foreground-process-group-of-the-tty model — why one probe answers
  "what's in the pane".
- `(modaliser terminal)` API surface.
- Native splits — the primary case. Getting the focused split's tty per host
  terminal: iTerm (built in, `focused-terminal-foreground-command`), WezTerm /
  Kitty (`run-shell` recipes via their CLIs), Ghostty / Alacritty (no
  native-split introspection — limits stated plainly).
- Reaching through multiplexers — the secondary case: tmux recipe
  (`display-message`); zellij limits; the nvim-RPC route that bypasses both and
  works under either.
- The nvim side — the `g:modaliser_focused` `FocusGained` / `FocusLost`
  autocmds (full snippet, both vimscript and lua).
- Capability matrix (the two tables above).
- Limits — scoped clearly: a non-nvim program in a focused **zellij** pane is
  not resolvable; the same program in a focused **native iTerm split** *is*.
  Ghostty / Alacritty have no native-split introspection.

### Doc 3 — `docs/how-to/remote-desktop.md` (how-to + explanation)

Reader goal: use Modaliser sanely when remoted into another machine that also
runs Modaliser.

Sections:
- The problem — two Modalisers, the same trigger keys.
- Setup — `set-leaders!` with `'arm-when-frontmost`; viewer bundle IDs (Jump
  Desktop `com.p5sys.jump.mac.viewer`, common VNC/RDP viewers); `set-arm-delay!`.
- How pass-and-arm works — the single-tap / double-tap behaviour; a Mermaid
  sequence diagram.
- Why it is designed this way — single tap targets what you are looking at.
- Caveats — the 0.5 s window; any non-leader key cancels the arm; both machines
  need Modaliser with matching leader keys.

### Index / cross-link updates

- `docs/how-to/index.md` — add Doc 1 and Doc 3 (new "Terminals" and/or
  "Remote" groupings, or fit into "Configuration basics" / "Operational").
- `docs/how-to/add-a-per-app-tree.md` — its "Bundle variants" note already
  mentions `'com.googlecode.iterm2/nvim` and `set-local-context-suffix!`; point
  it at Doc 1.

## Diagrams

Doc 3's pass-and-arm sequence is a Mermaid `sequenceDiagram` (host Modaliser /
remote viewer / remote Modaliser) — never ASCII art.

## Conventions

- how-to docs are hard-wrapped at ~70 columns (matching
  `add-a-per-app-tree.md`). Confirm the `docs/reference/` wrapping width
  against existing files before writing Doc 2.
- Code snippets must be checked against the live libraries — every exported
  name used (`set-local-context-suffix!`, `context-suffix-handler`,
  `nvim-remote-expr`, `set-arm-delay!`, …) verified present before shipping.

## Validation

No automated tests (documentation). Validation is user review of the spec, then
of the drafts. The Doc 1 "re-add the hook" recipe should be checked against the
user's actual `config.scm` so it genuinely restores `/nvim` detection.

## Build sequence

1. Doc 2 (reference) — it is the foundation Doc 1 links into.
2. Doc 1 (how-to) — links to Doc 2.
3. Doc 3 (remote desktop) — independent; can be done in parallel.
4. Index and cross-link updates.
