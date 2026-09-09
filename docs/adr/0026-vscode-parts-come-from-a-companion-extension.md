# What is open inside a VSCode window comes from a companion extension

## Context

`(modaliser apps vscode)` can already list VSCode's **windows** and say which
folder each is rooted at. Listing what is open *inside* one window — the editor
tabs, the terminals — and acting on a chosen one needs a source.

The framing this record carried for two revisions was that VSCode "exposes no
scripting dictionary and no IPC socket", which is what `apps/vscode.sld`'s header
still opens with. That is true of VSCode **as an application seen from outside**,
and it is the wrong frame. VSCode's extension API is a first-class, versioned,
documented surface onto exactly the state in question, and its extension host is
an ordinary Node process — so a companion extension can answer a query over a
socket, and the missing IPC is missing only until someone writes the peer.

Everything below is read out of the shipped bundle (VSCode **1.136.2**,
`Contents/Resources/app/`) or probed against the live application, never from
documentation about VSCode.

**The extension API carries the model, not a rendering of it.**
`out/vscode-dts/vscode.d.ts` ships inside the application:

- `window.terminals: readonly Terminal[]` (`:11164`). A `Terminal` carries
  `readonly name: string`, `show(preserveFocus?: boolean): void`, `processId`,
  and `shellIntegration.cwd: Uri | undefined`.
- `window.tabGroups: TabGroups` (`:11077`). A `Tab` carries `label`, `input`
  (a `TabInputText` and friends, so a real `uri` rather than a rendered path
  string), `isActive`, `isDirty`, `isPinned`, `isPreview` and `group`; a
  `TabGroup` carries `viewColumn` and `isActive`.
- `window.state: WindowState` (`:11217`), whose `focused: boolean` lets a
  window's own extension say whether it is the one the user is looking at.

**And the host can hold a socket.** The extension host is a Node process
(`out/vs/workbench/api/node/extensionHostProcess.js`); shipped extensions use
Node's `net` (`debug-auto-launch`, `js-debug-companion`, `npm`) and activate at
window start via `onStartupFinished` (`debug-auto-launch`, `copilot`,
`merge-conflict`). Modaliser's side of that already exists and is already
decided: `unix-socket-request` is a synchronous, timeout-bounded, never-raising
round-trip, and ADR-0020 established newline-delimited JSON over a Unix socket as
an integration boundary rather than a workaround.

**The two sources investigated before the extension, and what each cost.**

*The per-workspace state database.*
`~/Library/Application Support/Code/User/workspaceStorage/<hash>/state.vscdb` is
a SQLite file whose `memento/workbench.parts.editor` key does carry a complete
editor listing — a branch/leaf grid of editor groups with group structure and MRU
order. `terminal.integrated.layoutInfo` does **not** carry a terminal listing,
and structurally cannot: its entries are `{relativeSize, terminal}` where
`terminal` is a persistent-process id integer, and the names live in the pty host,
which substitutes an attach-target object for that integer over IPC at restore
time. Disk carries the join key and nothing else.

What rules the memento out is its cadence. `EditorPart.saveState()` is a
`Component` hook on `storageService.onWillSaveState`, which fires from three
places only: an idle flush whose `DEFAULT_FLUSH_INTERVAL` is **60 000 ms**, the
window *losing* focus, and shutdown. A four-minute poll of a live `state.vscdb`
recorded zero writes while its window sat idle. The blur flush cannot rescue the
press that needs it — the leader fires while VSCode is still frontmost — so the
stored list lags reality by up to a minute.

*The accessibility tree.* VSCode is Electron, so its tab strips and its terminal
tab list are rendered DOM mirrored into AX, and both are readable. With the
terminal panel shown and two terminals running, live 1.136.2 exposes an `AXList`
described `Terminal tabs`, row groups named `Terminal 1 zsh` / `Terminal 2 zsh`,
and an `AXPress`-able descendant per row; pressing one moved the live selection.
Editor tabs are the `AXTabButton`-subroled children of every tab group whose own
`AXDescription` is empty — an anchor by *absence*, because every other tab group
in the window carries a composite bar's localised aria-label.

That works, and a full design was written against it. What it costs is the
subject of the rejected option below: reading a *rendering* rather than a model
means the source can only see what is currently drawn.

## Decision

**What is open inside a VSCode window is read from a companion VSCode extension
over a Unix-domain socket, and acted on by handing that extension back a token it
minted. The extension is the source for both listings — editors and terminals —
and the accessibility tree is not used for either.**

*Which* of several windows is asked, and how a row stays bound to the window it
was read from, is a separate decision with its own rejected alternatives:
ADR-0027.

- **One method answers both panels.** A `parts` request returns the window's
  terminals and editor tabs together, with the window's own `focused` flag and
  workspace path. The shipped composition still calls it once per panel — two
  panels, two round-trips — because a shared per-visit memo is machinery bought
  before it is needed, and two socket round-trips are cheaper than the single
  accessibility walk they replace. The reply's shape is what leaves the memo
  available later without a protocol change.

