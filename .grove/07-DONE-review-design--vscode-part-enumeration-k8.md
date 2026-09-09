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

## Findings

### F1 — High: the editor-strip anchor is neither unique nor total

The design says the editor strip is the only `AXTabGroup` with an empty
description, stops at the first such group, and nevertheless requires one row
per editor tab in the frontmost window
(`docs/specs/vscode-editor-listing.md:62`, `:71`, `:293`). A live VSCode 1.136.2
scratch window disproved both sides of that contract:

- with **Multiple Tabs** and an editor split right, the one window exposed two
  empty-description `AXTabGroup`s;
- with **Single Tab**, it exposed no empty-description editor group (the only
  tab group was the labelled `Settings Switcher`);
- with **Hidden**, the result was the same: no empty-description editor group.

The first-match walk therefore returns one arbitrary editor group in a split
window and returns no editors at all in two supported tab-bar modes. Calling
editor groups out of scope at `docs/specs/vscode-editor-listing.md:384` does not
resolve the contradiction: `vscode-part-panels-k7` asks for one row per open
editor, and the live config's previous/next operations explicitly cross editor
groups. The artifact must settle which tabs the listing promises and state any
tab-bar setting it requires before k7 can implement it.

### F2 — High: the terminal blockers are not independent, and they do not rule out the requested panel

ADR-0026 and the spec treat no disk name, no AX rows while hidden, and no
default-bound index command as three independent fatal blockers. They are all
premised on leaving the terminal panel hidden and using a keybinding for the
action. In a live scratch window, showing the panel with two terminals produced
an `AXList` described `Terminal tabs`, named row groups `Terminal 1 zsh` and
`Terminal 2 zsh`, and an `AXPress` descendant in each row. Performing that
action on the first row moved the live DOM selection from Terminal 2 to
Terminal 1.

There is a real sequencing cost, but it is a design question rather than a
third proof of impossibility: `classify-and-snapshot` runs the provider before
`move-to!` fires a state's entry (`fsm.sld:751`, `:873`), so a deterministic
show-then-enumerate interaction does not fall out of the current state shape.
The design must price that sequencing change, or an explicit two-step UX,
against omitting the terminal panel. It cannot reject the panel on the present
evidence, especially when k7 records the human's explicit request for it and
for removing the `t` row.

### F3 — High: collision validation is placed below two collision sources

`jump-list-compose-providers` can compare only the extra edges and states
returned by its provider arguments (`docs/specs/vscode-editor-listing.md:183`).
The engine subsequently appends those edges to the owner's static edges without
a check (`fsm.sld:751`), and a provided state shadows a permanent state of the
same id (`fsm.sld:640`). Thus a data-dependent promoted leader can still collide
with a static screen key and silently dispatch to the static edge, while a
provided state can still shadow a permanent state. These are the same failure
classes the design says the merge eliminates.

The proposed signature also receives opaque provider procedures only, so it has
no contributor identity with which to satisfy the requirement to name both
contributors (`docs/specs/vscode-editor-listing.md:183`, `:332`). Ordinal
argument positions are not the panel/provider names a user needs to repair the
configuration. The validation seam needs access to the whole combined edge and
state namespace, plus retained origin data; the proposed merge has neither.

### F4 — High: the two integer handle spaces are not specified as disjoint

The existing accessibility surface hands Scheme bare integer handles and
recycles them from 1 on every enumeration
(`AccessibilityLibrary.swift:71`, `:98`). The spec adds another bare-integer
space, says only that it is independently monotonic, and then promises that a
handle from one space is never valid in the other
(`docs/specs/vscode-editor-listing.md:99`). Separate dictionaries do not provide
that property: the same integer can be a live key in both, so sending an
`ax-find-elements` handle to `ax-press-handle` can resolve to an unrelated tab.

