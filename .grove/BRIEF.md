# research-reimplementation-using-tauri — brief

## Goal

**Bootstrap a new peer project, `KeyEveryware-JSC`**, and seed a grove inside it to
reimplement the Modaliser exemplar on a new stack — **Tauri v2** (Rust host) +
**JavaScriptCore** runtime + **TypeScript** configuration — replacing the current
Swift/AppKit + LispKit + Scheme stack. The driving motivation is swapping the
config language Scheme→TypeScript for popularity; a better web-first UI host and
Rust tooling come along for the ride. This is a curiosity/learning POC, **not** a
deprecation or migration of Modaliser (which is reframed as `KeyEveryware-LK`, the
LispKit variant of a `KeyEveryware` family).

## Done when

- `~/Development/KeyEveryware-JSC` exists as a fresh git repo with a legible shell
  (README, CLAUDE.md, .gitignore, `docs/{adr,research,prd}/`).
- That repo carries a warm grove seed (`BOOTSTRAP.md`) that names the mandate, the
  confirmed stack, the first vertical slice, and the downstream research questions.
- The user can start the reimplementation by running `grove do <name>` in the new
  repo. No reimplementation code is built here (thin bootstrap).

## Decomposition

- `01-plan-k1` (planning, done) — grilled the scope; all decisions in its running
  log (D1–D7) and the seed material it drafted.
- `bootstrap-peer-repo` (work) — scaffold the peer repo shell + author the seed.

## Pointers

- Exemplar being reimplemented: this repo (Modaliser / `KeyEveryware-LK`). Its
  native surface (15 `*Library.swift` bridges, `SchemeEngine.swift`, `root.scm`)
  is the behavioural spec for the new project.
- Seed material + downstream research questions live in `01-plan-k1.md`.

## Notes

- Out of scope (deferred follow-up): renaming Modaliser → `KeyEveryware-LK`
  (touches Homebrew tap, bundle ID, TCC signing).
- No `CONTEXT.md` (Modaliser glossary) edits: KeyEveryware terms belong in the new
  project's own glossary.
