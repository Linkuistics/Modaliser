# Follow-ups discovered during Phase-3 tutorial execution (2026-05-20)

These are non-blocking discoveries logged during execution of
`docs/superpowers/plans/2026-05-19-docs-phase3-tutorial-modal-thinking.md`.
The tutorial work proceeded around them per the plan's *Out of scope*
guidance ("log a follow-up note in `docs/superpowers/plans/` and
proceed with whatever shape the existing libraries support").

## 1. Uppercase layout-block keys (D/F/G/C/V/B) do not fire

**Symptom.** During Task 6 (Step 3) verification, the `window:layout-block`
half-thirds row

```scheme
(("D" "F" "G")
 ("C" "V" "B"))                  ; half thirds
```

renders correctly (the diagram strip paints the letters in their
3×2 cells) but pressing those keys produces no window-snap. Lowercase
keys (`d f g e t m c`) in the same `layout-block` fire correctly.

**History.** The user reported these uppercase bindings *used to work*
in their previous Modaliser build. Pre-existing regression, unrelated
to the tutorial slice (no code changed in `Sources/`).

**Likely investigation paths.**

1. State-machine key matching when the Shift modifier is set. The DSL
   stores the bare key string ("D"), but the keymap layer may emit
   `"d"` + a Shift mask, and the route-by-string match in
   `state-machine.sld` may not normalise.
2. `layout-block` / `parse-matrix` may downcase or normalise key
   strings during cell-binding generation in `window-actions.sld`,
   stripping the uppercase distinction at config-load time.
3. The renderer (window-diagram.js) may paint uppercase letters
   visually but `block-children` may be generated with the lowercased
   variant.

**Workaround in the tutorial.** Step 3's snippet drops the half-thirds
row entirely. The pedagogical point (a block paints chrome and binds
spatial keys) survives. The prose mentions that `default-config.scm`
adds a denser half-thirds row, with the same form — a reader who tries
the bundled config and notices the missing fires will find this
follow-up note.

**Owner / when.** Bundle into the next `window-actions` / `state-machine`
edit. Not a docs-slice concern.

## 2. Selector matcher threshold is too strict

**Symptom.** The `(selector …)` in `default-config.scm` (and in the
tutorial's Step 4) is bound to `(modaliser fuzzy)`'s DP-based
matcher. On window lists with five-to-ten entries, the matcher
effectively requires the user to type nearly the entire window title
before the right entry is selected; a few subsequence characters
("saf" for "Safari — Apple Developer Documentation") are not enough.

**User reaction during Step 4 verification.** "The selector doesn't
work because it requires the full window name in the input box.
It feels like it is using the input box to match the title, not the
selected item in the list."

**Likely investigation paths.**

1. `FuzzyMatcher.match` in `Sources/Modaliser/FuzzyMatchLibrary.swift`
   — the scoring may be tuned too tightly toward contiguous matches.
2. The chooser UI may be reading raw score thresholds and refusing
   to highlight low-score entries — even when there are no better
   candidates, the user wants the *best available* highlighted.
3. Possible mismatch between what the matcher gets fed (just `text`?
   `text + subText`?) and the strings the user expects to match
   against.

**Workaround in the tutorial.** Step 4's prose has a callout block
warning the reader the matcher is conservative. The selector concept
is still introduced (it's a core Modaliser pattern); the prose just
sets the right expectation.

**Owner / when.** Bundle into the next `FuzzyMatchLibrary` /
chooser-UI edit. Worth investigating before public release
(2026-W21) — first impressions of a fuzzy-finder that doesn't fuzz
will be poor.
