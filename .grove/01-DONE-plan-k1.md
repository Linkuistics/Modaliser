# plan-k1

**Kind:** planning

## Goal

Plan how to add **herdr** modal controls to Modaliser, in the manner of the
existing iTerm controls — decompose into work leaves. (Refined through grilling.)

## Context

**What herdr is.** `herdr` (herdr.dev, v0.7.1, `/opt/homebrew/bin/herdr`) is an
"agent multiplexer that lives in your terminal" — *no GUI app, no Electron, no
native wrapper*. It runs as a background **server** with attach/detach **clients**
inside a host terminal (the user runs it in **iTerm**). It manages a hierarchy of
**workspaces → tabs → panes**, plus **git worktrees**, and is **agent-aware**
(per-pane agent status: idle/working/blocked/unknown).

**Control surface — a JSON socket API.** Unlike iTerm (AppleScript + synthetic
keystrokes) herdr exposes a full CLI over its socket (`~/.config/herdr/herdr.sock`),
each command emitting JSON:
- `herdr pane focus|split|swap|resize|zoom|list|current|close|move|rename …`
  (focus/swap take `--direction left|right|up|down`; split takes `--direction
  right|down` only → left/up need split-then-swap like iTerm)
- `herdr tab list|create|focus|rename|close`
- `herdr workspace list|create|focus|rename|close`
- `herdr worktree …`, `herdr agent …`, `herdr session …`, `herdr notification …`
- `herdr pane current` → `{"pane_id":"w9:p1","tab_id":"w9:t1","workspace_id":"w9",
  "agent_status":…,"cwd":…,"focused":true}`. IDs are `w<N>:p<M>` / `w<N>:t<M>`.

**How Modaliser's terminal layer works (target architecture).**
- `(modaliser terminal)` façade holds a `<terminal-backend>` record (14 pane ops +
  detect-fg + focused-pane-id + digit-jump + zoom + configured?), a registry, and a
  host→mux **focused-terminal-path** walk. ADRs 0002–0008; PRD
  `docs/prd/terminal-backends.md`.
- Backends are `'host` (keyed by bundle-id) or `'mux` (keyed by foreground-command).
  `muxes/tmux.sld` + `muxes/zellij.sld` are the mux models; `apps/iterm.sld` +
  `app-trees/com.googlecode.iterm2.scm` are the host model.
- **Once a mux backend is registered and detected as the active backend, the existing
  iTerm app-tree pane controls (Splits/Panes/Focus/Move/Zoom) already route to it via
  the façade dispatch** — so pane ops come nearly for free. herdr-specific surfaces
  (workspaces, worktrees, tabs, agents) need new UI.

**Likely shape:** a `muxes/herdr.sld` mux backend (CLI-driven, match-key `"herdr"`)
chained under the iTerm host, plus herdr-specific control tree(s). Detection is
probably *simpler* than tmux (one server, one globally-focused pane — the socket API
already knows it; the ADR-0006 tty-correlation dance may be unnecessary).

## Done when

Design is settled and the tree is grown into concrete work leaves (backend +
config wiring + any herdr-specific surfaces + tests + docs), with ADRs/PRD/glossary
updated inline as decisions land.

## Notes

## Decisions (running log)

**D1 — Context-sensitive tree composition (the core requirement).** herdr controls
are not just the auto-routed pane façade; the user wants the iTerm app-tree to change
shape based on the herdr situation in the frontmost iTerm window:
- **iTerm window has a single pane, running herdr** → **replace** the iTerm-specific
  actions with herdr-specific actions (iTerm is a dumb host window; herdr owns the
  multiplexing, so iTerm split/pane controls are noise).
- **Focused iTerm pane runs herdr but the window has other iTerm panes too** →
  **augment** the iTerm actions with herdr actions (both layers live).
