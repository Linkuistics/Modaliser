# Terminal-pane-aware trees & remote-desktop docs — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three documentation pages — a terminal-detection reference, a terminal-pane-aware-tree how-to, and a remote-desktop (arm mechanism) how-to — plus index/cross-link updates.

**Architecture:** Pure documentation. Three new Markdown files under `docs/`, two existing files edited for cross-links. No code changes. "Tests" are verification steps: every Scheme symbol cited is confirmed exported, every internal link resolves, prose wrapping matches each directory's convention.

**Tech Stack:** Markdown; Mermaid for one diagram; the docs describe Scheme (LispKit) config and the `(modaliser …)` libraries.

---

## Spec

Design spec: `docs/superpowers/specs/2026-05-22-terminal-pane-and-remote-docs-design.md`. Read it before starting — it records the verified mechanism facts and the per-terminal capability matrix.

## Conventions (apply to every task)

- **Wrapping:** prose in `docs/how-to/` hard-wraps at ~70 columns; prose in `docs/reference/` at ~76. Fenced code blocks and Markdown tables are NOT wrapped. Match the sibling files (`docs/how-to/add-a-per-app-tree.md`, `docs/reference/portability.md`).
- **Diagrams:** Mermaid only, never ASCII art.
- **Every Scheme symbol** named in a snippet must be confirmed exported by the verification step in its task before commit.
- **Commit** after each task with a `docs:` Conventional Commit subject.

## File structure

- Create `docs/reference/terminal-detection.md` — reference: the detection model, `(modaliser terminal)` API, per-terminal tty recipes, multiplexer recipes, nvim setup, capability matrix, limits.
- Create `docs/how-to/terminal-pane-aware-tree.md` — how-to recipe: wire a per-pane-aware iTerm local tree.
- Create `docs/how-to/remote-desktop.md` — how-to + explanation: the pass-and-arm mechanism.
- Modify `docs/how-to/index.md` — list the two new how-tos.
- Modify `docs/how-to/add-a-per-app-tree.md` — point its "Bundle variants" note at the new how-to.

Build order: reference first (the how-to links into it), then the two how-tos, then index/cross-links.

---

## Task 1: Reference — `docs/reference/terminal-detection.md`

**Files:**
- Create: `docs/reference/terminal-detection.md`
- Read for facts: `Sources/Modaliser/Scheme/lib/modaliser/terminal.sld`, `Sources/Modaliser/Scheme/lib/modaliser/event-dispatch.sld`, `Sources/Modaliser/Scheme/lib/modaliser/apps/iterm.sld`

- [ ] **Step 1: Verify the cited Scheme symbols exist**

Run:
```bash
grep -n 'focused-iterm-tty\|tty-foreground-command\|focused-terminal-foreground-command\|list-nvim-sockets\|nvim-server-focused?\|focused-nvim-socket\|nvim-remote-send\|nvim-remote-expr\|modaliser-tool-path' Sources/Modaliser/Scheme/lib/modaliser/terminal.sld
grep -n 'set-local-context-suffix!\|resolve-app-tree\|local-context-suffix' Sources/Modaliser/Scheme/lib/modaliser/event-dispatch.sld
```
Expected: every name appears in an `(export …)` clause. If any does not, stop and reconcile with the spec.

- [ ] **Step 2: Confirm the exact WezTerm and Kitty control commands**

The reference gives WezTerm/Kitty recipes; their CLIs must be quoted correctly. WebFetch the current official docs:
- WezTerm CLI: `https://wezterm.org/cli/cli/list.html` — confirm `wezterm cli list --format json` and that each pane object carries `is_active`, `tty_name` (or `pane_id`), and `pid`.
- Kitty remote control: `https://sw.kovidgoyal.net/kitty/remote-control/` — confirm `kitty @ ls` returns windows with `is_focused`, `foreground_processes` (each with `cmdline`, `pid`), and that `allow_remote_control yes` (or `--listen-on`) is the prerequisite.

Record the confirmed invocations; if a field name differs from the above, use the confirmed one in Step 3.

- [ ] **Step 3: Write `docs/reference/terminal-detection.md`**