- **The method set is bounded and is not `commands.executeCommand`.** `parts`,
  `focus-terminal`, `focus-editor`, and nothing else. A passthrough would make
  the socket a remote control for the whole workbench, and the trade-off being
  accepted here is only as good as the enumeration of what it *does* expose to
  anything running as the user:

  | what the socket gives | reads | acts |
  |---|---|---|
  | the window's workspace root path | yes | — |
  | every terminal's name and, where shell integration reports one, its cwd | yes | — |
  | every open editor's label, file path, dirty and active flags, and editor group | yes | — |
  | whether this window is the focused one | yes | — |
  | showing and focusing any terminal in that window | — | yes |
  | activating any actionable editor tab in that window | — | yes |

  Nothing else: no document contents, no settings, no file writes, no workbench
  commands, no reach outside the one window. Two boundaries make that enumeration
  the whole of it — the method set above, and the socket directory, which is
  created mode **0700** so the sockets and the last-focused pointer are not even
  listable by another user on the machine. The residual exposure is accepted on
  the same terms as herdr's (ADR-0020), with the surface deliberately smaller;
  what is *new* against herdr is a list of the human's open file paths and their
  workspace root, which is why it is enumerated rather than summarised.

- **Actions name a token the extension minted, never an index or a path.** The
  extension allocates from a counter that is **never reset** and keeps
  token → live object, pruned rather than replaced on each read, so a token names
  at most one thing for its window's lifetime and stays valid for as long as that
  thing does. An action whose token has gone stale does nothing. This is the same
  invariant, and the same reasoning, that the accessibility design reached for its
  element handles: the row and what it does come from one snapshot and cannot
  disagree, and a target that has gone away yields no action rather than the wrong
  one. A token is scoped to the peer that minted it and is not an address on its
  own — ADR-0027.

- **An action is a notification, not a request.** Nothing consumes an
  acknowledgement, so nothing waits for one (ADR-0014): the focus methods are put
  on the socket with `unix-socket-send` and the peer answers nothing. Only `parts`
  waits, and it waits on a bounded budget rather than herdr's 1000 ms ceiling,
  because a screen performs one read per panel and the tap's tolerance is spent on
  the total.

- **The transport is the one ADR-0020 already built.** Newline-delimited JSON,
  one request per connection, `unix-socket-request` owning the framing, the
  socket path installed by the host at boot and defaulting to "not configured",
  exactly as the herdr transport does. `swift test` stays inert for the same
  structural reason and not by discipline.

## Considered options

- **Read the accessibility tree.** A complete design, written and reviewed, and
  rejected on what reading a *rendering* costs rather than on any defect in the
  reading. Six consequences, all of them consequences of the same fact:
  the anchor for an editor strip is an **absence**, which under-identifies and
  goes silently empty if a future VSCode labels the strip; the tab's name lands
  in `AXDescription` or `AXTitle` unpredictably — the same tab group put it in
  different attributes fifteen minutes apart; three settings must be pinned
  (`workbench.editor.showTabs` at `multiple`, `editor.accessibilitySupport` at
  `off`, and `terminal.integrated.tabs.hideCondition` away from its
  `singleTerminal` default) purely so that the thing to be read is drawn; a
  window behind a modal renders only the modal and so answers nothing; the
  listing is frontmost-window-only, because AX gives a live window's rendered
  tree; and editor *group* identity is out of reach entirely, since the strips do
  not carry it. The extension has none of these: it reads the model, so nothing
  needs to be drawn, nothing needs to be pinned, a modal is irrelevant, and
  `TabGroup.viewColumn` is simply available.

  The terminal half is where the difference stops being a matter of degree. On
  AX, a terminal listing requires the terminal panel to be **shown** before it
  can be read — and a provider runs *before* its state's entry fires
  (`fsm.sld:751`, `:873`), so showing-then-enumerating needs either a two-step op
  that costs the user a keypress and puts a panel on screen as a side effect of
  asking what is open, or a change to the engine's ordering that every screen
  pays for. Neither is needed once the source is the model. Acting on a chosen
  terminal is the same story: `workbench.action.terminal.focusAtIndex1..9` ships
  with `primary: 0` — no keybinding on any platform — so a synthetic keystroke
  cannot reach it, while `Terminal.show()` is a direct call.

  **Reopen if** the extension proves unshippable in practice — a VSCode API
  break, or an install the user will not keep — since the AX design is worked out
  and its evidence is preserved above.

- **Read `memento/workbench.parts.editor` from the SQLite state database.** The
  option this question was expected to take, and the only source that survives
  the window not being frontmost. Rejected on the 60-second cadence: the failure
  mode is a row whose name and whose target disagree, which is a silent wrong
  jump. Reading it was never the obstacle — LispKit ships a SQLite library, so it
  needs no subprocess. It carries no terminal names at all, structurally.
  **Reopen if** a listing is ever wanted for a window that is *not* frontmost
  *and* the extension is unavailable, where stored state is the only source there
  is.

