# plan-k1

**Kind:** planning

## Goal

Plan a POC/spike that reimplements the Modaliser exemplar as a **new sibling
project, `KeyEveryware-JSC`**, using **Tauri v2** (Rust host) + **JavaScriptCore**
runtime + **TypeScript** as the configuration language — replacing the current
Swift/AppKit + LispKit + Scheme stack. Grill the design tree, commission
prior-art research where the stack is unfamiliar, and grow the grove into
concrete build leaves.

## Context

- Modaliser (this repo) is an **exemplar**: a reference app to be reimplemented
  in different ways to compare approaches. It is renamed **`KeyEveryware-LK`**
  (LispKit variant) in the family framing. Nothing here is deprecated.
- Primary motivation: **replace the config language Scheme → TypeScript** (more
  popular). Secondary: better web-UI story (Tauri/WRY web-first), Rust ecosystem.
- Trigger: the dev.to "macOS menu bar app with Tauri v2" guide; a curiosity /
  learning / POC exercise, not a production migration.
- Current native surface to (selectively) reproduce: 15 `*Library.swift` bridges,
  ~6.7k lines Swift (much macOS-only: AX, CGEvent taps, NSPanel overlays),
  ~11k lines Scheme.

## Done when

- The grove tree is grown with concrete downstream leaves (research + build).
- The key architectural forks are decided or explicitly deferred to a research
  leaf (see running log).

## Decisions (running log)

### D1 — What this grove is (motivation + framing)  [settled]

A new sibling project **`KeyEveryware-JSC`** reimplements the Modaliser exemplar
on **Tauri v2 + JavaScriptCore + TypeScript config**. Existing Modaliser becomes
**`KeyEveryware-LK`**. Motivation, in priority order: (1) swap the config language
Scheme→TypeScript for popularity; (2) better web-first UI host; (3) Rust
ecosystem/tooling. Explicitly a curious POC/spike, **not** a deprecation or
production migration of Modaliser.

### D2 — This grove's deliverable  [settled]

This grove **bootstraps a new peer project** `KeyEveryware-JSC` (a fresh git repo,
sibling to the Modaliser repo) and **seeds a grove inside it** that does the actual
reimplementation work. This grove's outputs are the new repo skeleton + its grove
root brief/first leaf — not the reimplementation itself.

### D3 — Handoff line (thin bootstrap)  [settled]

This grove is a **thin bootstrap**: (a) confirm stack/naming, (b) choose the first
vertical slice, (c) scaffold the peer repo skeleton + tooling stubs, (d) seed the
new grove's root brief + first planning leaf, **naming the downstream research
questions** (per driving.md). ALL research / design / build happens in the new
grove. Corollary: no Modaliser-glossary (`CONTEXT.md`) edits here — KeyEveryware
terms belong in the new project's own glossary, carried by its seed brief.

### D4 — First vertical slice  [settled]

**Leader → overlay → launch app / run command.** Global leader hotkey → which-key
overlay (Tauri webview) → type a sequence → launch an app or run a shell command.
Chosen because it touches all four layers (host hotkey, webview overlay,
TS-in-JSC config, one native action) and the two riskiest unknowns (global hotkey
capture + running TS config through JSC), while keeping the native action trivial
(`open`/NSWorkspace). Defers the AX window-management integration to a later slice.

### D5 — Scaffold depth  [settled]

**Legible shell + grove seed only.** The peer repo gets: README (family framing +
goal), CLAUDE.md, .gitignore, `docs/{adr,research,prd}` dirs, and the grove seed.
**Do NOT run `create-tauri-app` here** — producing the runnable Tauri v2 + TS
skeleton is the new grove's *first build leaf*, because it depends on TS-toolchain
research (D-research Q2). This avoids pre-committing project structure.

### D6 — Peer repo location  [settled]

`/Users/antony/Development/KeyEveryware-JSC` — a fresh, independent git repo,
sibling to `/Users/antony/Development/Modaliser`.

### D7 — LK rename deferred  [settled]

Renaming the existing Modaliser → `KeyEveryware-LK` is **out of scope** for this
grove and any grove now. It touches the Homebrew tap, bundle ID, and TCC
code-signing identity (stable-signing requirement), and is unrelated to the POC.
Recorded here as a **future follow-up workstream**, not a leaf.

## Seed material — draft for the bootstrap work leaf

This is the content the bootstrap leaf transcribes into the new peer repo. The
recommended mechanic: a comprehensive `BOOTSTRAP.md` at the new repo root (the
new grove's first `grove do` session runs `grove-llm root-init` and fills its root
brief + first planning leaf from it — keeping `main` clean of `.grove/` until the
grove actually starts, per the grove invariant that the default branch carries no
grove state).