Front-load with: a `# Terminal pane detection` H1 and a one-line intro ("How Modaliser works out what is running in the focused terminal split, and what each terminal makes possible."). Wrap prose at ~76 cols. Sections, in order:

1. **`## The model: the tty's foreground process group`** — Explain (from `terminal.sld:1-7`): the kernel truth for "what is receiving keystrokes" is the foreground process group of the controlling tty (`ps -o tpgid`); the row whose `pgid == tpgid` is the foreground process. One probe answers "is X in the focused split" for any full-screen program — vim, htop, lazygit, a plain shell. Detection is therefore two steps: (a) find the focused split's tty, (b) read its foreground command. Step (b) is universal; step (a) is per-terminal and is what varies.

2. **`## The (modaliser terminal) API`** — A definition list of each export with a one-line description:
   - `(focused-iterm-tty)` → the pty path of iTerm2's focused session, or `#f`.
   - `(tty-foreground-command tty)` → the foreground-process command string on `tty`, or `#f`.
   - `(focused-terminal-foreground-command)` → the focused terminal split's foreground command, or `#f`. **iTerm2-only today.**
   - `(list-nvim-sockets)` → RPC socket paths of all running nvim processes.
   - `(nvim-server-focused? sock)` → `#t` if that nvim reports `g:modaliser_focused == 1`.
   - `(focused-nvim-socket)` → socket of the focused nvim (direct or inside a multiplexer), or `#f`.
   - `(nvim-remote-send keys)` → send keystrokes to the focused nvim.
   - `(nvim-remote-expr expr)` → evaluate `expr` in the focused nvim, return the result string or `#f`.
   - `modaliser-tool-path` → PATH prefix (`/opt/homebrew/bin:/usr/local/bin:/usr/sbin`) for shelling out to Homebrew tools; GUI-launched Modaliser inherits a minimal PATH.

3. **`## Native splits — the primary case`** — Getting the focused split's tty per host terminal:
   - **iTerm2** — built in: `focused-terminal-foreground-command` queries `current session of current window` (the focused split) via AppleScript, then reads its tty's foreground command. Nothing to write — it just works.
   - **WezTerm** — no library support; a `run-shell` recipe using the confirmed `wezterm cli list --format json` command from Step 2 (pick the pane with `is_active`, read its foreground command). Present as a recipe to adapt, not a supported API.
   - **Kitty** — no library support; a `run-shell` recipe using `kitty @ ls`, gated on `allow_remote_control yes` in `kitty.conf`. Present as a recipe to adapt.
   - **Ghostty / Alacritty** — no native-split introspection. Ghostty exposes no control CLI; Alacritty has no IPC *and no splits by design* (single pane). State this plainly; for splitting under these, use a multiplexer (next section).

