# Configuration exploration: scope and current baseline

Exploratory context, 2026-09-10. This records the problem and inspected current
behavior. It does not select a language, approve a plugin architecture, or
authorize implementation.

## User intent

Give users more control over UI layout, including grid, flow, and masonry;
separate the facilities needed to control an app from how users compose those
facilities in configuration; investigate Racket, Common Lisp on SBCL, TypeScript,
and Lua. Compare both a new user configuration language over existing runtime
machinery and replacement of the current Scheme runtime.

The concrete example is the VS Code screen. The user wants to split its non-list
elements into groups and place the editor list with the previous/next editor
controls. They also observe that layout changes with list widths. The design must
distinguish author-controlled grouping, response to available display width, and
changes caused by the contents of a list.

The user subsequently selected **keep groups stable; wrap or truncate titles**.
Content-driven rearrangement is therefore a behavior to prevent by default in the
proposed design. Responsiveness to available display width is a distinct question.

## Current behavior, grounded in source

The baseline is `main` at `8f4c30f4`, following the v4.3.0 work. The initial
research change contains only the new Grove and documentation.

| Area | Inspected evidence | Implication for the investigation |
| --- | --- | --- |
| Display and dispatch | [Display DSL](../../Sources/Modaliser/Scheme/lib/modaliser/display-dsl.sld), `resolve-display`, `with-display`; [ADR-0011](../adr/0011-dispatch-structure-with-attached-display.md) | There is already a disjoint attached Display value. New layout composition should preserve that separation. |
| Layout controls | The Display DSL's `layout`, `cols`, `span`, and `order` constructors | `layout` accepts masonry and grid; columns are positive integers; spans are narrow/wide/full; row order is keys/declared. Flow and arbitrary layout nesting need a design beyond this constructor vocabulary. |
| Renderer structure | [Overlay JavaScript](../../Sources/Modaliser/Scheme/ui/overlay.js), panel-grid renderer | Loose items are appended above one panel grid; panels and embedded sections are added to that grid. Investigate the limits imposed by this partition. |
| Sizing | `balancePanelGridColumns` in the overlay JavaScript | Absent an explicit column count, the renderer measures candidate layouts and selects the shape closest to a fixed width/height target of 1.4. An explicit count bypasses that pass. Content measurements therefore participate in automatic selection. This is source evidence, not reproduction of the user's specific width change. |
| CSS | [Base CSS](../../Sources/Modaliser/Scheme/base.css), panel-grid rules | The stylesheet supplies ordinary grid followed by `grid-lanes`, with a grid layout override. Verify actual WebKit support and fallback on the supported macOS range; do not infer deployment support from source comments. |
| Config/runtime relationship | [Scheme engine](../../Sources/Modaliser/SchemeEngine.swift), context initialization and native library registration; [root bootstrap](../../Sources/Modaliser/Scheme/root.scm) | LispKit is embedded in Swift and native libraries are registered in that engine. A runtime replacement is larger than translating a user file. Quantify the affected roles before recommending it. |
| Facilities versus choices | [ADR-0021](../adr/0021-decision-free-libraries.md); [VS Code example](../../Sources/Modaliser/Scheme/examples/vscode.scm) | The library/config distinction already exists. The example imports app facilities, composes providers, selects alphabets, defines actions, and chooses presentation. Identify remaining authoring burden rather than proposing the existing distinction as new. |
| Live data | VS Code example's project/terminal/editor providers and corresponding listings | Dynamic keys and visible rows use related per-visit data. A cross-language design must account for that shared assignment and its lifetime. A startup-only serialized description is not automatically equivalent to the current live callbacks. |
| User composition | VS Code example's Grove Leaf action | Configuration joins app workspace discovery, a tool query, and an app action. Any candidate language needs a credible equivalent, or must explicitly document the lost capability. |
| Handoff/recovery | [ADR-0018](../adr/0018-configuration-as-one-explicit-value.md), [ADR-0022](../adr/0022-config-failure-degrades.md) | Evaluate validation, one explicit configuration value, diagnostic quality, and recovery. Current reload semantics are relaunch; runtime replacement does not silently authorize hot reload. |
| Outward effects | [ADR-0023](../adr/0023-native-reach-is-host-installed.md) | Integration tests currently use inert outward seams. Preserve that property in proposed evaluation and plugin contracts. |