No disjoint representation/range/tag is specified, and the planned native
tests cover allocation and stale refusal but not cross-space refusal. That
leaves the central “right target or no-op, never a wrong target” invariant open.
The requirements compound the ambiguity by demanding exact activation
“regardless of what has changed” (`docs/specs/vscode-editor-listing.md:306`)
while the design explicitly permits a no-op after the target disappears
(`:112`).

### F5 — High: the unstable name fallback sits below the test seam

`ax-tab-rows` collapses `AXDescription`-else-`AXTitle` into a single `name`
field before Scheme sees it (`docs/specs/vscode-editor-listing.md:82`). The pure
`editor-tabs` seam and its canned provider rows therefore contain `name`, not
the two source attributes (`:125`, `:351`). At the same time, native tree
walking is expressly left untested (`:365`).

The instruction to put one description-shaped row and one title-shaped row in
the fixture (`:372`) is impossible with the row type the design defines: both
arrive as indistinguishable `name` strings. An implementation that reads only
one of the two unstable attributes can pass every planned test. The fallback
must either move above the pure seam or gain its own testable native projection
seam.

### F6 — Medium: the catch-all error path releases keys but does not tear down modal state

The leader path is sound: `modal-activate!` snapshots before registering the
catch-all or showing the overlay (`fsm.sld:1930`), and the Swift wrapper logs
the error then finalises the capture (`KeyboardLibrary.swift:185`). The
catch-all path does less than the spec claims. On error it only assigns
`catchAllHandler = nil` (`KeyboardLibrary.swift:300`); it does not run
`modal-exit`, halt/reset the FSM, or hide the overlay. `/usr/bin/log` is also not
visible user feedback.

So a provider raise during a later snapshot cannot wedge keyboard capture, but
it can leave a stale overlay and live Scheme modal state while ordinary keys
pass through. The statement that both paths fail visibly and “nothing wedges”
(`docs/specs/vscode-editor-listing.md:193`) is too broad for a generic provider
composition facility.

### F7 — Medium: the performance conclusion is not a measurement of the shipping path

The 3.1 ms result comes from an uncommitted standalone Swift walker. It excludes
the specified alist marshalling, Scheme provider/lowering work, main-queue
execution, and eval-lock context, and the spec itself concedes that its “first
call” is not a cold launch/space case
(`docs/specs/vscode-editor-listing.md:250`). No instrument source or per-run
record landed in the producer commit, so the implementation cannot reproduce
the same measurement before comparing it.

That evidence supports “the raw pruned AX walk can be cheap,” but not “the
Editor listing is cheaper than the panel already on the screen” or “two panels
stay inside one panel's old budget” (`:260`). The no-`'next 'self` ruling is
independently sound; the shipping-path latency claim remains unverified and
needs to be treated as such by k7.

## Decisions (running log)

**The 60-second storage concern is confirmed, not a finding.** With the VSCode
window kept focused, opening `0019-seeding-and-upgrade.md` changed the
`memento/workbench.parts.editor` value 26 seconds later, and the changed value
contained that filename. This is direct evidence of material periodic lag and
rules out the doubt that the real write follows an editor change within a
second; the exact delay depends on where the change lands in the flush period.

**The locale half of the absence rule remains sound, but cannot rescue F1.**
Testing absence avoids an English label dependency. The live layout tests show
that absence is not a unique structural identity across editor groups and is
not present in Single/Hidden tab modes.

**ADR-0026 is one coherent decision record, not an excess record.** Its editor
source and terminal omission belong together because they are the two outcomes
of the same source-selection trade-off. F2 requires reworking that current-state
decision if integration accepts the finding; it does not call for a second ADR.

**Review coverage limitation.** The producer commit `f81bbf01`, its complete
artifact diff, the cited requirements/briefs/ADRs, the exact source paths above,
the human's live VSCode screen config, and VSCode 1.136.2's live AX tree were
inspected. The codebase-memory graph could not be queried: repeated guarded CLI
attempts reported a pre-coordination or unverified generation while no graph
process was visible. Exact source reads supplied the evidence above; no negative
or repo-exhaustive claim relies on an empty graph result.