4. **`## Reaching through a multiplexer`** — the secondary case:
   - **tmux** — `tmux display-message -p '#{pane_current_command}'` gives the focused pane's foreground command directly; `#{pane_tty}` gives its tty. Works under any host terminal. Give the exact `run-shell` recipe (see Step 3 code block below).
   - **zellij** — zellij exposes no per-pane tty/command query comparable to tmux. You can detect "zellij is running" (it is the host tty's foreground command) but not the focused zellij pane's contents directly.
   - **The nvim route bypasses both** — `focused-nvim-socket` scans every running nvim system-wide and asks each whether it holds terminal focus, so a focused nvim is found whether it is in a native split, a tmux pane, or a zellij pane, under any terminal.

   tmux recipe to include verbatim:
   ```scheme
   ;; Foreground command of the focused tmux pane, or #f if tmux isn't running.
   (define (focused-tmux-command)
     (let ((out (run-shell
                  (string-append
                    "export PATH=" modaliser-tool-path ":$PATH; "
                    "tmux display-message -p '#{pane_current_command}' 2>/dev/null"))))
       (let ((trimmed (string-trim out)))
         (if (string=? trimmed "") #f trimmed))))
   ```

5. **`## The nvim side`** — `focused-nvim-socket` works only if each nvim maintains the global `g:modaliser_focused`. Explain why: multiple nvim instances (or nvim nested in a multiplexer) all bind RPC sockets; the focus flag, updated by `FocusGained`/`FocusLost` autocmds, lets exactly one report focus. Give both snippets verbatim:

   `init.vim` / vimscript:
   ```vim
   augroup ModaliserFocus
     autocmd!
     autocmd FocusGained * let g:modaliser_focused = 1
     autocmd FocusLost   * let g:modaliser_focused = 0
   augroup END
   ```

   `init.lua` / Lua:
   ```lua
   local grp = vim.api.nvim_create_augroup("ModaliserFocus", { clear = true })
   vim.api.nvim_create_autocmd("FocusGained", {
     group = grp, callback = function() vim.g.modaliser_focused = 1 end,
   })
   vim.api.nvim_create_autocmd("FocusLost", {
     group = grp, callback = function() vim.g.modaliser_focused = 0 end,
   })
   ```

   Note: the terminal must have focus reporting enabled (modern terminals and multiplexers forward the xterm focus escapes to the active pane), and nvim with no flag set simply reads as not-focused (`get(g:, "modaliser_focused", 0)`).

6. **`## What each terminal supports`** — the two capability tables from the spec (host terminals; multiplexers). Copy them verbatim from the spec's "Verified facts" section.

7. **`## Limits`** — State precisely: a non-nvim program in a focused **native iTerm split** *is* resolvable; the same program in a focused **zellij** pane is *not* (zellij has no per-pane query). Ghostty and Alacritty have no native-split introspection at all. nvim is always resolvable via RPC regardless of host or multiplexer.

End with a `## Related` list linking `../how-to/terminal-pane-aware-tree.md` and `../how-to/add-a-per-app-tree.md`.

- [ ] **Step 4: Verify the file**

Run:
```bash
awk '{ if (length > m && $0 !~ /^( {0,3}\|| {0,3}```)/) m = length } END { print "max prose line: " m }' docs/reference/terminal-detection.md
grep -n '](' docs/reference/terminal-detection.md
```
Expected: max prose line ≤ ~80; every relative link target (`../how-to/terminal-pane-aware-tree.md`, `../how-to/add-a-per-app-tree.md`) exists or is created by a later task. Confirm there is no ASCII-art diagram.

- [ ] **Step 5: Commit**

```bash
git add docs/reference/terminal-detection.md
git commit -m "docs(reference): add terminal pane detection reference"
```

---

## Task 2: How-to — `docs/how-to/terminal-pane-aware-tree.md`

**Files:**
- Create: `docs/how-to/terminal-pane-aware-tree.md`
- Read for facts: `Sources/Modaliser/Scheme/lib/modaliser/apps/iterm.sld` (lines 523-561), `Sources/Modaliser/Scheme/lib/modaliser/event-dispatch.sld` (lines 72-115), `~/.config/modaliser/config.scm` (the inlined iTerm tree)

- [ ] **Step 1: Verify the cited symbols and the inlining situation**

Run:
```bash
grep -n 'context-suffix-handler\|install-context-suffix?\|set-local-context-suffix!' Sources/Modaliser/Scheme/lib/modaliser/apps/iterm.sld Sources/Modaliser/Scheme/lib/modaliser/event-dispatch.sld
grep -n 'string-contains?' Sources/Modaliser/Scheme/lib/modaliser/util.sld
```
Expected: `register!` accepts `'install-context-suffix?`; `set-local-context-suffix!` is exported by `(modaliser event-dispatch)`. Confirm where `string-contains?` comes from — if it is not in `(modaliser util)`, find its library and have the worked example import that library.

- [ ] **Step 2: Write `docs/how-to/terminal-pane-aware-tree.md`**

`# How to vary the terminal tree by what's in the focused pane` H1. Wrap prose at ~70 cols. Match the structure of `docs/how-to/add-a-per-app-tree.md` (intro paragraph, `## You'll need`, `## Steps`, `## Verify it worked`, `## Notes`, `## Related`). Content:

- **Intro** — You want F17 (the local leader) to show different bindings depending on what is running in the focused iTerm split — e.g. an nvim-specific tree when nvim is focused, a git tree when lazygit is focused. The dispatcher already supports this through a *context suffix*; this guide wires it up.

