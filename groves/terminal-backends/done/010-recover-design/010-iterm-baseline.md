---
kind: work
---

# 010 — iTerm baseline

iTerm is the daily driver and the existing implementation lives in
`Sources/Modaliser/Scheme/lib/modaliser/apps/iterm.sld` +
`Sources/Modaliser/Scheme/lib/modaliser/terminal.sld`. This task
audits which procedures there map to which locked op; no new code,
just notes.

## Audit checklist

For each of the 13 locked ops, identify the iterm.sld procedure and
note the mechanism (CLI / AppleScript / keystroke-proxy):

| Locked op            | iterm.sld procedure                     | Mechanism |
|----------------------|-----------------------------------------|-----------|
| focus-pane-h         | `focus-pane-left`   (iterm.sld:127)     | keystroke `cmd+alt+left` |
| focus-pane-j         | `focus-pane-down`   (iterm.sld:130)     | keystroke |
| focus-pane-k         | `focus-pane-up`     (iterm.sld:129)     | keystroke |
| focus-pane-l         | `focus-pane-right`  (iterm.sld:128)     | keystroke |
| split-pane-h         | `split-pane-left`   (iterm.sld:135)     | keystroke |
| split-pane-j         | `split-pane-down`   (iterm.sld:133)     | keystroke |
| split-pane-k         | `split-pane-up`     (iterm.sld:139)     | keystroke |
| split-pane-l         | `split-pane-right`  (iterm.sld:132)     | keystroke |
| move-pane-{h,j,k,l}  | `move-pane-{left,down,up,right}` (143-146) | keystroke |
| focus-pane-by-digit  | `focus-by-digit` (591) + `pane-list-block` (605) | chip renderer + AppleScript select-by-UUID |

For detection:

| What                | primitive                              |
|---------------------|----------------------------------------|
| focused-tty         | `focused-iterm-tty` (terminal.sld:28)  |
| pane-foreground-cmd | `focused-terminal-foreground-command` (terminal.sld:55) |

## Deliverable

Write `notes/iterm.md` with:
1. The matrix above, filled in with line refs and mechanism notes.
2. iTerm-specific concerns worth carrying to other backends:
   - The AppleScript `is running` guard (terminal.sld:28-37) — does
     every backend's detection need an equivalent (avoid auto-launch)?
   - `pane-list-block` chip renderer — how does it position chips?
     This is the template other backends' chip-renderers must
     conceptually match.
   - `register!` / `context-suffix-handler` (iterm.sld:523, 542) —
     the factory pattern. Worth replicating per backend?
3. Any concrete *renames* the 080 synthesis must consider (e.g. if
   we pick hjkl naming, `focus-pane-left` → `focus-pane-h`).
