# iTerm — baseline notes

The reference implementation. iTerm is the daily driver and the
existing modules are the most complete. Everything other backends
need to match (or consciously diverge from) is here.

## Op surface — what's already there

### Operations (keystroke-proxies — iTerm has no pane CLI)

| Locked op            | Procedure (file:line)                              | Mechanism |
|----------------------|----------------------------------------------------|-----------|
| `focus-pane-h`       | `focus-pane-left`  (`iterm.sld:127`)               | keystroke `cmd+alt+left`  (iTerm default) |
| `focus-pane-j`       | `focus-pane-down`  (`iterm.sld:130`)               | keystroke `cmd+alt+down`  (iTerm default) |
| `focus-pane-k`       | `focus-pane-up`    (`iterm.sld:129`)               | keystroke `cmd+alt+up`    (iTerm default) |
| `focus-pane-l`       | `focus-pane-right` (`iterm.sld:128`)               | keystroke `cmd+alt+right` (iTerm default) |
| `split-pane-h`       | `split-pane-left`  (`iterm.sld:135`)               | `cmd+d` then `cmd+ctrl+shift+h` (swap left) |
| `split-pane-j`       | `split-pane-down`  (`iterm.sld:133`)               | keystroke `cmd+shift+d`   (provisioned binding) |
| `split-pane-k`       | `split-pane-up`    (`iterm.sld:139`)               | `cmd+shift+d` then `cmd+ctrl+shift+k` (swap up) |
| `split-pane-l`       | `split-pane-right` (`iterm.sld:132`)               | keystroke `cmd+d`         (provisioned binding) |
| `move-pane-h`        | `move-pane-left`   (`iterm.sld:143`)               | keystroke `cmd+ctrl+shift+h` (provisioned) |
| `move-pane-j`        | `move-pane-down`   (`iterm.sld:146`)               | keystroke `cmd+ctrl+shift+j` (provisioned) |
| `move-pane-k`        | `move-pane-up`     (`iterm.sld:145`)               | keystroke `cmd+ctrl+shift+k` (provisioned) |
| `move-pane-l`        | `move-pane-right`  (`iterm.sld:144`)               | keystroke `cmd+ctrl+shift+l` (provisioned) |
| `focus-pane-by-digit`| `focus-by-digit` (`iterm.sld:591`) + `pane-list-block` (`iterm.sld:605`) | AX frames → `hints-show` chips → AppleScript `select session by UUID` |

**iTerm provisioning is non-trivial.** Splits in two directions and
all four moves rely on bindings the user's iTerm doesn't ship with;
`(iterm:configure-entry)` (`iterm.sld:383`) surfaces a one-shot
overlay action that writes them into `~/Library/Preferences/com.googlecode.iterm2.plist`.
`split-pane-{left,up}` and `split-pane-{right,down}` are intrinsically
asymmetric: iTerm's `cmd+d` always splits vertically with the new
pane to the *right*; getting a left-split requires post-split swap.
**Other backends with first-class CLI splits avoid this pain.**

### Detection

| What                | Procedure (file:line)                                 |
|---------------------|-------------------------------------------------------|
| focused tty         | `focused-iterm-tty`                  (`terminal.sld:28`)   |
| pane fg command     | `focused-terminal-foreground-command` (`terminal.sld:55`) — composes `focused-iterm-tty` + `tty-foreground-command` |

`focused-iterm-tty` uses AppleScript with an **`is running` guard**
(`terminal.sld:30`): `if application "iTerm2" is running then …`.
Without the guard a naked `tell application "iTerm2"` auto-launches
iTerm via Launch Services. **Every other AppleScript-based detection
recipe must take the same care** — this is portable to WezTerm
(if it has AppleScript) and absolutely required for any backend
where probing must not start the tool.

## Architectural patterns to lift (or consciously not)

### A. Keystroke-proxy as fallback mechanism

iTerm has no CLI. Every op is `send-keystroke`. Backends with CLIs
(tmux, WezTerm CLI, Kitty `@`, zellij `action`) should prefer the
CLI — it's race-free and doesn't require the user to have specific
key bindings configured. **Keystroke-proxy is the floor**, not the
default.

### B. AX-discovered geometry + `hints-show` chips

`make-iterm-panes-block` (`blocks/iterm-panes.sld:197`) does NOT use
iTerm to paint chips. It uses macOS Accessibility:

```scheme
(ax-find-elements-named "com.googlecode.iterm2"
                        "AXScrollArea" "AXStaticText")
```

(`iterm-panes.sld:144-145`) to enumerate pane frames in NSView
subview-tree DFS order, then `hints-show` (`modaliser hints` — a
native primitive that paints overlay windows at absolute screen
coordinates) draws the chips. The pane-to-UUID mapping uses
`(list-ref session-ids idx)` — AppleScript enumeration order
matches AX DFS order.

**Implication for other backends:**
- **WezTerm.app, Kitty.app, Ghostty.app** are AX-accessible macOS
  apps. The same `ax-find-elements-named` approach should work for
  any of them where AX exposes per-pane roles. Each backend's
  task probes its AX hierarchy and finds the right role names.