- **`## How it works`** (brief) — On every local-leader press, a hook installed via `set-local-context-suffix!` is called with the focused app's bundle ID and returns a suffix string (e.g. `/nvim`) or `#f`. `resolve-app-tree` then prefers the tree registered under `"com.googlecode.iterm2/nvim"`, falling back to the plain `"com.googlecode.iterm2"` tree. You register the variant trees with `define-tree`. For *how detection works*, link to `../reference/terminal-detection.md`.

- **`## The quick path: (iterm:register!)`** — If you use the bundled iTerm factory, `(iterm:register!)` installs the suffix hook for you; it already returns `/nvim`, `/zellij`, and `/zellij+nvim`. You only need to register the matching variant trees. Show:
  ```scheme
  (import (modaliser dsl)
          (modaliser terminal)                  ; nvim-remote-send
          (prefix (modaliser apps iterm) iterm:))
  (iterm:register!)

  (define-tree 'com.googlecode.iterm2/nvim
    (key "w" "Write"  (λ () (nvim-remote-send ":w<CR>")))
    (key "q" "Close"  (λ () (nvim-remote-send "<Esc>:q<CR>"))))
  ```

- **`## If you've inlined your iTerm tree`** — Inlining the iTerm tree by hand (a `(define-tree 'com.googlecode.iterm2 …)` instead of `(iterm:register!)`) keeps the bindings but **drops the suffix-hook install** — so pane detection silently does nothing. Two ways back: (a) **install your own hook** with `set-local-context-suffix!` (the next section) — best if you want to keep managing the tree by hand; or (b) **revert to `(iterm:register!)`** and add your customisations through its options (`'extra-bindings`, …) instead of inlining. Recommend (a) — you have already chosen to own the tree.

- **`## Worked example: a custom context suffix`** — The general recipe — branch on the focused split's foreground command. Show verbatim:
  ```scheme
  (import (modaliser event-dispatch)   ; set-local-context-suffix!
          (modaliser terminal))        ; focused-terminal-foreground-command
  ;; plus the library that exports string-contains? (confirmed in Step 1)

  ;; Runs on every F17 press. Probe the focused iTerm split and choose a
  ;; tree variant by what's running in it.
  (set-local-context-suffix!
    (lambda (bundle-id)
      (and (equal? bundle-id "com.googlecode.iterm2")
           (let ((cmd (focused-terminal-foreground-command)))
             (cond
               ((not cmd)                        #f)
               ((string-contains? cmd "nvim")    "/nvim")
               ((string-contains? cmd "lazygit") "/lazygit")
               (else                             #f))))))

  (define-tree 'com.googlecode.iterm2/lazygit
    (key "p" "Push"  (λ () (send-keystroke '() "P")))
    (key "f" "Pull"  (λ () (send-keystroke '() "p"))))
  ```
  Then the "interact with the app" depth: the suffix itself can ask the focused nvim a question — e.g. branch on its filetype:
  ```scheme
  ((string-contains? cmd "nvim")
   (let ((ft (nvim-remote-expr "&filetype")))
     (cond ((equal? ft "rust") "/nvim-rust")
           (else               "/nvim"))))
  ```
  Note this requires the nvim-side `g:modaliser_focused` autocmds — link to the reference's "The nvim side" section.

- **`## Verify it worked`** — Focus an iTerm split running nvim, tap F17: the nvim variant tree should appear. Switch the split to a plain shell, tap F17: the plain `com.googlecode.iterm2` tree. If you always get the plain tree, the hook is not installed (did you inline the tree?) or the variant tree's scope symbol is misspelt.

- **`## Notes`** — One hook total: `set-local-context-suffix!` replaces any previously installed hook (it is not additive). If you use both the iTerm factory and your own hook, compose them — call `(iterm:register! 'install-context-suffix? #f)` and have your hook delegate the iTerm branch to `(iterm:context-suffix-handler bundle-id …)`.

- **`## Related`** — link `../reference/terminal-detection.md`, `add-a-per-app-tree.md`.

- [ ] **Step 3: Verify the file**

