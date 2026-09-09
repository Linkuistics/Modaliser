# vscode-part-enumeration-k8

**Reviews:** `vscode-part-enumeration-k6`

## Goal

An adversarial read of `docs/specs/vscode-editor-listing.md` and ADR-0026 —
the design that decides how Modaliser learns what is open inside a VSCode
window. Findings, no fixes.

`vscode-part-panels-k7` builds to this spec, which is why this leaf sits ahead
of it rather than after it.

## Context

**Why this review was cut.** The producing session judged one necessary, which
in this grove is unusual — k3, k4 and k5 each judged one unnecessary and said
why. The reason here is empirical rather than procedural: within minutes of
writing the spec, checking its own claims found **three** defects in it —
a wrong ADR citation, an incomplete enumeration copied from the leaf's own
charter, and a real design hazard (recycled accessibility handles) that only
surfaced by enumerating rather than recalling. All three are recorded, corrected
and named in k6's decision log. An artifact with that defect density in its
first hour has more.

**The design in one paragraph, so you can attack it rather than reconstruct
it.** Editors are listed by walking the frontmost VSCode window's accessibility
tree at come-to-rest and pressing the tab element the row was read from.
Terminals get no listing at all. The stored editor state — a SQLite memento —
was rejected on a 60-second write cadence. A new merge in `(modaliser
jump-list)` composes several panels onto one `'provider` slot and raises on a
collision the engine would otherwise resolve first-wins.

### The specific doubts, in the order they are worth spending on

1. **Is "the editor tab strip is the only tab group with an empty
   accessibility description" actually unique?** This is the design's whole
   anchor and it was verified in exactly two window configurations, both this
   human's, both with one editor group and the default tab settings. Untested
   and worth attacking: `workbench.editor.showTabs` set to `single` or `none`; a
   floating / auxiliary editor window; an editor group moved into the panel
   area; a secondary sidebar carrying a webview with its own tab strip; a
   multi-root workspace; a non-English UI. The rule *should* survive the last
   one — it matches an absence precisely so a localised label cannot break it —
   but nobody has watched it.

2. **Are the three terminal blockers independent, or one restated three
   times?** The spec claims no name on disk, nothing in the accessibility tree,
   and no default-bound focus command. Blocker 1 only bites if you were going to
   read disk, so removing it may change nothing. The composition the session
   dismissed fastest and should have argued harder: **show the terminal panel
   first, then enumerate** — rejected because a provider runs before the user
   has chosen, but a two-step op (an `entry` that shows the panel, then the
   listing) was not seriously priced. Is that a real option?

3. **The 60-second staleness is an inference, not an observation.** It is read
   off the storage service's flush interval and its blur handler. The one
   experiment run — a four-minute poll of a live database — recorded *zero*
   writes on an idle window, which is consistent with the story and evidence for
   nothing. Nobody opened a tab and timed how long the stored state took to say
   so. If the real lag is a second, the rejected candidate comes back.

4. **The measurement's provenance.** 3.1 ms median warm and ~30 ms first call
   come from a standalone optimised Swift binary, reproduced fifteen minutes
   apart. The shipping path is a native procedure marshalling rows into Scheme
   inside the app, on the main queue, under the eval lock. Does the number
   transfer, and is the "first call" figure a cold number in any sense that
   matters — the app had been running for hours with its windows on screen.

5. **Does raising at the merge do what the spec says it does?** The session
   traced the two host error paths (leader handler, catch-all) and concluded a
   raise fails loudly and wedges nothing. Read that trace, not the conclusion.
   And ask the harder question the spec answers only by argument: on a screen
   whose panels have grown past their single alphabets, is raising on every
   press of that screen the behaviour a user wants, or has the design chosen
   loudness over a usable screen?

6. **Is the spec's `Out of scope` honest?** In particular "editor *groups*" —
   the design cannot see them and the section says nobody asked. Check whether
   the human's own configuration or the grove's brief chain implies they will.

### Pointers

- `docs/specs/vscode-editor-listing.md` and
  `docs/adr/0026-vscode-parts-come-from-the-accessibility-tree.md` — the
  artifacts under review.
- `.grove/06-DONE-design--vscode-part-enumeration-k6.md`, its
  `## Decisions (running log)` — every claim's evidence, including the raw
  shapes and the three corrections.
- `Sources/Modaliser/AccessibilityLibrary.swift` — the existing accessibility
  surface the design extends, and the handle-recycling header the hazard came
  from.
- `Sources/Modaliser/Scheme/lib/modaliser/jump-list.sld`, `jump-labels.sld`,
  `fsm.sld` — the composition's three ingredients.
- VSCode 1.136.2 is the version everything was established against; the shipped
  bundle is at
  `/Applications/Visual Studio Code.app/Contents/Resources/app/out/`, and its
  localised strings resolve through `out/nls.metadata.json`.

## Done when

- Each of the six doubts above is either confirmed as sound with the evidence
  that settles it, or written up as a finding.
- Anything else the read turns up is a finding too — the list above is where to
  start, not the scope.
- Findings are recorded as findings, with no fixes applied. If there is nothing
  worth acting on, cut no integration leaf and simply retire; that is a normal
  outcome.

## Notes

- **Reading a live VSCode is in scope and is how doubt 1 gets settled.** The
  producing session drove the app with a scratch window and cleaned up after
  itself: a temporary folder, a window closed by pressing its close button, and
  the `workspaceStorage` directory it created removed once the window was gone.
  Do the same if you open one — and note the workspace-trust prompt blocks the
  workbench from rendering, which is itself one of the spec's stated failure
  modes.
- Accessibility reads from a shell work on this machine without extra grants; a
  small `swiftc -O` program is the instrument the producing session used, and
  `osascript` against System Events is enough for a quick probe.
- **Do not turn a finding into a fix.** The integration step exists for that,
  and cutting it is this leaf's last act if the findings warrant one.
