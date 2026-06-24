# alist-json-extract-k37

**Kind:** work

## Goal

Assess and (if worthwhile) extract the overlay's generic JSON serializer (audit
finding D) — `alist->json` + its helper `every-pair-symbol-keyed?` — into a
shareable form, or conclude it stays UI-local.

## The candidate

- `alist->json`              `ui/overlay.scm:671`  — dispatches string/number/
  symbol/boolean/null/alist/list → JSON text.
- `every-pair-symbol-keyed?` `ui/overlay.scm:695` — alist-vs-list discriminator
  used by `alist->json`.

It is a genuinely generic value→JSON serializer EXCEPT it hard-codes the overlay's
escaper (`js-escape-overlay`) and the comma join (`string-join-comma`, removed in
k35 → now `string-join`).

## Sequencing

**Do after k36.** The coupling to the escape flavor is the main obstacle to
making this portable; k36 decides whether a parameterised escaper exists and where
it lives. With a pluggable escaper, `alist->json` could take the escaper as an
argument and move to a `(modaliser …)` library; without one, it stays UI-local.

## Open question

Is there a second consumer that would justify extraction, or is the overlay the
only caller? If overlay-only, the right answer may be **"leave local"** — record
that and close the leaf cheaply. Extraction earns its place only with a real
second user or a clear portability win.

## Done when

- A decision (extract → which library, with a pluggable escaper; or leave local)
  with reasoning, and the chosen change landed.
- If extracted: tests cover the serializer; `check-portable-surface.sh` green.

## Notes

- Don't write the literal `(lispkit ` token in any portable-tree file or comment.
