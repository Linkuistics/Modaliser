# configuration-runtimes-k4


## Goal

Produce `docs/research/configuration-runtimes-a.md`: an evidence-based comparison
of Racket, Common Lisp on SBCL, TypeScript, Lua, and the current LispKit/Scheme
baseline for user configuration and runtime architecture.



## Context

Read `docs/research/configuration-exploration-context.md`, especially Configuration
languages and runtime and Shared scenarios. The user explicitly confirmed both
front-end-only change and full Scheme-runtime replacement are in scope.
The downstream `configuration-design-k5` needs coherent language/runtime choices,
not a language popularity ranking.

## Done when

- Compare all four candidates and baseline using primary documentation.
- For each, specify a credible execution/deployment shape and distinguish facts
  from engineering inference: startup-only frontend, resident configuration
  runtime, and full replacement are different options.
- Cover ordinary composition, callback closures and captured state, dynamic
  providers, async work, errors, module resolution, native interoperability,
  tooling/diagnostics, packaging, and host event-loop ownership.
- TypeScript is paired with a specific plausible JavaScript runtime and transform
  pipeline; Common Lisp is distinguished from SBCL. Verify current embedding
  support instead of assuming SBCL cannot embed or using obsolete Racket/Lua facts.
- Apply candidates to the editor group and cross-facility action. Explain what a
  serialized description cannot preserve by itself and how live behavior would
  cross any proposed boundary.
- Compare migration/coexistence costs at design level. Do not promise support for
  all languages merely because a language-neutral contract is attractive.
- Cite performance evidence if available; otherwise mark startup, memory, input
  latency, and packaging measurements as unmeasured. Include walk-away checks.
- Produce conditional recommendations and research gaps, with no implementation
  code, dependency installs, benchmarks, or modification of personal configuration.

## Notes

Documentation only. Research current official docs: runtime hosting and macOS
distribution are load-bearing. The existing no-hot-reload policy remains the
baseline; any change must be proposed explicitly, not assumed from REPL support.

## Decisions (running log)

**Output path.** `docs/research/configuration-runtimes-a.md`, per the research
family rule that the kind decides the suffix. A later `-b` survey renames nothing.

**The three questions are separated rather than merged.** Authoring surface,
where the runtime lives, and who owns the native boundary are treated as three
independent axes. The coordinator's note is adopted: the current
`NativeLibrary`/`Expr` bridge is one possible native boundary, not the boundary,
so no candidate is scored against it as if it were fixed.

**Corrected from the sibling survey's frame: evaluation is asynchronous to the
event tap.** Verified at source — the tap runs its own thread and run loop
(`KeyboardCapture.swift:92`), `fireHotkeyHandler` installs a buffer and then
dispatches to the main queue (`KeyboardLibrary.swift:183-189`), and the comment
there states the intent: keystrokes keep buffering while Scheme runs. A slow
runtime therefore costs overlay latency, not dropped keys. This changes how the
latency axis is scored for every candidate.

**The discriminating axes are drawn from measured local defects, not a feature
matrix.** Three baseline properties do the discriminating: Θ(n) `string-ref`
(the 27 s stall recorded in `instrument.sld`), the absence of re-entrant
protected evaluation (ADR-0022's whole design), and the immutable-pair/absent-
stdlib stance. A generic language-features table would not have found any of them.

**The language surface the existing tree actually uses was measured, not
assumed.** 1 536 `define`s, 3 `define-syntax`, 3 `define-record-type`, 0
`dynamic-wind`, 0 `call-with-current-continuation`, 308 `(assoc`. The tree is
procedures + alists + parameters + `guard`, not macrology — which is what makes
full replacement arguable at all, and what removes "we need Scheme's macros" as
a defence of the baseline. Measured with an unaliased `grep` under positive and
negative controls after `grep`/`cat` were found aliased to `ugrep`/`bat` and
zsh's no-word-splitting default had silently voided two earlier readings.

**Racket's R7RS support is a package, not a core path.** This matters because it
converts "port the tree" from a hypothesis into a bounded, caveated option; the
caveats (restricted `define-library`, `cons` as `mcons`, `include-ci` absent) are
documented and recorded rather than assumed away.
