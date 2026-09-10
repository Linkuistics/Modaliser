# configuration-design-k5


## Goal

Synthesize the three surveys into a coherent exploratory design for user-owned
layout and configuration over app-control facilities. Write
`docs/specs/configuration-exploration.md`, clearly marked **proposed/exploratory**.



## Context

Read the shared context and `docs/research/layout-controls-a.md`,
`docs/research/app-facilities-a.md`, and
`docs/research/configuration-runtimes-a.md`. The user's decisions are in
`configuration-exploration-k1`. This is an agreement artifact to discuss, not an
accepted implementation specification.

## Done when

- Present two or three coherent overall approaches with a provisional
  recommendation and evidence that could change it.
- Show how each addresses an editor list grouped with previous/next controls,
  independently placed other commands, and stable groups under wider list titles.
- Define the conceptual interface between app Facilities, user Decisions,
  Configuration value/dispatch, and Display value/layout. Keep semantic grouping
  distinct from navigation and key ownership.
- Make responsive sizing, wrapping/truncation, dynamic snapshots, callback
  ownership, errors, compatibility, and runtime lifecycle concrete enough to
  compare; describe validation obligations without claiming they were tested.
- Compare both front-end-only change and runtime replacement. Give a reasoned
  language shortlist while preserving the user’s choice and identifying costs.
- Resolve contradictions between surveys; retain material uncertainty rather
  than silently selecting favorable claims. Cite survey evidence near conclusions.
- Record a short list of unresolved user choices and future experiments; neither
  runnable experiments nor implementation planning are authorized in this Grove.
- Existing accepted ADRs and current behavior documentation are not rewritten as
  though the proposal has been accepted. Only exploration documents change.

## Notes

Do not ask again whether to compare both runtime approaches or whether list
contents may rearrange groups: both are settled. Propose wrapping/truncation as
user controls. A real design review may be added if the resulting artifact earns
one; it remains documentation-only. Do not create implementation leaves, invoke
an implementation plan workflow, or perform a prototype.

### Source checks raised while the surveys ran

The coordinator found the following potentially load-bearing overstatements in
`app-facilities-a.md`. Verify them against the cited source and correct the survey
in place before building the synthesis on it. This is part of this leaf's
existing reconciliation goal; it does not require another broad survey.

- Its Swift-plugin option assumes every native plugin must expose LispKit's
  `NativeLibrary`/`Expr`. That describes an extension of the current registration
  mechanism, not every possible plugin design. Evaluate a Swift facility module
  with an app-owned semantic interface and a separate language adapter, including
  source modules built with the app, a versioned native boundary, and helpers.
