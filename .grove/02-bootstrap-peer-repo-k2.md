# bootstrap-peer-repo-k2

**Kind:** work

## Goal

Create the new peer project `KeyEveryware-JSC` as a fresh git repo at
`/Users/antony/Development/KeyEveryware-JSC` (sibling to `~/Development/Modaliser`),
give it a legible shell, and author a warm grove seed so the reimplementation can
start with `grove do <name>` there.

## Context

- This is the single work leaf of the `research-reimplementation-using-tauri`
  bootstrap grove. All scoping decisions (D1–D7) and the full **seed material**
  (new-project mandate, the eight downstream research questions Q1–Q8, the
  candidate first ADR, the `BOOTSTRAP.md` mechanic) are in the planning leaf
  `plan-k1` → `.grove/01-DONE-plan-k1.md`. **Read that leaf first** — it is this
  leaf's spec.
- Thin bootstrap (D5): **do not** run `create-tauri-app` or build any
  reimplementation code. Producing the runnable Tauri v2 + TS skeleton is the
  *new* grove's first build leaf.
- The repo is outside this worktree/repo; operate on the external path directly.

## Done when

1. `/Users/antony/Development/KeyEveryware-JSC` is a fresh git repo (`git init`,
   default branch `main`) with an initial commit.
2. Legible shell present:
   - `README.md` — the KeyEveryware family framing, this project's goal, and the
     confirmed stack (Tauri v2 + JavaScriptCore + TypeScript config).
   - `CLAUDE.md` — project instructions: what KeyEveryware-JSC is, that it's driven
     with grove, that `../Modaliser` is the behavioural exemplar, and how to start
     (`grove do <name>` → `root-init` → fill root brief + first leaf from
     `BOOTSTRAP.md`).
   - `.gitignore` — sensible defaults for a Rust/Tauri + TS project (target/,
     node_modules/, dist/, .DS_Store, etc.).
   - `docs/adr/`, `docs/research/`, `docs/prd/` (keep with `.gitkeep` if empty).
3. `BOOTSTRAP.md` at the repo root carries the seed: mandate, stack, the D4 first
   vertical slice, and the Q1–Q8 downstream research questions (grouped by the leaf
   each informs), transcribed/refined from `plan-k1`'s seed material.
4. `main` does **not** carry a `.grove/` tree (the first `grove do` session creates
   it via `root-init`, filling from `BOOTSTRAP.md`).

## Notes

- Verify with `git -C /Users/antony/Development/KeyEveryware-JSC log --oneline` and
  a `find` of the new tree before completing.
- If this proves bigger than one focused session (e.g. you want to split scaffold
  from seed-authoring), `grove-llm leaf-decompose` this leaf and do only the first
  child — but per D5 it should fit one session.
- After this leaf, the bootstrap grove has no live leaves → it reaches Finish; the
  reimplementation continues in the new repo's own grove.