- (Implicit third case: no herdr → today's plain iTerm tree, unchanged.)
So there are **two herdr trees** — a *replacing* tree and an *augmenting* tree —
composed into the iTerm app-tree by detected context. This is the branch name's "in
iterm controls": herdr controls live within the iTerm tree, swapped/augmented per
context. Mechanism to confirm: Modaliser's context-suffix / variant-tree rebuild
(`docs/how-to/terminal-pane-aware-tree.md`, `set-local-context-suffix!`).

**D2 — Mechanism is the context-suffix / variant-tree rebuild (confirmed).** The
bundled `iterm:context-suffix-handler` (`apps/iterm.sld`) already branches on
`focused-terminal-foreground-command` → `/nvim`, `/zellij`, `/zellij+nvim`, else #f;
`resolve-app-tree` prefers `com.googlecode.iterm2/<suffix>` over the plain screen.
The user's config inlines its iTerm tree via `(iterm:register! 'install-tree? #f)`,
so it uses the bundled handler with `rebuild? #f`. To add herdr:
- Extend the handler's cond to return `/herdr` (sole pane) vs an augment suffix
  (e.g. `/herdr+split`) — distinguished by **iTerm pane count** in the focused
  window: `(ax-find-elements-named "com.googlecode.iterm2" "AXScrollArea"
  "AXStaticText")` length (== 1 → replace, > 1 → augment). Already computed for chips.
- Register two variant screens: `com.googlecode.iterm2/herdr` (herdr-only) and
  the augment one (iTerm splits + herdr).

**D3 — Façade active-backend ambiguity ⇒ herdr trees use backend-DIRECT ops (open).**
The current app-tree's Focus/Split/Move use `terminal:focus-pane-*` (the façade).
When the focused iTerm pane runs herdr, the façade's `active-backend` walk resolves
to **herdr** (iTerm→herdr chain), so those bindings would drive herdr, not iTerm
splits — this is *why* separate herdr trees are needed. Implication: the herdr
variant trees should call **iterm-direct** ops for iTerm splits and **herdr-direct**
ops for herdr, not the shared façade. (herdr may still register as a façade mux
backend for detection/completeness, but the trees bind direct procedures.) To settle
in grilling.

**D4 — Scope: the full herdr surface (all capability groups).** User wants controls
for **panes, tabs, workspaces, and agents + worktrees**. And: in the single-pane
**replace** case there are **no iTerm controls at all** — everything is done within
herdr (herdr owns the whole window). So:
- **Replace tree** (`/herdr`) = herdr-only: panes + tabs + workspaces + agents +
  worktrees. Zero iTerm bindings.
- **Augment tree** (herdr + other iTerm panes) = iTerm split controls (iterm-direct)
  **plus** the same herdr surface (herdr-direct).
Agents + worktrees are the fuzzier, product-shaped surfaces (agent-status UX,
worktree UX) — candidates for their own planning+work leaves after panes/tabs/
workspaces land.

**D5 — Control mechanism: herdr's JSON socket-API CLI (decided).** Drive herdr via
`herdr pane|tab|workspace|worktree|agent …` over `run-shell`, not synthetic
keystrokes/AppleScript — same discipline as tmux/zellij backends, and herdr's API is
cleaner (structured JSON, one server that already tracks the focused pane, so the
ADR-0006 tty-correlation dance is likely unnecessary). PATH-prefix `run-shell` like
the tmux backend (GUI Modaliser has a minimal PATH; herdr is in /opt/homebrew/bin).

**D6 — Detection: iTerm→herdr chain via fg-command `herdr`; targeting via the
server's focused pane (needs empirical validation).** herdr is client/server; panes
run under the headless **server**, decoupled from any client tty. So:
- **"herdr is here"** = the focused iTerm pane's tty foreground command is the herdr
  *client* (`herdr`). Drives both the context suffix and the mux-chain descent.
  *Unverified* — at planning time no client was attached (only `herdr server`), so I
  could not confirm the client reports fg-command `herdr`. **Verification #1** for the
  backend leaf.
- **herdr's own inner fg-command** (herdr→nvim chaining) comes from the socket API
  (`herdr pane process-info --current` → e.g. `zsh`), not a tty.
- **Targeting the pane the user sees** = the server's globally-focused pane
  (`herdr pane current`). Simpler than tmux's tty-correlation *if* the server's focus
  tracks the OS-focused iTerm client. **Verification #2**: confirm focus-forwarding
  (single-client common case near-certain; multi-client / multiple named sessions is a
  v1 assumption: follow the server's focused pane, defer multi-session correlation).

**D7 — Augment layout: herdr owns top-level hjkl; iTerm splits behind an `i` drill.**
So the **augment tree = the replace (herdr) tree + one `i` "iTerm splits" drill-down**
(iterm-direct focus/split/move/zoom). hjkl means "move herdr pane" in *both* trees →
identical muscle memory, and the tree-builder is shared (build herdr tree; for
augment, append the iTerm-splits drill). iTerm-splits drill uses **iterm-direct** ops
(`iterm:focus-pane-*` etc.), never the façade (which points at herdr here).

**D8 — Code location + façade registration (decided, pushback welcome).**
- **`lib/modaliser/muxes/herdr.sld`** (portable): the `'mux` `<terminal-backend>`
  record (match-key `"herdr"`, 14 pane ops via `herdr pane` CLI + digit-jump + zoom +
  detect-fg via socket API), `register!`, **plus** herdr-direct ops for tabs /
  workspaces / worktrees / agents, and the shared herdr tree-builder + context-suffix
  contribution. Mirrors `muxes/{tmux,zellij}.sld` and `apps/iterm.sld`.
- **`lib/modaliser/blocks/herdr-{panes,tabs,workspaces}.{sld,js,css}`**: live-list
  overlay blocks mirroring `blocks/iterm-{panes,tabs}.*` (chips + digit dispatch).
- **User config** `app-trees/com.googlecode.iterm2.scm` (+ bundled `default-config`/
  `app-trees` sync — [[feedback_config_sync]]): register the `/herdr` (replace) and
  augment variant screens; compose the context-suffix handler to add the herdr cases
  (delegate the existing iTerm branch via `iterm:context-suffix-handler`, per the
  how-to's "compose your own hook" note).
- **Register herdr as a façade mux backend** (kind `'mux`) for detection completeness
  (`in-chain? 'herdr`, `focused-terminal-path`, generic capability-predicate trees) —
  *and* have the herdr trees bind **herdr-direct** ops (D3/D7), so the augment case's
  iterm-direct vs herdr-direct split is unambiguous. Both, not either.
- **Tests** `Tests/ModaliserTests/ModaliserMuxesHerdrLibraryTests.swift` mirror
  `Muxes{Tmux,Zellij}` backend tests. **Docs**: `CONTEXT.md` herdr terms (done in
  this session); reference/how-to updates; ADR for the replace/augment
  context-sensitivity.

**D9 — Docs reality + ADR/PRD timing.** The terminal-backends ADRs 0002–0008 and
`docs/prd/terminal-backends.md` referenced in `terminal.sld`/`tmux.sld`/CLAUDE.md
**no longer exist** — that grove was finished and cleaned up (`d2055ab`), leaving
dangling code-comment references. Live ADRs are numbered `0009`–`0012`; **`docs/prd/`
does not exist.** So:
- Follow the repo's **numbered-slug ADR** convention (`docs/adr/0013-<slug>.md`), not
  a bare slug — match the local files (0009–0012), per [[feedback_cross_project_consistency]].
- **Defer the replace/augment ADR to the detection/wiring leaf**, and any
  PRD/reference doc to a docs leaf — the core mechanism rests on *unvalidated*
  empirical assumptions (AX pane-count semantics, herdr-client fg-command,
  server-focus tracking — Verifications #1/#2). Writing binding docs before those are
  confirmed risks recording something false. The running log (D1–D9) + leaf briefs are
  the durable design record until then (grove constraint 4: lazy/just-in-time).
- Dangling refs to the deleted terminal-backends ADRs/PRD are pre-existing debt,
  out of scope here; noted in root BRIEF pointers as an optional future cleanup.

## Decomposition (revised post-doubt-review)

Ordered work leaves under the root. herdr owns top-level hjkl in both trees; augment =
replace + `i` iTerm-splits drill. Each leaf: implement + test + doc-touch.

1. **herdr mux backend + detection validation** (`muxes/herdr.sld`). **First, validate
   the load-bearing assumptions with a live herdr-in-iTerm client:** #1 fg-command is
   `herdr`; #2 server-focus tracks OS focus; **#3 does the socket API scope per
   client/tty/session?** (R6). If a validation fails, **decompose this leaf** (the
   detection approach changes). Then: the `'mux` `<terminal-backend>` (internal
   CLI-driven ops; split l/u = split+swap targeting the **returned pane_id**, R7;
   detect-fg + focused-pane-id + digit-jump + zoom + `configured? #t`), `register!`,
   PATH-prefixed `run-shell`, and a **compact/nested JSON extractor** (R5 — check for an
   existing portable JSON helper first). Backend op tests. → façade pane ops route to herdr.
2. **Detection classifier + variant-tree wiring.** Replace/augment classifier by
   **current-tab session count via AppleScript** (R1, *not* AX). Export iTerm-direct
   pane ops / a `build-iterm-splits-drill` helper from `apps/iterm.sld` (R2).
   **Compose** the context-suffix hook (R4: config → `'install-context-suffix? #f` +
   custom hook delegating to `iterm:context-suffix-handler`, adding the `/herdr` +
   augment cases). Register the two variant screens (skeleton). Tests: classifier +
   **variant resolution actually resolves, not falls back** (R4/R9). Own the
   replace/augment **ADR** (`docs/adr/0013-…`, post-validation). Config wiring in
   `app-trees/com.googlecode.iterm2.scm` + bundled sync ([[feedback_config_sync]]).
3. **herdr tree content** — internal `build-herdr-tree` (R3): pane focus/split/move/
   zoom/close/digit-jump + tabs + workspaces; the `i` iTerm-splits drill (R2 helper);
   live-list blocks `blocks/herdr-{panes,tabs,workspaces}.*`; chip rects (tmux-style,
   **area-relative**) correct in replace mode, augment chips a **documented limitation**
   (R8). JSON-extractor tests (R9).
4. **Agents surface** (planning+work) — agent-status via `herdr pane list`
   (jump-to-blocked, status chips/list). Fuzzy; own grilling.
5. **Worktrees surface** (planning+work) — herdr worktree create/switch UX. Fuzzy;
   own grilling.
6. **Docs + reference** — how-to / reference updates; PRD if it earns its place; ADR
   reconcile.

Optional/deferred: a **focused-iTerm-session-frame primitive** leaf (fixes augment
chips R8; shared cross-cutting helper tmux/zellij also want) — created only if the
limitation bites.

**D10 — Finalised (user).** (a) **Own cleanup leaf** for the dangling
terminal-backends ADR/PRD refs (→ leaf 7). (b) **Grow the tree + complete** now.
Suffix names: `/herdr` (replace), `/herdr+split` (augment — parallels `/zellij+nvim`).
Durable design promoted to the **root BRIEF** (every leaf session reads it via
brief-chain; this retired planning leaf's log is *not* in their bootstrap context).

## herdr CLI facts (for the leaf briefs)

- **Chip rects (tmux-style):** `herdr pane layout` → `{layout:{area:{x,y,width,height},
  panes:[{pane_id, focused, rect:{x,y,width,height}}], zoomed, focused_pane_id}}`, all
  in terminal **cells**. Derive chip pixel rects like tmux: herdr cell coords ÷ canvas
  × iTerm-focused-session AX frame. **Caveat:** the canvas `area` is *offset* (e.g.
  x:26) — herdr paints a left sidebar inside the iTerm session, so map **area-relative**,
  not whole-session.
- **Pane list / agent status:** `herdr pane list` → per-pane `{pane_id, tab_id,
  workspace_id, focused, agent_status:idle|working|blocked|unknown, cwd}`. Feeds both
  digit-jump and the agent surface.
- **IDs:** `w<N>:p<M>` (pane), `w<N>:t<M>` (tab), `w<N>` (workspace). `herdr pane
  current` returns the server's focused pane.
- **Split refocus:** `herdr pane split --direction right|down [--focus]`; left/up =
  split (down/right) `--focus` + `herdr pane swap --direction …`. All JSON-emitting;
  drive via PATH-prefixed `run-shell`, parse JSON.

## Doubt-review reconciliation (fresh-context adversarial pass, all verified vs code)

**R1 (fixes D2 — classifier mechanism was WRONG).** `ax-find-elements-named
"AXScrollArea"` walks the whole focused **window across all tabs**, not visible splits
— `iterm.sld` already compensates (scopes `iterm-list-session-ids` to `current tab`,
drops extra panes when AX > AppleScript count, iterm.sld:429-432,456-457). So an iTerm
window with 1 visible herdr split but a 2nd **tab** would miscount ≥2 → wrongly
"augment." **Fix:** classify by **current-tab session count via AppleScript**
(`sessions of current tab of current window` / the tab-scoped `iterm-list-session-ids`
primitive), not AX. == 1 → replace, > 1 → augment.

**R2 (fixes D3/D7/D8 — iTerm-direct ops are NOT exported; blocker).** `apps/iterm.sld`
keeps `focus-pane-*`/`split-pane-*`/`move-pane-*`/`toggle-pane-zoom` **internal**
(iterm.sld:137-163); the config only ever reached them via the façade. The augment
`i`-drill has nothing iterm-direct to bind. **Fix:** export the iTerm-direct pane ops
from `apps/iterm.sld` **or** (cleaner) have iterm.sld expose a small
`build-iterm-splits-drill` helper. Explicit work in the wiring/content leaf.

**R3 (sharpens D8 — keep the export surface small via internal tree-builders).** Naively
exporting herdr-direct ops for panes/tabs/workspaces/worktrees/agents is a far wider
public surface than the mux precedent (tmux/zellij export only `register!`+`backend`).
**Fix:** herdr.sld exports **tree-builders** (`build-herdr-tree`, block helpers,
context-suffix contribution, `register!`, `backend`) that use the ops *internally* —
mirroring iterm.sld's internal `rebuild-tree!`. Individual ops stay internal. This
resolves R2+the-surface together: libraries own the builders; config composes them.

**R4 (corrects D2 framing + adds config change + a test — variant lookup is UNEXERCISED).**
`set-local-context-suffix!` is a single global last-write-wins slot (event-dispatch.sld:
92-94). The config today calls `(iterm:register! 'install-tree? #f)` **without**
`'install-context-suffix? #f`, so it installs the *bundled* handler — and **no
`/nvim` or `/zellij` variant screen is registered anywhere in the shipping config**, so
`resolve-app-tree`'s variant path has **never been exercised in production**; herdr will
be its first real user. **Fix:** config must become `(iterm:register! 'install-tree? #f
'install-context-suffix? #f)` + a composed `set-local-context-suffix!` delegating the
iTerm branch to `iterm:context-suffix-handler`; and the wiring leaf must **test that
variant lookup resolves** (not silently falls back). "Mechanism already works" was too
rosy — it's implemented-but-never-activated.

**R5 (fixes D5/D6 — JSON parsing is real work; zellij's parser does NOT transfer).**
herdr emits **compact single-line** JSON; zellij's awk parser is hard-wired to
pretty-printed multiline (zellij.sld:129-157); tmux avoids JSON entirely via format
strings. herdr needs a **net-new** extractor for compact + **nested**
(`layout.panes[].rect.{x,y,w,h}`) JSON, staying inside the portability gate (no lispkit
json lib). **Fix:** backend leaf builds it — first check for an existing portable JSON
helper in the tree (the renderer pushes JSON); a small pure-Scheme reader may beat
fragile awk for nested shapes.

**R6 (elevates D5/D6 multi-client to a documented limitation + Verification #3).**
`herdr pane current` = the server's **global** focus. The augment case is *by
definition* multiple iTerm panes; if two attach herdr clients, `herdr pane current`
can't tell which is OS-focused, and Modaliser drives herdr out-of-band via `run-shell`
(not through the focused client), so server-focus need not track OS-focus. tmux/zellij
solve this with tty-correlation (ADR-0006 lineage); herdr may offer no per-client
scoping. **Fix:** **Verification #3** — does herdr's socket API support per-client /
per-tty / per-session scoping? If not, **multi-herdr-client is a documented v1 non-goal**
(common case = one herdr client, unambiguous). Not merely "deferred."

**R7 (mitigates split race, D-CLI).** split-left/up is two async `run-shell`
round-trips (`split --focus` then `swap`); if `split` returns before the server focuses
the new pane, `swap` acts on stale focus (tmux/zellij splits are single calls).
**Fix:** target `swap` at the **explicit new pane_id** returned by `split`'s JSON,
not "current"/direction — removes the race. Backend-leaf detail.

**R8 (known limitation — augment chip rendering targets the wrong split).** The
host-frame helper takes `(car panes)` = first AXScrollArea (tmux.sld:265-268,
zellij.sld:318-321 both flag this v1 soft spot); augment *is* multi-split, so `car` is
likely wrong, and there is no "which AXScrollArea is the focused iTerm session"
primitive. **Accept visibly:** chips are correct in **replace** mode (one AXScrollArea);
in **augment** mode accurate chips need a new focused-iTerm-session-frame primitive —
**documented v1 limitation** (hjkl focus still works; digit-jump is secondary). Optional
follow-up leaf (shared cross-cutting helper tmux/zellij also want).

**R9 (expands test scope, fixes D8).** Tests must cover the **novel** logic, not just
op dispatch: (a) the current-tab-session-count classifier (R1), (b) the composed
context-suffix + variant resolution (R4), (c) the compact/nested JSON extractor (R5).

**R10 (perf note).** `walk-path` is uncached and runs per façade op + capability
predicate (terminal.sld:200-227); herdr's detect-fg adds a socket round-trip per
descent. The herdr trees use **direct** ops (not façade) so keystroke-time is fine, but
each leader press still pays AppleScript session-count + (maybe) a herdr call in the
suffix handler. Acceptable; note it, revisit if sluggish.

**R11.** Confirms D9 (stale ADR/PRD refs are pre-existing debt, correctly scoped out).