- Absence of a standard Swift plugin-discovery API does not establish that native
  plugins are impossible or that Swift types cannot cross any binary boundary.
  [Swift library evolution](https://www.swift.org/blog/library-evolution/)
  distinguishes separately distributed frameworks from modules built together;
  do not require every app and plugin to enable evolution indiscriminately.
  [Apple's bundle loading guide](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/LoadingCode/Tasks/LoadingBundles.html)
  is a primary example of discovering/loading a principal class. Distinguish the
  bootstrap mechanism, interface ABI, and concrete payload types, and state what
  remains unproven for a Swift implementation.
- Library validation is conditional on signing policy. Apple's
  [Code Signing Tasks](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html)
  describes Apple-signed and same-Team-ID libraries as allowed. Loading arbitrary
  differently signed plugins with validation enabled is a different case from
  bundled or same-team code. Correct the claim that notarization inevitably
  requires disabling validation for every plugin design.
- `KeyboardLibrary.fireHotkeyHandler` and `registerAllKeysFunction` explicitly
  dispatch evaluation to the main queue; the tap has its own thread. The survey
  incorrectly says evaluation is "inside the keyboard tap". Main-thread blocking
  and input buffering still matter, but they are not execution on the tap thread.
- Request IDs correlate requests/replies; they do not alone prove a cancellation
  protocol. Check the Neovim comparison's cancellation cell or mark it unknown.
- Qualify claims such as "skew impossible", "invariant coverage complete",
  "inherits facilities for free", and WIT being the "only mature answer". Source
  evidence supports narrower claims; new-language adapters and operation types
  still need design. Do not turn preferences into technical impossibilities.

Two small issues remain in `layout-controls-a.md` / the shared context:

- The current-syntax example mixes the sugar `panel` with bare key-reference
  strings in `(panel "Find" "p" "P" "/")`. Replace those peer examples with
  prose or correct existing key nodes; do not copy invalid syntax into the spec.
- Narrow the shared context's `@supports` claim to the inspected source/default
  rule; "anywhere in the tree" is unnecessary and also matches the research
  documents discussing it. Treat markers such as **[inf]** as inference, not a
  claim of proof (the current surveys say "Sound, unobserved").
- Define span behavior when an arrangement reduces to one column. The comment
  beside `.panel-span-wide` in `base.css` assumes a span of two clamps to one
  explicit track; [CSS Grid's placement algorithm](https://drafts.csswg.org/css-grid-1/#auto-placement-algo)
  instead adds implicit columns when an unpositioned item's span needs them.
  Do not inherit that comment as proof. Specify normalization, rejection, or an
  explicit responsive placement rule and list the corresponding validation case.

Keep corrections targeted. Preserve useful evidence and recommendations wherever
they survive the source checks; explain any material change to the recommendation.

### Synthesis guardrails

- Keep the recommendation centred on the requested configuration, layout, and
  facility separation. Historical LispKit performance observations may inform
  migration costs; they do not turn this exploration into a bug-fix programme.
- Compare constrained declarative configuration fairly. A set of named operations
  alone cannot express arbitrary user joins, but a data representation can include
  sequencing, conditionals, bindings, and an expression language. That is an
  additional language/interpreter to design, not a proof that declarative
  composition is impossible. Preserve arbitrary resident user closures as the
  baseline capability unless the user chooses to reduce it.
- Distinguish content-driven automatic placement from constrained placement.
  Flow can keep line membership stable when child widths and the available-width
  budget stay fixed; masonry can pin lane assignments while allowing independent
  vertical stacking. Assess those choices alongside aligned grid instead of
  declaring every form of flow or masonry incompatible with stable groups.
  Define stability as membership/order/track assignment, and explain whether
  wrapping may move later content vertically. Width-driven responsive changes
  must use available display space, not a viewport sized by the content itself.
- The runtime survey is receiving a targeted primary-source correction pass for
  private JavaScriptCore ESM APIs, TypeScript transform packaging, Racket retained
  handles, current SBCL shared-library embedding, Lua bridge/error ownership,
  Swift ARC versus tracing GC, and unproved absolute claims. Build on the corrected
  version; do not resurrect the original stronger claims in the summary.
  Recheck these specific residual sentences before finalising: "third collector
  beside Swift ARC" (ARC is reference counting), Lua "no bridging layer to write"
  (C import does not provide marshalling, rooting, callback ownership, or safe
  error unwinding), and any claim that only Lua supports protected evaluation.
  The coordinator retrieved SBCL manual section 9.8.1 successfully: it documents
  `initialize_lisp` and states that C cannot currently run exit hooks or gracefully
  undo Lisp initialisation. That is an evidence-based lifecycle cost to compare
  with an app-lifetime embedded runtime or a restartable helper process.
  **`JSScript.h` is private too**, including its bytecode cache: WebKit's
  [Xcode project](https://raw.githubusercontent.com/WebKit/WebKit/main/Source/JavaScriptCore/JavaScriptCore.xcodeproj/project.pbxproj)
  marks `JSScript.h in Headers` as `ATTRIBUTES = (Private, )` (line 1274 at
  consultation), while `JSContext.h` is Public. Availability annotations alone
  do not establish public API. Correct runtime-survey prose, tables, sources,
  and recommendations that still call JSScript/cache public or a free benefit.
  Single-file TypeScript still needs a shipped type-stripper or an authoring
  transform; choosing a single file or module shim does not remove that cost.