- **tmux / zellij** run *inside* a host terminal's pane. AX sees
  the host pane only. Chips for mux-panes must be drawn:
  - by native command (`tmux display-panes`), or
  - by escape sequence sent to each mux-pane's tty, or
  - via host-pane absolute-screen geometry + mux-pane character-
    cell offsets (this is the "indirect and inexact" path).

### C. `register!` factory (one-stop convenience)

`(iterm:register!)` (`iterm.sld:542-561`) does three things in one
call:

1. `(rebuild-tree!)` — defines the iTerm app-tree.
2. `(focus-mode-register!)` — installs the sticky focus mode.
3. `(set-local-context-suffix! …)` — installs the per-press hook
   that probes `focused-terminal-foreground-command` and returns
   `"/nvim"` / `"/zellij"` / `"/zellij+nvim"`.

**Inlining bypasses (3) silently** — the user's `config.scm:142`
inlines the tree, getting (1)'s behaviour but losing the suffix
hook. Phase-1 docs document this trap
(`docs/how-to/terminal-pane-aware-tree.md:59-77`). Each backend's
factory should:
- Bundle these three things.
- Accept `'install-context-suffix? #f` so inlining users can
  compose their own handler that delegates via
  `(<backend>:context-suffix-handler bundle-id …)`.

### D. `context-suffix-handler` is a per-bundle cond

`context-suffix-handler` (`iterm.sld:523-535`) takes a bundle-id
and dispatches:

```
("com.googlecode.iterm2"
  ⇒ probe focused-terminal-foreground-command,
    return "/nvim", "/zellij", "/zellij+nvim", or #f)
(else #f)
```

The dispatch is bundle-id-keyed. For phase 2 this means: each
backend's `context-suffix-handler` only fires when *its own*
bundle-id is the frontmost. The composition story for "tmux
running inside iTerm" lands in 080 (synthesis):
- Implicit: iTerm's handler detects tmux in its focused pane and
  delegates to `tmux:context-suffix-handler`.
- Explicit: user composes a top-level handler that fans out.

### E. `pane-list-block` block protocol

`pane-list-block` returns a block-spec alist with:
- `on-render-fn` — paints chips + returns data merged into the
  block JSON.
- `on-leave-fn` — hides the chips when the overlay closes.

Other backends' chip-renderers must match this block-spec
shape — the overlay engine doesn't know or care which backend
painted the chips.

### F. Race-condition handling

`focus-by-digit` (`iterm.sld:591-597`) defends against a
leader-then-digit press *faster than the overlay render*: if the
digit isn't in the snapshot, `iterm-panes-refresh!` forces a
fresh snapshot before dispatching. Every backend's `focus-pane-
by-digit` needs the same care, especially if its snapshot is
expensive (CLI calls).

## Concrete renames the synthesis (080) must lock

If the abstraction uses hjkl in procedure names (user's typed
preference), iterm.sld needs:

| Current name         | New name      | Breaks |
|----------------------|---------------|--------|
| `focus-pane-left`    | `focus-pane-h`| user's `config.scm:157-160` |
| `focus-pane-right`   | `focus-pane-l`| ditto |
| `focus-pane-up`      | `focus-pane-k`| ditto |
| `focus-pane-down`    | `focus-pane-j`| ditto |
| `split-pane-left`    | `split-pane-h`| user's `config.scm:163-166` |
| `split-pane-right`   | `split-pane-l`| ditto |
| (… etc.)             |               |        |

Total: 12 procedures + 12 call sites in the user's config
(`config.scm:157-176`). If we keep direction-word names, the
abstraction inherits iterm.sld's convention and no config changes
are needed. **My recommendation, deferring to 080: keep
direction-word names** — the user typed `{hjkl}` to denote *the
four directions*, not to mandate the procedure names. The hjkl
keys are what configs bind; the procedure names can read clearly
in either form. Breakage isn't worth the rename.

If 080 chooses to rename: provide both as aliases for one release
cycle, then deprecate.

## Open questions surfaced

1. **AX-accessibility per terminal.** Confirm which Mac terminals
   expose pane geometry via AX (subsequent per-backend tasks).
2. **Mux chip rendering.** If `tmux display-panes` is acceptable
   UX, the abstraction may not need a uniform chip-painting
   primitive — each backend uses what works.
3. **`(modaliser blocks iterm-panes)` → `(modaliser blocks <backend>-panes)`?**
   Or one generic `(modaliser blocks panes)` parameterised by
   backend? Defer to 080.
4. **`configure-entry` provisioning analogue.** For backends
   needing user config (kitty's `allow_remote_control`, tmux's
   `display-panes` key binding), do we provide a similar one-shot
   provisioning overlay action, or just document the prerequisite?

## Capability matrix row

| Backend | Type           | Detection | 13-op surface | Mechanism                           | Chip render                         |
|---------|----------------|-----------|---------------|-------------------------------------|-------------------------------------|
| iTerm2  | host w/ splits | ✓ AppleScript+ps | ✓ all 13   | keystroke-proxy (12 ops) + AX+AppleScript (digit) | AX frames → `hints-show` |