### New project mandate (for the new grove's root brief)

Reimplement the **Modaliser exemplar** (`../Modaliser`, the LispKit variant) as
**`KeyEveryware-JSC`** on a new stack: **Tauri v2** (Rust host) + **JavaScriptCore**
runtime + **TypeScript** configuration. This is a curiosity / learning POC to
compare a TS-config approach against the Scheme-config original — not a production
tool. Reference the Modaliser source freely as the behavioural spec; the exemplar
is the sibling repo. First milestone = the D4 vertical slice.

### Downstream research questions (name them in the seed; the new grove answers them)

Grouped so the seed brief can point each downstream leaf at its evidence base:

- **Q1 — JSC embedding.** How does TS/JS config execute? (a) embed JavaScriptCore
  in Rust (`rusty_jsc` / `javascriptcore` crate) and run config there; (b) run
  config in the Tauri webview's JS context (WKWebView *is* JSC on macOS) and bridge
  to Rust; (c) a JS-engine sidecar. Which gives the cleanest host-primitive binding
  surface (the NativeLibrary equivalent)? Informs the runtime-architecture leaf.
- **Q2 — TypeScript toolchain.** How does `config.ts` become runnable? Transpile
  (esbuild/swc/tsc) at build vs. at config-load; how config is loaded and whether
  it hot-reloads (Modaliser does *not* — relaunch only); shipping `.d.ts` types for
  the config API. Informs the first build leaf (project scaffold) and config-loading
  leaf.
- **Q3 — Global leader/hotkey capture.** Can Tauri v2 capture *and suppress* a
  global leader key + the following sequence? Tauri `global-shortcut` plugin vs. a
  lower-level CGEvent tap via `objc2`/`core-graphics` from Rust. Modaliser uses a
  CGEvent tap with re-injection tagging — what's the Rust analogue? Informs the
  keyboard-capture leaf. (Needs Accessibility permission — see Q7.)
- **Q4 — Menu-bar (tray) app.** Dock-less (LSUIElement-equivalent) tray presence +
  activation policy in Tauri v2 (the dev.to guide's subject). Informs the scaffold
  leaf.
- **Q5 — Non-activating floating overlay panel.** Can Tauri create a borderless,
  always-on-top, **non-activating** webview panel that doesn't steal focus (the
  NSPanel behaviour Modaliser's which-key overlay + chooser rely on)? Known Tauri
  pain point; investigate the `tauri-nspanel` community crate. Informs the overlay
  leaf.
- **Q6 — Host-primitive bridge.** The equivalent of Modaliser's 15 `NativeLibrary`
  bridges: how does TS config call Rust host primitives (Tauri commands / IPC),
  and what API shape is exposed to config (launch app, run shell, …)? Informs the
  runtime-architecture + config-API leaves.
- **Q7 — Permissions & signing.** Accessibility (AX) needed even for slice 1 (the
  global hotkey tap requires it); the permission-onboarding flow; and stable
  code-signing so TCC grants survive rebuilds (parallels the Modaliser codesigning
  constraint). Informs the permissions leaf.
- **Q8 — App-launch primitive.** The trivial slice-1 action: `open`/NSWorkspace
  from Rust. Is fuzzy app-scanning in slice 1 or deferred? Informs slice-1 build.

### Candidate first ADR for the new project (do NOT write here)

`adopt-tauri-jsc-typescript-stack` — the stack choice is a real trade-off and
hard-to-reverse (ADR-worthy), but it belongs in the *new* repo and should be
written by the new grove **after** Q1–Q2 research confirms feasibility. Seed it as
a candidate, not a committed ADR.

## Tree plan

One work leaf grows from this planning leaf:

- **`bootstrap-peer-repo`** (work) — create `~/Development/KeyEveryware-JSC` (git
  init on `main`), write the legible shell (README, CLAUDE.md, .gitignore,
  `docs/{adr,research,prd}/`), and author `BOOTSTRAP.md` from the seed material
  above. Kept as one leaf per D5's thin-bootstrap decision; the work session may
  `leaf-decompose` if it proves bigger.

## Notes

- The new repo is *outside* this worktree and this Modaliser repo — the bootstrap
  leaf operates on an external path. That's intentional (D2/D6).
- Handoff: once the peer repo exists and is seeded, the user starts the new grove
  with `grove do <name>` inside `~/Development/KeyEveryware-JSC`.