Run:
```bash
awk '{ if (length > m && $0 !~ /^( {0,3}\|| {0,3}```)/) m = length } END { print "max prose line: " m }' docs/how-to/terminal-pane-aware-tree.md
grep -n '](' docs/how-to/terminal-pane-aware-tree.md
```
Expected: max prose line ≤ ~74; `../reference/terminal-detection.md` and `add-a-per-app-tree.md` resolve. Re-read every Scheme snippet: each of `set-local-context-suffix!`, `focused-terminal-foreground-command`, `nvim-remote-send`, `nvim-remote-expr`, `string-contains?`, `iterm:register!`, `iterm:context-suffix-handler` was confirmed in Step 1 / Task 1 Step 1.

- [ ] **Step 4: Commit**

```bash
git add docs/how-to/terminal-pane-aware-tree.md
git commit -m "docs(how-to): add terminal-pane-aware tree guide"
```

---

## Task 3: How-to — `docs/how-to/remote-desktop.md`

**Files:**
- Create: `docs/how-to/remote-desktop.md`
- Read for facts: `Sources/Modaliser/KeyboardHandlerRegistry.swift`, `Sources/Modaliser/Scheme/lib/modaliser/leader.sld`, `~/.config/modaliser/config.scm:31-38`

- [ ] **Step 1: Verify the arm-mechanism facts**

Run:
```bash
grep -n 'armWindow\|armState\|passThrough\|postEscape\|armBundleIds' Sources/Modaliser/KeyboardHandlerRegistry.swift
grep -n 'set-arm-delay!' Sources/Modaliser/KeyboardLibrary.swift
grep -n 'arm-when-frontmost' Sources/Modaliser/Scheme/lib/modaliser/leader.sld Sources/Modaliser/Scheme/lib/modaliser/dsl.sld
```
Expected: confirms `armWindow` default `0.5`, the `.idle`/`.armed` two-state machine, `set-arm-delay!` exported, and `set-leaders!`/`set-leader!` accept `'arm-when-frontmost`.

- [ ] **Step 2: Write `docs/how-to/remote-desktop.md`**

`# How to use Modaliser over a remote desktop` H1. Wrap prose at ~70 cols. Content:

- **Intro** — When you screen-share or remote into another Mac (Jump Desktop, VNC, RDP) that *also* runs Modaliser, both instances see the same trigger keys. Press F18 and the host's Modaliser would normally grab it — you would never reach the remote's Modaliser. The `arm-when-frontmost` mechanism resolves this.

- **`## Setup`** — In `config.scm`, list the remote-viewer bundle IDs in `set-leaders!`:
  ```scheme
  (set-leaders! 'global-keycode F18
                'local-keycode  F17
                'arm-when-frontmost '("com.p5sys.jump.mac.viewer"))
  ```
  `arm-when-frontmost` takes bundle IDs of remote-desktop *viewer* apps. Find a viewer's bundle ID with `osascript -e 'id of app "Jump Desktop"'`. Optionally tune the double-tap window (default 0.5 s) with `(set-arm-delay! 0.4)`.

- **`## How it works`** — The pass-and-arm sequence. When the frontmost app is in `arm-when-frontmost`:
  - **First F18 press** — the host's Modaliser does *not* open its modal. It "arms" (starts a ~0.5 s timer) and passes F18 straight through to the viewer window — so the keystroke reaches the *remote* machine, whose Modaliser opens *its* modal.
  - **Second F18 press within the window** — the host disarms, posts an Escape to the viewer (closing the remote modal the first press opened), and *then* opens the *host's* modal.
  - **Any other key, or the timer expiring** — the arm is dropped; keys flow normally to the remote.

  So: **single tap drives the remote; double tap drives the host.** Include this Mermaid diagram verbatim:
  ```mermaid
  sequenceDiagram
      participant U as You
      participant H as Host Modaliser
      participant V as Viewer window
      participant R as Remote Modaliser
      Note over H: Viewer app is frontmost (in arm-when-frontmost)
      U->>H: Press F18 (1st)
      H->>H: Arm — start 0.5s timer
      H-->>V: Pass F18 through
      V-->>R: F18 reaches the remote
      R->>R: Open remote modal
      Note over U,R: Single tap → remote modal
      U->>H: Press F18 again (within 0.5s)
      H->>H: Disarm
      H-->>V: Post Escape (closes remote modal)
      H->>H: Open host modal
      Note over U,H: Double tap → host modal
  ```

