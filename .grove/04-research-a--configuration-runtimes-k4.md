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