The graph CLI failed with an active-generation compatibility error before it
could list projects. No graph generation or index-coverage result is available.
The evidence here is a targeted source/document read, not an exhaustive symbol or
call-graph inventory. No app was run, screen captured, layout measured, or runtime
performance benchmarked for this baseline.

## Shared scenarios

1. **Editor group:** a list of open editors and previous/next actions form one
   visual group, while projects, terminals, and miscellaneous actions are arranged
   separately. Grouping must not add a dispatch prefix unless the user asks for
   navigation.
2. **Wide title:** replacing a short editor title with a long path must follow a
   stated width/overflow policy: groups stay in place and text wraps or truncates
   within the allotted width. Optional responsiveness to a smaller display must
   not turn a title change into a layout breakpoint.
3. **Live snapshot:** a terminal appears or disappears while a screen is active.
   Explain how visible rows, assigned keys, selected row, and target identities
   remain coherent under the existing visit model or an explicitly proposed one.
4. **App update:** VS Code changes how an operation works. Its facility changes;
   the user's grouping and key choices remain theirs. Show what happens if a
   capability disappears or is incompatible.
5. **Cross-facility action:** discover the focused VS Code workspace, obtain its
   live Grove task, and reveal it in VS Code. Show ordinary user composition,
   missing-value handling, and asynchronous completion where needed.
6. **Broken configuration:** an unknown operation, invalid layout, missing plugin,
   or language error produces actionable diagnostics and a recoverable startup.

## Questions the surveys must answer

### Layout

Compare extending screen-level options, a compositional Display-value layout
tree, and an unrestricted renderer/CSS escape hatch. Define grid, flow, and
masonry by their behavior rather than relying on a CSS property name. Include
group nesting, row/column flow, wrapping, min/preferred/max widths, spans,
alignment, gaps, overflow, ordering, embedded navigation, and zero/long lists.

Separate semantic order and key behavior from visual packing. Investigate the
native panel sizing and available-space constraints as well as the web layout.
Identify controls that are already available, controls hidden in theme/renderer
policy, and proposed additions. Study current WebKit deployment support using
primary sources, with explicit fallbacks where support varies.

### Facilities and plugins

Compare app-bundled modules, independently delivered in-process Swift code, and
separate helper processes. Distinguish source/package plugins from separately
compiled binaries and from plugins hosted inside the controlled app (such as the
VS Code companion). Define the smallest useful semantic surface: discovery,
typed entities/identity, queries, actions, optional subscriptions, errors, and
availability. Keep user keys, labels, grouping, and layout in configuration.

Use the VS Code example to locate wiring the library should hide and preferences
the user must retain. Examine Swift interoperability/ABI, version negotiation,
distribution, main-thread work, cancellation, crash behavior, trust, and lifecycle.
These are architectural trade-offs, not a request to install any plugin.

### Configuration languages and runtime

For Racket, Common Lisp/SBCL, TypeScript, Lua, and the current LispKit/Scheme
baseline, compare authoring, composition, modules, diagnostics, editor support,
native interoperability, callbacks, state, packaging, startup/latency evidence,
and maintenance. TypeScript needs a specified JavaScript runtime and preparation
pipeline; SBCL is a Common Lisp implementation, not a separate language.

Compare a startup-only frontend, a resident configuration runtime, and full
Scheme-runtime replacement. Trace closures, handles, async results, exceptions,
and lifecycle across each boundary. Separate a language-neutral facility
contract from a promise to ship multiple language runtimes. Include migration
shape and explicit compatibility trade-offs, without producing build tasks.

### Synthesis

Give two or three coherent overall alternatives with a provisional recommendation
and conditions that would change it. Apply all alternatives to the same editor
group and cross-facility action. Name questions research can settle, preferences
only the user can settle, and claims that would require a future experiment.

## Evidence discipline

Use primary sources for external technical claims, record the date consulted,
and cite each attributed limitation or failure mode. Distinguish documented facts,
local code observations, design inference, and unmeasured expectations. For prior
systems, explain what remains readable/usable after the tool is uninstalled.
Record where no adequate primary evidence was found. Documentation examples may
illustrate an interface, but no runnable prototype is part of this workstream.