- **`## Why it's designed this way`** — When you are remoted in, the thing you are looking at and working in is the *remote*. So the cheap, single action targets the remote; reaching the host — the less common intent — costs one extra tap. The host's Escape-post means the first (pass-through) tap leaves no stray modal open on the remote when you actually wanted the host.

- **`## Caveats`** — The double-tap must land inside the arm window (default 0.5 s; tune with `set-arm-delay!`). Pressing any non-leader key cancels the arm. Both machines must run Modaliser with the *same* leader keycodes. The mechanism is keyed on the *viewer app's* bundle ID being frontmost — a viewer running windowed still works as long as it is the frontmost app.

- **`## Related`** — link `../reference/dsl.md` (for `set-leaders!`), `add-a-per-app-tree.md`.

- [ ] **Step 3: Verify the file**

Run:
```bash
awk '{ if (length > m && $0 !~ /^( {0,3}\|| {0,3}```)/) m = length } END { print "max prose line: " m }' docs/how-to/remote-desktop.md
grep -n '](' docs/how-to/remote-desktop.md
```
Expected: max prose line ≤ ~74; links resolve. Confirm the Mermaid block is fenced as ` ```mermaid `. Confirm no ASCII-art diagram.

- [ ] **Step 4: Commit**

```bash
git add docs/how-to/remote-desktop.md
git commit -m "docs(how-to): add remote-desktop arm-mechanism guide"
```

---

## Task 4: Index and cross-link updates

**Files:**
- Modify: `docs/how-to/index.md`
- Modify: `docs/how-to/add-a-per-app-tree.md`

- [ ] **Step 1: Add the two new how-tos to `docs/how-to/index.md`**

After the existing `## Configuration basics` list, add a new section (match the existing entry style — link, em-dash, two-line wrapped description):
```markdown
## Terminal integration

- [Vary the terminal tree by what's in the focused pane](terminal-pane-aware-tree.md)
  — make F17 show different bindings depending on whether nvim, a
  git TUI, or a plain shell is running in the focused iTerm split.
```
And under `## Operational`, after the debug-binding entry, add:
```markdown
- [Use Modaliser over a remote desktop](remote-desktop.md) — the
  pass-and-arm mechanism for when a host and a remote machine both
  run Modaliser and see the same trigger keys.
```

- [ ] **Step 2: Point the "Bundle variants" note at the new how-to**

In `docs/how-to/add-a-per-app-tree.md`, find the `**Bundle variants.**` paragraph in `## Notes`. Append a sentence:
```markdown
For a full walkthrough of pane-aware variant trees, see
[terminal-pane-aware-tree.md](terminal-pane-aware-tree.md).
```
Keep the ~70-col wrap.

- [ ] **Step 3: Verify links resolve**

Run:
```bash
for f in terminal-pane-aware-tree.md remote-desktop.md; do test -f "docs/how-to/$f" && echo "ok $f" || echo "MISSING $f"; done
grep -n 'terminal-pane-aware-tree\|remote-desktop' docs/how-to/index.md docs/how-to/add-a-per-app-tree.md
```
Expected: both files exist; index and the per-app-tree note reference them.

- [ ] **Step 4: Commit**

```bash
git add docs/how-to/index.md docs/how-to/add-a-per-app-tree.md
git commit -m "docs(how-to): link terminal-pane-aware and remote-desktop guides"
```

---

## Final verification

- [ ] **Spec coverage:** every spec section maps to a task — Doc 2 → Task 1, Doc 1 → Task 2, Doc 3 → Task 3, index/cross-links → Task 4. The capability matrix lives in Task 1 Step 3 §6; the nvim autocmds in Task 1 Step 3 §5; the arm Mermaid diagram in Task 3 Step 2.
- [ ] **All five files** are committed; `git log --oneline` shows four `docs:` commits.
- [ ] **Cross-links** between the three new pages and into `add-a-per-app-tree.md` / `dsl.md` all resolve.
- [ ] Phase 2 (library-side detection backends) is **not** in scope here — confirm no task added library code.
