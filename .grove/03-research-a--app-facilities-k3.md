# app-facilities-k3


## Goal

Produce `docs/research/app-facilities-a.md`: compare ways to separate app-control
machinery from user composition, including possible Swift-based plugins.



## Context

Read `docs/research/configuration-exploration-context.md`, especially Facilities
and plugins and Shared scenarios. ADR-0021 is the baseline, not a new proposal.
The downstream `configuration-design-k5` needs a semantic facility interface and
ownership/lifecycle choices that can serve all candidate configuration languages.

## Done when

- Trace the VS Code example's discovery, editor/terminal providers, listing,
  activation, and Grove Leaf composition far enough to distinguish machinery
  from user choices. Explain avoidable user wiring without reclaiming preferences.
- Compare app-bundled modules, independently delivered in-process Swift plugins,
  and process-separated helpers. Distinguish source plugins, compiled binaries,
  and controlled-app companions.
- Compare a direct native interface and a language-neutral semantic interface;
  cover queries/actions, entity identity, availability/errors, snapshots,
  optional subscriptions, and where a language adapter belongs.
- Cite primary evidence for Swift/library interoperability, distribution and
  macOS loading constraints. Address compatibility, main-thread work,
  cancellation, crashes, and resource lifetimes without assuming an ABI is solved.
- Preserve the separation of Facilities from Decisions and discuss the existing
  inert outward test seams. Include relevant prior art and walk-away checks.
- Deliver alternatives, provisional recommendation, evidence gaps, and questions
  for design. No implementation, installations, or plugin scaffolding.

## Notes

Documentation only. Swift plugins are an option the user wants investigated, not
an accepted binary format or a requirement to ship third-party plugin loading.