- **Pair a stored listing with `code <path>` instead of a token.** Repairs the
  failure mode rather than the staleness — a stale row reopens the file it names
  instead of jumping to the wrong one. Rejected because `code` against a running
  instance was measured at ~1.1 s to return: acceptable for opening a grove leaf,
  absurd for switching tabs.

- **Numbered slots, no enumeration.** For editors this collapses to *do not build
  the panel*: `workbench.action.openEditorAtIndex1..9` registers with
  `mac: { primary: WinCtrl | Digit }` and no `when` clause, so ctrl-1 … ctrl-9
  already are the numbered slots and nine unnamed rows add nothing over pressing
  them. Two caveats found while pricing it, both from the registration: the index
  is active-group relative, and these ids are **not** in the default
  `terminal.integrated.commandsToSkipShell` array — unlike the editor-cycling
  commands, which are — so ctrl-3 pressed with the integrated terminal focused
  reaches the shell. For terminals the option does not exist at all, per
  `primary: 0` above.

- **The `code` CLI's own IPC socket** (`VSCODE_IPC_HOOK_CLI`). It exists, and it
  is how `code` reaches a running instance. Rejected: the protocol is private and
  unversioned, so building on it is building on something that may change without
  a deprecation, and it is the same path measured at ~1.1 s. Writing an extension
  is *less* speculative than reverse-engineering the socket the CLI uses, because
  the extension API is the surface VSCode commits to.

## Consequences

- **Modaliser gains a deliverable in a third language.** A TypeScript extension,
  with npm, a bundler and a `.vsix`, in a repository that is otherwise Swift and
  Scheme and has no CI. It is not part of the `.app`, so ADR-0019's exact-mirror
  invariant does not cover it and `build-app.sh` does not check it; its
  installation is a separate step against a separate application. This is the
  real price of the decision and it is paid once per machine rather than once per
  press.

- **The integration now has a version boundary that can skew.** Modaliser and the
  extension are installed separately and can disagree. The `parts` reply
  therefore carries a protocol version and Modaliser answers a mismatch with an
  empty listing and a log line, rather than by interpreting fields it does not
  understand.

- **A miss is still an empty listing, and there are more ways to miss.** The
  extension not installed, not yet activated, disabled for the profile, a stale
  pointer, a crashed host — every one of them ends at `unix-socket-request`
  returning `#f` or a reply that fails the `focused` gate, and every one of them
  shows no rows rather than wrong rows. That is the same contract the
  accessibility design held and it is unchanged. A window with **no folder open**
  is deliberately *not* on that list: it is an ordinary peer with a `null`
  workspace, because the source needs no workspace to enumerate a window and an
  empty listing there would narrow the requirement rather than degrade it.

- **The reply's latency is now a shared resource.** An accessibility read
  contends with the target app's main thread; a socket round-trip contends with
  the extension host's event loop, which every other extension in that window
  also uses. Neither is bounded by construction, so the read is timeout-bounded
  and degrades to empty — and the number that has to hold is the *per-screen
  total*, since a screen reads once per panel and a blocked eval thread is a
  blocked keyboard tap (ADR-0014). herdr's comparable wire time is 0.1–0.6 ms per
  read, which is the order to expect and not a measurement of this; the budget is
  set against the wedged case, which no healthy-path measurement can speak to.

- **The listing is no longer frontmost-only in principle.** Every window's
  extension is dialable, so a cross-window listing becomes reachable for the first
  time. Nothing has asked for one and none is built; what changes is that the
  door is no longer closed by the source.

- **`AccessibilityLibrary` gains nothing.** The two procedures the accessibility
  design specified — a tab-strip reader and an `AXPress` over a handle — are not
  built, and the one-never-reset-counter change that design required is not
  needed either: it existed only because a second reader would have opened a
  second handle space in that library. `ax-find-elements` remains the only space
  and keeps its reset.

- **ADR-0023 is engaged, not untouched, and is satisfied the way ADR-0020 is.**
  A socket reaches outside the process. The quarantine that matters is the
  inert-by-default seam: the socket path is a parameter defaulting to "not
  configured" and the host installs the real one at boot, so no test run can dial
  a live editor. This is the pattern the herdr transport already follows.

## See also

- ADR-0020 — the socket transport, and why a socket is an integration boundary
  rather than a workaround.
- ADR-0027 — addressing one window among several, and binding a row to the peer
  that minted it.
- ADR-0014 — an interactive command never blocks: why an action with no consumed
  result is sent rather than asked.
- ADR-0021 — no library authors a key, a label or an alphabet.
- `docs/specs/vscode-window-parts.md` — how the area works: the protocol, the
  method set, the Scheme surface, and the test seams.
